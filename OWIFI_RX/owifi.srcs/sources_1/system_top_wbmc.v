//////////////////////////////////////////////////////////////////////////////////
//
// Design Name: OWIFI_RX
// Module Name: system_top_wbmc
// Project Name: RA-Sentinel 802.11 receiver + direction finder
// Engineer: Tobias Weber
// Target Devices: Artix 7, XC7A100T (RASBB U10 + 4ch RASRF2400WBMC front end)
// Description:
//   OWIFI_RX merged with RASPMO's 4-channel front end: one openofdm decode
//   chain fed by the strongest of the four RASANT2400 antennas, plus a
//   per-frame amplitude-comparison direction finder and RASPMO's polar
//   indicator on a 1080p HDMI output next to the station list.
//
//   ARCHITECTURE (what came from where):
//     * 4ch LVDS deserializer, FCLK word rotation, link supervision, DC
//       removal, per-channel iq_balance: RASPMO top.v, verbatim - the
//       hardware-proven WBMC front half, all in the ADC1 120MHz DCLK domain
//       (ADC2's lanes cross through sample_cdc exactly as in RASPMO).
//     * dot11 + signal_watchdog + frame_buffer + spi_frame_if + frame_log +
//       text_screen: OWIFI_RX system_top_rasbb, verbatim - all in the
//       free-running 100MHz domain, samples crossing through an async FIFO
//       (widened 24 -> 96 bits for the four channels).
//     * NEW ant_select.v: per-channel |s|^2 leaky average -> argmax antenna
//       selection with hysteresis, FROZEN while dot11 is mid-frame (state !=
//       S_WAIT_POWER_TRIGGER) so the mux can never switch under a decode.
//       With the four RASANT2400s pointing N/E/S/W, strongest-power IS the
//       correct selection metric; selection settles in ~1us, well inside the
//       8us short preamble.
//     * NEW df_frame.v: on every short-preamble detection the four averaged
//       STF powers become a bearing through df_amp.v's math (log-domain
//       normalisation -> explut -> X=E-W / Y=N-S -> CORDIC atan2), committed
//       into a persistent angle table at frame end (green = FCS ok, red =
//       bad, decaying over a few seconds). polar_view.v renders it unchanged.
//     * WHY AMPLITUDE, NOT PHASE: the four MAX2831 LOs are reference-locked
//       but not LO-locked, and the array is 2.03 lambda in radius - see the
//       header of RASPMO's df_amp.v. Phase is a later refinement.
//     * NEW fast_heal.v (2026-09-24), one per ADC: detects an ISERDES
//       grouping slip within microseconds and re-inits only that receiver's
//       ISERDES (anchor, taps, supervisor and downstream state kept), with
//       that ADC's two channels blanked meanwhile. The 2 s global heal
//       (fe_rst) stays as the backstop. Registers 0x1A..0x1C.
//
//   SCREEN LAYOUT (1920x1080 @ 148.75MHz, RASPMO's proven hdmi_clk):
//     top centre: the OWIFI station list (text_screen windowed at (448,0),
//       char geometry unchanged), capped at 8 stations - 2 header rows +
//       8 list rows = 160px. Rows below stay blank forever (S_FILL blanks
//       them once, the list never paints past MAX_STA).
//     below it: polar DF disc, centred (960,620), R_MAX 324 - dead centre
//       of the band the list leaves free. NOTE polar_view maps amplitude
//       1:1 (255 counts = 255px), so full-scale rays stop short of this
//       rim by ~70px - cosmetic, accepted for the larger graticule.
//   The text window's blank lower rows do overlap the disc region, but
//   text is the LOWEST composite priority and blank cells render black, so
//   the priority mux stays a formality.
//
//   RASPMO's FFTs, waterfalls, spectrum panes and scope are deliberately NOT
//   here - that is what pays for the decode chain (they were 64 of RASPMO's
//   82 BRAM tiles and its whole DSP-side FF budget).
//
// Dependencies:
//   RASPMO repo (referenced by tools/build_wbmc.tcl, never copied):
//     lvds_rx_new.v, adc_sequencer.v, sample_cdc.v, link_supervisor.v,
//     iq_balance.v, dp_ram.v, cordic_vec.v, freqmap.v, polar_view.v,
//     hdmi_clk.v
//   this repo: ant_select.v, df_frame.v, div_combine.v, div_regs.v, fast_heal.v, frame_buffer.v, spi_frame_if.v,
//     text_screen.v (windowed), frame_log.v (BRG column), ovl_box.v (pop-up
//     box, lower right), disp_regs.v (DISP_CTRL), registers.v,
//     conf_reg.v, hdmi/*.vhd, ip/Video_clk.xcix
//   openofdm/openViterbi: dot11 tree, signal_watchdog, Viterbi_decoder
//
// Additional Comments: https://github.com/Tobias-DG3YEV/RA-Sentinel
//
//////////////////////////////////////////////////////////////////////////////////
// Copyright (C) 2026 Tobias Weber
// License: GNU GPL v3
//////////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps

module system_top_wbmc (
    /* 50MHz RASBB system clock */
    input  wire SYS_clk,

    /* ADC1 LVDS (WBMC RX1/RX2 baseband) - RASPMO pinout, bank 35 */
    input  wire ADC_dclk_P, ADC_dclk_N,
    input  wire ADC_fclk_P, ADC_fclk_N,
    input  wire ADC_chA_P,  ADC_chA_N,   // CH1 I
    input  wire ADC_chB_P,  ADC_chB_N,   // CH1 Q
    input  wire ADC_chC_P,  ADC_chC_N,   // CH2 I
    input  wire ADC_chD_P,  ADC_chD_N,   // CH2 Q

    /* ADC2 LVDS (WBMC RX3/RX4 baseband) */
    input  wire ADC2_dclk_P, ADC2_dclk_N,
    input  wire ADC2_fclk_P, ADC2_fclk_N,
    input  wire ADC2_chA_P,  ADC2_chA_N, // CH3 I
    input  wire ADC2_chB_P,  ADC2_chB_N, // CH3 Q
    input  wire ADC2_chC_P,  ADC2_chC_N, // CH4 I
    input  wire ADC2_chD_P,  ADC2_chD_N, // CH4 Q

    /* SPI slave (STM32 HKU is the master, shared flash bus) */
    input  wire SPI_ncs,
    input  wire SPI_sclk,
    input  wire SPI_copi,
    output wire SPI_cipo,

    /* HDMI: polar DF indicator + station list */
    output wire TMDS_clk_p,  TMDS_clk_n,
    output wire [2:0] TMDS_data_p, TMDS_data_n,

    /* SNAPLINK v1 to FPGA2 over the DEBUG bus (JOB-04, SPEC section 5 v0.3).
       The old J5 debug outputs (dbgBitClk & co) are retired: these 27 lines
       now carry the snapshot link. LCLK rides the physical DEBUG_D6 line
       (V14 here, MRCC P-side D15 on U11); data bit 6 takes DEBUG_A0 (T10). */
    output wire        o_snaplink_lclk,    // V14 (DEBUG_D6 line), 20 MHz forwarded
    output wire [23:0] o_snaplink_d,       // DEBUG_Dn, bit 6 on T10 (DEBUG_A0 line)
    output wire        o_snaplink_valid,   // T11 (DEBUG_A1)
    output wire        o_snaplink_aux,     // R12 (DEBUG_A2), driven 0
    input  wire        i_snaplink_ready,   // T13 (DEBUG_A3), from FPGA2

    input  wire Key0,
    input  wire Key1
);

`include "common_params.v"

localparam ADCBITS = 12;
localparam NCH     = 4;

/* Antenna compass map, same convention as RASPMO top.v: channel 0 = North,
   angles increasing clockwise. A wrong map only rotates/mirrors the display. */
localparam CH_N = 0, CH_E = 1, CH_S = 2, CH_W = 3;

/* Per-channel blind adaptive I/Q imbalance correction (same switch as RASPMO).
   MUST stay equal treatment across the aperture - comment out for A/B only. */
`define IQ_CORR

/****************************************************************************/
/* Clocks.                                                                  */
/*   Video_clk IP: 195MHz IDELAYCTRL reference + 120MHz POR/utility clock.  */
/*     (its 65/325MHz legacy video outputs are unused at 1080p)             */
/*   hdmi_clk (RASPMO, proven): 148.75MHz pixel + 743.75MHz TMDS serial.    */
/*   pll_rx: free-running 100MHz, openwifi's native receiver rate.          */
/*                                                                          */
/* pll_rx is a PLLE2, NOT a third MMCM, and that is load-bearing: SYS_clk's */
/* ball E3 sits in clock region X1Y2 and the XC7A100T's column X1 holds     */
/* exactly TWO MMCM sites (X1Y1/X1Y2) - the two video MMCMs take both, and  */
/* a third MMCM behind this pin cannot be legally placed under any          */
/* CLOCK_DEDICATED_ROUTE setting (measured: IO Clock Placer failures with   */
/* default AND BACKBONE). The CMTs' PLL halves in that column are free, the */
/* IOB->PLL dedicated-route rule is satisfied, and 50MHz x20 /10 is integer */
/* math the PLL does exactly.                                               */
/****************************************************************************/
wire clk_120M;
wire clk_195M;
wire clk_pix;
wire clk_serial;
wire mmcm_locked;
wire hdmi_clk_locked;

