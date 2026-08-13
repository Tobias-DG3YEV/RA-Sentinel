//////////////////////////////////////////////////////////////////////////////////
//
// Design Name: RASPMO
// Module Name: top of RASPMO
// Project Name: Radio Access Spectrum Monitor
// Engineer: Tobias Weber
// Target Devices: Artix 7, XC7A100T-CSG324 (RASBB onboard FPGA)
// Description:  Quad-split 1080p HDMI: complex (two-sided) spectrum + waterfall
//               per RX channel, one 960x540 pane each.
//
//                 CH1 = RF-TRANS_1 (U4):  ADC1 chA/chB (I/Q)
//                 CH2 = RF-TRANS_2 (U6):  ADC1 chC/chD
//                 CH3 = RF-TRANS_3 (U8):  ADC2 chA/chB
//                 CH4 = RF-TRANS_4 (U10): ADC2 chC/chD
//
//               Two ADCs, own DCLK/FCLK each, both off the front-end's 40MHz
//               TCXO -> frequency-locked, phase unknown. ADC2 hops into ADC1's
//               DCLK domain via a gray-pointer FIFO (sample_cdc.v); everything
//               downstream lives in the ADC1 domain.
//
//               One 1024-pt complex FFT PER CHANNEL (4x fftmain + 4x logfn),
//               free-running. Every sample of every channel gets transformed -
//               back-to-back 51.2us frames, no gaps, nothing for a short burst
//               to hide in and the max-hold dots see the lot.
//
//               The four chains are identical instances on one CE and one
//               reset, so they're in lockstep: same latency, o_sync on the same
//               clock. Hence ONE frame counter, ONE tag FIFO (four packed AGC
//               shifts) and ONE write FSM for all of them. Data replicated,
//               control not.
//
//               No host interface: RASBB brings no SPI into the fabric (the
//               PCIE_* nets stop at the config flash) and no reset button (S1
//               is PROGRAM_B). Reset = internal power-up pulse, that's it.
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
    input wire i_SYS_clk,
    // HDMI output
    output wire o_TMDS_clk_n,
    output wire o_TMDS_clk_p,
    output wire [2:0] o_TMDS_data_n,
    output wire [2:0] o_TMDS_data_p,
    // ADC1 LVDS input - one-wire per channel (RX1/RX2 baseband)
    input wire i_ADC_dclk_P, i_ADC_dclk_N, // 120MHz bit clock
    input wire i_ADC_fclk_P, i_ADC_fclk_N, // 20MHz frame clock
    input wire i_ADC_chA_P, i_ADC_chA_N,   // channel A = RX1 I
    input wire i_ADC_chB_P, i_ADC_chB_N,   // channel B = RX1 Q
    input wire i_ADC_chC_P, i_ADC_chC_N,   // channel C = RX2 I
    input wire i_ADC_chD_P, i_ADC_chD_N,   // channel D = RX2 Q
    // ADC2 LVDS input - one-wire per channel (RX3/RX4 baseband)
    input wire i_ADC2_dclk_P, i_ADC2_dclk_N,
    input wire i_ADC2_fclk_P, i_ADC2_fclk_N,
    input wire i_ADC2_chA_P, i_ADC2_chA_N, // channel A = RX3 I
    input wire i_ADC2_chB_P, i_ADC2_chB_N, // channel B = RX3 Q
    input wire i_ADC2_chC_P, i_ADC2_chC_N, // channel C = RX4 I
    input wire i_ADC2_chD_P, i_ADC2_chD_N  // channel D = RX4 Q
);

// -----------------------------------------------------------------------------
// Parameters
// -----------------------------------------------------------------------------
parameter FFTLEN = 10; //FFT length in bits (1024 point complex FFT)
parameter ADCBITS = 12;
parameter NCH = 4;     // receive channels (panes)

/* orange per-lane bit-error numbers under each spectrum. Only means anything
   with the BMC firmware in ADC ramp-test mode. Off -> whole render path incl.
   the BCD converters gets stripped. Level readout stays either way. */
//`define SHOW_BER_RATES

/* blind adaptive I/Q imbalance correction per channel, sits between the DC
   removal and everything downstream. Nulls E[I*Q], equalises E[Q^2]=E[I^2].
   Kills the zero-IF image (30..40dB uncorrected). ~5 DSP + 1 word latency per
   channel, I delayed to match so I/Q stay aligned. */
`define IQ_CORR

/* pane 4 -> 4-channel time-domain scope instead of CH4 spectrum+waterfall.
   960 samples/sweep, 1px = 1 sample, trigger on CH1 rising through 50% of its
   averaged peak, auto sweep if untriggered. CH1 yellow, CH2 green, CH3 cyan,
   CH4 light red. CH4's DSP keeps running, only its pixels get taken over; the
   polar disc still composites over it. Off -> whole scope path (capture +
   4x 1k x 12 dp_ram) stripped, generate ties scope_active low. */
//`define SCOPE_VIEW

