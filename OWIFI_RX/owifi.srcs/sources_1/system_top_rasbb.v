//////////////////////////////////////////////////////////////////////////////////
//
// Design Name: OWIFI_RX
// Module Name: system_top_rasbb
// Project Name: RA-Sentinel 802.11 receiver
// Engineer: Tobias Weber
// Target Devices: Artix 7, XC7A100T (RASBB baseboard + 1ch RASRF front end)
// Description:
//   802.11 OFDM receiver (openofdm dot11) on the REAL RASBB signal chain.
//   Replaces the Wukong-devboard system_top: the ADC path is the complete
//   hardware-proven RASM2400 front end (adc_frontend.v - deserializer, word
//   alignment, link supervision, DC removal, adaptive I/Q balance), and the
//   whole receiver runs synchronously in the 120MHz ADC bit-clock domain
//   with the native 20MHz sample strobe - openofdm's expected 20MSPS
//   complex baseband, no resampling, no CDC FIFO. (openwifi runs dot11 at
//   100MHz on a -1 Zynq; this is 120MHz on a -2 Artix - watch timing, the
//   fallback is an async FIFO into a free-running 100MHz domain.)
//
//   PHASE 1 (this file): receive-and-observe. Decode results go to the J5
//   debug header (RASDBG adapter) and ILA; the DCMI frame streamer to the
//   STM32 is intentionally NOT ported yet - its RASBB pins must first be
//   derived from the RASBB .kicad_pcb (never the .net - known desync).
//
//   Port names deliberately match RASM2400's top so the proven RASBB
//   constraint set (pins_RASRF.xdc + RASBB_common.xdc, honest 8.333ns
//   ADC_dclk clock) carries over with only the TMDS lines removed.
//
// Dependencies: adc_frontend.v (+ its deps), openwifi/dot11.v tree,
//               signal_watchdog.v, SPI_Peripheral.v, registers.v,
//               Video_clk IP (195MHz IDELAYCTRL ref from 50MHz SYS_clk)
//
// Additional Comments: https://github.com/Tobias-DG3YEV/RA-Sentinel
//
//////////////////////////////////////////////////////////////////////////////////
// Copyright (C) 2026 Tobias Weber
// License: GNU GPL v3
//////////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps

module system_top_rasbb (
    /* 50MHz RASBB system clock */
    input  wire SYS_clk,

    /* ADC LVDS from the RASRF via the PCIe connector - every used pair
       externally terminated with 100R (HR bank: no usable on-die term). */
    input  wire ADC_dclk_P, ADC_dclk_N,
    input  wire ADC_fclk_P, ADC_fclk_N,
    input  wire ADC_chA_P,  ADC_chA_N,
    input  wire ADC_chB_P,  ADC_chB_N,
    input  wire ADC_chC_P,  ADC_chC_N,

    /* SPI slave (STM32 HKU is the master) */
    input  wire SPI_ncs,
    input  wire SPI_sclk,
    input  wire SPI_copi,
    output wire SPI_cipo,

    /* HDMI: scrolling log of received frames (see HDMI_FRAME_LOG below) */
    output wire TMDS_clk_p,  TMDS_clk_n,
    output wire [2:0] TMDS_data_p, TMDS_data_n,

    /* J5 debug header (RASDBG adapter) */
    output wire dbgBitClk,   // short-preamble detected
    output wire dbgFrameRdy, // PHY header valid (sig_valid)
    output wire dbgIser,     // LVDS link healthy
    output wire dbgQser,     // FCS OK (stretched pulse)
    output wire [11:0] dbgOutI, // {pkt_len[5:0], samples_valid, demod_ongoing, state[3:0]}
    output wire [11:0] dbgOutQ, // {fcs_err_cnt[2:0], byte_strobe, byte_out[7:0]}

    /* debug-header keys (Key0 = manual reset, glitch-filtered) */
    input  wire Key0,
    input  wire Key1
);