Video_clk video_clk0 (
    .i_clk_50M(SYS_clk),
    .o_clk_65M(),
    .o_clk_325M(),
    .o_clk_195M(clk_195M),
    .o_clk_120M(clk_120M),
    .reset(1'b0),
    .locked(mmcm_locked)
);

hdmi_clk hdmi_clk0 (
    .i_clk_50M(SYS_clk),
    .o_clk_pix(clk_pix),
    .o_clk_serial(clk_serial),
    .o_locked(hdmi_clk_locked)
);

wire clk_100M;
wire clk_100M_unbuf;
wire clk_20M, clk_20M_unbuf;
wire pll100_fb;
wire pll100_locked;

PLLE2_BASE #(
    .CLKIN1_PERIOD(20.000),   // 50MHz SYS_clk
    .CLKFBOUT_MULT(20),       // VCO 1000MHz
    .DIVCLK_DIVIDE(1),
    .CLKOUT0_DIVIDE(10),      // 100MHz
    .CLKOUT1_DIVIDE(50)       // 20MHz SNAPLINK LCLK (JOB-04)
) pll_rx (
    .CLKIN1(SYS_clk),
    .CLKFBIN(pll100_fb),
    .CLKFBOUT(pll100_fb),
    .CLKOUT0(clk_100M_unbuf),
    .CLKOUT1(clk_20M_unbuf),
    .CLKOUT2(), .CLKOUT3(), .CLKOUT4(), .CLKOUT5(),
    .LOCKED(pll100_locked),
    .PWRDWN(1'b0),
    .RST(1'b0)
);
BUFG bufg_100M (.I(clk_100M_unbuf), .O(clk_100M));
BUFG bufg_20M  (.I(clk_20M_unbuf),  .O(clk_20M));

/****************************************************************************/
/* Power-on reset (gated on BOTH video MMCMs), Key0 glitch-filtered as in   */
/* system_top_rasbb (the raw pad shares the J5 bundle with fast outputs).   */
/****************************************************************************/
reg [4:0] por_ctr = 5'h00;
reg por_rst = 1'b1;
always @(posedge clk_120M) begin
    if (!mmcm_locked || !hdmi_clk_locked) begin
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
/* Deserializer self-heal.                                                  */
/*                                                                          */
/* THE FREEZE THIS FIXES (root-caused 2026-08-08 from the F1/F2 header      */
/* forensics): after minutes-to-hours of operation ADC2's link dies with    */
/* lk2=0, both strobe heartbeats ALIVE, and F2 showing a word like 42F -    */
/* whose EVEN bits (100011) and ODD bits (000111) are each a perfectly      */
/* clean cyclic 3-run of the 20MHz FCLK, but offset by one word position    */
/* AGAINST EACH OTHER. That is an ISERDES internal bit-grouping slip        */
/* between the EVEN/ODD primitive pair: wordsync (CLKDIV) is generated in   */
/* fabric and the ISERDES clocks come straight off the IBUFDS, so their     */
/* phase relation is unconstrained silicon margin - thermal drift can walk  */
/* one primitive of the pair across an internal setup window and slip its   */
/* grouping (UG471: any CLKDIV phase change requires an ISERDES reset).     */
/* No IDELAY tap can undo it (taps move sub-UI sampling, not grouping), so  */
/* the supervisor sweeps all 32 taps forever, and lvds_rx's own re-anchor   */
/* watchdog never fires because the FCLK edge still lands at bitctr 0.      */
/*                                                                          */
/* THE HEAL: if fe_valid stays low for 2 seconds - the DF is dead and the   */
/* sweeps demonstrably cannot fix it - pulse fe_rst, a front-half-only      */
/* reset that re-runs both lvds_rx init FSMs (serdes_rst + re-anchor + CS   */
/* sequencing, identical to power-up, which trains correctly at any         */
/* temperature), the sequencers, the CDC, the rotation decode and the       */
/* supervisors. The 100MHz receiver side just sees fe_valid drop (it was    */
/* down already) and the display/station list are untouched. Recovery is    */
/* ~200ms; a healthy system never triggers (fe_valid low that long only     */
/* happens broken or unplugged, where a 2s retry cadence is harmless).      */
/*                                                                          */
/* The watchdog runs on clk_100M, NOT clk_120M: the free-running PLLE2      */
/* clock is part of the XDC's SYS_clk clock group, so its crossings from    */
/* the DCLK domains are declared asynchronous. clk_120M is the Video_clk    */
/* IP's clock and is NOT captured by that group (the IP's auto-derived      */
/* clocks appear after the XDC's get_clocks evaluates) - a first draft of   */
/* this watchdog on clk_120M put a real timed path on sup_adc2/o_healthy    */
/* -> fe_valid sync and failed timing by -7ns.                              */
/****************************************************************************/
(* keep = "true" *) reg heal_rst_reg  = 1'b0;
(* keep = "true" *) reg stall_rst_reg = 1'b0;   // receiver-stall watchdog, see before iq_capture_inst
wire fe_rst = global_rst | heal_rst_reg | stall_rst_reg;

/****************************************************************************/
/*                                                                          */
/*  4-CHANNEL ADC FRONT HALF - RASPMO top.v, verbatim (minus ramp checkers, */
/*  AGC, FFT). Everything below runs in the ADC1 DCLK domain.               */
/*                                                                          */
/****************************************************************************/
wire [4:0] cal_tap1, cal_tap2;
wire       cal_load1, cal_load2;
wire [4:0] tap_eff1, tap_eff2;      // TAP_OVR 0x19 or the supervisors (see the override block)
wire       load_eff1, load_eff2;
wire [7:0] reanchor_cnt1, reanchor_cnt2;   // lvds_rx FCLK re-anchors (each receiver's own clock)
wire       rx_ready1, rx_ready2;           // lvds_rx init done (each receiver's own clock)
wire       fh1_req_tog, fh2_req_tog;       // fast heal -> lvds_rx ISERDES re-init
wire       fh1_freeze, fh2_freeze;         // fast heal -> link_supervisor
wire       fh1_blank, fh2_blank;           // fast heal -> sample FIFO
wire       sup1_mon, sup2_mon;             // link_supervisor monitoring a good link
wire [15:0] tap_ovr;                       // iq_capture register file (clk_100M)
wire [31:0] lane_tap1, lane_tap2;          // LANE_TAP1 0x12 / LANE_TAP2 0x0F (clk_100M)
wire [23:0] lofs1, lofs2;                  // the same, synced: 4 x signed 6 bit per ADC
wire        lofs_ld1, lofs_ld2;            // reload pulse after an offset change
wire [1:0]  iqb_sel;                       // IQB_CTRL 0x07 (clk_100M)
wire [3:0]  iqb_bypass;
wire        iqb_clear_tog;
wire [31:0] iqb_coef;                      // read-back {w_p, e_g} of channel iqb_sel
wire [1:0]  fh_enable, fh_force_tog;
wire       lvds_dclk, lvds_fclk, lvds_dclk2, lvds_fclk2;
wire       lvds_dclk_buffered;  // BUFG'd ADC1 bit clock - the processing domain
wire       lvds_dclk2_buffered; // BUFG'd ADC2 bit clock - deserialize+CDC only

wire [4*ADCBITS-1:0] adc1_data;
wire [4*ADCBITS-1:0] adc2_data;
wire [ADCBITS-1:0]   adc1_fclk_word;
wire [ADCBITS-1:0]   adc2_fclk_word;

lvds_rx #(.NLANES(4)) lvds_irx0 (
    .i_lvds_dclk_P(ADC_dclk_P),
    .i_lvds_dclk_N(ADC_dclk_N),
    .i_lvds_fclk_P(ADC_fclk_P),
    .i_lvds_fclk_N(ADC_fclk_N),
    .i_lvds_d_P({ADC_chD_P, ADC_chC_P, ADC_chB_P, ADC_chA_P}),
    .i_lvds_d_N({ADC_chD_N, ADC_chC_N, ADC_chB_N, ADC_chA_N}),
    .i_rst(fe_rst),
    .i_ctrlClk(lvds_dclk_buffered),
    .i_data_delay_tap(tap_eff1),
    .i_data_delay_load(load_eff1),
    .i_lane_tap_ofs(lofs1),
    .o_lvds_dclk(lvds_dclk),
    .o_lvds_fclk(lvds_fclk),
    .o_data(adc1_data),
    .o_fclk_word(adc1_fclk_word),
    .i_reinit_tog(fh1_req_tog),
    .o_ready(rx_ready1),
    .o_reanchor_count(reanchor_cnt1)
);

lvds_rx #(.NLANES(4)) lvds_irx1 (
    .i_lvds_dclk_P(ADC2_dclk_P),
    .i_lvds_dclk_N(ADC2_dclk_N),
    .i_lvds_fclk_P(ADC2_fclk_P),
    .i_lvds_fclk_N(ADC2_fclk_N),
    .i_lvds_d_P({ADC2_chD_P, ADC2_chC_P, ADC2_chB_P, ADC2_chA_P}),
    .i_lvds_d_N({ADC2_chD_N, ADC2_chC_N, ADC2_chB_N, ADC2_chA_N}),
    .i_rst(fe_rst),
    .i_ctrlClk(lvds_dclk_buffered),
    .i_data_delay_tap(tap_eff2),
    .i_data_delay_load(load_eff2),
    .i_lane_tap_ofs(lofs2),
    .o_lvds_dclk(lvds_dclk2),
    .o_lvds_fclk(lvds_fclk2),
    .o_data(adc2_data),
    .o_fclk_word(adc2_fclk_word),
    .i_reinit_tog(fh2_req_tog),
    .o_ready(rx_ready2),
    .o_reanchor_count(reanchor_cnt2)
);

BUFG BUFG_lvds_dclk_1 (
    .I(lvds_dclk),
    .O(lvds_dclk_buffered)
);
BUFG BUFG_lvds_dclk_2 (
    .I(lvds_dclk2),
    .O(lvds_dclk2_buffered)
);

/* one IDELAYCTRL per bank; both lvds_rx pin groups live in bank 35 */
IDELAYCTRL IDELAYCTRL0 (
   .RDY(),
   .REFCLK(clk_195M),
   .RST(global_rst)
);