`ifdef SHOW_BER_RATES
localparam SHOW_RATES = 1'b1;
`else
localparam SHOW_RATES = 1'b0;
`endif

/* Polar DF indicator blend weights, both in 256ths, exact at the endpoints.

   POLAR_ALPHA = how much of the indicator shows on pixels it DRAWS (rays,
   rings, crosshair):  0 invisible / 128 half+half / 256 opaque.
   POLAR_DIM   = how much spectrum SURVIVES inside the outer ring, i.e. the
   veil that lifts it off a busy background: 256 none / 128 half / 0 black.

   Only the 512px centre disc is touched, not the panes. Override at build
   time: set_property verilog_define {POLAR_ALPHA=96 POLAR_DIM=64} \
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

/* FFT/logfn buses are per channel - declared down at the transform chains. */

/*******************/
/* Clock generation */
/*******************/
(* mark_debug = "true" *) wire mmcm_locked;
wire hdmi_clk_locked;

/* Video_clk = 120MHz utility clock (ILA/reset domain) + 195MHz IDELAYCTRL ref.
   Its 65/325MHz video outputs are dead weight, 1080p comes from hdmi_clk. */
Video_clk video_clk0 (
    .i_clk_50M(i_SYS_clk),
    .o_clk_65M(),
    .o_clk_325M(),
    .o_clk_195M(clk_195M),
    .o_clk_120M(clk_120M),
    .reset(1'b0),
    .locked(mmcm_locked)
);

hdmi_clk hdmi_clk0 (
    .i_clk_50M(i_SYS_clk),
    .o_clk_pix(clk_pix),
    .o_clk_serial(clk_serial),
    .o_locked(hdmi_clk_locked)
);

/***************************************
    Power-up reset. No button reaches the fabric, so this is just a startup
    pulse. Counter held at 0 until BOTH MMCMs lock - clk_120M is a raw MMCM
    output and can glitch or run wrong before lock, and counting on that would
    release global_rst at some arbitrary far-too-early moment.
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

/****************************************************************************/
/* Deserializer self-heal.                                                  */
/*                                                                          */
/* Failure mode: an ADC's spectra go permanently garbled after minutes to   */
/* hours. The captured FCLK word shows EVEN and ODD bits each a clean       */
/* cyclic run of the 20MHz FCLK but offset one word position from each      */
/* other = an ISERDES bit-grouping slip across the EVEN/ODD primitive pair. */
/* CLKDIV is fabric-generated while the ISERDES clocks come straight off    */
/* the IBUFDS, so their phase relation is unconstrained silicon margin and  */
/* thermal drift can walk one primitive over an internal setup window       */
/* (UG471: any CLKDIV phase change needs an ISERDES reset).                 */
/*                                                                          */
/* Nothing downstream can see it out: IDELAY taps move sub-UI sampling, not */
/* grouping, so the supervisor sweeps all 32 forever, and lvds_rx's         */
/* re-anchor watchdog stays quiet because the FCLK edge is still at bitctr  */
/* 0. Picks on ADC2/lvds_irx1, the marginal one.                            */
/*                                                                          */
/* Cure: 2s unhealthy -> pulse fe_rst. Front half only - both lvds_rx init  */
/* FSMs (serdes_rst + re-anchor + CS), sequencers, CDC, rotation decode,    */
/* DC/IQ, supervisors. FFT/waterfall/display stay on global_rst and keep    */
/* running; o_lvds_dclk is a bare IBUFDS passthrough and never gated by     */
/* i_rst, so the processing clock survives. ~200ms to recover. A healthy    */
/* system never fires this.                                                 */
/*                                                                          */
/* Lives on clk_120M next to global_rst - the XDC already calls the         */
/* Video_clk family async to both DCLK domains and false-paths the          */
/* heal_rst_reg fanout like global_rst_reg. Only the declaration has to be  */
/* up here; the counter sits below the supervisors.                         */
/****************************************************************************/
(* keep = "true", mark_debug = "true" *) reg heal_rst_reg = 1'b0;
wire fe_rst = global_rst | heal_rst_reg;

/****************************************************************************

       #     ######    #####          #        #     #  ######    #####
      # #    #     #  #     #         #        #     #  #     #  #     #
     #   #   #     #  #               #        #     #  #     #  #
    #     #  #     #  #               #        #     #  #     #   #####
    #######  #     #  #               #         #   #   #     #        #
    #     #  #     #  #     #         #          # #    #     #  #     #
    #     #  ######    #####          #######     #     ######    #####

/****************************************************************************/

// Data-path IDELAY control - driven by the two link_supervisor instances
// further down (they need the FCLK decode, declared later). One tap per
// ADC: the two DCLKs take different (non-clock-capable, fabric-routed) paths
// to their ISERDES, so the two ADCs' data eyes do NOT sit at the same tap.
wire [4:0] cal_tap1, cal_tap2;
wire       cal_load1, cal_load2;
wire      lvds_dclk_buffered;  // BUFG'd ADC1 bit clock - the processing domain
wire      lvds_dclk2_buffered; // BUFG'd ADC2 bit clock - deserialize+CDC only

wire [4*ADCBITS-1:0] adc1_data; // lanes A..D = RX1 I/Q, RX2 I/Q
wire [4*ADCBITS-1:0] adc2_data; // lanes A..D = RX3 I/Q, RX4 I/Q (ADC2 DCLK domain)
wire [ADCBITS-1:0]   adc1_fclk_word; // FCLK captured like a data lane - see lvds_rx
wire [ADCBITS-1:0]   adc2_fclk_word; // (ADC2 DCLK domain, crosses in the CDC below)

lvds_rx #(.NLANES(4)) lvds_irx0 (
    .i_lvds_dclk_P(i_ADC_dclk_P),
    .i_lvds_dclk_N(i_ADC_dclk_N),
    .i_lvds_fclk_P(i_ADC_fclk_P),
    .i_lvds_fclk_N(i_ADC_fclk_N),
    .i_lvds_d_P({i_ADC_chD_P, i_ADC_chC_P, i_ADC_chB_P, i_ADC_chA_P}),
    .i_lvds_d_N({i_ADC_chD_N, i_ADC_chC_N, i_ADC_chB_N, i_ADC_chA_N}),
    .i_rst(fe_rst),
    .i_ctrlClk(lvds_dclk_buffered),
    .i_data_delay_tap(cal_tap1),
    .i_data_delay_load(cal_load1),
    .o_lvds_dclk(lvds_dclk),
    .o_lvds_fclk(lvds_fclk),
    .o_data(adc1_data),
    .o_fclk_word(adc1_fclk_word)
);

lvds_rx #(.NLANES(4)) lvds_irx1 (
    .i_lvds_dclk_P(i_ADC2_dclk_P),
    .i_lvds_dclk_N(i_ADC2_dclk_N),
    .i_lvds_fclk_P(i_ADC2_fclk_P),
    .i_lvds_fclk_N(i_ADC2_fclk_N),
    .i_lvds_d_P({i_ADC2_chD_P, i_ADC2_chC_P, i_ADC2_chB_P, i_ADC2_chA_P}),
    .i_lvds_d_N({i_ADC2_chD_N, i_ADC2_chC_N, i_ADC2_chB_N, i_ADC2_chA_N}),
    .i_rst(fe_rst),
    .i_ctrlClk(lvds_dclk_buffered), // cal FSM domain, shared with instance 0
    .i_data_delay_tap(cal_tap2),
    .i_data_delay_load(cal_load2),
    .o_lvds_dclk(lvds_dclk2),
    .o_lvds_fclk(lvds_fclk2),
    .o_data(adc2_data),
    .o_fclk_word(adc2_fclk_word)
);

/* Explicit BUFGs - leave it to Vivado and it drops its own in with whatever
   line delay it feels like. ADC1's clock feeds the whole pipeline, ADC2's only
   its own sequencer + the CDC write side. */
BUFG BUFG_lvds_dclk_1 (
    .I(lvds_dclk),
    .O(lvds_dclk_buffered)
);
BUFG BUFG_lvds_dclk_2 (
    .I(lvds_dclk2),
    .O(lvds_dclk2_buffered)
);

/* One IDELAYCTRL covers every IDELAYE2 in bank 35, and both lvds_rx instances
   live there. One site per bank -> it belongs here, not inside lvds_rx. */
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
    .i_rst(fe_rst),
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
    .i_rst(fe_rst),
    .o_adc_frameStrobe(adc2_frameStrobe),
    .o_fft_frameStrobe(),
    .o_frameCounter(),
    .o_mem_sampleStrobe()
);

/* ADC2 -> ADC1 CDC. Same TCXO both sides so the rates are identical; the FIFO
   only soaks up the unknown phase + startup transient. Costs CH3/CH4 one
   sample of latency, which nobody can see in per-pane spectra. */
wire [4*ADCBITS-1:0] adc2_data_s;
wire [ADCBITS-1:0]   adc2_fclk_word_s;
sample_cdc #(.W(5*ADCBITS)) adc2_cdc ( // 4 data lanes + the FCLK word: bundled
    .i_wclk(lvds_dclk2_buffered),      // so the frame decode below sees the
    .i_wrst(fe_rst),                   // FCLK word of the SAME captured word
    .i_wen(adc2_frameStrobe),          // as the data it aligns
    .i_wdata({adc2_fclk_word, adc2_data}),
    .i_rclk(lvds_dclk_buffered),
    .i_rrst(fe_rst),
    .i_ren(adc_frameStrobe),
    .o_rdata({adc2_fclk_word_s, adc2_data_s})
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

/* Per-lane word-boundary re-alignment ("rotation") off the decoded FCLK word.

   lvds_rx cuts the stream into ADCBITS-wide words at a boundary that is some
   arbitrary-but-stable offset from the ADC's real one (FCLK anchor phase,
   ISERDES CLKDIV grouping, ADC2 CDC latency - all constant, though the anchor
   can differ per CONFIGURATION if the FCLK sample lands near a DCLK edge). So
   the true sample is always SOME contiguous ADCBITS window across two
   consecutive captured words.

   FCLK rides the identical ISERDES pipeline (lvds_rx o_fclk_word) carrying a
   fixed pattern: high for the first half-word (SBAS673A Fig. 130 - word starts
   at the FCLK rising edge, LSB first), so an aligned FCLK word == FCLK_PAT.
   Slide the same window over two consecutive FCLK words, find FCLK_PAT, and
   that base is where the DATA windows are true words. Per ADC, every boot, no
   test pattern, both words shift together with the anchor.

   Commits only after 16 identical decodes in a row - a metastable capture can
   garble one word, and FCLK being periodic we get a fresh decode every word
   anyway. FCLK_PHASE_ADJ is an escape hatch if FCLK ever turns out offset from
   the data lanes by whole bits; expect 0, it comes off the same output
   structure. */
localparam ROT_POS = ADCBITS + 1; // window base positions (13)
localparam [ADCBITS-1:0] FCLK_PAT = {{(ADCBITS/2){1'b0}}, {(ADCBITS/2){1'b1}}}; // 12'h03F
localparam [3:0] FCLK_PHASE_ADJ = 4'd0;

(* keep = "true", mark_debug = "true" *) reg [ADCBITS-1:0] fclk1_cur;
reg [ADCBITS-1:0] fclk1_hist;
(* keep = "true", mark_debug = "true" *) reg [ADCBITS-1:0] fclk2_cur;
reg [ADCBITS-1:0] fclk2_hist;
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

/* Combinational pattern search. Inverted match (swapped pair on some future
   board) sits a half-word away. Bases 0 and ROT_POS-1 pick the same alignment
   one word apart; loop keeps the highest hit - deterministic, equally valid. */
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

/* Commit with hysteresis: 16 consecutive identical decodes. */
(* mark_debug = "true" *) reg [3:0] rot1_cur, rot2_cur;
reg [3:0] rot1_cand, rot2_cand;
reg [3:0] rot1_cnt,  rot2_cnt;
(* keep = "true", mark_debug = "true" *) reg [7:0] rot_change_count; // diagnostic
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
wire [3:0]         rot_base  [0:2*NCH-1]; // per-ADC decoded frame base
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

// ADC1 chA/chB aliases for the debug snapshot below (kept for ILA probing)
(* keep = "true", mark_debug = "true" *) wire [ADCBITS-1:0] adc_ipar;
(* keep = "true", mark_debug = "true" *) wire [ADCBITS-1:0] adc_qpar;
assign adc_ipar = lane_sample[0];
assign adc_qpar = lane_sample[1];

/* LVDS BER check against the ADC3424 digital-ramp pattern (BMC firmware,
   ADC1_RAMP_TEST_MODE). One checker per lane, all in the processing domain -
   ADC2's are checked AFTER the CDC on purpose, so the FIFO is under test too.
   Read-only; against real signal it just counts noise. */
wire [ADCBITS-1:0] ramp_expected  [0:2*NCH-1];
wire [31:0]        ramp_samples   [0:2*NCH-1];
wire [31:0]        ramp_errors    [0:2*NCH-1];
wire [31:0]        ramp_biterrors [0:2*NCH-1];
wire [2*NCH-1:0]   ramp_locked;

genvar ln;
generate for (ln = 0; ln < 2*NCH; ln = ln + 1) begin : gen_rampchk
    ramp_checker #(.WIDTH(ADCBITS)) ramp_checker_lane (
        .i_clk(lvds_dclk_buffered),
        .i_rst(fe_rst),
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
/* Link supervisors: per-ADC IDELAY tap ownership + auto retraining.        */
/*                                                                          */
/* fclkN_hit from the decode above is a free always-on link-health metric.  */
/* Each supervisor sweeps all 32 taps at boot counting decode misses,       */
/* commits the CENTRE of the widest clean plateau (max margin both ways),   */
/* then keeps watching and re-sweeps if misses persist - e.g. the front-end */
/* master clock tuned off 40MHz, where the fixed-ns fabric insertion delay  */
/* walks the sampling point across the scaled UI. No test pattern, works    */
/* live, reacts in ~3ms, resweeps in ~27ms. FSM details in                  */
/* link_supervisor.v.                                                       */
/****************************************************************************/
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
    .o_retrain_count(retrain_count1)
);

link_supervisor sup_adc2 (
    .i_clk(lvds_dclk_buffered),
    .i_rst(fe_rst),
    .i_ce(adc_frameStrobe),
    .i_hit(fclk2_hit),
    .o_tap(cal_tap2),
    .o_load(cal_load2),
    .o_healthy(link_ok2),
    .o_retrain_count(retrain_count2)
);

// legacy names kept for the (normally disabled) ILA snapshot below
wire       cal_done  = link_ok1 & link_ok2;
wire [4:0] tap_best1 = cal_tap1;

/* The watchdog itself - why is up at the fe_rst block. link_ok1/2 are in the
   ADC1 DCLK domain, the hop to clk_120M is covered by the XDC async groups.
   Pulse is 128 clk_120M cycles (~1.07us) so every DCLK consumer sees it many
   times over; lvds_rx treats it as an async assert anyway.
   NOTE resets on global_rst, NOT fe_rst - it has to survive its own pulse. */
(* ASYNC_REG = "true" *) reg [1:0] links_up_sync = 2'b00;
always @(posedge clk_120M) links_up_sync <= {links_up_sync[0], cal_done};

localparam HEAL_CYCLES = 28'd239_999_999;   // 2s at 120MHz
reg [27:0] dead_ctr   = 28'd0;
reg [6:0]  heal_pulse = 7'd0;
(* keep = "true", mark_debug = "true" *) reg [7:0] heal_cnt = 8'd0;
                                // lifetime heals - the one-glance ILA answer
                                // to "did the watchdog fire, or did the link
                                // recover on its own?"
always @(posedge clk_120M) begin
    if (global_rst) begin
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
        if (links_up_sync[1])
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

/* ILA snapshot: re-register the recovered samples + ramp expectations into
   clk_120M, where u_ila_0 arms reliably. These lvds_dclk buses hold still for
   ~6 clk_120M cycles between 20MHz samples, so one async register only tears
   on the odd transition cycle - good enough to eyeball a ramp. */
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

/* Flip the top address bit = swap the memory halves = FFT-shift. Puts DC in
   the middle, negative frequencies left, positive right. */
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
/* Per-channel DC kill = zero-IF centre spike suppression. Every I/Q pair has
   its own static offset (LO self-mixing + baseband/coupling offsets of a
   direct-conversion front end). Leaky integrator per rail:
       acc += (sample - acc>>K),  dc = acc>>K
   K=15 -> 1st order HPF, fc ~97Hz at 20MSPS. Five orders below the 19.5kHz bin
   width, so it nulls the DC bin and nothing else. Settles in ~5ms. Feeds BOTH
   the AGC peak detector and the FFT. */
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
        if (fe_rst) begin
            dc_acc_i <= 0;
            dc_acc_q <= 0;
        end
        else if (adc_frameStrobe) begin
            dc_acc_i <= dc_acc_i + (raw_i - dc_i);
            dc_acc_q <= dc_acc_q + (raw_q - dc_q);
        end
    end

    /* subtract + saturate: near-full-scale sample minus an opposite-sign
       offset overflows 12 bits for a moment. Registered - keep the
       subtract/saturate out of the AGC path or 120MHz won't close. Same one
       sample of latency on all four channels, so nothing skews. */
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
    iq_balance iq_bal (
        .i_clk(lvds_dclk_buffered),
        .i_rst(fe_rst),
        .i_ce(adc_frameStrobe),
        .i_i(hp_i_r),
        .i_q(hp_q_r),
        .o_i(bal_i),
        .o_q(bal_q),
        .o_wp(),
        .o_eg()
    );
    assign hp_i[c] = bal_i;
    assign hp_q[c] = bal_q;
`else
    assign hp_i[c] = hp_i_r;
    assign hp_q[c] = hp_q_r;