`include "common_params.v"

localparam ADCBITS = 12;

/****************************************************************************/
/* Clocks: Video_clk MMCM (from RASM2400) gives the 195MHz IDELAYCTRL       */
/* reference; everything else runs on the ADC-derived 120MHz from the       */
/* front end. SYS_clk drives only the MMCM and the quasi-static SPI block.  */
/****************************************************************************/
wire clk_65M;     // unused for now (future DCMI pacing)
wire clk_120M;    // free-running - NOT the sample domain, unused
wire clk_195M;
wire clk_325M;
wire mmcm_locked;

Video_clk video_clk0 (
    .i_clk_50M(SYS_clk),
    .o_clk_65M(clk_65M),
    .o_clk_325M(clk_325M),
    .o_clk_195M(clk_195M),
    .o_clk_120M(clk_120M),
    .reset(1'b0),
    .locked(mmcm_locked)
);

/****************************************************************************/
/* Power-on reset, lock-gated; Key0 honored only after a sustained 8.5us    */
/* low (the raw pad shares the J5 bundle with fast debug outputs - ns       */
/* crosstalk glitches were MEASURED resetting the whole design on RASM2400).*/
/****************************************************************************/
reg [4:0] por_ctr = 5'h00;
reg por_rst = 1'b1;
always @(posedge clk_120M) begin
    if (!mmcm_locked) begin
        por_ctr <= 5'h00;
        por_rst <= 1'b1;
    end
    else if (por_ctr != 5'h1f) begin
        por_ctr <= por_ctr + 5'h1;
        por_rst <= 1'b1;
    end
    else
        por_rst <= 1'b0;
end

(* ASYNC_REG = "true" *) reg [1:0] key0_sync = 2'b11;
always @(posedge clk_120M) key0_sync <= {key0_sync[0], Key0};

reg [9:0] key0_low_ctr = 10'd0;
reg key0_rst = 1'b0;
always @(posedge clk_120M) begin
    if (key0_sync[1]) begin
        key0_low_ctr <= 10'd0;
        key0_rst <= 1'b0;
    end
    else if (key0_low_ctr == 10'h3FF)
        key0_rst <= 1'b1;
    else
        key0_low_ctr <= key0_low_ctr + 10'd1;
end

(* keep = "true" *) reg global_rst_reg = 1'b1;
always @(posedge clk_120M) global_rst_reg <= por_rst | key0_rst;
wire global_rst = global_rst_reg;

/****************************************************************************/
/* ADC front end: the proven RASM2400 chain. fe_clk = 120MHz ADC bit clock. */
/****************************************************************************/
wire fe_clk;
wire fe_strobe;
wire signed [ADCBITS-1:0] fe_i, fe_q;
wire fe_valid;
wire link_ok;
wire [7:0] retrain_count;
wire [7:0] rot_change_count;
wire signed [15:0] iqbal_wp, iqbal_eg;

adc_frontend #(
    .ADCBITS(ADCBITS),
    /* 1ch RASRF: DB0 (Q) lands on the port named ADC_chC (RASBB net RX1,
       U10 pins K2/K1) - see pins_RASRF.xdc header table. chB would be the
       RASRF2400BMC's CH1 Q. */
    .Q_FROM_CHB(0)
) fe0 (
    .ADC_dclk_P(ADC_dclk_P), .ADC_dclk_N(ADC_dclk_N),
    .ADC_fclk_P(ADC_fclk_P), .ADC_fclk_N(ADC_fclk_N),
    .ADC_chA_P(ADC_chA_P),   .ADC_chA_N(ADC_chA_N),
    .ADC_chB_P(ADC_chB_P),   .ADC_chB_N(ADC_chB_N),
    .ADC_chC_P(ADC_chC_P),   .ADC_chC_N(ADC_chC_N),
    .i_rst(global_rst),
    .i_delay_refclk(clk_195M),
    .o_clk(fe_clk),
    .o_sample_strobe(fe_strobe),
    .o_i(fe_i),
    .o_q(fe_q),
    .o_samples_valid(fe_valid),
    .o_link_ok(link_ok),
    .o_retrain_count(retrain_count),
    .o_rot_change_count(rot_change_count),
    /* fe_clk domain, quasi-static; frame_log 2FF-syncs them itself */
    .o_iqbal_wp(iqbal_wp),
    .o_iqbal_eg(iqbal_eg)
);

/****************************************************************************/
/* Receiver clock domain: 100MHz, openwifi's native rate. The first
   all-in-the-120MHz-domain build FAILED setup by -1.19ns in the Viterbi
   path-metric add-compare-select (14 logic levels) - the honest-constraint
   discipline says that ships as intermittent decode garbage, so dot11 gets
   the domain it was designed for and the samples cross through an async
   FIFO (16 deep, mostly empty: 20MHz in, drained at 100MHz).             */
/****************************************************************************/
wire clk_100M;
wire clk_100M_unbuf;
wire mmcm100_fb;
wire mmcm100_locked;

MMCME2_BASE #(
    .CLKIN1_PERIOD(20.000),   // 50MHz SYS_clk
    .CLKFBOUT_MULT_F(20.0),   // VCO 1000MHz
    .DIVCLK_DIVIDE(1),
    .CLKOUT0_DIVIDE_F(10.0)   // 100MHz
) mmcm_rx (
    .CLKIN1(SYS_clk),
    .CLKFBIN(mmcm100_fb),
    .CLKFBOUT(mmcm100_fb),
    .CLKOUT0(clk_100M_unbuf),
    .CLKOUT0B(), .CLKOUT1(), .CLKOUT1B(), .CLKOUT2(), .CLKOUT2B(),
    .CLKOUT3(), .CLKOUT3B(), .CLKOUT4(), .CLKOUT5(), .CLKOUT6(),
    .LOCKED(mmcm100_locked),
    .PWRDWN(1'b0),
    .RST(1'b0)
);
BUFG bufg_100M (.I(clk_100M_unbuf), .O(clk_100M));

/* fe_valid into the RX domain */
(* ASYNC_REG = "true" *) reg [1:0] fe_valid_sync = 2'b00;
always @(posedge clk_100M) fe_valid_sync <= {fe_valid_sync[0], fe_valid};

/* RX-domain reset: held until the MMCM locks AND the front end delivers
   valid samples - dot11 then starts from a clean stream, never from the
   frozen ISERDES constants of an outage. */
(* ASYNC_REG = "true" *) reg [1:0] rst_rx_sync = 2'b11;
always @(posedge clk_100M)
    rst_rx_sync <= {rst_rx_sync[0], global_rst | ~mmcm100_locked};

/* rst_100 holds only the domain itself; the SPI port and the frame buffer use
   it so the STM32 can still read status while the ADC link is down. dot11
   additionally waits for valid samples. */
wire rst_100 = rst_rx_sync[1];
wire rst_rx  = rst_100 | ~fe_valid_sync[1];

/* sample CDC: 24-bit I/Q pairs through an async FIFO (FWFT so dout is
   valid whenever not empty; each non-empty cycle pops one sample). */
wire        smp_empty;
wire [23:0] smp_dout;
wire        smp_strobe = ~smp_empty;

xpm_fifo_async #(
    .FIFO_WRITE_DEPTH(16),
    .WRITE_DATA_WIDTH(24),
    .READ_DATA_WIDTH(24),
    .READ_MODE("fwft"),
    .FIFO_READ_LATENCY(0),
    .CDC_SYNC_STAGES(2),
    .FIFO_MEMORY_TYPE("distributed")
) smp_fifo (
    .rst(global_rst),
    .wr_clk(fe_clk),
    .wr_en(fe_strobe & fe_valid),
    .din({fe_i, fe_q}),
    .rd_clk(clk_100M),
    .rd_en(~smp_empty),
    .dout(smp_dout),
    .empty(smp_empty),
    .full(), .almost_full(), .almost_empty(), .data_valid(), .dbiterr(),
    .overflow(), .prog_empty(), .prog_full(), .rd_data_count(), .rd_rst_busy(),
    .sbiterr(), .underflow(), .wr_ack(), .wr_data_count(), .wr_rst_busy(),
    .injectdbiterr(1'b0), .injectsbiterr(1'b0), .sleep(1'b0)
);

/* 12 -> 16 bit: openofdm was written for full-scale 16-bit I/Q (AD9361).
   Shift left 4 so power thresholds and equalizer scaling see the levels
   they were tuned for. */
wire signed [11:0] rx_i = smp_dout[23:12];
wire signed [11:0] rx_q = smp_dout[11:0];
wire [31:0] sample_in = { {rx_i, 4'b0000}, {rx_q, 4'b0000} };

/****************************************************************************/
/* SPI port (STM32H743 master) - frame read-out + config registers.         */
/*                                                                          */
/* The registers now live in the clk_100M domain together with dot11, which */
/* also removes the old SYS_clk -> receiver crossing on their outputs.      */
/*                                                                          */
/* CIPO rides D17 = SO_FLASH_uC. The slave keeps the pad tri-stated until   */
/* it has recognised one of its own opcodes, so config-flash traffic (which */
/* shares this bus AND this chip select whenever firmware throws            */
/* SWITCH_FLASH_1) can never be answered - see spi_frame_if.v.              */
/****************************************************************************/
wire SPI_reg_wrStrobe;
wire [SPI_REG_ADDRESS_WIDTH-1:0] SPI_reg_addr;
wire [SPI_REG_REGISTER_WIDTH-1:0] SPI_reg_wrData;
wire [SPI_REG_REGISTER_WIDTH-1:0] SPI_reg_rdData;

wire spi_cipo_int;
wire spi_cipo_oe;
assign SPI_cipo = spi_cipo_oe ? spi_cipo_int : 1'bz;

wire [15:0] reg_powerThresh;
wire [15:0] reg_window_size;
wire [31:0] reg_num_sample_to_skip;
wire        num_sample_changed;
wire [31:0] reg_minPlateau;

conf_registers conf_registers_inst (
    .i_clock(clk_100M),
    .i_reset(rst_100),
    .i_SPI_addr(SPI_reg_addr),
    .o_SPIdata(SPI_reg_rdData),
    .i_SPIdata(SPI_reg_wrData),
    .i_SPI_wrStrobe(SPI_reg_wrStrobe),
    .o_regPowerThreshold(reg_powerThresh),
    .o_num_sample_to_skip_stb(num_sample_changed),
    .o_reg_num_sample_to_skip(reg_num_sample_to_skip),
    .o_reg_window_size(reg_window_size),
    .o_reg_minPlateau(reg_minPlateau)
);

/****************************************************************************/
/* Receiver: dot11 + its watchdog, both in the fe_clk domain.               */
/****************************************************************************/
wire [4:0]  state;
wire        pkt_header_valid;
wire        pkt_header_valid_strobe;
wire        short_preamble_detected;
wire        demod_is_ongoing;
wire [15:0] pkt_len;
wire [7:0]  pkt_rate;
wire [7:0]  byte_out;
wire        byte_out_strobe;
wire        fcs_ok;
wire        fcs_out_strobe;
wire        csi_valid;
wire [31:0] equalizer;
wire        equalizer_valid;
wire [15:0] eq_phase_out;
wire        eq_phase_out_stb;
wire        receiver_rst;
/* frame-log diagnostic taps */
wire [15:0] cfo_phase;
wire [31:0] mag_sq_avg;
wire        long_preamble_detected;
wire [31:0] sync_long_metric;
wire        sync_long_metric_stb;

wire sig_valid = pkt_header_valid_strobe & pkt_header_valid;
wire dot11_reset = rst_rx | receiver_rst;
wire signal_watchdog_enable = (state <= S_DECODE_SIGNAL);

signal_watchdog signal_watchdog_inst (
    .i_clk(clk_100M),
    .i_rstn(~rst_rx),
    .i_enable(signal_watchdog_enable),
    .i_data(sample_in[31:16]),
    .q_data(sample_in[15:0]),
    .i_iq_valid(smp_strobe),
    .i_signal_len(pkt_len),
    .i_sig_valid(sig_valid),
    .i_power_trigger(1'b1),
    .i_min_signal_len_th(14),
    .i_max_signal_len_th(1700),
    .i_dc_running_sum_th(64),
    .i_equalizer_monitor_enable(1),
    .i_small_eq_out_counter_th(8),
    .i_state(state),
    .i_equalizer(equalizer),
    .i_equalizer_valid(equalizer_valid),
    .o_receiver_rst(receiver_rst)
);

dot11 dot11_inst (
    .i_clock(clk_100M),
    .i_enable(1'b1),
    .i_reset(dot11_reset),

    .i_num_sample_changed(num_sample_changed),
    .i_reg_power_thres(reg_powerThresh),
    .i_reg_num_sample_to_skip(reg_num_sample_to_skip),
    .i_reg_window_size(reg_window_size),
    .i_min_plateau(reg_minPlateau),
    .i_threshold_scale(0),

    .i_rssi_half_db(11'd0),
    .i_sample_in(sample_in),
    .i_sample_in_strobe(smp_strobe),
    .i_soft_decoding(1'b1),
    .i_force_ht_smoothing(1'b0),
    .i_disable_all_smoothing(1'b0),
    .i_fft_win_shift(4'b1),

    .o_demod_is_ongoing(demod_is_ongoing),
    .o_short_preamble_detected(short_preamble_detected),
    .o_phase_offset(cfo_phase),
    .o_mag_sq_avg(mag_sq_avg),
    .o_long_preamble_detected(long_preamble_detected),
    .o_sync_long_metric(sync_long_metric),
    .o_sync_long_metric_stb(sync_long_metric_stb),
    .o_pkt_header_valid(pkt_header_valid),
    .o_pkt_header_valid_strobe(pkt_header_valid_strobe),
    .o_pkt_len(pkt_len),
    .o_pkt_rate(pkt_rate),

    .o_state(state),
    .o_equalizer_out(equalizer),
    .o_equalizer_out_strobe(equalizer_valid),
    .o_csi_valid(csi_valid),

    .o_byte_out_strobe(byte_out_strobe),
    .o_byte_out(byte_out),

    .o_eq_phase_out_stb(eq_phase_out_stb),
    .o_eq_phase_out(eq_phase_out),

    .o_fcs_out_strobe(fcs_out_strobe),
    .o_fcs_ok(fcs_ok)
);

/****************************************************************************/
/* Frame delivery to the STM32 (phase 2).                                   */
/*                                                                          */
/* dot11 streams bytes long before it knows whether the frame is any good,  */
/* so the buffer commits only on a valid FCS and rewinds otherwise. The     */
/* watchdog's receiver_rst is fed in as the abort signal - without it every */
/* false SIGNAL detection (we measured a steady trickle of those between    */
/* real frames) would leak buffer space.                                    */
/****************************************************************************/
/* declared here because the SPI status block below reads the error count;
   the counters themselves are driven in the debug section at the end. */
reg [20:0] fcs_stretch;
reg [2:0]  fcs_err_cnt;
reg [7:0]  last_byte;

reg [6:0] us_div;
reg       us_tick;
always @(posedge clk_100M) begin
    if (rst_100) begin
        us_div  <= 7'd0;
        us_tick <= 1'b0;
    end
    else if (us_div == 7'd99) begin
        us_div  <= 7'd0;
        us_tick <= 1'b1;
    end
    else begin
        us_div  <= us_div + 7'd1;
        us_tick <= 1'b0;
    end
end

wire [4:0]  fb_frame_count;
wire        fb_overflow;
wire [3:0]  fb_desc_idx;
wire [7:0]  fb_desc_byte;
wire [15:0] fb_pay_offset;
wire [7:0]  fb_pay_byte;
wire        fb_pop;
wire        fb_flush;
wire        fb_clr_sticky;
wire        fb_keep_bad;

frame_buffer #(
    .ADDR_BITS(15),      // 32KB - 8 BRAM36 of the 124 still free
    .DESC_BITS(4)        // up to 16 frames queued
) frame_buffer_inst (
    .i_clk(clk_100M),
    .i_rst(rst_100),
    .i_us_tick(us_tick),
    .i_hdr_valid_stb(pkt_header_valid_strobe),
    .i_hdr_valid(pkt_header_valid),
    .i_pkt_len(pkt_len),
    .i_pkt_rate(pkt_rate),
    .i_byte_stb(byte_out_strobe),
    .i_byte(byte_out),
    .i_fcs_stb(fcs_out_strobe),
    .i_fcs_ok(fcs_ok),
    .i_abort(receiver_rst),
    .i_keep_bad(fb_keep_bad),
    .i_flush(fb_flush),
    .i_clr_sticky(fb_clr_sticky),
    .o_frame_count(fb_frame_count),
    .o_overflow(fb_overflow),
    .i_desc_idx(fb_desc_idx),
    .o_desc_byte(fb_desc_byte),
    .i_pay_offset(fb_pay_offset),
    .o_pay_byte(fb_pay_byte),
    .i_pop(fb_pop)
);

spi_frame_if #(
    .REG_ADDR_W(SPI_REG_ADDRESS_WIDTH),
    .DESC_BITS(4)
) spi_if_inst (
    .i_clk(clk_100M),
    .i_rst(rst_100),
    .i_sclk(SPI_sclk),
    .i_copi(SPI_copi),
    .i_ncs(SPI_ncs),
    .o_cipo(spi_cipo_int),
    .o_cipo_oe(spi_cipo_oe),
    .i_link_ok(link_ok),
    .i_fe_valid(fe_valid_sync[1]),
    .i_demod_ongoing(demod_is_ongoing),
    .i_retrain_count(retrain_count),
    .i_rot_change_count(rot_change_count),
    .i_fcs_err_cnt({5'd0, fcs_err_cnt}),
    .i_frame_count(fb_frame_count),
    .i_buf_overflow(fb_overflow),
    .o_desc_idx(fb_desc_idx),
    .i_desc_byte(fb_desc_byte),
    .o_pay_offset(fb_pay_offset),
    .i_pay_byte(fb_pay_byte),
    .o_pop(fb_pop),
    .o_flush(fb_flush),
    .o_clr_sticky(fb_clr_sticky),
    .o_keep_bad(fb_keep_bad),
    .o_reg_addr(SPI_reg_addr),
    .o_reg_wr(SPI_reg_wrStrobe),
    .o_reg_wdata(SPI_reg_wrData),
    .i_reg_rdata(SPI_reg_rdData)
);

/****************************************************************************/
/* HDMI frame log (optional - comment out HDMI_FRAME_LOG to drop it).       */
/*                                                                          */
/* A scrolling text table of received frames on the HDMI output. It only    */
/* OBSERVES dot11's outputs; nothing here can stall or perturb the receiver, */
/* the frame buffer or the SPI port, so the STM32 sees exactly what it saw   */
/* before. The pixel clocks already existed - Video_clk has been generating  */
/* clk_65M/clk_325M unused since the first RASBB build.                     */
/*                                                                          */
/* WATCH TIMING when touching this: the Viterbi path-metric ACS runs at      */
/* +0.067ns and is congestion-sensitive - adding the frame buffer alone once */
/* cost 175ps. build_rasbb.tcl refuses to emit a bitstream on negative slack. */
/****************************************************************************/
`define HDMI_FRAME_LOG