wire adc_frameStrobe;
adc_sequencer adc_sequencer0 (
    .i_lvds_frameClk(lvds_fclk),
    .i_lvds_bitClk(lvds_dclk_buffered),
    .i_fft_lineSync(1'b0),
    .i_rst(fe_rst),
    .o_adc_frameStrobe(adc_frameStrobe),
    .o_fft_frameStrobe(),
    .o_frameCounter(),
    .o_mem_sampleStrobe()
);

wire adc2_frameStrobe;
adc_sequencer adc_sequencer1 (
    .i_lvds_frameClk(lvds_fclk2),
    .i_lvds_bitClk(lvds_dclk2_buffered),
    .i_fft_lineSync(1'b0),
    .i_rst(fe_rst),
    .o_adc_frameStrobe(adc2_frameStrobe),
    .o_fft_frameStrobe(),
    .o_frameCounter(),
    .o_mem_sampleStrobe()
);

/* ADC2 -> ADC1 clock domain crossing (gray-pointer FIFO, one sample latency
   on CH3/CH4 - a constant, harmless to the amplitude DF). */
wire [4*ADCBITS-1:0] adc2_data_s;
wire [ADCBITS-1:0]   adc2_fclk_word_s;
sample_cdc #(.W(5*ADCBITS)) adc2_cdc (
    .i_wclk(lvds_dclk2_buffered),
    .i_wrst(fe_rst),
    .i_wen(adc2_frameStrobe),
    .i_wdata({adc2_fclk_word, adc2_data}),
    .i_rclk(lvds_dclk_buffered),
    .i_rrst(fe_rst),
    .i_ren(adc_frameStrobe),
    .o_rdata({adc2_fclk_word_s, adc2_data_s})
);

wire [ADCBITS-1:0] lane_raw [0:2*NCH-1];
assign lane_raw[0] = adc1_data  [0*ADCBITS +: ADCBITS]; // CH1 I
assign lane_raw[1] = adc1_data  [1*ADCBITS +: ADCBITS]; // CH1 Q
assign lane_raw[2] = adc1_data  [2*ADCBITS +: ADCBITS]; // CH2 I
assign lane_raw[3] = adc1_data  [3*ADCBITS +: ADCBITS]; // CH2 Q
assign lane_raw[4] = adc2_data_s[0*ADCBITS +: ADCBITS]; // CH3 I
assign lane_raw[5] = adc2_data_s[1*ADCBITS +: ADCBITS]; // CH3 Q
assign lane_raw[6] = adc2_data_s[2*ADCBITS +: ADCBITS]; // CH4 I
assign lane_raw[7] = adc2_data_s[3*ADCBITS +: ADCBITS]; // CH4 Q

/* Per-lane word-boundary re-alignment from the decoded FCLK word - see
   RASPMO top.v for the full derivation (SBAS673A Fig. 130). */
localparam ROT_POS = ADCBITS + 1;
localparam [ADCBITS-1:0] FCLK_PAT = {{(ADCBITS/2){1'b0}}, {(ADCBITS/2){1'b1}}};
localparam [3:0] FCLK_PHASE_ADJ = 4'd0;

reg [ADCBITS-1:0] fclk1_cur, fclk1_hist;
reg [ADCBITS-1:0] fclk2_cur, fclk2_hist;
always @(posedge lvds_dclk_buffered) begin
    if (fe_rst) begin
        fclk1_cur <= 0; fclk1_hist <= 0;
        fclk2_cur <= 0; fclk2_hist <= 0;
    end
    else if (adc_frameStrobe) begin
        fclk1_cur <= adc1_fclk_word;   fclk1_hist <= fclk1_cur;
        fclk2_cur <= adc2_fclk_word_s; fclk2_hist <= fclk2_cur;
    end
end

wire [2*ADCBITS-1:0] fclk1_win = {fclk1_hist, fclk1_cur};
wire [2*ADCBITS-1:0] fclk2_win = {fclk2_hist, fclk2_cur};

reg [3:0] fclk1_dec, fclk2_dec;
reg       fclk1_hit, fclk2_hit;
integer fd;
always @* begin
    fclk1_dec = 4'd0; fclk1_hit = 1'b0;
    fclk2_dec = 4'd0; fclk2_hit = 1'b0;
    for (fd = 0; fd < ROT_POS; fd = fd + 1) begin
        if (fclk1_win[fd +: ADCBITS] == FCLK_PAT) begin
            fclk1_dec = fd[3:0] + FCLK_PHASE_ADJ; fclk1_hit = 1'b1;
        end
        else if (fclk1_win[fd +: ADCBITS] == ~FCLK_PAT) begin
            fclk1_dec = ((fd >= ADCBITS/2) ? fd[3:0] - ADCBITS/2
                                           : fd[3:0] + ADCBITS/2) + FCLK_PHASE_ADJ;
            fclk1_hit = 1'b1;
        end
        if (fclk2_win[fd +: ADCBITS] == FCLK_PAT) begin
            fclk2_dec = fd[3:0] + FCLK_PHASE_ADJ; fclk2_hit = 1'b1;
        end
        else if (fclk2_win[fd +: ADCBITS] == ~FCLK_PAT) begin
            fclk2_dec = ((fd >= ADCBITS/2) ? fd[3:0] - ADCBITS/2
                                           : fd[3:0] + ADCBITS/2) + FCLK_PHASE_ADJ;
            fclk2_hit = 1'b1;
        end
    end
end

reg [3:0] rot1_cur, rot2_cur;
reg [3:0] rot1_cand, rot2_cand;
reg [3:0] rot1_cnt,  rot2_cnt;
reg [7:0] rot_change_count;
always @(posedge lvds_dclk_buffered) begin
    if (fe_rst) begin
        rot1_cur <= 4'd0; rot1_cand <= 4'd0; rot1_cnt <= 4'd0;
        rot2_cur <= 4'd0; rot2_cand <= 4'd0; rot2_cnt <= 4'd0;
        rot_change_count <= 8'd0;
    end
    else if (adc_frameStrobe) begin
        if (fclk1_hit) begin
            if (fclk1_dec == rot1_cur)
                rot1_cnt <= 4'd0;
            else if (fclk1_dec == rot1_cand) begin
                if (rot1_cnt == 4'd15) begin
                    rot1_cur <= fclk1_dec;
                    rot1_cnt <= 4'd0;
                    rot_change_count <= rot_change_count + 8'd1;
                end
                else rot1_cnt <= rot1_cnt + 4'd1;
            end
            else begin
                rot1_cand <= fclk1_dec;
                rot1_cnt  <= 4'd0;
            end
        end
        if (fclk2_hit) begin
            if (fclk2_dec == rot2_cur)
                rot2_cnt <= 4'd0;
            else if (fclk2_dec == rot2_cand) begin
                if (rot2_cnt == 4'd15) begin
                    rot2_cur <= fclk2_dec;
                    rot2_cnt <= 4'd0;
                    rot_change_count <= rot_change_count + 8'd1;
                end
                else rot2_cnt <= rot2_cnt + 4'd1;
            end
            else begin
                rot2_cand <= fclk2_dec;
                rot2_cnt  <= 4'd0;
            end
        end
    end
end

reg  [ADCBITS-1:0] lane_cur  [0:2*NCH-1];
reg  [ADCBITS-1:0] lane_hist [0:2*NCH-1];
wire [3:0]         rot_base  [0:2*NCH-1];
wire [ADCBITS-1:0] lane_sample [0:2*NCH-1];

genvar rl;
generate for (rl = 0; rl < 2*NCH; rl = rl + 1) begin : gen_rot
    assign rot_base[rl] = (rl < NCH) ? rot1_cur : rot2_cur;
    always @(posedge lvds_dclk_buffered) begin
        if (fe_rst) begin
            lane_cur[rl]  <= {ADCBITS{1'b0}};
            lane_hist[rl] <= {ADCBITS{1'b0}};
        end
        else if (adc_frameStrobe) begin
            lane_cur[rl]  <= lane_raw[rl];
            lane_hist[rl] <= lane_cur[rl];
        end
    end
    wire [2*ADCBITS-1:0] rot_pair = {lane_hist[rl], lane_cur[rl]};
    assign lane_sample[rl] = rot_pair[rot_base[rl] +: ADCBITS];
end
endgenerate

/* IDELAY tap override for eye scans (TAP_OVR 0x19, 2026-09-24): the register
   lives in clk_100M; the IDELAY control is in ADC1's DCLK domain. The word is
   2FF-synced and taken only when two consecutive samples agree, so enable and
   tap bits apply together. A load pulse goes out on every change while an
   override is on AND once when it is released - that one hands the IDELAYs
   back to the supervisor's tap. While an ADC's override is on its supervisor
   is frozen (no blind sweeps against a pinned IDELAY), its link counts as
   healthy for fe_valid, the stall watchdog pauses, and its fast heal is off. */
(* ASYNC_REG = "true" *) reg [15:0] tovr_s0 = 16'd0, tovr_s1 = 16'd0;
reg [15:0] tovr_q = 16'd0, tovr_d = 16'd0;
reg        tovr_ld1 = 1'b0, tovr_ld2 = 1'b0;
always @(posedge lvds_dclk_buffered) begin
    tovr_s0 <= tap_ovr; tovr_s1 <= tovr_s0;
    if (tovr_s1 == tovr_s0) tovr_q <= tovr_s1;
    tovr_d <= tovr_q;
    tovr_ld1 <= (tovr_q[5]  & (tovr_q[5:0]  != tovr_d[5:0]))  | (~tovr_q[5]  & tovr_d[5]);
    tovr_ld2 <= (tovr_q[13] & (tovr_q[13:8] != tovr_d[13:8])) | (~tovr_q[13] & tovr_d[13]);
end
wire       ovr1 = tovr_q[5], ovr2 = tovr_q[13];
assign tap_eff1  = ovr1 ? tovr_q[4:0]  : cal_tap1;
assign tap_eff2  = ovr2 ? tovr_q[12:8] : cal_tap2;
assign load_eff1 = tovr_ld1 | (~ovr1 & cal_load1) | lofs_ld1;
assign load_eff2 = tovr_ld2 | (~ovr2 & cal_load2) | lofs_ld2;

/* Per-lane IDELAY offsets (LANE_TAP1 0x12 / LANE_TAP2 0x0F, 2026-10-06). The
   supervisor centres one tap on FCLK; a data lane whose board skew puts its
   ODD-half eye elsewhere gets a signed offset on top (lvds_rx i_lane_tap_ofs,
   saturated 0..31). Main WBMC 2026-10-05: ADC1 chD (ch1 Q) clean only at taps
   0..5 with the supervisor at 16 -> default -14 for that lane. Synced like
   TAP_OVR (2FF + two equal samples); a change reloads that ADC's IDELAYs with
   the current common tap. */
(* ASYNC_REG = "true" *) reg [47:0] lofs_s0 = 48'd0, lofs_s1 = 48'd0;
reg [47:0] lofs_q = 48'd0, lofs_d = 48'd0;
reg        lofs_ld1_r = 1'b0, lofs_ld2_r = 1'b0;
always @(posedge lvds_dclk_buffered) begin
    lofs_s0 <= {lane_tap2[29:24], lane_tap2[21:16], lane_tap2[13:8], lane_tap2[5:0],
                lane_tap1[29:24], lane_tap1[21:16], lane_tap1[13:8], lane_tap1[5:0]};
    lofs_s1 <= lofs_s0;
    if (lofs_s1 == lofs_s0) lofs_q <= lofs_s1;
    lofs_d <= lofs_q;
    lofs_ld1_r <= (lofs_q[23:0]  != lofs_d[23:0]);
    lofs_ld2_r <= (lofs_q[47:24] != lofs_d[47:24]);
end
assign lofs1 = lofs_q[23:0];
assign lofs2 = lofs_q[47:24];
assign lofs_ld1 = lofs_ld1_r;
assign lofs_ld2 = lofs_ld2_r;

/* Link supervisors: IDELAY tap ownership + automatic retraining, driven by
   the always-on FCLK decode as the health metric. */
wire link_ok1, link_ok2;
wire [7:0] retrain_count1, retrain_count2;

link_supervisor sup_adc1 (
    .i_clk(lvds_dclk_buffered),
    .i_rst(fe_rst),
    .i_ce(adc_frameStrobe),
    .i_hit(fclk1_hit),
    .o_tap(cal_tap1),
    .o_load(cal_load1),
    .o_healthy(link_ok1),
    .o_retrain_count(retrain_count1),
    .i_freeze(fh1_freeze | ovr1),
    .o_mon(sup1_mon)
);

link_supervisor sup_adc2 (
    .i_clk(lvds_dclk_buffered),
    .i_rst(fe_rst),
    .i_ce(adc_frameStrobe),
    .i_hit(fclk2_hit),
    .o_tap(cal_tap2),
    .o_load(cal_load2),
    .o_healthy(link_ok2),
    .o_retrain_count(retrain_count2),
    .i_freeze(fh2_freeze | ovr2),
    .o_mon(sup2_mon)
);

/****************************************************************************/
/* Fast link heal (2026-09-24), one fast_heal per ADC - see fast_heal.v.    */
/* The ISERDES of lvds_rx_new run on a fabric-made CLKDIV and their bit     */
/* grouping slips now and then (1-2/min on ADC2, ADC2 first in 35/35 heals).*/
/* Detection is on the FCLK decode of that ADC (T1: 64 consecutive misses,  */
/* T2: a clean hit at the wrong position / the rotation moving), the cure   */
/* is that receiver's ISERDES reset+CE sequence alone (lvds_rx i_reinit_tog,*/
/* 64-cycle delay, anchor untouched), with the supervisor frozen and the    */
/* ADC's two channels zeroed at the sample FIFO meanwhile. Nothing else is  */
/* reset: taps, rotation decode, sequencers, CDC, DC/IQ state, fe_valid.    */
/* After CAP failed attempts it gives up and the old path (supervisor       */
/* re-sweep, then the 2 s global heal) takes over. FH_CTRL 0x1A enables    */
/* (default on) and forces an attempt; FH_STAT1/2 0x1B/0x1C count.          */
/****************************************************************************/
(* ASYNC_REG = "true" *) reg [1:0] fhe_s0 = 2'b11, fhe_s1 = 2'b11;
(* ASYNC_REG = "true" *) reg [2:0] fhf1_s = 3'd0, fhf2_s = 3'd0;
/* receiver re-anchor events: bit 0 of each lvds_rx's re-anchor counter
   toggles once per re-anchor (receiver's own clock) */
(* ASYNC_REG = "true" *) reg [2:0] ra1_sy = 3'd0, ra2_sy = 3'd0;
always @(posedge lvds_dclk_buffered) begin
    fhe_s0 <= fh_enable; fhe_s1 <= fhe_s0;
    fhf1_s <= {fhf1_s[1:0], fh_force_tog[0]};
    fhf2_s <= {fhf2_s[1:0], fh_force_tog[1]};
    ra1_sy <= {ra1_sy[1:0], reanchor_cnt1[0]};
    ra2_sy <= {ra2_sy[1:0], reanchor_cnt2[0]};
end
wire [7:0] fh1_att, fh1_ok, fh1_gu, fh1_t2;
wire [7:0] fh2_att, fh2_ok, fh2_gu, fh2_t2;
wire [2:0] fh1_st, fh2_st;
wire [3:0] fh1_ref, fh2_ref;

fast_heal fh_adc1 (
    .i_clk(lvds_dclk_buffered),
    .i_rst(fe_rst),
    .i_rst_cnt(global_rst),
    .i_ce(adc_frameStrobe),
    .i_enable(fhe_s1[0] & ~ovr1),
    .i_force(fhf1_s[2] ^ fhf1_s[1]),
    .i_hit(fclk1_hit),
    .i_dec(fclk1_dec),
    .i_rot(rot1_cur),
    .i_mon(sup1_mon),
    .i_ready(rx_ready1),
    .i_reanchor(ra1_sy[2] ^ ra1_sy[1]),
    .o_req_tog(fh1_req_tog),
    .o_freeze(fh1_freeze),
    .o_blank(fh1_blank),
    .o_attempts(fh1_att),
    .o_success(fh1_ok),
    .o_giveups(fh1_gu),
    .o_t2(fh1_t2),
    .o_state(fh1_st),
    .o_rot_ref(fh1_ref)
);

fast_heal fh_adc2 (
    .i_clk(lvds_dclk_buffered),
    .i_rst(fe_rst),
    .i_rst_cnt(global_rst),
    .i_ce(adc_frameStrobe),
    .i_enable(fhe_s1[1] & ~ovr2),
    .i_force(fhf2_s[2] ^ fhf2_s[1]),
    .i_hit(fclk2_hit),
    .i_dec(fclk2_dec),
    .i_rot(rot2_cur),
    .i_mon(sup2_mon),
    .i_ready(rx_ready2),
    .i_reanchor(ra2_sy[2] ^ ra2_sy[1]),
    .o_req_tog(fh2_req_tog),
    .o_freeze(fh2_freeze),
    .o_blank(fh2_blank),
    .o_attempts(fh2_att),
    .o_success(fh2_ok),
    .o_giveups(fh2_gu),
    .o_t2(fh2_t2),
    .o_state(fh2_st),
    .o_rot_ref(fh2_ref)
);

/****************************************************************************/
/* Per-channel DC removal + adaptive I/Q balance (RASPMO gen_ch, minus the  */
/* AGC/level-readout machinery that belonged to the spectrum display).      */
/****************************************************************************/
localparam DC_K = 15;

wire signed [ADCBITS-1:0] hp_i [0:NCH-1];
wire signed [ADCBITS-1:0] hp_q [0:NCH-1];
/* CH1's converged corrector coefficients for the frame-log header (each
   channel has its own corrector; one representative pair is displayed) */
wire [15:0] iqbal_wp, iqbal_eg;
wire [15:0] wp_all [0:NCH-1];   // every channel's coefficients, for IQB_CTRL 0x07
wire [15:0] eg_all [0:NCH-1];

/* IQB_CTRL (0x07, 2026-10-06): bypass per channel and a restart of all
   correctors, from the clk_100M register file into the ADC1 DCLK domain. */
(* ASYNC_REG = "true" *) reg [4:0] iqb_s0 = 5'd0, iqb_s1 = 5'd0;
reg       iqb_clr_d = 1'b0;
reg       iqb_clr = 1'b0;
always @(posedge lvds_dclk_buffered) begin
    iqb_s0    <= {iqb_clear_tog, iqb_bypass};
    iqb_s1    <= iqb_s0;
    iqb_clr_d <= iqb_s1[4];
    iqb_clr   <= iqb_s1[4] ^ iqb_clr_d;
end

genvar c;
generate for (c = 0; c < NCH; c = c + 1) begin : gen_ch

    wire signed [ADCBITS-1:0] raw_i = lane_sample[2*c];
    wire signed [ADCBITS-1:0] raw_q = lane_sample[2*c+1];

    reg signed [ADCBITS+DC_K-1:0] dc_acc_i, dc_acc_q;
    wire signed [ADCBITS-1:0] dc_i = dc_acc_i >>> DC_K;
    wire signed [ADCBITS-1:0] dc_q = dc_acc_q >>> DC_K;

    always @(posedge lvds_dclk_buffered) begin
        if (fe_rst) begin
            dc_acc_i <= 0;
            dc_acc_q <= 0;
        end
        else if (adc_frameStrobe) begin
            dc_acc_i <= dc_acc_i + (raw_i - dc_i);
            dc_acc_q <= dc_acc_q + (raw_q - dc_q);
        end
    end

    wire signed [ADCBITS:0] hp_i_full = raw_i - dc_i;
    wire signed [ADCBITS:0] hp_q_full = raw_q - dc_q;
    reg signed [ADCBITS-1:0] hp_i_r, hp_q_r;
    always @(posedge lvds_dclk_buffered) begin
        if (fe_rst) begin
            hp_i_r <= 0;
            hp_q_r <= 0;
        end
        else if (adc_frameStrobe) begin
            hp_i_r <=
                (hp_i_full > $signed(13'sd2047))  ? $signed(12'sd2047)  :
                (hp_i_full < $signed(-13'sd2048)) ? $signed(-12'sd2048) : hp_i_full[ADCBITS-1:0];
            hp_q_r <=
                (hp_q_full > $signed(13'sd2047))  ? $signed(12'sd2047)  :
                (hp_q_full < $signed(-13'sd2048)) ? $signed(-12'sd2048) : hp_q_full[ADCBITS-1:0];
        end
    end
`ifdef IQ_CORR
    wire signed [ADCBITS-1:0] bal_i, bal_q;
    wire [15:0] wp_c, eg_c;
    iq_balance iq_bal (
        .i_clk(lvds_dclk_buffered),
        .i_rst(fe_rst | iqb_clr),
        .i_ce(adc_frameStrobe),
        .i_i(hp_i_r),
        .i_q(hp_q_r),
        .i_bypass(iqb_s1[c]),
        .o_i(bal_i),
        .o_q(bal_q),
        .o_wp(wp_c),
        .o_eg(eg_c)
    );
    assign hp_i[c] = bal_i;
    assign hp_q[c] = bal_q;
    assign wp_all[c] = wp_c;
    assign eg_all[c] = eg_c;
    if (c == 0) begin : gen_iqtap
        assign iqbal_wp = wp_c;
        assign iqbal_eg = eg_c;
    end
`else
    assign hp_i[c] = hp_i_r;
    assign hp_q[c] = hp_q_r;
    assign wp_all[c] = 16'd0;
    assign eg_all[c] = 16'd0;
    if (c == 0) begin : gen_iqtap
        assign iqbal_wp = 16'd0;
        assign iqbal_eg = 16'd0;
    end
`endif
end
endgenerate

/* IQB_CTRL read-back: the selected channel's coefficients, 2FF into clk_100M.
   Quasi-static values; a read during fast adaptation may be torn by an LSB. */
(* ASYNC_REG = "true" *) reg [31:0] iqb_coef_s0 = 32'd0, iqb_coef_s1 = 32'd0;
always @(posedge clk_100M) begin
    iqb_coef_s0 <= {wp_all[iqb_sel], eg_all[iqb_sel]};
    iqb_coef_s1 <= iqb_coef_s0;
end
assign iqb_coef = iqb_coef_s1;

/****************************************************************************/
/* Sample CDC into the receiver domain: all four channels in one word, so   */
/* they can never skew against each other in the crossing. 20MHz writes,    */
/* drained at 100MHz - the FIFO idles nearly empty.                         */
/****************************************************************************/
wire fe_valid = (link_ok1 | ovr1) & (link_ok2 | ovr2);

wire        smp_empty;
wire [95:0] smp_dout_raw;
wire        smp_strobe_raw = ~smp_empty;

xpm_fifo_async #(
    .FIFO_WRITE_DEPTH(16),
    .WRITE_DATA_WIDTH(96),
    .READ_DATA_WIDTH(96),
    .READ_MODE("fwft"),
    .FIFO_READ_LATENCY(0),
    .CDC_SYNC_STAGES(2),
    .FIFO_MEMORY_TYPE("distributed")
) smp_fifo (
    .rst(fe_rst),
    .wr_clk(lvds_dclk_buffered),
    .wr_en(adc_frameStrobe & fe_valid),
    /* a fast heal zeroes only its own ADC's two channels (never wr_en: the
       healthy ADC keeps streaming and the ADC_SKEW history stays aligned) */
    .din({fh2_blank ? 48'd0 : {hp_i[3], hp_q[3], hp_i[2], hp_q[2]},
          fh1_blank ? 48'd0 : {hp_i[1], hp_q[1], hp_i[0], hp_q[0]}}),
    .rd_clk(clk_100M),
    .rd_en(~smp_empty),
    .dout(smp_dout_raw),
    .empty(smp_empty),
    .full(), .almost_full(), .almost_empty(), .data_valid(), .dbiterr(),
    .overflow(), .prog_empty(), .prog_full(), .rd_data_count(), .rd_rst_busy(),
    .sbiterr(), .underflow(), .wr_ack(), .wr_data_count(), .wr_rst_busy(),
    .injectdbiterr(1'b0), .injectsbiterr(1'b0), .sleep(1'b0)
);

/* ADC1/ADC2 sample alignment (2026-09-24). With one signal split into J2
   and J3, ch2 (ADC2) lagged ch1 (ADC1) by exactly 2 instants in every frame
   (cross-ADC coherence 0.07 at lag 0, 0.72 at lag 2): the ADC2 lanes reach
   this FIFO two samples later than ADC1's (sample_cdc + word rotation). Every
   consumer below (dot11 mux, ant_select, df_frame powers, iq_capture and
   phase_cmp) takes the ALIGNED stream: ch0/ch1 delayed by ADC_SKEW[2:0]
   instants and ch2/ch3 by ADC_SKEW[6:4] (register 0x17, default 2 / 0). One
   clock of latency, identical for all four channels.
   2026-09-30: the aligned stream is smp_al; the consumers take smp_dout /
   smp_strobe, which is smp_al after the diversity combiner's delay line
   (div_combine below, 255 instants). */
reg  [95:0] smp_hist [0:7];
reg  [95:0] smp_al;
reg         smp_al_strobe;
wire [95:0] smp_dout;
wire        smp_strobe;
wire [7:0]  adc_skew;
integer     sh;
wire [95:0] smp_w_hi = (adc_skew[6:4] == 3'd0) ? smp_dout_raw : smp_hist[adc_skew[6:4] - 3'd1];
wire [95:0] smp_w_lo = (adc_skew[2:0] == 3'd0) ? smp_dout_raw : smp_hist[adc_skew[2:0] - 3'd1];
always @(posedge clk_100M) begin
    smp_al_strobe <= smp_strobe_raw & ~fe_rst;
    if (smp_strobe_raw) begin
        smp_hist[0] <= smp_dout_raw;
        for (sh = 1; sh < 8; sh = sh + 1) smp_hist[sh] <= smp_hist[sh - 1];
        smp_al <= { smp_w_hi[95:48], smp_w_lo[47:0] };
    end
end

/****************************************************************************/
/* Receiver-domain resets (system_top_rasbb pattern).                       */
/****************************************************************************/
(* ASYNC_REG = "true" *) reg [1:0] fe_valid_sync = 2'b00;
always @(posedge clk_100M) fe_valid_sync <= {fe_valid_sync[0], fe_valid};

(* ASYNC_REG = "true" *) reg [1:0] rst_rx_sync = 2'b11;
always @(posedge clk_100M)
    rst_rx_sync <= {rst_rx_sync[0], global_rst | ~pll100_locked};

wire rst_100 = rst_rx_sync[1];
wire rst_rx  = rst_100 | ~fe_valid_sync[1];

/* the self-heal watchdog itself - see the fe_rst block up top for the why
   and for why it lives on clk_100M. It watches fe_valid_sync above; the
   pulse is 128 cycles (~1.3us) so every dclk-domain consumer samples it
   many times over. */
localparam HEAL_CYCLES = 28'd199_999_999;   // 2s at 100MHz
reg [27:0] dead_ctr   = 28'd0;
reg [6:0]  heal_pulse = 7'd0;
reg [7:0]  heal_cnt   = 8'd0;   // lifetime heals, header "HL:" field - the
                                // one-glance answer to "did the watchdog
                                // fire, or did the link recover on its own?"
always @(posedge clk_100M) begin
    if (rst_100) begin
        dead_ctr     <= 28'd0;
        heal_pulse   <= 7'd0;
        heal_rst_reg <= 1'b0;
        heal_cnt     <= 8'd0;
    end
    else if (heal_pulse != 7'd0) begin
        heal_pulse   <= heal_pulse - 7'd1;
        heal_rst_reg <= 1'b1;
        dead_ctr     <= 28'd0;
    end
    else begin
        heal_rst_reg <= 1'b0;
        if (fe_valid_sync[1])
            dead_ctr <= 28'd0;
        else if (dead_ctr == HEAL_CYCLES) begin
            dead_ctr   <= 28'd0;
            heal_pulse <= 7'd127;
            heal_cnt   <= heal_cnt + 8'd1;
        end
        else
            dead_ctr <= dead_ctr + 28'd1;
    end
end

/****************************************************************************/
/* Antenna selection: per-channel power average -> argmax with hysteresis,  */
/* frozen while dot11 is anywhere but S_WAIT_POWER_TRIGGER.                 */
/****************************************************************************/
localparam PWRW = 25;

wire [4:0] state;          // dot11 state, declared ahead of its instance
wire       ant_freeze = (state != S_WAIT_POWER_TRIGGER);

wire [1:0]          ant_sel;
wire [NCH*PWRW-1:0] ant_pwr;

ant_select #(
    .NCH(NCH),
    .ADCBITS(ADCBITS),
    .PWRW(PWRW),
    .AVG_SHIFT(4)          // ~16-sample leaky average: inside the STF window
) ant_select_inst (
    .i_clk(clk_100M),
    .i_rst(rst_rx),
    .i_strobe(smp_strobe),
    .i_iq(smp_dout),
    .i_freeze(ant_freeze),
    .o_sel(ant_sel),
    .o_pwr(ant_pwr)
);

/* Receiver noise floor per channel (2026-10-03, noise_floor.v): the variance
   of quiet stretches - no frame decoding, lowest total of each 0.21 s period -
   for tracking the MAX2831 gain drift without a transmitter. NF_CTRL 0x6E,
   NF_DATA 0x6F. Same samples as ant_select; global reset so a receiver reset
   does not clear its settings. */
noise_floor #(
    .NCH(NCH),
    .ADCBITS(ADCBITS),
    .ADDR(7'h6E)
) noise_floor_inst (
    .i_clk(clk_100M),
    .i_rst(rst_100),
    .i_strobe(smp_strobe),
    .i_iq(smp_dout),
    /* "idle" = no frame being decoded: S_WAIT_POWER_TRIGGER or S_SYNC_SHORT.
       With the trigger near the noise, noise alone flips WAIT <-> SYNC_SHORT
       every few tens of us; gating on WAIT only left ~6 % of the blocks and
       kept just those where the detector's channel ran low - a selection
       bias on that channel (2026-10-03). Only a detected short preamble
       (S_SYNC_LONG on) excludes a block now; a real frame's start inside a
       block raises its total and fails the selection anyway. A link down
       holds dot11 in reset (= WAIT), hence !rst_rx. */
    .i_idle(((state == S_WAIT_POWER_TRIGGER) || (state == S_SYNC_SHORT)) && !rst_rx),
    .i_SPI_addr(SPI_reg_addr),
    .i_SPI_wrStrobe(SPI_reg_wrStrobe),
    .i_SPIdata(SPI_reg_wrData),
    .o_SPIdata(SPI_reg_rdData)
);

/* Diversity combiner (2026-09-30, div_combine.v). It delays all four
   channels by 255 instants (smp_dout / smp_strobe, what every consumer
   takes) and hands the decoder either the maximum-ratio combination of the
   four (DIV_CTRL 0x1F bit 0 = 1) or the selected channel as before (0, the
   default). The weights are measured on the undelayed stream and hold still
   from the short-preamble detect to the end of the frame. Unlike
   ant_select's freeze they keep following the estimate in S_SYNC_SHORT: the
   power trigger also fires on noise, and weights frozen there would be
   noise weights. By the time a frame's preamble reaches the decoder the
   estimator has had 255 instants of it, so they no longer move anyway. */
wire               div_freeze = (state != S_WAIT_POWER_TRIGGER) && (state != S_SYNC_SHORT);
wire signed [11:0] sel_i_r, sel_q_r;
wire               smp_strobe_d;
wire               div_enable;
wire [95:0]        div_weights;
wire [1:0]         div_ref;
wire               div_half;
wire [15:0]        div_sat_count, div_upd_count;

div_combine #(
    .DLOG2(8),
    .AVG_SHIFT(6)
) div_combine_inst (
    .i_clk(clk_100M),
    .i_rst(rst_rx),
    .i_strobe(smp_al_strobe),
    .i_iq(smp_al),
    .i_enable(div_enable),
    .i_sel(ant_sel),
    .i_freeze(div_freeze),
    .o_strobe(smp_strobe),
    .o_iq(smp_dout),
    .o_rx_strobe(smp_strobe_d),
    .o_rx_i(sel_i_r),
    .o_rx_q(sel_q_r),
    .o_weights(div_weights),
    .o_ref(div_ref),
    .o_half(div_half),
    .o_sat_count(div_sat_count),
    .o_upd_count(div_upd_count)
);

/* 12 -> 16 bit: openofdm was tuned for full-scale 16-bit I/Q (AD9361) */
wire [31:0] sample_in = { {sel_i_r, 4'b0000}, {sel_q_r, 4'b0000} };

/****************************************************************************/
/* SPI port (STM32H743 master) - frame read-out + config registers.        */
/* Identical to system_top_rasbb; see there for the shared-flash-bus rules. */
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
/* Receiver: dot11 + watchdog (system_top_rasbb, verbatim).                 */
/****************************************************************************/
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
    .i_iq_valid(smp_strobe_d),
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
    .i_sample_in_strobe(smp_strobe_d),
    .i_soft_decoding(1'b1),
    .i_force_ht_smoothing(1'b0),
    .i_disable_all_smoothing(1'b0),
    .i_fft_win_shift(4'b1),

    .o_demod_is_ongoing(demod_is_ongoing),
    .o_short_preamble_detected(short_preamble_detected),
    .o_phase_offset(cfo_phase),
    .o_cfo_fine(cfo_fine),
    .o_fs_cpe_sum(fs_cpe_sum),
    .o_fs_cpe_sq_sum(fs_cpe_sq),
    .o_fs_evm_sum(fs_evm_sum),
    .o_fs_evm_cnt(fs_evm_cnt),
    .o_fs_nsym(fs_nsym),
    .o_fs_peg(fs_peg),
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
/* Frame delivery to the STM32 (system_top_rasbb, verbatim).                */
/****************************************************************************/
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
    .ADDR_BITS(15),
    .DESC_BITS(4)
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
    .i_link_ok(link_ok1),      // retained meaning: primary ADC link health
    .i_fe_valid(fe_valid_sync[1]),
    .i_demod_ongoing(demod_is_ongoing),
    .i_retrain_count(retrain_count1),
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
/* IQ snapshot capture (doc/iq_capture/SPEC.md, JOB-03): 4 slots x 1024      */
/* instants of all four channels at the 96-bit tap, armed by the STF        */
/* detect, kept on MAC match / pass-all (/ FCS), registers 0x10..0x71 on    */
/* the SPI config bus. The read-out port feeds snaplink_tx (JOB-04); until  */
/* that exists a drain stub consumes every snapshot immediately, so         */
/* SENT_COUNT and RD_XOR (0x6C / 0x71) show the block working on air.       */
/****************************************************************************/
wire [575:0] cap_rd_desc;
/* dot11 frame statistics (frame_stats.v) -> descriptor v2 bytes 52..71 */
wire [31:0]  fs_cpe_sum, fs_cpe_sq, fs_evm_sum, fs_peg;
wire [15:0]  fs_evm_cnt, fs_nsym;
wire [15:0]  cfo_fine;          // sync_short's CFO estimate before /16
wire         cap_rd_valid, cap_rd_ready, cap_rd_inst_valid, cap_rd_last;
wire [95:0]  cap_rd_inst;
wire         cap_enabled, cap_armed;
wire [15:0]  cap_ph1_meta;
wire         cap_ph_meta_valid;
wire         cap_mac_hit;       // the frame in flight has a source MAC of the filter list (display solo mode)
wire [47:0] cap_mac0;              // capture MAC filter slot 0: the pinned station (DISP_CTRL b3)
wire        cap_mac0_en;
wire [8:0]   mark_ang;
wire         mark_ok;
wire [15:0]  mark_cnt, cap_ph_cal;
wire [8:0]   mark_raw, mark_brg;
wire [31:0]  gain_trim;
wire [2:0]   cap_used;
wire [191:0] diag_bus;          // 0x7A..0x7F, built next to LINK_DBG below
wire [15:0]  df_mode;           // 0x1D DF_MODE -> df_frame (pattern table on/off, window)
wire [31:0]  df_stat;           // 0x1E DF_STAT <- df_frame
reg  [31:0]  fh1_stat = 32'd0, fh2_stat = 32'd0;   // 0x1B / 0x1C, clk_100M
reg  [5:0]   fh_st = 6'd0;                         // 0x1A state fields
reg  [15:0]  fh_rot = 16'd0;                       // 0x1A rotation / reference fields

/* Receiver-stall watchdog (JOB-07, 2026-09-19). On air the front half can
   slip into a state where fe_valid stays HIGH but the samples are garbage:
   dot11 then sees no preamble for minutes (TRIG_COUNT frozen at ~0/s while
   the front end reports strong RSSI) until the link finally dies and the
   fe_valid watchdog above heals it - 13 minutes in the 10:57 event. On any
   real channel the STF detector arms hundreds of times per second (DSSS
   beacons alone trigger it), so "no short_preamble_detected for 10 s while
   fe_valid is high" is a safe stall criterion: it pulses the same fe_rst.
   A truly silent channel would re-train the deserializer every 10 s, ~200 ms
   dead time each, which is harmless. Both counters go to the capture block's
   register file (HEAL_COUNT 0x72, STALL_COUNT 0x73, SPEC v0.4 s4). */
/* v0.4b (12:50): criterion is a RATE, not silence. In the 12:08 stall the
   garbage samples still produced ~1.5 false STF detects per second, which
   kept resetting a "10 s without STF" timer and delayed the heal by 4 min;
   a healthy channel gives >= 1000 detects per 10 s. So: fewer than 32 STF
   rising edges in a 10 s window while fe_valid is high -> fe_rst. */
localparam STALL_CYCLES = 30'd999_999_999;   // 10 s at 100 MHz
localparam STALL_MIN_STF = 8'd32;
reg [29:0] stall_ctr   = 30'd0;
reg [7:0]  stall_stf   = 8'd0;               // STF edges seen in this window (saturating)
reg        stf_d_wd    = 1'b0;
reg [6:0]  stall_pulse = 7'd0;
reg [7:0]  stall_cnt   = 8'd0;
always @(posedge clk_100M) begin
    stf_d_wd <= short_preamble_detected;
    if (rst_100) begin
        stall_ctr <= 30'd0; stall_stf <= 8'd0; stall_pulse <= 7'd0; stall_rst_reg <= 1'b0; stall_cnt <= 8'd0;
    end
    else if (stall_pulse != 7'd0) begin
        stall_pulse   <= stall_pulse - 7'd1;
        stall_rst_reg <= 1'b1;
        stall_ctr     <= 30'd0;
        stall_stf     <= 8'd0;
    end
    else begin
        stall_rst_reg <= 1'b0;
        if (short_preamble_detected & ~stf_d_wd & (stall_stf != 8'd255)) stall_stf <= stall_stf + 8'd1;
        if (!fe_valid_sync[1] || tap_ovr[5] || tap_ovr[13]) begin
            stall_ctr <= 30'd0; stall_stf <= 8'd0;          // the fe_valid watchdog owns this case;
        end                                                 // eye scans (TAP_OVR) garble on purpose
        else if (stall_ctr == STALL_CYCLES) begin
            stall_ctr <= 30'd0;
            if (stall_stf < STALL_MIN_STF) begin
                stall_pulse <= 7'd127;
                stall_cnt   <= stall_cnt + 8'd1;
            end
            stall_stf <= 8'd0;
        end
        else stall_ctr <= stall_ctr + 30'd1;
    end
end

iq_capture #(
    .NSLOT(4), .NSAMP_MAX(1024), .SLOT_W(2), .PTR_W(10),
    .ADDR_WIDTH(SPI_REG_ADDRESS_WIDTH),
    /* Per-lane IDELAY offsets from rasbb_lanescan.py on the main WBMC,
       2026-10-06 (VALIDATION 7.11), supervisor at tap 16, lane n at [8n +: 6]:
       ADC1 lane 3 (chD = ch1 Q) -31 = always tap 0 - clean only at taps
         0..5 on the main WBMC and 0..2 on the second one, and the
         supervisor's tap varies by board and boot (16 / 7), so a relative
         offset can land on the edge (VALIDATION 7.12);
       ADC2 lane 0 (chA = ch2 I) -5 - its floor rises from tap 21, breaks at 25.
       Every other lane is clean from tap 0 to >= 29. */
    .LANE_TAP1_DEF(32'h21_00_00_00),
    .LANE_TAP2_DEF(32'h00_00_00_3B)
) iq_capture_inst (
    .i_clk(clk_100M),
    .i_rst(rst_100),
    .i_fe_valid(fe_valid_sync[1]),
    .i_smp_strobe(smp_strobe),
    .i_smp(smp_dout),
    .i_stf_det(short_preamble_detected),
    .i_hdr_stb(pkt_header_valid_strobe),
    .i_hdr_valid(pkt_header_valid),
    .i_pkt_len(pkt_len),
    .i_pkt_rate(pkt_rate),
    .i_byte_stb(byte_out_strobe),
    .i_byte(byte_out),
    .i_fcs_stb(fcs_out_strobe),
    .i_fcs_ok(fcs_ok),
    .i_abort(receiver_rst),
    .i_rx_idle(state == S_WAIT_POWER_TRIGGER),
    .i_ant_sel(ant_sel),
    .i_cfo(cfo_fine),
    .i_peg(fs_peg),
    .i_cpe_sum(fs_cpe_sum),
    .i_cpe_sq(fs_cpe_sq),
    .i_evm_sum(fs_evm_sum),
    .i_evm_cnt(fs_evm_cnt),
    .i_nsym(fs_nsym),
    .i_SPI_addr(SPI_reg_addr),
    .i_SPI_wrStrobe(SPI_reg_wrStrobe),
    .i_SPIdata(SPI_reg_wrData),
    .o_SPIdata(SPI_reg_rdData),
    .i_fpga2_ready(sl_fpga2_ready),
    .i_tx_busy(sl_tx_busy),
    .i_heal_count({24'd0, heal_cnt}),
    .i_stall_count({24'd0, stall_cnt}),
    .o_rd_desc(cap_rd_desc),
    .o_rd_valid(cap_rd_valid),
    .i_rd_ready(cap_rd_ready),
    .o_rd_inst(cap_rd_inst),
    .o_rd_inst_valid(cap_rd_inst_valid),
    .o_rd_last(cap_rd_last),
    .i_mark_dbg({6'd0, mark_ok, mark_ang, mark_cnt}),
    .i_diag(diag_bus),
    .i_fh_state(fh_st),
    .i_fh_rot(fh_rot),
    .i_fh_stat1(fh1_stat),
    .i_fh_stat2(fh2_stat),
    .i_df_stat(df_stat),
    .o_df_mode(df_mode),
    .i_mark_raw({6'd0, mark_ok, mark_brg, 7'd0, mark_raw}),
    .o_ph_cal(cap_ph_cal),
    .o_adc_skew(adc_skew),
    .o_gain_trim(gain_trim),
    .o_tap_ovr(tap_ovr),
    .o_lane_tap1(lane_tap1),
    .o_lane_tap2(lane_tap2),
    .o_iqb_sel(iqb_sel),
    .o_iqb_bypass(iqb_bypass),
    .o_iqb_clear_tog(iqb_clear_tog),
    .o_mac0(cap_mac0),
    .o_mac0_en(cap_mac0_en),
    .i_iqb_coef(iqb_coef),
    .o_fh_enable(fh_enable),
    .o_fh_force_tog(fh_force_tog),
    .o_ph1_meta(cap_ph1_meta),
    .o_ph_meta_valid(cap_ph_meta_valid),
    .o_mac_hit(cap_mac_hit),
    .o_enabled(cap_enabled),
    .o_armed(cap_armed),
    .o_used(cap_used)
);

/* SNAPLINK v1 transmitter (JOB-04): whole packets are staged in an 8k-word
   FIFO and shifted out at 20 MHz with a forwarded clock; see snaplink_tx.v. */
wire        sl_fpga2_ready, sl_tx_busy;
wire [31:0] sl_pkt_count;
snaplink_tx #(.FIFO_DEPTH(8192)) snaplink_tx_inst (
    .i_clk(clk_100M),
    .i_rst(rst_100),
    .i_lclk(clk_20M),
    .i_rd_desc(cap_rd_desc),
    .i_rd_valid(cap_rd_valid),
    .o_rd_ready(cap_rd_ready),
    .i_rd_inst(cap_rd_inst),
    .i_rd_inst_valid(cap_rd_inst_valid),
    .i_rd_last(cap_rd_last),
    .i_ready_pad(i_snaplink_ready),
    .o_lclk_pad(o_snaplink_lclk),
    .o_d(o_snaplink_d),
    .o_valid(o_snaplink_valid),
    .o_aux(o_snaplink_aux),
    .o_fpga2_ready(sl_fpga2_ready),
    .o_busy(sl_tx_busy),
    .o_pkt_count(sl_pkt_count)
);

/****************************************************************************/
/* Direction finder: STF powers -> bearing -> persistent angle table.       */
/****************************************************************************/
wire [8:0] brg_idx;
wire       brg_ok;

wire [8:0] df_angAddr;
wire [7:0] df_angLen;
wire [7:0] df_angFrq;

/* diversity combiner control / read-back and receiver frame counters */
div_regs #(.ADDR_WIDTH(SPI_REG_ADDRESS_WIDTH)) div_regs_inst (
    .i_clock(clk_100M),
    .i_reset(rst_100),
    .i_SPI_addr(SPI_reg_addr),
    .i_SPI_wrStrobe(SPI_reg_wrStrobe),
    .i_SPIdata(SPI_reg_wrData),
    .o_SPIdata(SPI_reg_rdData),
    .o_enable(div_enable),
    .i_weights(div_weights),
    .i_ref(div_ref),
    .i_half(div_half),
    .i_sat_count(div_sat_count),
    .i_upd_count(div_upd_count),
    .i_fcs_stb(fcs_out_strobe),
    .i_fcs_ok(fcs_ok),
    .i_hdr_stb(sig_valid)
);

/* Run-time display switches (DISP_CTRL 0x0C, written by the ECU's on-screen
   menu): pause freezes the station list, the rays and the labels (no new
   frames, no ageing / decay); show_bad enables the FCS-bad rays and label
   moves; brg_shift / ph_shift are the label position and phase dot EMA
   weights; clear resets the three display
   blocks (frame_log repaints a blank list) without touching the receiver.
   solo (b2) leaves rays, labels and phase dots only to the transmitters in
   the capture MAC filter list: cap_mac_hit is iq_capture's filter verdict
   for the frame in flight (df_frame reads it at the frame end), sta_hit the
   same held from one frame end to the next for frame_log's station event,
   which follows the frame end by ~50 clocks. */
wire       disp_pause, disp_show_bad, disp_clear, disp_solo, disp_pin;
reg        sta_hit = 1'b0;
always @(posedge clk_100M)
    if (fcs_out_strobe) sta_hit <= cap_mac_hit;
wire [2:0] disp_brg_shift, disp_ph_shift;

disp_regs #(.ADDR(7'h0C)) disp_regs_inst (
    .i_clock(clk_100M),
    .i_reset(rst_100),
    .i_SPI_addr(SPI_reg_addr),
    .i_SPI_wrStrobe(SPI_reg_wrStrobe),
    .i_SPIdata(SPI_reg_wrData),
    .o_SPIdata(SPI_reg_rdData),
    .o_pause(disp_pause),
    .o_show_bad(disp_show_bad),
    .o_solo(disp_solo),
    .o_pin(disp_pin),
    .o_brg_shift(disp_brg_shift),
    .o_ph_shift(disp_ph_shift),
    .o_clear(disp_clear)
);

wire disp_rst_100 = rst_100 | disp_clear;      // frame_log, polar_labels
wire disp_rst_rx  = rst_rx  | disp_clear;      // df_frame
wire disp_tick    = us_tick & ~disp_pause;     // ageing / decay stop while paused

/* Colour of FCS-good rays: a freqmap code (df_frame FRQ_OK), 96 = (130, 255, 0). */
localparam [7:0] RAY_FRQ_OK = 8'd96;

/* frame_log's station event (declared here: df_frame waits for it to paint
   an FCS-bad frame's ray only when its SA is a listed station) */
wire        sta_stb;
wire        sta_fcs;

df_frame #(
    .PWRW(PWRW),
    .ANGBITS(9),
    .FRQBITS(8),
    .CH_N(CH_N), .CH_E(CH_E), .CH_S(CH_S), .CH_W(CH_W),
    .DIR_MIN(11'd24),
    /* LEN_FLOOR in l2q3 counts (0.376dB each). 64 ~= -46dBFS STF power.
       Was 96 (~-34dBFS), which sat right inside the observed on-air range
       (PWR -24..-41): the weakest real stations computed a fine bearing and
       then had it discarded as "too weak" - BRG read "---" and no ray/label
       appeared. The ADC noise average sits ~12dB below the new floor. */
    .LEN_FLOOR(8'd64),
    .LEN_SHIFT(1),
    .FRQ_OK(RAY_FRQ_OK),   // freqmap colour: yellow-green for FCS-good rays
    .FRQ_BAD(8'd224),      //                 red/violet for FCS-bad rays
    .SHOW_BAD(2),          // FCS-bad rays only for SAs already in the station list
    .DECAY_US(16'd50000),  // one table decay sweep per 50ms -> rays fade in ~2s
    .STAGES(16),
    /* measured array response, IQCAP/iqcap_fpga_pattern.py from the 2026-09-25 tripod sweep */
    .TABLE_FILE({`OWIFI_SRC, "/df_pattern_2026-09-25.mem"})
) df_frame_inst (
    .i_clk(clk_100M),
    .i_rst(disp_rst_rx),
    .i_us_tick(disp_tick),
    .i_pwr(ant_pwr),
    .i_gain_trim(gain_trim),
    .i_stf_det(short_preamble_detected & ~disp_pause),
    .i_fcs_stb(fcs_out_strobe),
    .i_fcs_ok(fcs_ok),
    .i_abort(receiver_rst),
    .i_show_bad(disp_show_bad),
    .i_adm_stb(sta_stb),
    .i_adm_fcs(sta_fcs),
    .i_solo(disp_solo),
    .i_mac_hit(cap_mac_hit),
    .o_brg_idx(brg_idx),
    .o_brg_ok(brg_ok),
    .i_pat_en(df_mode[0]),
    .i_pat_halfwin(df_mode[15:8]),
    .o_df_stat(df_stat),
    .i_ph_ang(cap_ph1_meta),
    .i_ph_valid(cap_ph_meta_valid),
    .o_mark_ang(mark_ang),
    .o_mark_ok(mark_ok),
    .o_mark_cnt(mark_cnt),
    .i_ph_cal(cap_ph_cal),
    .o_mark_raw(mark_raw),
    .o_mark_brg(mark_brg),
    .i_rdClk(clk_pix),
    .i_rdAddr(df_angAddr),
    .o_rdLen(df_angLen),
    .o_rdFrq(df_angFrq)
);

/****************************************************************************/
/* HDMI: 1080p. text_screen is the timing master (windowed to the right     */
/* side), polar_view renders the DF disc on the left; the regions are       */
/* disjoint so the composite is a plain mux.                                */
/****************************************************************************/
wire        log_wr;
wire [12:0] log_wrAddr;
wire [17:0] log_wrData;
wire [5:0]  log_topGray;
wire [47:0] sta_mac;
wire [11:0] sta_rgb;
wire [8:0]  sta_brg;
wire        sta_brg_ok;
wire [8:0]  sta_ph;
wire        sta_ph_ok;
/* the frame's calibrated J2-vs-J1 phase (PH_CAL applied) as an angle bin,
   for the per-station phase dots - what the single rim marker used to show */
wire [15:0] ph_calibrated = cap_ph1_meta - cap_ph_cal;

/* Freeze forensics: a 4-digit hex word in the header row (refreshed ~1Hz by
   frame_log), readable AFTER a decode freeze because the video path lives
   on. Digit 1: {demod, link_ok1, link_ok2, fe_valid} - healthy idle reads 7,
   mid-decode F, a dead ADC link drops its bit. Digit 2: {alive1, alive2,
   ant_sel} - the alive bits are per-ADC word-strobe heartbeats, so healthy
   reads C..F (C+antenna); 8..B means ADC2's deserializer stopped producing
   words entirely (DCLK/FCLK dead), while lk2=0 WITH alive2=1 means words
   still flow but their FCLK content is wrong - the F2 header field then
   shows what actually arrives. Digit 3: dot11 state (stuck nonzero =
   receiver hung, watchdog failing). Digit 4: low nibble of the summed link
   retrain count (ticking = the supervisors are fighting for the eye). */
(* ASYNC_REG = "true" *) reg [1:0] lk1_sync = 2'b00, lk2_sync = 2'b00;
always @(posedge clk_100M) begin
    lk1_sync <= {lk1_sync[0], link_ok1};
    lk2_sync <= {lk2_sync[0], link_ok2};
end

/* per-ADC strobe heartbeat: a counter bit that flips every 2^16 words
   (3.3ms at 20MSPS), watched from clk_100M with a ~42ms timeout. Clean
   separation of "no words at all" from "words with wrong content". */
reg [16:0] strobe_ctr1 = 17'd0, strobe_ctr2 = 17'd0;
always @(posedge lvds_dclk_buffered)
    if (adc_frameStrobe)  strobe_ctr1 <= strobe_ctr1 + 17'd1;
always @(posedge lvds_dclk2_buffered)
    if (adc2_frameStrobe) strobe_ctr2 <= strobe_ctr2 + 17'd1;

(* ASYNC_REG = "true" *) reg [2:0] hb1_sync = 3'd0, hb2_sync = 3'd0;
reg [22:0] hb1_age = 23'd0, hb2_age = 23'd0;
always @(posedge clk_100M) begin
    hb1_sync <= {hb1_sync[1:0], strobe_ctr1[16]};
    hb2_sync <= {hb2_sync[1:0], strobe_ctr2[16]};
    if (hb1_sync[2] ^ hb1_sync[1]) hb1_age <= 23'd0;
    else if (!hb1_age[22])         hb1_age <= hb1_age + 23'd1;
    if (hb2_sync[2] ^ hb2_sync[1]) hb2_age <= 23'd0;
    else if (!hb2_age[22])         hb2_age <= hb2_age + 23'd1;
end
wire alive1 = ~hb1_age[22];
wire alive2 = ~hb2_age[22];

wire [7:0] retrain_sum = retrain_count1 + retrain_count2;

/* Per-ADC link-drop counters for diagnosis (LINK_DBG 0x7A, 2026-09-24): the
   heal (fe_rst) resets the link supervisors and with them their own retrain
   counters, so drops are counted here in clk_100M, reset only at power-up.
   drop = link_ok fell (words arrive, content wrong), dead = the word-strobe
   heartbeat stopped (no words at all). */
reg        lk1_d = 1'b0, lk2_d = 1'b0, al1_d = 1'b0, al2_d = 1'b0;
reg [7:0]  drop1 = 8'd0, drop2 = 8'd0, dead1 = 8'd0, dead2 = 8'd0;
always @(posedge clk_100M) begin
    lk1_d <= lk1_sync[1]; lk2_d <= lk2_sync[1]; al1_d <= alive1; al2_d <= alive2;
    if (lk1_d & ~lk1_sync[1] & (drop1 != 8'hFF)) drop1 <= drop1 + 8'd1;
    if (lk2_d & ~lk2_sync[1] & (drop2 != 8'hFF)) drop2 <= drop2 + 8'd1;
    if (al1_d & ~alive1 & (dead1 != 8'hFF)) dead1 <= dead1 + 8'd1;
    if (al2_d & ~alive2 & (dead2 != 8'hFF)) dead2 <= dead2 + 8'd1;
end
wire [31:0] link_dbg = {dead2[2:0], tap_eff2, dead1[2:0], tap_eff1, drop2, drop1};   // taps in [20:16] / [28:24]

/****************************************************************************/
/* Link-health instrumentation (0x7B..0x7F, 2026-09-24): what precedes a    */
/* heal, per ADC, across heals, against die temperature and supplies.       */
/****************************************************************************/
/* (a) FCLK decode misses per ADC per 2^24 words (0.84 s), ADC1 DCLK domain,
   NOT reset by fe_rst: a continuous margin metric (healthy = 0). */
reg [23:0] mw_ctr = 24'd0;
reg [15:0] mw_m1 = 16'd0, mw_m2 = 16'd0, mw_l1 = 16'd0, mw_l2 = 16'd0;
reg        mw_tog = 1'b0;
always @(posedge lvds_dclk_buffered) begin
    if (adc_frameStrobe) begin
        mw_ctr <= mw_ctr + 24'd1;
        if (mw_ctr == 24'hFFFFFF) begin
            mw_l1 <= mw_m1; mw_l2 <= mw_m2; mw_tog <= ~mw_tog;
            mw_m1 <= {15'd0, ~fclk1_hit}; mw_m2 <= {15'd0, ~fclk2_hit};
        end
        else begin
            if (~fclk1_hit && mw_m1 != 16'hFFFF) mw_m1 <= mw_m1 + 16'd1;
            if (~fclk2_hit && mw_m2 != 16'hFFFF) mw_m2 <= mw_m2 + 16'd1;
        end
    end
end
(* ASYNC_REG = "true" *) reg [2:0] mw_tog_s = 3'd0;
reg [15:0] miss1_w = 16'd0, miss2_w = 16'd0;
always @(posedge clk_100M) begin
    mw_tog_s <= {mw_tog_s[1:0], mw_tog};
    if (mw_tog_s[2] ^ mw_tog_s[1]) begin      // latched values stable for 0.84 s
        miss1_w <= mw_l1; miss2_w <= mw_l2;
    end
end

/* (b) retrains, re-anchors and rotation changes, accumulated across heals:
   the source counters reset with fe_rst, so sample them as slow multi-bit
   values (accept two equal consecutive samples) and add the increments. */
function [7:0] acc_step; input [7:0] acc, last, now;
    begin acc_step = (now >= last) ? acc + (now - last) : acc + now; end
endfunction
(* ASYNC_REG = "true" *) reg [7:0] rt1_s0, rt1_s1, rt2_s0, rt2_s1, ra1_s0, ra1_s1, ra2_s0, ra2_s1, rc_s0, rc_s1;
reg [7:0] rt1_last = 0, rt2_last = 0, ra1_last = 0, ra2_last = 0, rc_last = 0;
reg [7:0] rt1_acc = 0, rt2_acc = 0, ra1_acc = 0, ra2_acc = 0, rc_acc = 0;
always @(posedge clk_100M) begin
    rt1_s0 <= retrain_count1; rt1_s1 <= rt1_s0;
    rt2_s0 <= retrain_count2; rt2_s1 <= rt2_s0;
    ra1_s0 <= reanchor_cnt1;  ra1_s1 <= ra1_s0;
    ra2_s0 <= reanchor_cnt2;  ra2_s1 <= ra2_s0;
    rc_s0  <= rot_change_count; rc_s1 <= rc_s0;
    if (rt1_s0 == rt1_s1 && rt1_s1 != rt1_last) begin rt1_acc <= acc_step(rt1_acc, rt1_last, rt1_s1); rt1_last <= rt1_s1; end
    if (rt2_s0 == rt2_s1 && rt2_s1 != rt2_last) begin rt2_acc <= acc_step(rt2_acc, rt2_last, rt2_s1); rt2_last <= rt2_s1; end
    if (ra1_s0 == ra1_s1 && ra1_s1 != ra1_last) begin ra1_acc <= acc_step(ra1_acc, ra1_last, ra1_s1); ra1_last <= ra1_s1; end
    if (ra2_s0 == ra2_s1 && ra2_s1 != ra2_last) begin ra2_acc <= acc_step(ra2_acc, ra2_last, ra2_s1); ra2_last <= ra2_s1; end
    if (rc_s0  == rc_s1  && rc_s1  != rc_last)  begin rc_acc  <= acc_step(rc_acc,  rc_last,  rc_s1);  rc_last  <= rc_s1;  end
end

/* (c) which link fails first: on the clock where "both healthy" ends. A
   front-half reset drops both supervisors, but through two synchronisers and
   a high-fanout reset they can fall a cycle apart - so a drop within ~10 us
   of a reset counts as "both". */
reg        both_ok_d = 1'b0;
reg [7:0]  ff1 = 8'd0, ff2 = 8'd0, ffb = 8'd0;
reg [9:0]  ff_hold = 10'd0;
always @(posedge clk_100M) begin
    both_ok_d <= lk1_sync[1] & lk2_sync[1];
    if (rst_rx_sync[0] | rst_100 | heal_rst_reg | stall_rst_reg) ff_hold <= 10'd1023;
    else if (ff_hold != 10'd0)                  ff_hold <= ff_hold - 10'd1;
    if (both_ok_d & ~(lk1_sync[1] & lk2_sync[1])) begin
        if (ff_hold != 10'd0)                ffb <= ffb + 8'd1;
        else if (~lk1_sync[1] & lk2_sync[1]) ff1 <= ff1 + 8'd1;
        else if (lk1_sync[1] & ~lk2_sync[1]) ff2 <= ff2 + 8'd1;
        else                                 ffb <= ffb + 8'd1;   // both at once (a reset, or a common cause)
    end
end

/* (d) XADC: die temperature, VCCINT, VCCAUX in the default sequencer mode,
   DRP-polled every ~10 ms. T[degC] = code*503.975/4096 - 273.15, V = code*3/4096. */
reg  [6:0]  xa_addr = 7'h00;
reg         xa_den = 1'b0, xa_wait = 1'b0;
reg  [19:0] xa_tick = 20'd0;
reg  [1:0]  xa_sel = 2'd0;
reg  [11:0] xa_temp = 12'd0, xa_vint = 12'd0, xa_vaux = 12'd0, xa_tmax = 12'd0;
wire [15:0] xa_do;
wire        xa_drdy, xa_jbusy, xa_jlock;
reg  [7:0]  xa_reads = 8'd0;     // completed DRP reads (wraps) - proves the reader runs
XADC #(
    .INIT_40(16'h0000),     // default averaging, no external channel
    .INIT_41(16'h0000),     // SEQ = default mode: on-chip sensors, calibrated
    .INIT_42(16'h0400)      // ADCCLK = DCLK/4 = 25 MHz (max 26)
) xadc_inst (
    .DCLK(clk_100M), .DEN(xa_den), .DWE(1'b0), .DADDR(xa_addr), .DI(16'h0000),
    .DO(xa_do), .DRDY(xa_drdy), .RESET(1'b0), .CONVST(1'b0), .CONVSTCLK(1'b0),
    .VP(1'b0), .VN(1'b0), .VAUXP(16'h0000), .VAUXN(16'h0000),
    .ALM(), .OT(), .BUSY(), .CHANNEL(), .EOC(), .EOS(), .JTAGBUSY(xa_jbusy), .JTAGLOCKED(xa_jlock), .JTAGMODIFIED(), .MUXADDR()
);
always @(posedge clk_100M) begin
    xa_den <= 1'b0;
    xa_tick <= xa_tick + 20'd1;
    if (!xa_wait && xa_tick == 20'd0) begin
        xa_addr <= {5'd0, xa_sel}; xa_den <= 1'b1; xa_wait <= 1'b1;
    end
    /* no DRDY within a full tick period (~10 ms): the request was dropped
       (first DEN right after configuration, or JTAG owns the DRP) - retry */
    if (xa_wait && !xa_drdy && xa_tick == 20'hFFFFF) xa_wait <= 1'b0;
    if (xa_wait && xa_drdy) begin
        xa_wait <= 1'b0;
        case (xa_sel)
            2'd0: begin xa_temp <= xa_do[15:4]; if (xa_do[15:4] > xa_tmax) xa_tmax <= xa_do[15:4]; end
            2'd1: xa_vint <= xa_do[15:4];
            default: xa_vaux <= xa_do[15:4];
        endcase
        xa_sel <= (xa_sel == 2'd2) ? 2'd0 : xa_sel + 2'd1;
        xa_reads <= xa_reads + 8'd1;
    end
end

assign diag_bus = {
    {ffb, ff2, ff1, rc_acc},                           // 0x7F first-fail counts, rotation changes
    {ra2_acc, ra1_acc, rt2_acc, rt1_acc},              // 0x7E re-anchors, retrains (8-bit wrap)
    {miss2_w, miss1_w},                                // 0x7D FCLK misses per 0.84 s window
    {xa_reads[3:0], xa_tmax, xa_jlock, xa_jbusy, xa_wait, 1'b0, xa_vaux}, // 0x7C (+ reader status in the pad bits)
    {4'd0, xa_vint, 4'd0, xa_temp},                    // 0x7B
    link_dbg                                           // 0x7A
};

/* (e) fast-heal counters and states into clk_100M (FH_CTRL/FH_STAT 0x1A..0x1C):
   slow multi-bit values, taken when two consecutive samples agree */
(* ASYNC_REG = "true" *) reg [31:0] fhs1_s0 = 32'd0, fhs1_s1 = 32'd0, fhs2_s0 = 32'd0, fhs2_s1 = 32'd0;
(* ASYNC_REG = "true" *) reg [5:0]  fhst_s0 = 6'd0, fhst_s1 = 6'd0;
(* ASYNC_REG = "true" *) reg [15:0] fhr_s0 = 16'd0, fhr_s1 = 16'd0;
always @(posedge clk_100M) begin
    fhr_s0 <= {fh2_ref, rot2_cur, fh1_ref, rot1_cur}; fhr_s1 <= fhr_s0;
    if (fhr_s0 == fhr_s1) fh_rot <= fhr_s1;
    fhs1_s0 <= {fh1_t2, fh1_gu, fh1_ok, fh1_att}; fhs1_s1 <= fhs1_s0;
    fhs2_s0 <= {fh2_t2, fh2_gu, fh2_ok, fh2_att}; fhs2_s1 <= fhs2_s0;
    fhst_s0 <= {fh2_st, fh1_st};                  fhst_s1 <= fhst_s0;
    if (fhs1_s0 == fhs1_s1) fh1_stat <= fhs1_s1;
    if (fhs2_s0 == fhs2_s1) fh2_stat <= fhs2_s1;
    if (fhst_s0 == fhst_s1) fh_st    <= fhst_s1;
end
wire [15:0] dbg_word = { demod_is_ongoing, lk1_sync[1], lk2_sync[1], fe_valid_sync[1],
                         alive1, alive2, ant_sel,
                         state[3:0],
                         retrain_sum[3:0] };

frame_log #(
    .MAX_STA(8)            // compact list: 2 header + 8 station rows
) frame_log_inst (
    .i_clk(clk_100M),
    .i_rst(disp_rst_100),
    .i_us_tick(us_tick),
    .i_hdr_stb(pkt_header_valid_strobe & ~disp_pause),   // paused: no frame starts, so bytes / FCS are ignored
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
    .i_fclk1(fclk1_cur),
    .i_fclk2(fclk2_cur),
    .i_heal(heal_cnt),
    .i_brg_idx(brg_idx),
    .i_brg_ok(brg_ok),
    .i_ph_ang(ph_calibrated[15:7]),
    .i_ph_ok(cap_ph_meta_valid),
    .i_dbg(dbg_word),
    .o_wr(log_wr),
    .o_wrAddr(log_wrAddr),
    .o_wrData(log_wrData),
    .o_topRowGray(log_topGray),
    .o_sta_stb(sta_stb),
    .o_sta_mac(sta_mac),
    .o_sta_rgb(sta_rgb),
    .o_sta_brg(sta_brg),
    .o_sta_brg_ok(sta_brg_ok),
    .o_sta_fcs(sta_fcs),
    .o_sta_ph(sta_ph),
    .o_sta_ph_ok(sta_ph_ok),
    /* DISP_CTRL b3: the station of capture filter slot 0 keeps the top row */
    .i_pin_en(disp_pin & cap_mac0_en),
    .i_pin_mac(cap_mac0)
);

wire        vid_hs, vid_vs, vid_de;
wire [7:0]  txt_r, txt_g, txt_b;

(* ASYNC_REG = "true" *) reg [1:0] rst_pix_sync = 2'b11;
always @(posedge clk_pix) rst_pix_sync <= {rst_pix_sync[0], global_rst};
wire rst_pix = rst_pix_sync[1];

`ifndef OWIFI_SRC
`define OWIFI_SRC "owifi.srcs/sources_1"
`endif

/* 1024x768 character window at (448,0): horizontally centred at the top of
   the 1080p screen. Char geometry (128x48 cells) is unchanged; only the top
   10 rows (header + 8-station list) ever hold glyphs, the rest stay blank
   and render black under the disc. Requires VIDEO_1920_1080 to be defined
   by the build (see video_define.v). */
text_screen #(
    .FONT_FILE({`OWIFI_SRC, "/font8x16.mem"}),
    .TEXT_X0(448),
    .TEXT_Y0(0)
) text_screen_inst (
    .i_pixClk(clk_pix),
    .i_rst(rst_pix),
    .o_hs(vid_hs), .o_vs(vid_vs), .o_de(vid_de),
    .o_r(txt_r), .o_g(txt_g), .o_b(txt_b),
    .i_wrClk(clk_100M),
    .i_wr(log_wr),
    .i_wrAddr(log_wrAddr),
    .i_wrData(log_wrData),
    .i_topRowGray(log_topGray)
);

wire       polar_active, polar_shade;
wire [7:0] polar_r, polar_g, polar_b;

polar_view #(
    .REG_X0(0),   .REG_Y0(160),
    .REG_W(1920), .REG_H(920),    // disc centred at (960,620), below the list
    .R_MAX(324),
    .STAGES(16)
) polar_0 (
    .i_pixClk(clk_pix),
    .i_rst(rst_pix),
    .i_video_hs(vid_hs),
    .i_video_vs(vid_vs),
    .i_video_de(vid_de),
    .o_angAddr(df_angAddr),
    .i_angLen(df_angLen),
    .i_angFrq(df_angFrq),
    .o_active(polar_active),
    .o_shade(polar_shade),
    .o_r(polar_r), .o_g(polar_g), .o_b(polar_b)
);

/* MAC labels around the disc rim, at each station's last bearing */
wire       lab_active;
wire [7:0] lab_r, lab_g, lab_b;

polar_labels #(
    .CX(960), .CY(620),     // matches polar_0's region centre
    .R_LAB(340),            // just outside the outer ring (R_MAX 324 + 16)
    .NSLOT(8),
    .R_DOT(332),            // phase dots between the ring and the labels
    .DOT_HALF(4),           // 9x9 squares
    .EXPIRE_S(4'd10),
    .FONT_FILE({`OWIFI_SRC, "/font8x16.mem"}),
    .SINCOS_FILE({`OWIFI_SRC, "/sincos512.mem"})
) polar_labels_inst (
    .i_clk(clk_100M),
    .i_rst(disp_rst_100),
    .i_us_tick(disp_tick),
    .i_sta_stb(sta_stb & (~disp_solo | sta_hit)),
    .i_sta_mac(sta_mac),
    .i_sta_rgb(sta_rgb),
    .i_sta_brg(sta_brg),
    .i_sta_brg_ok(sta_brg_ok),
    .i_sta_fcs(sta_fcs),
    .i_sta_ph(sta_ph),
    .i_sta_ph_ok(sta_ph_ok),
    .i_bad_fcs(disp_show_bad),
    .i_brg_shift(disp_brg_shift),
    .i_ph_shift(disp_ph_shift),
    .i_pixClk(clk_pix),
    .i_rst_pix(rst_pix),
    .i_video_vs(vid_vs),
    .i_video_de(vid_de),
    .o_active(lab_active),
    .o_r(lab_r), .o_g(lab_g), .o_b(lab_b)
);

/* Phase rim marker (4.b): replaced 2026-09-25 by per-station phase dots in
   polar_labels (one steady dot per listed station, in its own colour). The
   single marker showed only the most recent frame, and the AP's ACK after
   every client frame moved it straight back to the AP's phase.
   phase_marker.v is kept in the repo but no longer instantiated. */

/* Pop-up box (2026-10-02): white window in the lower right corner with the
   project logo and a text the ECU writes over the config bus (registers
   0x08..0x0B, console OT / OS / OZ / OA). Hidden until the ECU shows it. */
wire       ovl_active;
wire [7:0] ovl_r, ovl_g, ovl_b;

ovl_box #(
    .BASE_ADDR(7'h08),
    .FONT_FILE({`OWIFI_SRC, "/font8x16_96.mem"}),
    .LOGO_FILE({`OWIFI_SRC, "/logo.mem"})
) ovl_box_inst (
    .i_clk(clk_100M),
    .i_rst(rst_100),
    .i_SPI_addr(SPI_reg_addr),
    .i_SPI_wrStrobe(SPI_reg_wrStrobe),
    .i_SPIdata(SPI_reg_wrData),
    .o_SPIdata(SPI_reg_rdData),
    .i_pixClk(clk_pix),
    .i_rst_pix(rst_pix),
    .i_video_vs(vid_vs),
    .i_video_de(vid_de),
    .o_active(ovl_active),
    .o_r(ovl_r), .o_g(ovl_g), .o_b(ovl_b)
);

/* Composite: labels, polar disc and text own disjoint pixels by construction
   (labels outside the rings, text in its right-side window), so their order
   is a formality: labels, then polar, then text. The pop-up box is the one
   real overlay and sits on top of everything. One output register stage;
   syncs delayed in step so the whole frame shifts one pixel, invisibly. */
reg [7:0] disp_r_q, disp_g_q, disp_b_q;
reg       disp_hs_q, disp_vs_q, disp_de_q;
always @(posedge clk_pix) begin
    disp_r_q  <= ovl_active ? ovl_r : lab_active ? lab_r : polar_active ? polar_r : txt_r;
    disp_g_q  <= ovl_active ? ovl_g : lab_active ? lab_g : polar_active ? polar_g : txt_g;
    disp_b_q  <= ovl_active ? ovl_b : lab_active ? lab_b : polar_active ? polar_b : txt_b;
    disp_hs_q <= vid_hs;
    disp_vs_q <= vid_vs;
    disp_de_q <= vid_de;
end

rgb2dvi #(
    .kGenerateSerialClk(1'b0),   // clk_serial comes from hdmi_clk
    .kClkRange(1),
    .kRstActiveHigh(1'b1)
) rgb2dvi_inst (
    .TMDS_Clk_p(TMDS_clk_p),
    .TMDS_Clk_n(TMDS_clk_n),
    .TMDS_Data_p(TMDS_data_p),
    .TMDS_Data_n(TMDS_data_n),
    .aRst(rst_pix),
    .aRst_n(~rst_pix),
    .vid_pData({disp_r_q, disp_b_q, disp_g_q}),
    .vid_pVDE(disp_de_q),
    .vid_pHSync(disp_hs_q),
    .vid_pVSync(disp_vs_q),
    .PixelClk(clk_pix),
    .SerialClk(clk_serial)
);

/****************************************************************************/
/* Debug header (system_top_rasbb, verbatim).                               */
/****************************************************************************/
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

always @(posedge clk_100M)
    if (byte_out_strobe) last_byte <= byte_out;

/* J5 debug outputs retired by JOB-04 (the bus carries SNAPLINK now); the
   fcs_stretch / last_byte forensics registers stay for a future ILA. */

endmodule