`endif

    /* averaged amplitude -> dBFS for the pane readout.
       L16 = 16*log2(peak) from MSB position + a 16-entry mantissa LUT, then
       dB = (176 - L16)*6.02/16 ~= *3/8, rounded. */
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
/* Frame framing for all four chains.                                       */
/*                                                                          */
/* in_ctr = FFT CE ticks mod 1024 since reset. The four fftmains are the    */
/* same module on the same CE and reset, so their internal counters frame   */
/* identically -> in_ctr==0 IS the first sample of every input frame, no    */
/* guessing at pipeline latency, one counter does the lot.                  */
/****************************************************************************/
reg  [FFTLEN-1:0] in_ctr;

wire in_frame_end   = adc_frameStrobe && (in_ctr == {FFTLEN{1'b1}});
wire in_frame_start = adc_frameStrobe && (in_ctr == {FFTLEN{1'b0}});

always @(posedge lvds_dclk_buffered) begin
    if (global_rst)
        in_ctr <= {FFTLEN{1'b0}};
    else if (adc_frameStrobe)
        in_ctr <= in_ctr + 1'b1; // wraps mod 1024
end

/****************************************************************************/
/* Per-channel auto-ranging input shift = block floating point.             */
/*                                                                          */
/* ZipCPU fftgen with BFLYSHIFT=0 wraps once a coherent tone passes ~128 LSB */
/* at its input, and the chain has to span 3 LSB (ADC noise rms) .. 2047.   */
/* So each frame's peak |sample| picks a shift 0..4 (6dB hysteresis) and the */
/* display write adds +16 log-counts per shift step back - every pane stays  */
/* absolutely calibrated whatever the ranging is doing.                     */
/* Re-ranges at the end of every frame, 51.2us.                             */
/****************************************************************************/
(* mark_debug = "true" *) wire [3*NCH-1:0] active_shift; // packed, 3 bits/channel
wire [11:0] peak_final [0:NCH-1];
wire signed [ADCBITS-1:0] fft_in_i [0:NCH-1];
wire signed [ADCBITS-1:0] fft_in_q [0:NCH-1];

genvar g;
generate for (g = 0; g < NCH; g = g + 1) begin : gen_agc

    reg  [2:0]  shift_r;   // shift applied to the frame now entering this FFT
    reg  [11:0] peak_acc;  // running max |sample| over the current input frame

    wire [11:0] abs_i = hp_i[g][ADCBITS-1] ? (~hp_i[g] + 1'b1) : hp_i[g];
    wire [11:0] abs_q = hp_q[g][ADCBITS-1] ? (~hp_q[g] + 1'b1) : hp_q[g];
    wire [11:0] abs_max = (abs_i > abs_q) ? abs_i : abs_q;

    /* Registered |sample| - splits the abs->compare->accumulate chain, cheap
       insurance at 120MHz. Costs one sample of delay, so a frame's last sample
       lands in the next frame's accumulator and each peak covers 1023 of 1024.
       Statistically the same thing. */
    reg [11:0] abs_max_r;
    always @(posedge lvds_dclk_buffered) begin
        if (global_rst)
            abs_max_r <= 12'd0;
        else if (adc_frameStrobe)
            abs_max_r <= abs_max;
    end

    assign peak_final[g] = (abs_max_r > peak_acc) ? abs_max_r : peak_acc;

    /* raise fast at 7/8 of the exact 128<<shift wrap limits, lower only 6dB
       below them - hysteresis so a peak hovering at a boundary can't flutter
       the shift */
    wire [2:0] shift_up = (peak_final[g] < 12'd112) ? 3'd0 :
                          (peak_final[g] < 12'd224) ? 3'd1 :
                          (peak_final[g] < 12'd448) ? 3'd2 :
                          (peak_final[g] < 12'd896) ? 3'd3 : 3'd4;
    wire [2:0] shift_dn = (peak_final[g] < 12'd56)  ? 3'd0 :
                          (peak_final[g] < 12'd112) ? 3'd1 :
                          (peak_final[g] < 12'd224) ? 3'd2 :
                          (peak_final[g] < 12'd448) ? 3'd3 : 3'd4;
    wire [2:0] new_shift = (shift_up > shift_r) ? shift_up :
                           (shift_dn < shift_r) ? shift_dn : shift_r;

    always @(posedge lvds_dclk_buffered) begin
        if (global_rst) begin
            shift_r  <= 3'd4; // power-up in the safe (max-shift) state
            peak_acc <= 12'd0;
        end
        else if (adc_frameStrobe) begin
            if (in_ctr == {FFTLEN{1'b1}}) begin // last sample of this frame
                shift_r  <= new_shift;          // retune for the next one
                peak_acc <= 12'd0;
            end
            else if (abs_max_r > peak_acc)
                peak_acc <= abs_max_r;
        end
    end

    assign active_shift[3*g +: 3] = shift_r;
    assign fft_in_i[g] = hp_i[g] >>> shift_r;
    assign fft_in_q[g] = hp_q[g] >>> shift_r;

    /* Averaged amplitude for the pane's level readout = mean of the per-frame
       peaks over 16384 frames = 0.84s, comfortably under the 1s display latch.
       16384 * 4095 = 67,092,480 -> 26 bits. */
    reg [25:0] pk_sum;
    reg [13:0] pk_frames;
    wire [25:0] pk_sum_next = pk_sum + {14'b0, peak_final[g]};

    always @(posedge lvds_dclk_buffered) begin
        if (global_rst) begin
            pk_sum        <= 26'd0;
            pk_frames     <= 14'd0;
            avg_peak_r[g] <= 12'd0;
        end
        else if (in_frame_end) begin
            if (pk_frames == 14'd16383) begin
                avg_peak_r[g] <= pk_sum_next[25:14];
                pk_sum        <= 26'd0;
                pk_frames     <= 14'd0;
            end
            else begin
                pk_sum    <= pk_sum_next;
                pk_frames <= pk_frames + 14'd1;
            end
        end
    end

end
endgenerate

/****************************************************************************/
/* FOUR INDEPENDENT FFTs - one 1024-pt complex transform + one log magnitude */
/* per channel. Free-running, so every sample gets transformed and the       */
/* max-hold traces have no gaps for a burst to hide in.                      */
/*                                                                           */
/* Same module, same i_ce, same i_reset -> exact lockstep, o_sync on the     */
/* same clock. That is what lets ONE in_ctr, ONE tag FIFO and ONE write FSM  */
/* below drive all four. Replicate data, not control.                        */
/*                                                                           */
/* ~3.3k LUT / 7.9k FF / 11.5 BRAM tiles / 8 DSP per instance.               */
/****************************************************************************/
localparam logfn_ow = 9; //width of the output of the log() module

wire [31:0] fft_result   [0:NCH-1];
wire        fft_lineSync [0:NCH-1];
wire [logfn_ow-1:0] logfn_result [0:NCH-1];
wire        logfn_sync   [0:NCH-1];

/* ILA taps - CH0 stands in for the lot, they're timing-identical and probing
   all four would cost 4x the capture width. */
(* keep = "true", mark_debug = "true" *) wire [31:0] dbg_fft_result = fft_result[0];
(* keep = "true", mark_debug = "true" *) wire [logfn_ow-1:0] dbg_logfn_result = logfn_result[0];

generate for (g = 0; g < NCH; g = g + 1) begin : gen_fft

    fftmain fftx (
        .i_clk(lvds_dclk_buffered),
        .i_reset(global_rst),
        .i_ce(adc_frameStrobe),
        .i_sample({fft_in_i[g], fft_in_q[g]}),
        .o_result(fft_result[g]),
        .o_sync(fft_lineSync[g])
    );

    logfn #(
        16, 8
    ) logfnx (
        .i_clk(lvds_dclk_buffered),
        .i_reset(global_rst),
        .i_ce(fft_frameStrobe),
        .i_sync(fft_lineSync[g]),
        .i_real(fft_result[g][31:16]),
        .i_imag(fft_result[g][15:0]),
        .o_sample(logfn_result[g]),
        .o_sync(logfn_sync[g])
    );

end
endgenerate

/* One sync frames the bank (lockstep, see above) and feeds the sequencer. */
assign logfn_lineSync = logfn_sync[0];

/****************************************************************************/
/* Tag FIFO, input frame -> output frame: carries the AGC shifts a frame was */
/* scaled by. Pushed on the first CE of an input frame, popped at the logfn  */
/* sync. Push k and pop k are the same frame by construction, so the         */
/* compensation is exact for ANY fixed pipeline latency. Depth 8 covers 8    */
/* frames of it; reality is 2-3.                                             */
/*                                                                           */
/* No channel field - a frame's channel is implicit in which pipeline spat   */
/* it out. All four frame-locked, so one pointer pair indexes one packed     */
/* word holding all four shifts.                                             */
/****************************************************************************/
reg [3*NCH-1:0] tag_mem [0:7];
reg [2:0] tag_wr, tag_rd;
(* mark_debug = "true" *) reg [3*NCH-1:0] out_shift; // shift applied to each
                          // channel's CURRENT output frame, packed 3 bits/ch
wire [3*NCH-1:0] tag_head = tag_mem[tag_rd];

/* Peak decay pacing (see peak RAM below): every 4th video frame arms one decay
   step, applied over the next output frame. All four output frames coincide so
   one flag covers the lot, and the step lands within 51.2us. */
reg           decay_pending;
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
        out_shift <= {NCH{3'd4}};
        decay_pending   <= 1'b0;
        decay_active    <= 1'b0;
        decay_frame_ctr <= 2'd0;
    end
    else begin
        if (in_frame_start) begin
            tag_mem[tag_wr] <= active_shift; // all four shifts, packed
            tag_wr <= tag_wr + 3'd1;
        end
        if (adc_frameStrobe && logfn_lineSync) begin // first output of a frame
            out_shift <= tag_head;
            tag_rd <= tag_rd + 3'd1;
            decay_active  <= decay_pending;
            decay_pending <= 1'b0;
        end
        if (vframe_tick) begin
            decay_frame_ctr <= decay_frame_ctr + 2'd1;
            if (decay_frame_ctr == 2'd3)
                decay_pending <= 1'b1; // set AFTER the clear above so it can't be lost
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
/* Data per channel, control (state / write enables / address) single - the
   four output frames are clock-for-clock aligned. */
(* keep = "true" *) reg [7:0] wrSpec_new  [0:NCH-1];
(* keep = "true" *) reg [7:0] wrSpec_peak [0:NCH-1];
reg  [7:0] peak_old_r [0:NCH-1]; // registered peak RAM readback, per bank
reg  [7:0] peak_dec_r [0:NCH-1]; // peak_old_r minus one, floor 0 - registered in
                                 // the same posedge stage as peak_old_r

/* Log-domain auto-range compensation: +16 counts per AGC shift bit of the frame
   coming out of that channel's pipeline (out_shift, exact via the tag FIFO).
   9-bit sum, saturated to 8'hFF.
   DON'T make this combinational. It is registered into the posedge domain to
   keep the carry chain and saturation mux out of the posedge->negedge
   half-period path. Safe because logfn_result only moves on the
   fft_frameStrobe posedge (5 cycles before the negedge FSM captures) and
   out_shift on adc_frameStrobe (4.5 cycles), so the register always holds the
   bin being captured. */
wire [7:0] spec_fresh [0:NCH-1];

/* Decayed old peak, floor-guarded - 0-1 would wrap to 255. Decrement is
   precomputed alongside the RAM readback (peak_dec_r, same latency as
   peak_old_r) so the negedge FSM's half-period cone is just this mux + the
   compare. Doing the decrement combinationally there does NOT close timing. */
wire [7:0] peak_decayed [0:NCH-1];

generate for (g = 0; g < NCH; g = g + 1) begin : gen_specfresh
    wire [8:0] comp = {1'b0, logfn_result[g][7:0]}
                      + {2'b00, out_shift[3*g +: 3], 4'b0000};
    reg  [7:0] fresh_r;
    always @(posedge lvds_dclk_buffered)
        fresh_r <= comp[8] ? 8'hFF : comp[7:0];
    assign spec_fresh[g]   = fresh_r;
    assign peak_decayed[g] = decay_active ? peak_dec_r[g] : peak_old_r[g];
end
endgenerate

/* Waterfall column decimation: 2 adjacent bins -> 1 stored column (max), so a
   128x512 store per pane spans everything and each column draws 2px wide,
   lined up under the same bins in the spectrum above. mem_wrAddr walks
   even-then-odd inside each pair (the FFT-shift only flips the MSB), so one
   hold register is enough to pair them. */
reg  [7:0] wf_hold  [0:NCH-1];
reg        wf_wea;
reg  [8:0] wf_wcol;
reg  [7:0] wf_wdata [0:NCH-1];

integer wi;
always@(negedge lvds_dclk_buffered)
begin

    case(wrSpec_state)

        state_wrSpec_read:
        begin
            if(mem_wordWrStrobe == 1'b1) begin

                /* Live trace = newest compensated log value. Peak RAM =
                   max(fresh, decayed old) for every bin on every sweep;
                   decay_active spans exactly one whole sweep when armed, so
                   the decay is uniform.
                   All four channels go out on the SAME strobe into their own
                   banks -> a bin's four amplitudes always share one transform
                   interval. df_amp relies on that, don't break it. */
                for (wi = 0; wi < NCH; wi = wi + 1) begin
                    wrSpec_peak[wi] <= (spec_fresh[wi] > peak_decayed[wi])
                                       ? spec_fresh[wi] : peak_decayed[wi];
                    wrSpec_new[wi]  <= spec_fresh[wi];
                    if (mem_wrAddr[0] == 1'b0)
                        wf_hold[wi]  <= spec_fresh[wi];
                    else
                        wf_wdata[wi] <= (wf_hold[wi] > spec_fresh[wi])
                                        ? wf_hold[wi] : spec_fresh[wi];
                end
                wrPeak_wea <= 1;
                wrSpec_wea <= 1;
                if (mem_wrAddr[0] != 1'b0) begin
                    wf_wcol <= mem_wrAddr[9:1];
                    wf_wea  <= 1;
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
/* Waterfall row bookkeeping. One write-row pointer for all four panes, so   */
/* their histories scroll together. Advances every 8 video frames -> 7.5     */
/* rows/s, ~17s of history in 128 rows. Read side: screen.v hands over the   */
/* pane-local row (0 = top, newest, still being written), older lines walk   */
/* down by mod-128 arithmetic.                                               */
/* The pointer crosses to the pixel domain unsynchronised but is only        */
/* latched once a frame at wf_RdScreenSync (last active line, next to        */
/* vsync; the advance happens a couple of sync cycles later). Worst case a   */
/* tear misplaces one history line in one pane, once. Not worth a CDC.       */
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
/* Per-channel display memories: spectrum + peak (1024x8 each) and a         */
/* 128x512x8 waterfall history. Writes in the processing domain, all four    */
/* banks on the same strobe - every channel has its own transform, so there  */
/* is no "current channel" to gate on and each bank gets every bin of every  */
/* frame. Reads on the inverted pixel clock: every bank sees the same        */
/* address and screen.v's pane index picks which one shows.                  */
/****************************************************************************/
wire [7:0] spec_doutb [0:NCH-1];
wire [7:0] peak_doutb [0:NCH-1];
wire [7:0] wf_doutb   [0:NCH-1];
wire [7:0] peak_douta [0:NCH-1];

genvar b;
generate for (b = 0; b < NCH; b = b + 1) begin : gen_membank

    dp_ram #(.ADDRBITS(10), .BITS(8)) specMem (
        .i_clka(lvds_dclk_buffered),
        .i_wea(wrSpec_wea),
        .i_addra(mem_wrAddr),
        .i_dina(wrSpec_new[b]),
        .o_douta(),
        .i_clkb(scr_rdStrobe),
        .i_addrb(scr_rdAddr),
        .o_doutb(spec_doutb[b])
    );

    dp_ram #(.ADDRBITS(10), .BITS(8)) peakMem (
        .i_clka(lvds_dclk_buffered),
        .i_wea(wrPeak_wea),
        .i_addra(mem_wrAddr),
        .i_dina(wrSpec_peak[b]),
        .o_douta(peak_douta[b]),
        .i_clkb(scr_rdStrobe),
        .i_addrb(scr_rdAddr),
        .o_doutb(peak_doutb[b])
    );

    waterfall_mem #(.ROWBITS(7), .COLBITS(9), .BITS(8)) wfMem (
        .i_wclk(lvds_dclk_buffered),
        .i_we(wf_wea),
        .i_wrow(wf_wr_row),
        .i_wcol(wf_wcol),
        .i_wdata(wf_wdata[b]),
        .i_rclk(scr_rdStrobe),
        .i_rrow(wf_rd_row),
        .i_rcol(scr_rdAddr[9:1]),
        .o_rdata(wf_doutb[b])
    );

end
endgenerate

/* Registered readback, one per bank: keeps the BRAM output out of the
   half-cycle path into the negedge write FSM. The write address is stable for
   ~6 DCLK cycles before the write strobe, so one cycle of extra read latency
   is invisible. The 4:1 mux this stage used to carry is gone - each bank now
   feeds its own compare instead of being selected by out_chan. */
generate for (g = 0; g < NCH; g = g + 1) begin : gen_peakrd
    always @(posedge lvds_dclk_buffered) begin
        peak_old_r[g] <= peak_douta[g];
        peak_dec_r[g] <= (peak_douta[g] != 8'd0) ? (peak_douta[g] - 8'd1) : 8'd0;
    end
end
endgenerate

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
/* Direction finder + polar indicator, drawn transparently over the middle of */
/* all four spectra (POLAR_ALPHA / POLAR_DIM at the top of the file).         */
/*                                                                           */
/* RAY COLOUR = FREQUENCY. df_amp keeps the winning bin index with each       */
/* bearing, freqmap.v ramps it blue-green-yellow-red-violet. The code is the  */
/* top 8 bits of mem_wrAddr, already FFT-shifted, so the ramp runs the same   */
/* way a pane reads left to right: blue at the most negative offset, green/   */
/* yellow around DC, violet at the top. A ray's colour tells you where in the */
/* pane its signal lives. Want colour by |f| instead? Feed the folded index   */
/* here - both band edges then come out the same colour.                      */
/*                                                                           */
/* ANTENNA MAP. Four RASANT2400s pointing outward at 0/90/180/270 on a 25cm   */
/* radius. 0deg is read as compass NORTH, angles clockwise -> ch 0=N 1=E 2=S  */
/* 3=W. Different harness? Change these four parameters, nothing else. A      */
/* wrong map only rotates or mirrors the display and any known-bearing source */
/* exposes it instantly.                                                      */
/*                                                                           */
/* Amplitude, not phase: at 2.03 lambda radius the baselines are 2.88 lambda  */
/* adjacent / 4.07 diagonal, so phase alone wraps ~6x. See df_amp.v.          */
/****************************************************************************/
/* One pulse per round, held off ~100 clocks so the negedge write FSM has     */
/* drained the frame's last bins into the snapshot.                           */
/*                                                                           */
/* A round is ONE output frame. Sweep is 1024 bins x 4 clocks + drain = 4136  */
/* clocks against 6144 in a frame, leaving ~1900 for the decay sweep. An      */
/* early round is just ignored (df_amp only takes i_round_done in ST_IDLE),   */
/* which costs one sweep and nothing else.                                    */
reg [6:0] df_round_dly;
always @(posedge lvds_dclk_buffered) begin
    if (global_rst)
        df_round_dly <= 7'd0;
    else if (adc_frameStrobe && logfn_lineSync)
        df_round_dly <= 7'd100;
    else if (df_round_dly != 7'd0)
        df_round_dly <= df_round_dly - 7'd1;
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
    .i_wr_addr(mem_wrAddr),
    .i_wr_data({wrSpec_new[3], wrSpec_new[2], wrSpec_new[1], wrSpec_new[0]}),
    .i_round_done(df_round_done),
    .i_rdClk(clk_pix),
    .i_rdAddr(df_angAddr),
    .o_rdLen(df_angLen),
    .o_rdFrq(df_angFrq)
);

wire       polar_active, polar_shade;
wire [7:0] polar_r, polar_g, polar_b;

/* Region = whole screen, so the indicator lands dead centre where the four
   panes meet and spreads its 512px disc across all of them. screen.v's grey
   2x2 grid runs straight through and gets darkened with everything else - the
   graticule crosshair sits on those same two lines. */
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

/* Scope view: capture in the ADC word domain, draw in the pixel domain over
   pane 4. Trigger at half CH1's averaged peak so it tracks the input level. */
`ifdef SCOPE_VIEW
localparam SCOPE_EN = 1'b1;
`else
localparam SCOPE_EN = 1'b0;
`endif
wire       scope_active;
wire [7:0] scope_r, scope_g, scope_b;
generate if (SCOPE_EN) begin : gen_scope
    scope_view #(
        .PANE_X0(960),
        .PANE_Y0(540),
        .W(960),
        .H(540)
    ) scope_0 (
        .i_pixClk(clk_pix),
        .i_rst(global_rst),
        .i_video_hs(video_hs),
        .i_video_vs(video_vs),
        .i_video_de(video_de),
        .o_active(scope_active),
        .o_r(scope_r), .o_g(scope_g), .o_b(scope_b),
        .i_adcClk(lvds_dclk_buffered),
        .i_ce(adc_frameStrobe),
        .i_s1(hp_i[0]),
        .i_s2(hp_i[1]),
        .i_s3(hp_i[2]),
        .i_s4(hp_i[3]),
        .i_trig_level({1'b0, adc_avg_peak[0][11:1]}) // 50% of CH1 peak
    );
end
else begin : gen_no_scope
    assign scope_active = 1'b0;
    assign scope_r = 8'h00;
    assign scope_g = 8'h00;
    assign scope_b = 8'h00;
end
endgenerate

/* Per-pane text overlays: averaged ADC level (linear LSB + dBFS) top-left,
   plus the two lane bit-error rates (ramp-test mode only). One instance per
   pane, outputs OR'd over the video - render areas are disjoint by
   construction. Panes are told apart by grid position, no ID digit needed. */
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

/* Display priority: pane text on top, then the polar indicator composited over
   screen.v's spectra, then bare screen.v. The indicator owns no pixels itself,
   it just hands over two masks and a colour:

     polar_active  drew here          -> its colour at POLAR_ALPHA over the
                                         darkened background
     polar_shade   inside outer ring  -> background at POLAR_DIM
     neither                          -> screen.v untouched

   Spectra stay readable straight through the disc, nothing outside it is
   dimmed. Pane readouts live in the corners and win regardless.

   THE WEIGHTS FOLD - the nice bit. Veiling the background then blending over it
   is two chained multiplies, second waiting on the first. Both weights are
   compile-time constants, so their product is one too:

     out = (fg*A + (bg*D >> 8)*(256-A)) >> 8  ==  (fg*A + bg*(A1*D >> 8)) >> 8

   -> one weighted sum per case, all three evaluated in parallel and picked by
   the masks. Constant weights = shift-adds, no DSP, no divide, and >>8 is exact
   at every endpoint: A=256 -> fg, A=0 & D=256 -> bg, D=0 -> black disc. */
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

/* Scope pane replaces screen.v's pixels BEFORE the polar composite, so the DF
   disc dims it exactly like the spectrum panes and stays continuous. */
wire [7:0] base_r = scope_active ? scope_r : video_r;
wire [7:0] base_g = scope_active ? scope_g : video_g;
wire [7:0] base_b = scope_active ? scope_b : video_b;

wire [7:0] comp_r = polar_comp(polar_r, base_r, polar_active, polar_shade);
wire [7:0] comp_g = polar_comp(polar_g, base_g, polar_active, polar_shade);
wire [7:0] comp_b = polar_comp(polar_b, base_b, polar_active, polar_shade);

/* Two-stage output pipeline. The composite is the deepest pixel-domain logic
   outside pane_overlay and it lands in the already-tight path from screen.v's
   colour registers through the overlay mux into rgb2dvi. Stage 1 = composite,
   stage 2 = overlay mux, so neither carries the other.

   Overlays get registered in the SAME stage as the composite they're muxed
   against, and the syncs are delayed by both stages. Everything stays aligned
   and the frame just shifts two pixels right - invisible. Delay only the
   colour and you shear the image against the sync. */
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
      .TMDS_Clk_p(o_TMDS_clk_p),
      .TMDS_Clk_n(o_TMDS_clk_n),
      .TMDS_Data_p(o_TMDS_data_p),
      .TMDS_Data_n(o_TMDS_data_n),

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