`ifdef HDMI_FRAME_LOG
wire        log_wr;
wire [12:0] log_wrAddr;
wire [17:0] log_wrData;   // {rgb444[11:0], glyph[5:0]}
wire [5:0]  log_topGray;

frame_log frame_log_inst (
    .i_clk(clk_100M),
    .i_rst(rst_100),
    .i_us_tick(us_tick),
    .i_hdr_stb(pkt_header_valid_strobe),
    .i_hdr_valid(pkt_header_valid),
    .i_pkt_len(pkt_len),
    .i_pkt_rate(pkt_rate),
    .i_byte_stb(byte_out_strobe),
    .i_byte(byte_out),
    .i_fcs_stb(fcs_out_strobe),
    .i_fcs_ok(fcs_ok),
    .i_cfo_phase(cfo_phase),
    .i_stf_det(short_preamble_detected),
    .i_pwr(mag_sq_avg),
    .i_lts_det(long_preamble_detected),
    .i_lts_metric(sync_long_metric),
    .i_lts_metric_stb(sync_long_metric_stb),
    .i_eq(equalizer),
    .i_eq_stb(equalizer_valid),
    .i_iqbal_wp(iqbal_wp),
    .i_iqbal_eg(iqbal_eg),
    .o_wr(log_wr),
    .o_wrAddr(log_wrAddr),
    .o_wrData(log_wrData),
    .o_topRowGray(log_topGray)
);

wire        vid_hs, vid_vs, vid_de;
wire [7:0]  vid_r, vid_g, vid_b;

/* video reset: hold until the pixel MMCM is up. Deliberately NOT tied to
   fe_valid - the log must stay readable while the ADC link is down. */
(* ASYNC_REG = "true" *) reg [1:0] rst_pix_sync = 2'b11;
always @(posedge clk_65M) rst_pix_sync <= {rst_pix_sync[0], global_rst};
wire rst_pix = rst_pix_sync[1];

/* The character generator reads its font with $readmemh, and both synthesis
   and XSim resolve a relative $readmem path against the TOOL's working
   directory, not the source file's - so the build scripts pass this in (see
   OWIFI_SRC in build_rasbb.tcl). Getting it wrong is silent: the font ROM
   loads as X, synthesis only warns, and the HDMI frame log comes up garbled.
   Same trap as openofdm's LUT_DIR. */
`ifndef OWIFI_SRC
`define OWIFI_SRC "owifi.srcs/sources_1"
`endif

