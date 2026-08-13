//////////////////////////////////////////////////////////////////////////////////
//
// Design Name: RASPMO
// Module Name: top of RASPMO
// Project Name: Radio Access Spectrum Monitor
// Engineer: Tobias Weber
// Target Devices: Artix 7, XC7A100T-CSG324 (RASBB onboard FPGA)
// Description:  Quad-split 1080p HDMI display: a complex (two-sided) spectrum
//               + waterfall for EACH of the RASRF2400BMC's four receive
//               channels, one 960x540 pane per channel.
//
//               Channel map (traced through the RASRF2400WBMC PCB nets):
//                 CH1 = RF-TRANS_1 (U4):  ADC1 chA (I) + chB (Q)
//                 CH2 = RF-TRANS_2 (U6):  ADC1 chC (I) + chD (Q)
//                 CH3 = RF-TRANS_3 (U8):  ADC2 chA (I) + chB (Q)
//                 CH4 = RF-TRANS_4 (U10): ADC2 chC (I) + chD (Q)
//               ADC1 and ADC2 each ship their own DCLK/FCLK; both derive from
//               the front-end's single 40MHz TCXO, so the two 120MHz domains
//               are frequency-locked with unknown phase. ADC2's samples cross
//               into ADC1's DCLK domain through a small gray-pointer FIFO
//               (sample_cdc.v) and the whole processing pipeline runs in the
//               ADC1 domain.
//
//               ONE 1024-point complex FFT is time-multiplexed across the four
//               channels, one whole FFT frame (51.2us) per channel round-robin
//               -> each pane refreshes at ~4.9kHz, far above the 60Hz display.
//               Input-side frame framing is tracked by counting FFT CE ticks
//               from reset (the ZipCPU pipeline defines its frames exactly the
//               same way), and a small tag FIFO carries {channel, AGC shift}
//               from each input frame to its output frame (popped at the
//               logfn output sync) - so display routing and the log-domain
//               AGC compensation are exact regardless of pipeline latency.
//
//               There is no SPI or other path from an external host into this
//               FPGA's fabric on RASBB (the exposed PCIE_CS/MOSI/MISO/SCK
//               nets only reach the config flash, not user logic), and no
//               user-facing reset button (S1 goes to the dedicated PROGRAM_B
//               config pin). So unlike RASM2400, there is no runtime register
//               interface here, and reset is a simple internal power-up pulse.
//
// Dependencies: adc_sequencer.v, screen.v, lvds_rx_new.v, sample_cdc.v,
//               dp_ram.v, waterfall_mem.v, pane_overlay.v, hdmi_clk.v,
//               fft/*.v, hdmi/*.vhd
//
// Additional Comments: https://github.com/Tobias-DG3YEV/RA-Sentinel
//
//////////////////////////////////////////////////////////////////////////////////
// Copyright (C) 2026 Tobias Weber
// License: GNU GPL v3
//
// This project is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTIBILITY or FITNESS FOR A PARTICULAR PURPOSE.
// See the GNU General Public License for more details.
//
// You should have received a copy of the GNU Lesser General Public License
// along with this program. If not, see
// <http://www.gnu.org/licenses/> for a copy.
//////////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps

module top(
    // Master Clock Input (50MHz, single-ended, bank 35 @ 1.8V)
    input wire SYS_clk,
    // HDMI output
    output wire TMDS_clk_n,
    output wire TMDS_clk_p,
    output wire [2:0] TMDS_data_n,
    output wire [2:0] TMDS_data_p,
    // ADC1 LVDS input - one-wire per channel (RX1/RX2 baseband)
    input wire ADC_dclk_P, ADC_dclk_N, // 120MHz bit clock
    input wire ADC_fclk_P, ADC_fclk_N, // 20MHz frame clock
    input wire ADC_chA_P, ADC_chA_N,   // channel A = RX1 I
    input wire ADC_chB_P, ADC_chB_N,   // channel B = RX1 Q
    input wire ADC_chC_P, ADC_chC_N,   // channel C = RX2 I
    input wire ADC_chD_P, ADC_chD_N,   // channel D = RX2 Q
    // ADC2 LVDS input - one-wire per channel (RX3/RX4 baseband)
    input wire ADC2_dclk_P, ADC2_dclk_N,
    input wire ADC2_fclk_P, ADC2_fclk_N,
    input wire ADC2_chA_P, ADC2_chA_N, // channel A = RX3 I
    input wire ADC2_chB_P, ADC2_chB_N, // channel B = RX3 Q
    input wire ADC2_chC_P, ADC2_chC_N, // channel C = RX4 I
    input wire ADC2_chD_P, ADC2_chD_N  // channel D = RX4 Q
);

// -----------------------------------------------------------------------------
// Parameters
// -----------------------------------------------------------------------------
parameter FFTLEN = 10; //FFT length in bits (1024 point complex FFT)
parameter ADCBITS = 12;
parameter NCH = 4;     // receive channels (panes)

/* Compile-time switch: leave defined to render the orange per-lane
   bit-error-rate numbers along the bottom of each pane's spectrum (only
   meaningful while the RASRF2400BMC firmware runs ADC ramp-test mode);
   comment out to hide them - the whole rate render path incl. the BCD
   converters is then stripped by synthesis. The white level readout in the
   pane's top-left corner stays either way. */
//`define SHOW_BER_RATES