text_screen #(
    .FONT_FILE({`OWIFI_SRC, "/font8x16.mem"})
) text_screen_inst (
    .i_pixClk(clk_65M),
    .i_rst(rst_pix),
    .o_hs(vid_hs), .o_vs(vid_vs), .o_de(vid_de),
    .o_r(vid_r), .o_g(vid_g), .o_b(vid_b),
    .i_wrClk(clk_100M),
    .i_wr(log_wr),
    .i_wrAddr(log_wrAddr),
    .i_wrData(log_wrData),
    .i_topRowGray(log_topGray)
);

/* generics and port mapping match RASM2400's proven instantiation, including
   the {r,b,g} channel order and the inverted aRst_n */
rgb2dvi #(
    .kGenerateSerialClk(1'b0),   // clk_325M comes from Video_clk already
    .kClkRange(1),
    .kRstActiveHigh(1'b1)
) rgb2dvi_inst (
    .TMDS_Clk_p(TMDS_clk_p),
    .TMDS_Clk_n(TMDS_clk_n),
    .TMDS_Data_p(TMDS_data_p),
    .TMDS_Data_n(TMDS_data_n),
    .aRst(rst_pix),
    .aRst_n(~rst_pix),
    .vid_pData({vid_r, vid_b, vid_g}),
    .vid_pVDE(vid_de),
    .vid_pHSync(vid_hs),
    .vid_pVSync(vid_vs),
    .PixelClk(clk_65M),
    .SerialClk(clk_325M)
);
`else
assign TMDS_clk_p = 1'b0;
assign TMDS_clk_n = 1'b1;
assign TMDS_data_p = 3'b000;
assign TMDS_data_n = 3'b111;
`endif

/****************************************************************************/
/* Debug header: everything needed to SEE a frame arrive with a scope.      */
/****************************************************************************/

/* stretch the FCS-OK pulse to ~21ms so an LED/scope can't miss it */
always @(posedge clk_100M) begin
    if (rst_rx) begin
        fcs_stretch <= 21'd0;
        fcs_err_cnt <= 3'd0;
    end
    else begin
        if (fcs_out_strobe && fcs_ok)
            fcs_stretch <= 21'h1FFFFF;
        else if (fcs_stretch != 21'd0)
            fcs_stretch <= fcs_stretch - 21'd1;
        if (fcs_out_strobe && !fcs_ok)
            fcs_err_cnt <= fcs_err_cnt + 3'd1;
    end
end

/* latch the last decoded byte for the header pins */
always @(posedge clk_100M)
    if (byte_out_strobe) last_byte <= byte_out;

assign dbgBitClk   = short_preamble_detected;
assign dbgFrameRdy = sig_valid;
assign dbgIser     = link_ok;
assign dbgQser     = (fcs_stretch != 21'd0);
assign dbgOutI     = { pkt_len[5:0], fe_valid, demod_is_ongoing, state[3:0] };
assign dbgOutQ     = { fcs_err_cnt, byte_out_strobe, last_byte };

endmodule