`ifdef SHOW_BER_RATES
localparam SHOW_RATES = 1'b1;
`else
localparam SHOW_RATES = 1'b0;
`endif

/* The polar direction indicator sits in the middle of the screen, across all
   four spectrum panes, composited over them by two compile-time weights. Both
   are in 256ths and both are exact at their endpoints.

   POLAR_ALPHA - how much of the indicator's own colour shows on the pixels it
   DRAWS (rays, range rings, crosshair):
     0   indicator invisible
     128 half and half with the spectra under it
     256 fully opaque - it hides whatever it covers

   POLAR_DIM - how much of the spectra SURVIVES inside the outer ring, i.e. the
   veil that lifts the indicator off a busy background:
     256 no darkening at all
     128 spectra at half brightness under the disc
     0   solid black disc, the indicator on its own background

   Outside the outer ring nothing is touched, so this darkens a 512px disc in
   the centre of the screen and not the panes as a whole. Override either from
   the build without editing the source:
       set_property verilog_define {POLAR_ALPHA=96 POLAR_DIM=64} \
                                   [get_filesets sources_1] */
`ifndef POLAR_ALPHA
`define POLAR_ALPHA 160
`endif
`ifndef POLAR_DIM
`define POLAR_DIM 96
`endif

//------------------------------------------------------------------------------
// Signals
//------------------------------------------------------------------------------
(* keep = "true" *) wire lvds_dclk;
(* keep = "true", mark_debug = "true" *) wire lvds_fclk;
(* keep = "true" *) wire lvds_dclk2;
wire lvds_fclk2;

(* mark_debug = "true" *) wire adc_frameStrobe;

wire clk_120M;
wire clk_195M;
wire clk_pix;     // 148.75MHz pixel clock (1080p)
wire clk_serial;  // 743.75MHz TMDS serial clock

(* mark_debug = "true" *) wire video_hs;
(* mark_debug = "true" *) wire video_vs;
(* mark_debug = "true" *) wire video_de;
wire[7:0] video_r;
wire[7:0] video_g;
wire[7:0] video_b;

wire[7:0]   scr_rdSpecAmpl;
wire        scr_rdStrobe;
wire[9:0]   scr_rdAddr;
wire[1:0]   scr_pane;
wire        wf_RdScreenSync;
wire        wfActive;
wire [6:0]  wfRow;
wire [7:0]  wf_rdSpecAmpl;

wire                fft_lineSync;
(* keep = "true", mark_debug = "true" *) wire[31:0] fft_result;

/*******************/
/* Clock generation */
/*******************/
(* mark_debug = "true" *) wire mmcm_locked;
wire hdmi_clk_locked;

/* Video_clk still provides the 120MHz utility clock (ILA / reset domain) and
   the 195MHz IDELAYCTRL reference; its legacy 65/325MHz video outputs are
   unused since the move to 1080p (hdmi_clk below). */
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

/***************************************
    Power-up reset

    RASBB provides no user-facing reset button into this FPGA's fabric (the
    only board button is wired to the dedicated PROGRAM_B config pin), so
    global_rst is just an internal startup pulse held for a while after
    clk_120M comes up, rather than being derived from an external key.

    Held in reset (and the counter held at 0) until BOTH MMCMs report locked -
    clk_120M is a direct MMCM output, so before lock it can glitch or run at
    the wrong frequency, and counting on it then would let global_rst release
    on an arbitrary, possibly much-too-early, timeline.
****************************************/
reg [4:0] por_ctr = 5'h00;
(* mark_debug = "true" *) reg global_rst = 1'b1;
always @(posedge clk_120M) begin
    if (!mmcm_locked || !hdmi_clk_locked) begin
        por_ctr <= 5'h00;
        global_rst <= 1'b1;
    end
    else if (por_ctr != 5'h1f) begin
        por_ctr <= por_ctr + 5'h1;
        global_rst <= 1'b1;
    end
    else begin
        global_rst <= 1'b0;
    end
end

/****************************************************************************

       #     ######    #####          #        #     #  ######    #####
      # #    #     #  #     #         #        #     #  #     #  #     #
     #   #   #     #  #               #        #     #  #     #  #
    #     #  #     #  #               #        #     #  #     #   #####
    #######  #     #  #               #         #   #   #     #        #
    #     #  #     #  #     #         #          # #    #     #  #     #
    #     #  ######    #####          #######     #     ######    #####

/****************************************************************************/

// Self-calibrating data-path IDELAY control - driven by the sweep FSM further
// down (needs the ramp-checker error counters, declared later). One tap per
// ADC: the two DCLKs take different (non-clock-capable, fabric-routed) paths
// to their ISERDES, so the two ADCs' data eyes do NOT sit at the same tap -
// calibrating both from ADC1 chB (as before) parked ADC2 wherever ADC1
// happened to like.
reg [4:0] cal_tap1, cal_tap2;
reg       cal_load1, cal_load2;
wire      lvds_dclk_buffered;  // BUFG'd ADC1 bit clock - the processing domain
wire      lvds_dclk2_buffered; // BUFG'd ADC2 bit clock - deserialize+CDC only

wire [4*ADCBITS-1:0] adc1_data; // lanes A..D = RX1 I/Q, RX2 I/Q
wire [4*ADCBITS-1:0] adc2_data; // lanes A..D = RX3 I/Q, RX4 I/Q (ADC2 DCLK domain)

lvds_rx #(.NLANES(4)) lvds_irx0 (
    .i_lvds_dclk_P(ADC_dclk_P),
    .i_lvds_dclk_N(ADC_dclk_N),
    .i_lvds_fclk_P(ADC_fclk_P),
    .i_lvds_fclk_N(ADC_fclk_N),
    .i_lvds_d_P({ADC_chD_P, ADC_chC_P, ADC_chB_P, ADC_chA_P}),
    .i_lvds_d_N({ADC_chD_N, ADC_chC_N, ADC_chB_N, ADC_chA_N}),
    .i_rst(global_rst),
    .i_ctrlClk(lvds_dclk_buffered),
    .i_data_delay_tap(cal_tap1),
    .i_data_delay_load(cal_load1),
    .o_lvds_dclk(lvds_dclk),
    .o_lvds_fclk(lvds_fclk),
    .o_data(adc1_data)
);

lvds_rx #(.NLANES(4)) lvds_irx1 (
    .i_lvds_dclk_P(ADC2_dclk_P),
    .i_lvds_dclk_N(ADC2_dclk_N),
    .i_lvds_fclk_P(ADC2_fclk_P),
    .i_lvds_fclk_N(ADC2_fclk_N),
    .i_lvds_d_P({ADC2_chD_P, ADC2_chC_P, ADC2_chB_P, ADC2_chA_P}),
    .i_lvds_d_N({ADC2_chD_N, ADC2_chC_N, ADC2_chB_N, ADC2_chA_N}),
    .i_rst(global_rst),
    .i_ctrlClk(lvds_dclk_buffered), // cal FSM domain, shared with instance 0
    .i_data_delay_tap(cal_tap2),
    .i_data_delay_load(cal_load2),
    .o_lvds_dclk(lvds_dclk2),
    .o_lvds_fclk(lvds_fclk2),
    .o_data(adc2_data)
);

/* We buffer the bit clocks here for further blocks to avoid that the synth.
   Else Vivado inserts its own BUFG here which would lead to unpredictive line
   delay. ADC1's clock fans out to the whole processing pipeline; ADC2's only
   to its own frame sequencer and the CDC FIFO write side. */
BUFG BUFG_lvds_dclk_1 (
    .I(lvds_dclk),
    .O(lvds_dclk_buffered)
);
BUFG BUFG_lvds_dclk_2 (
    .I(lvds_dclk2),
    .O(lvds_dclk2_buffered)
);

/* IDELAYCTRL calibrates all IDELAYE2s of I/O bank 35 (both lvds_rx instances'
   pins live there, and a bank has exactly one IDELAYCTRL site - hence a single
   instance here in top rather than one per lvds_rx). */
IDELAYCTRL IDELAYCTRL0 (
   .RDY(),
   .REFCLK(clk_195M),
   .RST(global_rst)
);

wire [FFTLEN-1:0]   adc_frameCounter;
wire                logfn_lineSync;
wire                fft_frameStrobe;
(* mark_debug = "true" *) wire mem_wordWrStrobe;

adc_sequencer adc_sequencer0
(
    .i_lvds_frameClk(lvds_fclk),
    .i_lvds_bitClk(lvds_dclk_buffered),
    .i_fft_lineSync(logfn_lineSync),
    .i_rst(global_rst),
    .o_adc_frameStrobe(adc_frameStrobe),
    .o_fft_frameStrobe(fft_frameStrobe),
    .o_frameCounter(adc_frameCounter),
    .o_mem_sampleStrobe(mem_wordWrStrobe)
);

/* ADC2 word cadence in its own DCLK domain - only the sample strobe is used,
   as the write enable of the CDC FIFO below. */
wire adc2_frameStrobe;
adc_sequencer adc_sequencer1
(
    .i_lvds_frameClk(lvds_fclk2),
    .i_lvds_bitClk(lvds_dclk2_buffered),
    .i_fft_lineSync(1'b0),
    .i_rst(global_rst),
    .o_adc_frameStrobe(adc2_frameStrobe),
    .o_fft_frameStrobe(),
    .o_frameCounter(),
    .o_mem_sampleStrobe()
);

/* ADC2 -> ADC1 clock domain crossing. Both DCLKs come from the same TCXO, so
   write and read rates are identical; the FIFO only absorbs the unknown phase
   and the startup transient. One extra sample period of latency on CH3/CH4 -
   irrelevant for independent per-pane spectra. */
wire [4*ADCBITS-1:0] adc2_data_s;
sample_cdc #(.W(4*ADCBITS)) adc2_cdc (
    .i_wclk(lvds_dclk2_buffered),
    .i_wrst(global_rst),
    .i_wen(adc2_frameStrobe),
    .i_wdata(adc2_data),
    .i_rclk(lvds_dclk_buffered),
    .i_rrst(global_rst),
    .i_ren(adc_frameStrobe),
    .o_rdata(adc2_data_s)
);

/* All 8 ADC lanes as one array in the processing (ADC1 DCLK) domain.
   Lane n: even = I, odd = Q; lanes 2c/2c+1 belong to channel c. */
wire [ADCBITS-1:0] lane_raw [0:2*NCH-1];
assign lane_raw[0] = adc1_data  [0*ADCBITS +: ADCBITS]; // CH1 I (ADC1 chA)
assign lane_raw[1] = adc1_data  [1*ADCBITS +: ADCBITS]; // CH1 Q (ADC1 chB)
assign lane_raw[2] = adc1_data  [2*ADCBITS +: ADCBITS]; // CH2 I (ADC1 chC)
assign lane_raw[3] = adc1_data  [3*ADCBITS +: ADCBITS]; // CH2 Q (ADC1 chD)
assign lane_raw[4] = adc2_data_s[0*ADCBITS +: ADCBITS]; // CH3 I (ADC2 chA)
assign lane_raw[5] = adc2_data_s[1*ADCBITS +: ADCBITS]; // CH3 Q (ADC2 chB)
assign lane_raw[6] = adc2_data_s[2*ADCBITS +: ADCBITS]; // CH4 I (ADC2 chC)
assign lane_raw[7] = adc2_data_s[3*ADCBITS +: ADCBITS]; // CH4 Q (ADC2 chD)

/* Per-lane word-boundary re-alignment ("rotation").

   lvds_rx chops the serial stream into ADCBITS-wide words at a boundary
   that is only ever an ARBITRARY-BUT-STABLE offset from the ADC's true
   word boundary: the FCLK anchor phase through its 2-FF synchronizer, the
   ISERDES CLKDIV grouping, the ADC's LSB-first serial order vs. capture
   order, per-ISERDES CLKDIV routing skew, the ADC2 CDC FIFO latency - all
   constant offsets. So the true sample is always SOME contiguous
   ADCBITS-wide window of two consecutive captured words. Keeping the last
   two words per lane and letting a calibrated base select that window
   makes the framing exact regardless of every one of those offsets. The
   ROT_POS window bases cover every possible alignment without even
   needing to know the stream's time direction. The base per lane is found
   by the calibration FSM below against the ADC ramp test pattern, then
   frozen. Cost: two regs and a 13:1 mux per lane, plus one word of
   latency (irrelevant for a spectrum display). Scales with ADCBITS only -
   nothing here assumes 20MSPS. */
localparam ROT_POS = ADCBITS + 1; // number of window base positions (13)

reg  [ADCBITS-1:0] lane_cur  [0:2*NCH-1];
reg  [ADCBITS-1:0] lane_hist [0:2*NCH-1];
reg  [3:0]         rot_base  [0:2*NCH-1]; // driven by the calibration FSM
wire [ADCBITS-1:0] lane_sample [0:2*NCH-1];

genvar rl;
generate for (rl = 0; rl < 2*NCH; rl = rl + 1) begin : gen_rot
    always @(posedge lvds_dclk_buffered) begin
        if (global_rst) begin
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

// ADC1 chA/chB aliases for the debug snapshot below (kept for ILA probing)
(* keep = "true", mark_debug = "true" *) wire [ADCBITS-1:0] adc_ipar;
(* keep = "true", mark_debug = "true" *) wire [ADCBITS-1:0] adc_qpar;
assign adc_ipar = lane_sample[0];
assign adc_qpar = lane_sample[1];

/* LVDS link BER checking against the ADC3424's digital-ramp test pattern
   (see RASRF2400BMC firmware, ADC1_RAMP_TEST_MODE). One checker per lane, all
   in the processing domain (the ADC2 lanes are checked after the CDC, which
   deliberately includes the FIFO in what is being verified). Purely
   observational - harmless noise against real signal content. */
wire [ADCBITS-1:0] ramp_expected  [0:2*NCH-1];
wire [31:0]        ramp_samples   [0:2*NCH-1];
wire [31:0]        ramp_errors    [0:2*NCH-1];
wire [31:0]        ramp_biterrors [0:2*NCH-1];
wire [2*NCH-1:0]   ramp_locked;

genvar ln;
generate for (ln = 0; ln < 2*NCH; ln = ln + 1) begin : gen_rampchk
    ramp_checker #(.WIDTH(ADCBITS)) ramp_checker_lane (
        .i_clk(lvds_dclk_buffered),
        .i_rst(global_rst),
        .i_ce(adc_frameStrobe),
        .i_sample(lane_sample[ln]),
        .o_expected(ramp_expected[ln]),
        .o_sample_count(ramp_samples[ln]),
        .o_error_count(ramp_errors[ln]),
        .o_bit_error_count(ramp_biterrors[ln]),
        .o_locked(ramp_locked[ln])
    );
end
endgenerate

// legacy names for the calibration FSM, debug snapshot and ILA (ADC1 chA/chB);
// kept so the post-synth debug hook can find them by these exact names
(* keep = "true" *) wire [31:0] chA_ramp_samples,   chB_ramp_samples;
(* keep = "true" *) wire [31:0] chA_ramp_errors,    chB_ramp_errors;
(* keep = "true" *) wire [31:0] chA_ramp_biterrors, chB_ramp_biterrors;
(* keep = "true" *) wire        chA_ramp_locked,    chB_ramp_locked;
(* keep = "true" *) wire [ADCBITS-1:0] chA_ramp_expected, chB_ramp_expected;
assign chA_ramp_samples   = ramp_samples[0];
assign chB_ramp_samples   = ramp_samples[1];
assign chA_ramp_errors    = ramp_errors[0];
assign chB_ramp_errors    = ramp_errors[1];
assign chA_ramp_biterrors = ramp_biterrors[0];
assign chB_ramp_biterrors = ramp_biterrors[1];
assign chA_ramp_locked    = ramp_locked[0];
assign chB_ramp_locked    = ramp_locked[1];
assign chA_ramp_expected  = ramp_expected[0];
assign chB_ramp_expected  = ramp_expected[1];

/****************************************************************************/
/* Self-calibrating sweep: per-ADC IDELAY tap + per-lane word rotation.     */
/*                                                                          */
/* The one-lane deserializer captures the two DDR half-bits with two        */
/* ISERDES: EVEN (undelayed) and ODD (via the data IDELAYE2). The ODD tap   */
/* must land in the data eye or the interleaved word is garbled. On top of  */
/* that, the word boundary itself is only known up to a constant offset     */
/* (see the rotation block above). This FSM finds both against the ADC     */
/* digital-ramp test pattern, in three phases:                              */
/*                                                                          */
/*   R0  coarse rotation search: at 4 spread-out taps, sweep all ROT_POS    */
/*       window bases (applied to all lanes at once) and record each        */
/*       lane's best base. Coarse taps guard against the power-on tap      */
/*       sitting on an eye edge and drowning the base search in bit noise.  */
/*   T   tap sweep at the per-lane best bases: all 32 taps, each ADC       */
/*       judged on the SUM of its own 4 lanes' sample mismatches - the two  */
/*       ADCs' DCLKs take different fabric routes, so each gets its own     */
/*       winner (this replaces the old single tap tuned on ADC1 chB only). */
/*   R1  fine rotation re-sweep at the final taps; per-lane best is then    */
/*       COMMITTED. Lanes whose best window still shows >= ERR_TRUST_MAX    */
/*       mismatches were not seeing a plausible ramp (e.g. firmware only    */
/*       ramps chA/chB) and inherit the base of their ADC's chB lane        */
/*       instead of freezing noise-fit garbage.                             */
/*                                                                          */
/* ~97 windows x ~4.4ms = ~0.45s once after reset. Minimize SAMPLE          */
/* mismatches, not bit-errors: a frozen word scores ~1 bit-error/sample     */
/* and would win a bit-error sweep, but it mismatches the prev+1 ramp       */
/* EVERY sample - sample errors are ~max for stuck OR misframed capture     */
/* and ~0 only for a truly correct ramp. Runs in the lvds_dclk_buffered     */
/* domain, same as the ramp checkers - no CDC. rot_base changes reach the   */
/* rotation muxes mid-stream, which momentarily tears one word - part of    */
/* sweeping, gone once committed.                                           */
/****************************************************************************/
localparam [19:0] CAL_SETTLE = 20'd2048;    // ~17us settle after a change
localparam [19:0] CAL_WINDOW = 20'd524288;  // ~4.4ms error-count window
localparam [31:0] ERR_TRUST_MAX = 32'd1024; // ramp-plausibility threshold:
    // a live-RF (non-ramp) window mismatches ~87k of ~87k samples, a
    // correctly framed ramp ~0 - anything above this is "not a ramp"
localparam NL = 2*NCH; // 8 lanes

// the 4 spread-out taps used during the coarse rotation phase
function [4:0] cal_coarse_tap;
    input [1:0] i;
    begin
        case (i)
            2'd0:    cal_coarse_tap = 5'd0;
            2'd1:    cal_coarse_tap = 5'd10;
            2'd2:    cal_coarse_tap = 5'd21;
            default: cal_coarse_tap = 5'd31;
        endcase
    end
endfunction

localparam PH_R0 = 2'd0, PH_T = 2'd1, PH_R1 = 2'd2;
localparam CAL_LOAD=3'd0, CAL_SETTLE_ST=3'd1, CAL_MEAS=3'd2, CAL_LATCH=3'd3,
           CAL_JUDGE=3'd4, CAL_COMMIT=3'd5, CAL_HELD=3'd6;
(* mark_debug = "true" *) reg [2:0]  cal_state;
(* mark_debug = "true" *) reg [1:0]  cal_phase;
(* mark_debug = "true" *) reg        cal_done;
(* mark_debug = "true" *) reg [NL-1:0] cal_lane_ok; // per-lane: best window was ramp-plausible
reg [1:0]  cal_coarse_i;                 // R0: coarse-tap index
reg [3:0]  cal_base_i;                   // R0/R1: swept window base
reg [4:0]  cal_tap_i;                    // T: swept tap
(* mark_debug = "true" *) reg [4:0]  tap_best1, tap_best2;
reg [31:0] tap_best_err1, tap_best_err2;
reg [19:0] cal_timer;
reg [31:0] cal_err_start  [0:NL-1];
reg [31:0] cal_err_delta  [0:NL-1];
reg [31:0] base_best_err  [0:NL-1];
reg [3:0]  base_best      [0:NL-1];
integer li;

// per-ADC mismatch sums for the tap phase (regs are stable in CAL_JUDGE)
wire [33:0] cal_sum_adc1 = cal_err_delta[0] + cal_err_delta[1]
                         + cal_err_delta[2] + cal_err_delta[3];
wire [33:0] cal_sum_adc2 = cal_err_delta[4] + cal_err_delta[5]
                         + cal_err_delta[6] + cal_err_delta[7];

always @(posedge lvds_dclk_buffered or posedge global_rst) begin
    if (global_rst) begin
        cal_tap1      <= 5'd0;
        cal_tap2      <= 5'd0;
        cal_load1     <= 1'b0;
        cal_load2     <= 1'b0;
        cal_phase     <= PH_R0;
        cal_coarse_i  <= 2'd0;
        cal_base_i    <= 4'd0;
        cal_tap_i     <= 5'd0;
        tap_best1     <= 5'd0;
        tap_best2     <= 5'd0;
        tap_best_err1 <= 32'hFFFFFFFF;
        tap_best_err2 <= 32'hFFFFFFFF;
        cal_timer     <= 20'd0;
        cal_state     <= CAL_LOAD;
        cal_done      <= 1'b0;
        cal_lane_ok   <= {NL{1'b0}};
        for (li = 0; li < NL; li = li + 1) begin
            cal_err_start[li] <= 32'd0;
            cal_err_delta[li] <= 32'd0;
            base_best_err[li] <= 32'hFFFFFFFF;
            base_best[li]     <= 4'd0;
            rot_base[li]      <= 4'd0;
        end
    end
    else begin
        cal_load1 <= 1'b0; // loads are one-cycle pulses; default deasserted
        cal_load2 <= 1'b0;
        case (cal_state)
            CAL_LOAD: begin // apply this window's taps + rotation bases
                case (cal_phase)
                    PH_R0: begin
                        cal_tap1 <= cal_coarse_tap(cal_coarse_i);
                        cal_tap2 <= cal_coarse_tap(cal_coarse_i);
                        for (li = 0; li < NL; li = li + 1)
                            rot_base[li] <= cal_base_i;
                    end
                    PH_T: begin
                        cal_tap1 <= cal_tap_i;
                        cal_tap2 <= cal_tap_i;
                        for (li = 0; li < NL; li = li + 1)
                            rot_base[li] <= base_best[li];
                    end
                    default: begin // PH_R1
                        cal_tap1 <= tap_best1;
                        cal_tap2 <= tap_best2;
                        for (li = 0; li < NL; li = li + 1)
                            rot_base[li] <= cal_base_i;
                    end
                endcase
                cal_load1 <= 1'b1;
                cal_load2 <= 1'b1;
                cal_timer <= 20'd0;
                cal_state <= CAL_SETTLE_ST;
            end
            CAL_SETTLE_ST: begin // let the delay + pipeline settle
                if (cal_timer >= CAL_SETTLE) begin
                    for (li = 0; li < NL; li = li + 1)
                        cal_err_start[li] <= ramp_errors[li];
                    cal_timer <= 20'd0;
                    cal_state <= CAL_MEAS;
                end
                else cal_timer <= cal_timer + 20'd1;
            end
            CAL_MEAS: begin // count errors accrued this window
                if (cal_timer >= CAL_WINDOW)
                    cal_state <= CAL_LATCH;
                else cal_timer <= cal_timer + 20'd1;
            end
            CAL_LATCH: begin // snapshot per-lane deltas (gate on locked so an
                             // unlocked no-sample lane can't latch a bogus win)
                for (li = 0; li < NL; li = li + 1)
                    cal_err_delta[li] <= ramp_locked[li]
                        ? (ramp_errors[li] - cal_err_start[li])
                        : 32'hFFFFFFFF;
                cal_state <= CAL_JUDGE;
            end
            CAL_JUDGE: begin
                cal_state <= CAL_LOAD; // default: next window
                case (cal_phase)
                    PH_R0: begin
                        for (li = 0; li < NL; li = li + 1)
                            if (cal_err_delta[li] < base_best_err[li]) begin
                                base_best_err[li] <= cal_err_delta[li];
                                base_best[li]     <= cal_base_i;
                            end
                        if (cal_base_i == ROT_POS-1) begin
                            cal_base_i <= 4'd0;
                            if (cal_coarse_i == 2'd3) begin
                                cal_phase <= PH_T;
                                cal_tap_i <= 5'd0;
                            end
                            else cal_coarse_i <= cal_coarse_i + 2'd1;
                        end
                        else cal_base_i <= cal_base_i + 4'd1;
                    end
                    PH_T: begin
                        if (cal_sum_adc1 < {2'b00, tap_best_err1}) begin
                            tap_best_err1 <= cal_sum_adc1[31:0];
                            tap_best1     <= cal_tap_i;
                        end
                        if (cal_sum_adc2 < {2'b00, tap_best_err2}) begin
                            tap_best_err2 <= cal_sum_adc2[31:0];
                            tap_best2     <= cal_tap_i;
                        end
                        if (cal_tap_i == 5'd31) begin
                            cal_phase  <= PH_R1;
                            cal_base_i <= 4'd0;
                            // fresh slate for the fine rotation re-sweep
                            for (li = 0; li < NL; li = li + 1)
                                base_best_err[li] <= 32'hFFFFFFFF;
                        end
                        else cal_tap_i <= cal_tap_i + 5'd1;
                    end
                    default: begin // PH_R1
                        for (li = 0; li < NL; li = li + 1)
                            if (cal_err_delta[li] < base_best_err[li]) begin
                                base_best_err[li] <= cal_err_delta[li];
                                base_best[li]     <= cal_base_i;
                            end
                        if (cal_base_i == ROT_POS-1)
                            cal_state <= CAL_COMMIT;
                        else cal_base_i <= cal_base_i + 4'd1;
                    end
                endcase
            end
            CAL_COMMIT: begin // freeze per-lane bases (taps already loaded)
                for (li = 0; li < NL; li = li + 1) begin
                    if (base_best_err[li] < ERR_TRUST_MAX) begin
                        rot_base[li]    <= base_best[li];
                        cal_lane_ok[li] <= 1'b1;
                    end
                    else begin
                        // lane wasn't seeing a ramp - inherit its ADC's chB
                        // lane result rather than freezing a noise fit
                        rot_base[li]    <= (li < NL/2) ? base_best[1]
                                                       : base_best[NL/2+1];
                        cal_lane_ok[li] <= 1'b0;
                    end
                end
                cal_done  <= 1'b1;
                cal_state <= CAL_HELD;
            end
            CAL_HELD: begin
            end
            default: cal_state <= CAL_HELD;
        endcase
    end
end

/* Diagnostic snapshot: re-register the recovered ADC samples (adc_ipar/qpar)
   and the ramp checker's expected values into the clk_120M domain so they can
   be observed on u_ila_0, which arms reliably. These lvds_dclk-domain buses
   are stable for ~6 clk_120M cycles between the 20MHz samples, so a single
   async register tears only on the occasional transition cycle - fine for
   seeing the ramp pattern. Purely observational. */
(* mark_debug = "true" *) reg [11:0] dbg_adc_ipar, dbg_adc_qpar;
(* mark_debug = "true" *) reg [11:0] dbg_chA_expected, dbg_chB_expected;
(* mark_debug = "true" *) reg        dbg_frameStrobe;
(* mark_debug = "true" *) reg [4:0]  dbg_cal_best_tap, dbg_cal_tap;
(* mark_debug = "true" *) reg        dbg_cal_done;
always @(posedge clk_120M) begin
    dbg_adc_ipar     <= adc_ipar;
    dbg_adc_qpar     <= adc_qpar;
    dbg_chA_expected <= chA_ramp_expected;
    dbg_chB_expected <= chB_ramp_expected;
    dbg_frameStrobe  <= adc_frameStrobe;
    dbg_cal_best_tap <= tap_best1;
    dbg_cal_tap      <= cal_tap1;
    dbg_cal_done     <= cal_done;
end

/* Inverting the top address bit swaps the upper/lower half of the spectrum
   memory - i.e. an FFT-shift. For this complex FFT it is exactly what is
   needed to put DC in the middle with negative frequencies on the left and
   positive on the right. */
wire[FFTLEN-1:0]    mem_wrAddr;
assign mem_wrAddr = {~adc_frameCounter[FFTLEN-1], adc_frameCounter[FFTLEN-2:0]};

/**********************************************************************************
    ######      #     #     #   ###    #####          #######  #######  #######
    #     #    # #    ##    #   ###   #     #         #        #           #
    #     #   #   #   # #   #    #    #               #        #           #
    #     #  #     #  #  #  #   #      #####          #####    #####       #
    #     #  #######  #   # #               #         #        #           #
    #     #  #     #  #    ##         #     #         #        #           #
    ######   #     #  #     #          #####          #        #           #
***********************************************************************************/
/* Per-channel digital DC removal (zero-IF center-spike suppression). Each
   channel's I/Q pair carries its own static DC offset (LO self-mixing plus
   baseband/coupling offsets of the direct-conversion front end). A leaky
   integrator per rail tracks the mean: acc += (sample - acc>>K), dc=acc>>K,
   K=15 -> first-order high-pass with fc ~= 97Hz at 20MSPS - five orders of
   magnitude below the 19.5kHz bin width, so only the DC bin is nulled. The
   cleaned samples feed BOTH the AGC peak detector and the FFT. Settles ~5ms. */
localparam DC_K = 15;

wire signed [ADCBITS-1:0] hp_i [0:NCH-1];
wire signed [ADCBITS-1:0] hp_q [0:NCH-1];
wire [11:0] adc_avg_peak [0:NCH-1]; // per-channel averaged wave amplitude
wire [6:0]  adc_db_mag   [0:NCH-1]; // same in -dBFS
reg  [11:0] avg_peak_r   [0:NCH-1]; // driven by the level-readout block below

genvar c;
generate for (c = 0; c < NCH; c = c + 1) begin : gen_ch

    wire signed [ADCBITS-1:0] raw_i = lane_sample[2*c];
    wire signed [ADCBITS-1:0] raw_q = lane_sample[2*c+1];

    reg signed [ADCBITS+DC_K-1:0] dc_acc_i, dc_acc_q;
    wire signed [ADCBITS-1:0] dc_i = dc_acc_i >>> DC_K;
    wire signed [ADCBITS-1:0] dc_q = dc_acc_q >>> DC_K;

    always @(posedge lvds_dclk_buffered) begin
        if (global_rst) begin
            dc_acc_i <= 0;
            dc_acc_q <= 0;
        end
        else if (adc_frameStrobe) begin
            dc_acc_i <= dc_acc_i + (raw_i - dc_i);
            dc_acc_q <= dc_acc_q + (raw_q - dc_q);
        end
    end

    /* subtract, with saturation: a near-full-scale sample minus an
       opposite-sign offset can exceed 12 bits for a moment.
       REGISTERED per channel (one sample of latency, identical for all four
       channels, so every FFT frame still holds 1024 contiguous same-channel
       samples) - this keeps the subtract/saturate out of the long
       mux->abs->AGC timing path, which failed at 120MHz when combinational. */
    wire signed [ADCBITS:0] hp_i_full = raw_i - dc_i;
    wire signed [ADCBITS:0] hp_q_full = raw_q - dc_q;
    reg signed [ADCBITS-1:0] hp_i_r, hp_q_r;
    always @(posedge lvds_dclk_buffered) begin
        if (global_rst) begin
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
    assign hp_i[c] = hp_i_r;
    assign hp_q[c] = hp_q_r;

    /* Per-channel dBFS conversion of the averaged wave amplitude, for the
       pane's level readout: L16 = 16*log2(peak) via MSB position + a 16-entry
       mantissa LUT, then dB = (176 - L16)*6.02/16 ~= *3/8, rounded. */
    reg [3:0] pk_msb;
    always @* begin
        casez (avg_peak_r[c])
            12'b1???????????: pk_msb = 4'd11;
            12'b01??????????: pk_msb = 4'd10;
            12'b001?????????: pk_msb = 4'd9;
            12'b0001????????: pk_msb = 4'd8;
            12'b00001???????: pk_msb = 4'd7;
            12'b000001??????: pk_msb = 4'd6;
            12'b0000001?????: pk_msb = 4'd5;
            12'b00000001????: pk_msb = 4'd4;
            12'b000000001???: pk_msb = 4'd3;
            12'b0000000001??: pk_msb = 4'd2;
            12'b00000000001?: pk_msb = 4'd1;
            default:          pk_msb = 4'd0;
        endcase
    end
    wire [11:0] pk_norm = avg_peak_r[c] << (4'd11 - pk_msb); // MSB now at bit 11
    reg [3:0] pk_lut; // round(16*log2(1 + n/16)) for the 4 bits below the MSB
    always @* begin
        case (pk_norm[10:7])
            4'd0: pk_lut=4'd0;  4'd1: pk_lut=4'd1;  4'd2: pk_lut=4'd3;  4'd3: pk_lut=4'd4;
            4'd4: pk_lut=4'd5;  4'd5: pk_lut=4'd6;  4'd6: pk_lut=4'd7;  4'd7: pk_lut=4'd8;
            4'd8: pk_lut=4'd9;  4'd9: pk_lut=4'd10; 4'd10:pk_lut=4'd11; 4'd11:pk_lut=4'd12;
            4'd12:pk_lut=4'd13; 4'd13:pk_lut=4'd14; 4'd14:pk_lut=4'd14; 4'd15:pk_lut=4'd15;
        endcase
    end
    wire [7:0] pk_l16   = {pk_msb, 4'b0000} + {4'b0000, pk_lut};
    wire [7:0] db_diff  = 8'd176 - pk_l16;
    wire [9:0] db_x3    = {2'b00, db_diff} + {1'b0, db_diff, 1'b0}; // diff*3
    assign adc_db_mag[c]   = (avg_peak_r[c] == 12'd0) ? 7'd99
                             : ((db_x3 + 10'd4) >> 3); // /8 rounded; 0..66
    assign adc_avg_peak[c] = avg_peak_r[c];
end
endgenerate

/****************************************************************************/
/* Channel rotation + per-channel auto-ranging input shift (block floating  */
/* point). ONE FFT is shared: each 1024-sample input frame belongs to one   */
/* channel, round-robin. The FFT pipeline (ZipCPU fftgen, BFLYSHIFT=0)      */
/* wraps if a coherent tone exceeds ~128 LSB at its input, while the chain  */
/* spans 3 LSB (ADC noise rms) .. 2047 LSB - so per channel, the peak       */
/* |sample| of each frame picks a shift 0..4 (6dB hysteresis), and +16      */
/* log-counts per shift step are added back at the display write so every   */
/* pane stays absolutely calibrated in any ranging state.                   */
/*                                                                          */
/* in_ctr counts FFT CE ticks mod 1024 from reset - the pipeline defines    */
/* its input frames exactly the same way (all internal counters run on CE   */
/* from the same reset), so in_ctr==0 IS the first sample of an FFT input   */
/* frame, with no assumption about pipeline latency.                        */
/****************************************************************************/
reg  [FFTLEN-1:0] in_ctr;
(* mark_debug = "true" *) reg [1:0] fft_chan; // channel now feeding the FFT
reg  [2:0] agc_shift_ch [0:NCH-1];
(* mark_debug = "true" *) reg [2:0] active_shift; // shift applied to the current input frame
reg  [11:0] agc_peak_acc;

wire signed [ADCBITS-1:0] sel_i = hp_i[fft_chan];
wire signed [ADCBITS-1:0] sel_q = hp_q[fft_chan];

wire [11:0] agc_abs_i = sel_i[ADCBITS-1] ? (~sel_i + 1'b1) : sel_i;
wire [11:0] agc_abs_q = sel_q[ADCBITS-1] ? (~sel_q + 1'b1) : sel_q;
wire [11:0] agc_abs_max = (agc_abs_i > agc_abs_q) ? agc_abs_i : agc_abs_q;

/* Registered |sample| with a channel tag: breaks the mux->abs->threshold
   chain across a register (the raw chain missed 120MHz timing). The tag
   gates the peak accumulator so the one cross-frame-boundary sample (which
   belongs to the PREVIOUS channel after rotation) can never contaminate the
   next channel's peak - each frame's AGC peak covers 1023 of its 1024
   samples, which is statistically identical. */
reg  [11:0] abs_max_r;
reg  [1:0]  abs_chan_r;
reg         abs_vld_r;
always @(posedge lvds_dclk_buffered) begin
    if (global_rst)
        abs_vld_r <= 1'b0;
    else if (adc_frameStrobe) begin
        abs_max_r  <= agc_abs_max;
        abs_chan_r <= fft_chan;
        abs_vld_r  <= 1'b1;
    end
end
wire abs_for_cur = abs_vld_r && (abs_chan_r == fft_chan);
wire [11:0] peak_final = (abs_for_cur && abs_max_r > agc_peak_acc) ? abs_max_r
                                                                   : agc_peak_acc;

/* raise fast at 7/8 of the exact 128<<shift wrap limits, lower only 6dB below
   them - hysteresis so a peak hovering at a boundary can't flutter the shift */
wire [2:0] agc_shift_up = (peak_final < 12'd112) ? 3'd0 :
                          (peak_final < 12'd224) ? 3'd1 :
                          (peak_final < 12'd448) ? 3'd2 :
                          (peak_final < 12'd896) ? 3'd3 : 3'd4;
wire [2:0] agc_shift_dn = (peak_final < 12'd56)  ? 3'd0 :
                          (peak_final < 12'd112) ? 3'd1 :
                          (peak_final < 12'd224) ? 3'd2 :
                          (peak_final < 12'd448) ? 3'd3 : 3'd4;
wire [2:0] agc_new_shift = (agc_shift_up > active_shift) ? agc_shift_up :
                           (agc_shift_dn < active_shift) ? agc_shift_dn : active_shift;

wire [1:0] next_chan = fft_chan + 2'd1;
wire in_frame_end   = adc_frameStrobe && (in_ctr == {FFTLEN{1'b1}});
wire in_frame_start = adc_frameStrobe && (in_ctr == {FFTLEN{1'b0}});

always @(posedge lvds_dclk_buffered) begin
    if (global_rst) begin
        in_ctr       <= 0;
        fft_chan     <= 2'd0;
        active_shift <= 3'd4; // power-up in the safe (max-shift) state
        agc_peak_acc <= 12'd0;
        agc_shift_ch[0] <= 3'd4;
        agc_shift_ch[1] <= 3'd4;
        agc_shift_ch[2] <= 3'd4;
        agc_shift_ch[3] <= 3'd4;
    end
    else if (adc_frameStrobe) begin
        in_ctr <= in_ctr + 1'b1; // wraps mod 1024
        if (in_ctr == {FFTLEN{1'b1}}) begin // last sample of this channel's frame
            agc_shift_ch[fft_chan] <= agc_new_shift;   // retune the finished channel
            fft_chan     <= next_chan;                 // rotate
            active_shift <= agc_shift_ch[next_chan];   // next frame's applied shift
            agc_peak_acc <= 12'd0;
        end
        else if (abs_for_cur && abs_max_r > agc_peak_acc)
            agc_peak_acc <= abs_max_r;
    end
end

/* Averaged ADC wave amplitude per channel for the on-screen level readouts:
   mean of that channel's per-FFT-frame peaks over 4096 of its frames = 0.84s
   (each channel owns every 4th frame), so the 1s-latched display shows a true
   average. */
reg [23:0] pk_sum    [0:NCH-1];
reg [11:0] pk_frames [0:NCH-1];
wire [23:0] pk_sum_next = pk_sum[fft_chan] + {12'b0, peak_final};

integer pi;
always @(posedge lvds_dclk_buffered) begin
    if (global_rst) begin
        for (pi = 0; pi < NCH; pi = pi + 1) begin
            pk_sum[pi]     <= 24'd0;
            pk_frames[pi]  <= 12'd0;
            avg_peak_r[pi] <= 12'd0;
        end
    end
    else if (in_frame_end) begin
        if (pk_frames[fft_chan] == 12'd4095) begin
            avg_peak_r[fft_chan] <= pk_sum_next[23:12];
            pk_sum[fft_chan]     <= 24'd0;
            pk_frames[fft_chan]  <= 12'd0;
        end
        else begin
            pk_sum[fft_chan]    <= pk_sum_next;
            pk_frames[fft_chan] <= pk_frames[fft_chan] + 12'd1;
        end
    end
end

wire signed [ADCBITS-1:0] fft_in_i = sel_i >>> active_shift;
wire signed [ADCBITS-1:0] fft_in_q = sel_q >>> active_shift;

fftmain fft0(
    .i_clk(lvds_dclk_buffered),
    .i_reset(global_rst),
    .i_ce(adc_frameStrobe),
    .i_sample({fft_in_i, fft_in_q}),
    .o_result(fft_result),
    .o_sync(fft_lineSync)
);

/***************************/
/*  Calculate the log of the squared output  */
/***************************/
localparam logfn_ow = 9; //width of the output of the log() module

(* keep = "true", mark_debug = "true" *) wire[logfn_ow-1:0]  logfn_result;

logfn #(
    16, 8
) logfn_0 (
    .i_clk(lvds_dclk_buffered),
    .i_reset(global_rst),
    .i_ce(fft_frameStrobe),
    .i_sync(fft_lineSync),
    .i_real(fft_result[31:16]),
    .i_imag(fft_result[15:0]),
    .o_sample(logfn_result),
    .o_sync(logfn_lineSync)
);

/****************************************************************************/
/* Input-frame -> output-frame tag FIFO: pushed with {channel, shift} at    */
/* the first CE of every input frame, popped at every logfn output sync -   */
/* push k and pop k are the same frame by construction, so the routing is   */
/* exact for ANY fixed pipeline latency (depth 8 covers up to 8 frames of   */
/* it; the real latency is ~2-3 frames).                                    */
/****************************************************************************/
reg [4:0] tag_mem [0:7];
reg [2:0] tag_wr, tag_rd;
(* mark_debug = "true" *) reg [1:0] out_chan;  // channel the CURRENT output frame belongs to
reg [2:0] out_shift; // AGC shift that was applied to that frame's input
wire [4:0] tag_head = tag_mem[tag_rd];

/* Per-pane peak decay pacing (see peak RAM section): every 4th video frame
   ALL panes get one decay step pending; each pane's step is applied during
   the next output frame belonging to it (at most 205us later). */
reg [NCH-1:0] decay_pending;
reg           decay_active;
reg [1:0]     decay_frame_ctr;

/* video-frame tick, synchronized into the processing domain */
reg [2:0] wfsync_sync;
always @(posedge lvds_dclk_buffered)
    wfsync_sync <= {wfsync_sync[1:0], wf_RdScreenSync};
wire vframe_tick = wfsync_sync[1] & ~wfsync_sync[2];

always @(posedge lvds_dclk_buffered) begin
    if (global_rst) begin
        tag_wr    <= 3'd0;
        tag_rd    <= 3'd0;
        out_chan  <= 2'd0;
        out_shift <= 3'd4;
        decay_pending   <= {NCH{1'b0}};
        decay_active    <= 1'b0;
        decay_frame_ctr <= 2'd0;
    end
    else begin
        if (in_frame_start) begin
            tag_mem[tag_wr] <= {fft_chan, active_shift};
            tag_wr <= tag_wr + 3'd1;
        end
        if (adc_frameStrobe && logfn_lineSync) begin // first output of a frame
            out_chan  <= tag_head[4:3];
            out_shift <= tag_head[2:0];
            tag_rd <= tag_rd + 3'd1;
            decay_active <= decay_pending[tag_head[4:3]];
            decay_pending[tag_head[4:3]] <= 1'b0;
        end
        if (vframe_tick) begin
            decay_frame_ctr <= decay_frame_ctr + 2'd1;
            if (decay_frame_ctr == 2'd3)
                decay_pending <= {NCH{1'b1}}; // set AFTER the clear above so it can't be lost
        end
    end
end

/***********************************************************************************************************
     #####   ######   #######   #####   #######  ######   #     #  #     #       ######      #     #     #
    #     #  #     #  #        #     #     #     #     #  #     #  ##   ##       #     #    # #    ##   ##
    #        #     #  #        #           #     #     #  #     #  # # # #       #     #   #   #   # # # #
     #####   ######   #####    #           #     ######   #     #  #  #  #       ######   #     #  #  #  #
          #  #        #        #           #     #   #    #     #  #     #       #   #    #######  #     #
    #     #  #        #        #     #     #     #    #   #     #  #     #       #    #   #     #  #     #
     #####   #        #######   #####      #     #     #   #####   #     #       #     #  #     #  #     #
***********************************************************************************************************/

(* mark_debug = "true" *) wire spectrumActive;

(* keep = "true" *) reg [1:0] wrSpec_state;
localparam state_wrSpec_read  = 2'b00;
localparam state_wrSpec_write = 2'b01;
localparam state_wrSpec_wait  = 2'b10;
initial wrSpec_state = state_wrSpec_read;

(* keep = "true" *) reg wrSpec_wea;
initial wrSpec_wea = 0;
(* keep = "true" *) reg wrPeak_wea;
initial wrPeak_wea = 0;
(* keep = "true" *) reg [7:0] wrSpec_new;
(* keep = "true" *) reg [7:0] wrSpec_peak;
wire [7:0] wrPeak_old; // old peak value of the CURRENT output channel's bank

/* log-domain auto-range compensation: +16 counts per AGC shift bit of the
   frame now emerging from the pipeline (out_shift, exact via the tag FIFO);
   saturating 9-bit sum, clamped to 8'hFF below */
wire [8:0] spec_comp  = {1'b0, logfn_result[7:0]} + {2'b00, out_shift, 4'b0000};
wire [7:0] spec_fresh = spec_comp[8] ? 8'hFF : spec_comp[7:0];
/* decayed old peak, floor-guarded (0-1 would wrap to 255) */
wire [7:0] peak_decayed = (decay_active && wrPeak_old != 8'd0) ? (wrPeak_old - 8'd1)
                                                               : wrPeak_old;

/* Waterfall column decimation: two adjacent bins -> one stored column (max),
   so a 128x512 store per pane covers the full span and each column is drawn
   2px wide, aligned under the same bins in the spectrum. mem_wrAddr walks
   even-then-odd within every aligned pair (the FFT-shift only inverts the MSB),
   so a simple hold register pairs them up. */
reg  [7:0] wf_hold;
reg        wf_wea;
reg  [8:0] wf_wcol;
reg  [7:0] wf_wdata;

always@(negedge lvds_dclk_buffered)
begin

    case(wrSpec_state)

        state_wrSpec_read:
        begin
            if(mem_wordWrStrobe == 1'b1) begin

                /* Live trace: always store the NEWEST auto-range-compensated
                   log value (spec_fresh - see its definition above for the
                   AGC compensation math).
                   Peak RAM: max(fresh, decayed old peak) for EVERY bin on
                   EVERY sweep - uniform decay (decay_active spans exactly one
                   whole sweep of this pane when armed). */
                wrSpec_peak <= (spec_fresh > peak_decayed) ? spec_fresh : peak_decayed;
                wrPeak_wea <= 1;
                wrSpec_new <= spec_fresh;
                wrSpec_wea <= 1;
                if (mem_wrAddr[0] == 1'b0)
                    wf_hold <= spec_fresh;
                else begin
                    wf_wdata <= (wf_hold > spec_fresh) ? wf_hold : spec_fresh;
                    wf_wcol  <= mem_wrAddr[9:1];
                    wf_wea   <= 1;
                end
                wrSpec_state <= state_wrSpec_write;
            end
        end

        state_wrSpec_write:
        begin
            wrSpec_wea <= 0;
            wrPeak_wea <= 0;
            wf_wea     <= 0;
            wrSpec_state <= state_wrSpec_wait;
        end

        state_wrSpec_wait:
        begin
            wrSpec_state <= state_wrSpec_read;
        end

    endcase

end

/****************************************************************************/
/* Waterfall row bookkeeping. The write-row pointer (shared by all four     */
/* panes - their histories scroll in step) advances once every 8 video      */
/* frames -> 7.5 rows/s, ~17s of history over 128 rows. Read side, pixel    */
/* domain: screen.v supplies the pane-local display row (0 = top); the top  */
/* line shows the in-progress newest row and older lines follow downward    */
/* via mod-128 row arithmetic. The write-row pointer crosses into the pixel */
/* domain un-synchronized but is latched only once per frame at             */
/* wf_RdScreenSync (the last active line, vsync-adjacent, while the advance */
/* also happens on the frame tick a couple of sync-latency cycles later) -  */
/* a torn sample would cost one misplaced history line in one pane, once.   */
/****************************************************************************/
reg [6:0] wf_wr_row;
reg [2:0] wf_adv_ctr;
always @(posedge lvds_dclk_buffered) begin
    if (global_rst) begin
        wf_wr_row  <= 7'd0;
        wf_adv_ctr <= 3'd0;
    end
    else if (vframe_tick) begin
        wf_adv_ctr <= wf_adv_ctr + 3'd1;
        if (wf_adv_ctr == 3'd7)
            wf_wr_row <= wf_wr_row + 7'd1;
    end
end

reg [6:0] wf_row_snap; // pixel-domain snapshot of the write row, per frame
always @(posedge clk_pix)
    if (wf_RdScreenSync)
        wf_row_snap <= wf_wr_row;

wire [6:0] wf_rd_row = wf_row_snap - wfRow; // row 0 = newest, wraps mod 128

/****************************************************************************/
/* Per-channel display memories: spectrum + peak (1024x8 each) and the      */
/* 128x512x8 waterfall history. Write ports run in the processing domain,   */
/* gated to the bank of the channel the current OUTPUT frame belongs to     */
/* (out_chan); read ports run on the inverted pixel clock, all banks read   */
/* the same address every pixel and screen.v's pane index picks the bank.   */
/****************************************************************************/
wire [7:0] spec_doutb [0:NCH-1];
wire [7:0] peak_doutb [0:NCH-1];
wire [7:0] wf_doutb   [0:NCH-1];
wire [7:0] peak_douta [0:NCH-1];

genvar b;
generate for (b = 0; b < NCH; b = b + 1) begin : gen_membank

    dp_ram #(.ADDRBITS(10), .BITS(8)) specMem (
        .i_clka(lvds_dclk_buffered),
        .i_wea(wrSpec_wea && (out_chan == b)),
        .i_addra(mem_wrAddr),
        .i_dina(wrSpec_new),
        .o_douta(),
        .i_clkb(scr_rdStrobe),
        .i_addrb(scr_rdAddr),
        .o_doutb(spec_doutb[b])
    );

    dp_ram #(.ADDRBITS(10), .BITS(8)) peakMem (
        .i_clka(lvds_dclk_buffered),
        .i_wea(wrPeak_wea && (out_chan == b)),
        .i_addra(mem_wrAddr),
        .i_dina(wrSpec_peak),
        .o_douta(peak_douta[b]),
        .i_clkb(scr_rdStrobe),
        .i_addrb(scr_rdAddr),
        .o_doutb(peak_doutb[b])
    );

    waterfall_mem #(.ROWBITS(7), .COLBITS(9), .BITS(8)) wfMem (
        .i_wclk(lvds_dclk_buffered),
        .i_we(wf_wea && (out_chan == b)),
        .i_wrow(wf_wr_row),
        .i_wcol(wf_wcol),
        .i_wdata(wf_wdata),
        .i_rclk(scr_rdStrobe),
        .i_rrow(wf_rd_row),
        .i_rcol(scr_rdAddr[9:1]),
        .o_rdata(wf_doutb[b])
    );

end
endgenerate

/* Registered: the 4-bank douta mux spans physically spread BRAMs and would
   otherwise land in the half-cycle path into the negedge write FSM. The write
   address is stable for ~6 DCLK cycles before the write strobe, so one cycle
   of extra read latency is invisible. */
reg [7:0] peak_old_r;
always @(posedge lvds_dclk_buffered)
    peak_old_r <= peak_douta[out_chan];
assign wrPeak_old = peak_old_r;

// pane-select read muxes into screen.v (which re-registers them)
assign scr_rdSpecAmpl = spec_doutb[scr_pane];
wire [7:0] scr_rdPeak = peak_doutb[scr_pane];
assign wf_rdSpecAmpl  = wf_doutb[scr_pane];

/***********************************************************
     #####    #####   ######   #######  #######  #     #
    #     #  #     #  #     #  #        #        ##    #
    #        #        #     #  #        #        # #   #
     #####   #        ######   #####    #####    #  #  #
          #  #        #   #    #        #        #   # #
    #     #  #     #  #    #   #        #        #    ##
     #####    #####   #     #  #######  #######  #     #
************************************************************/
screen #(
    .PANE_W(960),
    .PANE_H(540),
    .SPEC_H(283),
    .STRIP_H(1),
    .WF_ROWS(128),
    .BIN_OFS(32)
)
screen_0 (
    /* spectrum ports */
    .i_amplitude(scr_rdSpecAmpl),
    .i_peak(scr_rdPeak),
    .o_ReadStrobe(scr_rdStrobe),
    .o_addr(scr_rdAddr),
    .o_pane(scr_pane),
    .o_spectrumActive(spectrumActive),
    /* waterfall ports */
    .i_wfPixel(wf_rdSpecAmpl),
    .o_wf_sync(wf_RdScreenSync),
    .o_wfActive(wfActive),
    .o_wfRow(wfRow),
    /* HDMI access */
    .i_pixClk(clk_pix), // Pixel clock = 148.75MHz @ 1920x1080
    .i_rst(global_rst),
    .o_hs(video_hs),
    .o_vs(video_vs),
    .o_de(video_de),
    .o_rgb_r(video_r),
    .o_rgb_g(video_g),
    .o_rgb_b(video_b)
);

/****************************************************************************/
/* Direction finder + polar indicator, drawn transparently in the centre of   */
/* the screen across all four spectra (POLAR_ALPHA / POLAR_DIM, top of file) */
/*                                                                          */
/* RAY COLOUR = FREQUENCY. df_amp stores the winning bin's index with each   */
/* bearing and freqmap.v ramps it blue-green-yellow-red-violet. The code is  */
/* the top 8 bits of the DISPLAY address mem_wrAddr, which is already        */
/* FFT-shifted (see its assign above), so the ramp runs in the same order as */
/* the spectrum panes read left to right: blue at the most negative offset   */
/* frequency, green/yellow around DC in the middle, violet at the highest.   */
/* A ray's colour therefore points at where along a pane its signal sits.    */
/* Colouring by |f| from DC instead is a matter of feeding the folded index  */
/* here; it would make the two band edges the same colour.                   */
/*                                                                          */
/* ANTENNA MAP. The four RASANT2400s point outward at 0/90/180/270deg on a  */
/* 25cm-radius circle. This reads the user's 0deg as compass NORTH with the */
/* angles increasing clockwise, so channel 0=N, 1=E, 2=S, 3=W. If the       */
/* physical harness differs the fix is these four parameters and nothing    */
/* else - a wrong map only rotates or mirrors the display, and it is        */
/* trivially spotted against a source of known bearing.                     */
/*                                                                          */
/* Amplitude comparison, not phase: at 2.03 lambda radius the interferometer*/
/* baselines are 2.88 lambda (adjacent) and 4.07 lambda (diagonal), so      */
/* phase alone is ~6-fold ambiguous - see the header of df_amp.v.           */
/****************************************************************************/
/* One pulse per completed round of all four channels, taken from the       */
/* out_chan 3->0 rollover and held off ~100 clocks so the negedge spectrum  */
/* write FSM has finished draining channel 3's last bins into the snapshot. */
reg [1:0] df_chan_d;
reg [6:0] df_round_dly;
always @(posedge lvds_dclk_buffered) begin
    if (global_rst) begin
        df_chan_d    <= 2'd0;
        df_round_dly <= 7'd0;
    end
    else begin
        df_chan_d <= out_chan;
        if ((df_chan_d == 2'd3) && (out_chan != 2'd3))
            df_round_dly <= 7'd100;
        else if (df_round_dly != 7'd0)
            df_round_dly <= df_round_dly - 7'd1;
    end
end
wire df_round_done = (df_round_dly == 7'd1);

wire [8:0] df_angAddr;
wire [7:0] df_angLen;
wire [7:0] df_angFrq;   // colour code of the bin that won each bearing

df_amp #(
    .FFTLEN(FFTLEN),
    .ANGBITS(9),
    .CH_N(0), .CH_E(1), .CH_S(2), .CH_W(3),
    .AMP_FLOOR(8'd128),   // noise floor gate; below this no ray is drawn at all
    .AMP_SHIFT(1),
    .FRQBITS(8),          // ray colour code = mem_wrAddr[9:2], see below
    .DIR_MIN(11'd24),     // minimum beam disagreement for a trustworthy bearing
    .STAGES(16)
) df_0 (
    .i_clk(lvds_dclk_buffered),
    .i_rst(global_rst),
    .i_wr_en(wrSpec_wea),
    .i_wr_chan(out_chan),
    .i_wr_addr(mem_wrAddr),
    .i_wr_data(wrSpec_new),
    .i_round_done(df_round_done),
    .i_frame_tick(vframe_tick),
    .i_rdClk(clk_pix),
    .i_rdAddr(df_angAddr),
    .o_rdLen(df_angLen),
    .o_rdFrq(df_angFrq)
);

wire       polar_active, polar_shade;
wire [7:0] polar_r, polar_g, polar_b;

/* Region = the whole screen, so the indicator lands dead centre on the point
   where the four panes meet and spreads its 512px disc over all four spectra.
   screen.v's grey 2x2 grid frame runs through it and is darkened with the rest
   of the background; the graticule crosshair lies along those same two lines. */
polar_view #(
    .REG_X0(0),    .REG_Y0(0),
    .REG_W(1920),  .REG_H(1080),
    .R_MAX(256),
    .STAGES(16)
) polar_0 (
    .i_pixClk(clk_pix),
    .i_rst(global_rst),
    .i_video_hs(video_hs),
    .i_video_vs(video_vs),
    .i_video_de(video_de),
    .o_angAddr(df_angAddr),
    .i_angLen(df_angLen),
    .i_angFrq(df_angFrq),
    .o_active(polar_active),
    .o_shade(polar_shade),
    .o_r(polar_r), .o_g(polar_g), .o_b(polar_b)
);

/* Per-pane readout overlays: the averaged ADC level (linear LSB + dBFS) in
   each pane's top-left corner, and the two lane bit-error rates (only
   meaningful during the front-end's ADC ramp-test mode). One instance per
   pane, outputs OR'd over the video - their render areas are disjoint by
   construction. Panes are identified by their grid position, so there is no
   channel-ID digit. */
wire [NCH-1:0] ovl_active;
wire [7:0] ovl_r [0:NCH-1];
wire [7:0] ovl_g [0:NCH-1];
wire [7:0] ovl_b [0:NCH-1];

genvar p;
generate for (p = 0; p < NCH; p = p + 1) begin : gen_overlay
    pane_overlay #(
        .PIXCLK_HZ(148_750_000),
        .UPDATE_PERIOD_S(1),
        .PANE_X0((p % 2) * 960),
        .PANE_Y0((p / 2) * 540),
        .SPEC_H(283),
        .SHOW_RATES(SHOW_RATES)
    ) pane_overlay_i (
        .i_pixClk(clk_pix),
        .i_rst(global_rst),
        .i_video_hs(video_hs),
        .i_video_vs(video_vs),
        .i_video_de(video_de),
        .i_biterrors_I(ramp_biterrors[2*p]),
        .i_biterrors_Q(ramp_biterrors[2*p+1]),
        .i_adc_peak(adc_avg_peak[p]),
        .i_adc_db(adc_db_mag[p]),
        .o_active(ovl_active[p]),
        .o_r(ovl_r[p]),
        .o_g(ovl_g[p]),
        .o_b(ovl_b[p])
    );
end
endgenerate

reg [7:0] ovl_r_mux, ovl_g_mux, ovl_b_mux;
reg       ovl_any;
integer oi;
always @* begin
    ovl_any   = 1'b0;
    ovl_r_mux = 8'h00;
    ovl_g_mux = 8'h00;
    ovl_b_mux = 8'h00;
    for (oi = 0; oi < NCH; oi = oi + 1) begin
        if (ovl_active[oi]) begin
            ovl_any   = 1'b1;
            ovl_r_mux = ovl_r[oi];
            ovl_g_mux = ovl_g[oi];
            ovl_b_mux = ovl_b[oi];
        end
    end
end

/* Display priority: the per-pane text readouts on top, then the polar indicator
   composited over screen.v's four spectra, then screen.v alone. The indicator
   owns no pixels outright - it hands over two masks and a colour:

     polar_active  it drew here          -> its colour, POLAR_ALPHA of it, over
                                            the darkened background
     polar_shade   inside the outer ring -> background at POLAR_DIM brightness
     neither                             -> screen.v untouched

   so the spectra stay readable straight through the disc and are not dimmed
   anywhere outside it. The four pane readouts sit in the pane corners, far from
   the centre, and stay on top regardless.

   THE WEIGHTS FOLD. Veiling the background and then blending the indicator over
   it is two chained multiplies, and the second would have to wait on the first.
   Both weights are compile-time constants, so their product is one too:

     out = (fg*A + (bg*D >> 8)*(256-A)) >> 8  ==  (fg*A + bg*(A1*D >> 8)) >> 8

   which is a single weighted sum per case, evaluated in parallel with the other
   two and selected by the masks. Constant weights mean shift-adds - no DSP, no
   runtime divide - and the >>8 is exact at every endpoint: A=256 gives fg, A=0
   with D=256 gives bg, D=0 gives a black disc. */
localparam integer POLAR_A   = `POLAR_ALPHA;                       // indicator
localparam integer POLAR_D   = `POLAR_DIM;                         // veil
localparam integer POLAR_A1D = ((256 - POLAR_A) * POLAR_D) / 256;  // both

function [7:0] polar_comp;
    input [7:0] fg;      // indicator pixel
    input [7:0] bg;      // spectrum/waterfall pixel underneath
    input       drawn;   // polar_active
    input       shade;   // polar_shade
    reg [15:0] acc;      // max is 255*256 = 65280 in every branch
    begin
        if      (drawn) acc = fg * POLAR_A + bg * POLAR_A1D;
        else if (shade) acc = bg * POLAR_D;
        else            acc = {bg, 8'h00};
        polar_comp = acc[15:8];
    end
endfunction

wire [7:0] comp_r = polar_comp(polar_r, video_r, polar_active, polar_shade);
wire [7:0] comp_g = polar_comp(polar_g, video_g, polar_active, polar_shade);
wire [7:0] comp_b = polar_comp(polar_b, video_b, polar_active, polar_shade);

/* Two-stage output pipeline. The composite is the deepest logic in the pixel
   domain outside pane_overlay, and it landed in the path that already ran from
   screen.v's colour registers through the overlay mux into rgb2dvi - a domain
   that had 0.399ns of slack at 148.75MHz before any of this. Stage 1 takes the
   composite, stage 2 the overlay mux, so neither has to carry the other.

   The overlays are registered in the SAME stage as the composite they will be
   muxed against, and the syncs are delayed by both stages, so everything stays
   mutually aligned and the whole frame simply shifts two pixels right - which
   is invisible. Delaying only the colour would shear the image against the
   sync. */
reg [7:0] comp_r_q, comp_g_q, comp_b_q;
reg [7:0] ovl_r_q,  ovl_g_q,  ovl_b_q;
reg       ovl_any_q;
reg       vid_hs_q, vid_vs_q, vid_de_q;
always @(posedge clk_pix) begin
    comp_r_q  <= comp_r;
    comp_g_q  <= comp_g;
    comp_b_q  <= comp_b;
    ovl_r_q   <= ovl_r_mux;
    ovl_g_q   <= ovl_g_mux;
    ovl_b_q   <= ovl_b_mux;
    ovl_any_q <= ovl_any;
    vid_hs_q  <= video_hs;
    vid_vs_q  <= video_vs;
    vid_de_q  <= video_de;
end

wire [7:0] disp_r = ovl_any_q ? ovl_r_q : comp_r_q;
wire [7:0] disp_g = ovl_any_q ? ovl_g_q : comp_g_q;
wire [7:0] disp_b = ovl_any_q ? ovl_b_q : comp_b_q;

reg [7:0] disp_r_q, disp_g_q, disp_b_q;
reg       disp_hs_q, disp_vs_q, disp_de_q;
always @(posedge clk_pix) begin
    disp_r_q  <= disp_r;
    disp_g_q  <= disp_g;
    disp_b_q  <= disp_b;
    disp_hs_q <= vid_hs_q;
    disp_vs_q <= vid_vs_q;
    disp_de_q <= vid_de_q;
end

rgb2dvi
#(
      .kGenerateSerialClk(1'b0),
      .kClkRange(1),
      .kRstActiveHigh(1'b1)
)
rgb2dvi_m0 (
     // DVI 1.0 TMDS video interface
      .TMDS_Clk_p(TMDS_clk_p),
      .TMDS_Clk_n(TMDS_clk_n),
      .TMDS_Data_p(TMDS_data_p),
      .TMDS_Data_n(TMDS_data_n),

     //Auxiliary signals
      .aRst(global_rst),
      .aRst_n(~global_rst),

      // Video in
      .vid_pData( { disp_r_q, disp_b_q, disp_g_q } ),
      .vid_pVDE(disp_de_q),
      .vid_pHSync(disp_hs_q),
      .vid_pVSync(disp_vs_q),
      .PixelClk(clk_pix),
      .SerialClk(clk_serial) // 5x PixelClk
);

endmodule
