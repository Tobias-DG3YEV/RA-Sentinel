//////////////////////////////////////////////////////////////////////////////////
//
// Design Name: RASPMO
// Module Name: LVDS_RX
// Project Name: Radio Access Spectrum Monitor
// Target Devices: Artix 7, XC7A100T-CSG324 (RASBB onboard FPGA)
// Description:  Receives and deserializes one ADC3424's LVDS interface (up to
//               four one-wire lanes, 12 bit @ 20MSPS DDR each, plus the shared
//               DCLK/FCLK) from the RASRF2400BMC front-end. Two instances of
//               this module (one per ADC3424) feed the quad-split display.
//
// Additional Comments: https://github.com/Tobias-DG3YEV/RA-Sentinel
//
// This is a cleaned-up descendant of RASM2400's lvds_rx.v. That version carried
// a set of IDELAYE2 taps on the DCLK/FCLK clock paths (all left at a fixed
// IDELAY_VALUE of 0) that were used to hand-tune skew while the ADC bit clock
// was unstable due to a missing 100 ohm DCLK termination on that board. With
// the termination fixed the clock is clean, so those clock-path delay taps are
// removed here; IBUFDS_DIFF_OUT's true/complementary outputs are used directly
// as the two ISERDES clock phases instead. The IDELAYE2 in the data path is
// kept: it is not a skew workaround, it is the only way to drive an ISERDESE2
// DDLY input on 7-series (DDLY can only be sourced from an adjacent IDELAYE2,
// never routed in from general fabric per UG471).
//
// The IDELAYCTRL lives in top.v now: both lvds_rx instances' pins share I/O
// bank 35, which has exactly one IDELAYCTRL site - one instance calibrates all
// of the bank's IDELAYE2s.
//
// ISERDESE2 cannot deserialize a 12 bit word in one primitive (DATA_WIDTH does
// not support 12 in either SDR or DDR mode). The workaround used here: split
// each 12 bit word across two ISERDESE2 primitives run in SDR/DATA_WIDTH=6,
// one capturing on each DCLK phase ("EVEN"/"ODD"), and concatenate their 6 bit
// halves back into the 12 bit sample.
//
//////////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps

module lvds_rx #(
    parameter NLANES   = 4, // one-wire data lanes (ADC3424 channels A..D)
    // Serial bits per word per wire. 12 = ADC3424 1-wire/12x mode (DDR ->
    // DCLK = 6 x fS, max 80MSPS per SBAS673A Table 3). A future 125MSPS
    // build needs 2-wire/6x mode (SER_BITS=6, DCLK = 3 x fS = 375MHz) - that
    // also needs the Dx1 pairs routed (unconnected on RASRF2400BMC Rev A)
    // and a clock-capable DCLK pin + BUFIO/BUFR restructure of this module;
    // the parameter keeps the word geometry in one place for that day.
    parameter SER_BITS = 12
)(
    input wire  i_lvds_dclk_P, i_lvds_dclk_N, // 120MHz ADC bit clock
    input wire  i_lvds_fclk_P, i_lvds_fclk_N, // 20MHz ADC frame clock
    input wire  [NLANES-1:0] i_lvds_d_P,      // one-wire serial data lanes
    input wire  [NLANES-1:0] i_lvds_d_N,
    input wire  i_rst,                        // module reset, active high

    // Runtime data-path IDELAY control (from top.v's self-cal FSM). The ODD
    // ISERDES samples the opposite DDR half-bit via this IDELAY; its tap must
    // land in the data eye. i_ctrlClk clocks the IDELAY load port; it is the
    // clock domain of the self-cal FSM (ADC1's BUFG'd DCLK), NOT necessarily
    // this instance's own bit clock - the IDELAY data path is asynchronous to
    // its control clock anyway, C/LD/CNTVALUEIN just have to be one coherent
    // domain.
    input wire          i_ctrlClk,
    input wire  [4:0]   i_data_delay_tap,     // IDELAY tap to load
    input wire          i_data_delay_load,    // 1-cycle pulse: load i_data_delay_tap

    output wire         o_lvds_dclk,          // unbuffered bit clock (BUFG in top.v)
    output wire         o_lvds_fclk,          // buffered frame clock
    output wire [NLANES*SER_BITS-1:0] o_data, // parallel data, lane n = o_data[n*SER_BITS +: SER_BITS]

    // FCLK captured through the IDENTICAL EVEN/ODD ISERDES pipeline as the
    // data lanes. FCLK is electrically just a data lane carrying the fixed
    // pattern "high for the first SER_BITS/2 bit-times of each word" (SBAS673A
    // Fig. 130: a new word starts at the FCLK rising edge, LSB first). So
    // whatever word-boundary offset the capture imposes on the data lanes, it
    // imposes the SAME offset on this word - top.v decodes the pattern's
    // position and gets the true frame alignment every boot, deterministically,
    // with no test pattern and immune to the FCLK-anchor sampling ambiguity
    // (a +/-1-cycle anchor difference shifts data and this word together).
    output wire [SER_BITS-1:0] o_fclk_word,
    /* low while the ISERDES are held in reset / not yet enabled after a
       power-on or a re-anchor: their outputs are frozen at a constant and
       must NOT be treated as samples. */
    output wire         o_ready
);

// DDR: each DCLK period carries two serial bits, so a word spans SER_BITS/2
// DCLK cycles (6 at 12x). bitctr, wordsync/CLKDIV and the ISERDES DATA_WIDTH
// are all derived from this so a serialization-mode change is one edit.
localparam DCLKS_PER_WORD = SER_BITS / 2;

localparam C_DLYTYPE = "VAR_LOAD"; /* runtime-loadable tap - see self-cal FSM in top.v */
localparam C_IODELAY_MASTERCLOCK = 195; /* MHz */
localparam DATA_DELAY_VALUE = 0; /* power-on tap; overwritten by the self-cal sweep */

`ifdef SIMULATION
localparam INIT_DELAY_POR = 32; /* number of cycles the Init waits to release the serdes reset */
`else
localparam INIT_DELAY_POR = 16'h8000;
`endif
localparam INIT_DELAY_CS  = 12; /* number of cycles the Init waits to enable serdes CS after reset release */

/****************************************************************************/
//    #######  ######      #     #     #  #######
//    #        #     #    # #    ##   ##  #
//    #        #     #   #   #   # # # #  #
//    #####    ######   #     #  #  #  #  #####
//    #        #   #    #######  #     #  #
//    #        #    #   #     #  #     #  #
//    #        #     #  #     #  #     #  #######

wire lvds_fclk_buffered;
wire fclk_comp; // complementary copy for the FCLK ODD ISERDES (via IDELAY)

/* IBUFDS_DIFF_OUT instead of plain IBUFDS: the complementary output feeds
   the N-side IDELAYE2 -> ODD ISERDES exactly like every data lane, so FCLK
   can be deserialized as a word (see o_fclk_word). The true output serves
   the legacy roles unchanged. */

/* DIFF_TERM = FALSE on every ADC input buffer: these pins are terminated
   EXTERNALLY with 100 ohm across each pair on RASBB.

   DIFF_TERM cannot work here and never did, despite Vivado accepting the
   attribute and report_io printing "100 Ohm Differential". Per UG471 (7
   Series SelectIO Resources, v1.10) p.91: the on-die differential
   termination is a property of the LVDS input buffer only - "The LVDS_25
   I/O standard is only available in the HR I/O banks. It requires a VCCO
   to be powered at 2.5V ... when the optional internal differential
   termination is implemented (DIFF_TERM = TRUE)". These ports are
   DIFF_SSTL18_II in bank 35 at VCCO = 1.8V, so neither condition holds.

   MEASURED 2026-07-29 at the PCIe connector with the external resistors
   fitted: 400 mVpp single-ended / 800 mVpp differential = VOD 400 mV,
   which at the ADC's default 3.5 mA drive is ~114 ohm, i.e. ONE
   termination. Had the on-die 100 ohm also been active the pair would sit
   at 50 ohm and show ~175 mVpp single-ended.

   The HR banks do offer an on-die alternative for this IOSTANDARD -
   IN_TERM = UNTUNED_SPLIT_40/50/60 (UG471 p.33, Table 1-7 lists
   DIFF_SSTL18_II) - but it is a Thevenin split to VCCO/2 = 0.9V, which
   fights the ~1.2V common mode of the ADC's LVDS current-mode driver.
   External 100 ohm across the pair is the correct termination for this
   link; do not enable IN_TERM as well. */
IBUFDS_DIFF_OUT #(
    .DIFF_TERM("FALSE"),
    .IOSTANDARD("DEFAULT")
) IBUFDS_adc_fclk (
    .O(lvds_fclk_buffered),
    .OB(fclk_comp),
    .I(i_lvds_fclk_P),
    .IB(i_lvds_fclk_N)
);

assign o_lvds_fclk = lvds_fclk_buffered;

/****************************************************************************
    ######   ###  #######         #####   #        #######   #####   #    #
    #     #   #      #           #     #  #        #     #  #     #  #   #
    #     #   #      #           #        #        #     #  #        #  #
    ######    #      #           #        #        #     #  #        ###
    #     #   #      #           #        #        #     #  #        #  #
    #     #   #      #           #     #  #        #     #  #     #  #   #
    ######   ###     #            #####   #######  #######   #####   #    #
*/

wire [1:0] lvds_dclk_BUFDS; // [0]=true, [1]=complementary - used directly as the two ISERDES clock phases

IBUFDS_DIFF_OUT #(
    .DIFF_TERM("FALSE"), // external 100R on RASBB - see IBUFDS_adc_fclk above
    .IOSTANDARD("DEFAULT")
) IBUFDS_adc_dclk (
	.O(lvds_dclk_BUFDS[0]), // 120/60MHz
	.OB(lvds_dclk_BUFDS[1]), // 120/60MHz
    .I(i_lvds_dclk_P),
    .IB(i_lvds_dclk_N)
);

assign o_lvds_dclk = lvds_dclk_BUFDS[0];

assign o_ready = (initSM == state_initdone) && anchored;

/*********************************************************
     #####   #     #  #     #   #####
    #     #   #   #   ##    #  #     #
    #          # #    # #   #  #
     #####      #     #  #  #  #
          #     #     #   # #  #
    #     #     #     #    ##  #     #
     #####      #     #     #   #####
*/

// sync states
localparam state_powerOn   = 2'b00;
localparam state_syncing   = 2'b01;
localparam state_init      = 2'b10;
localparam state_initdone  = 2'b11;

(* mark_debug = "true" *) reg [1:0] initSM;
initial initSM = 0;
(* mark_debug = "true" *) reg serdes_rst;
initial serdes_rst = 1'b1;
(* mark_debug = "true" *) reg serdes_CS;
initial serdes_CS = 1'b0;
reg [15:0] initctr;

(* mark_debug = "true" *) wire wordsync;
(* keep = "true", mark_debug = "true" *) reg [3:0] bitctr;
(* mark_debug = "true" *) reg fclk_shifted;

/* FCLK synchronizer + anchor state (see the frame-alignment block below). */
reg  [1:0] fclk_sync;
reg        fclk_s_d;
(* mark_debug = "true" *) reg        anchored;
reg  [3:0] mism_ctr;
(* mark_debug = "true" *) reg        reanchor_pulse;
(* keep = "true", mark_debug = "true" *) reg [7:0] reanchor_count; // sticky diagnostic

/* INIT_DELAY_POR (32768 cycles = 273us at 120MHz) is a POWER-ON delay: it
   waits for the front end's clocks to be trustworthy. Re-using it for a
   re-anchor was measured to be the dominant noise source of the whole
   instrument.

   MEASURED 2026-07-30 by ILA: every slip held all 8 ISERDES in reset for
   exactly 274us (32768/120MHz = 273.07us), during which their outputs freeze
   at a constant - 0xB54 on all data lanes, 0xAAA on the FCLK word. That
   frozen constant is a ~1200 LSB DC step into the DC remover and the FFT, and
   a 273us broadband splat lifts the averaged spectrum floor by tens of dB and
   spikes the peak-hold trace (which then decays slowly = the "jumping peak
   max line"). The link itself was fine: framing 0xC0F, tap 16, samples clean
   at +/-8 LSB in between.

   A re-anchor does not need the power-on wait. Per UG471 the ISERDES only
   needs its reset held a couple of CLKDIV cycles for the new CLKDIV phase to
   take effect, so re-init now uses INIT_DELAY_REANCHOR: a 273us outage
   becomes ~0.5us. fast_reinit latches on the first re-anchor and stays set
   until i_rst, so only the true power-on pass pays the long delay. */
localparam INIT_DELAY_REANCHOR = 64; // 0.53us at 120MHz
reg fast_reinit;
initial fast_reinit = 1'b0;
wire [15:0] init_delay = fast_reinit ? INIT_DELAY_REANCHOR[15:0] : INIT_DELAY_POR[15:0];

always @(posedge lvds_dclk_BUFDS[1] or posedge i_rst) // 120MHz driven
begin
    if(i_rst == 1) begin
        initSM <= state_powerOn;
        serdes_rst <= 1;
        serdes_CS <= 0;
        initctr <= 0;
        fast_reinit <= 1'b0;
    end
    else if (reanchor_pulse) begin
        /* The frame anchor slipped: wordsync (= ISERDES CLKDIV) is about to
           change phase, which invalidates the ISERDES bit grouping (UG471:
           CLKDIV must be stable; a phase change requires an ISERDES reset).
           Re-run the init sequence against the new anchor - but with the SHORT
           delay, see fast_reinit below. */
        initSM <= state_powerOn;
        serdes_rst <= 1;
        serdes_CS <= 0;
        initctr <= 0;
        fast_reinit <= 1'b1;
    end
    else begin
        case (initSM)
            state_powerOn: begin
                // wait for a stable stretch of clocks and a high phase of wordsync before releasing reset
                if(initctr >= init_delay && wordsync == 1) begin
                    serdes_rst <= 0;
                    serdes_CS <= 0;
                    if(initctr >= init_delay+INIT_DELAY_CS && wordsync == 1) begin
                        initctr <= 0;
                        initSM <= state_syncing;
                    end
                end
                else begin
                    initctr <= initctr + 1;
                end
            end

            state_init: begin
                if(wordsync == 0) begin
                    initSM <= state_syncing;
                end
                else begin
                    initctr <= initctr + 1;
                end
            end

            state_syncing: begin
                if(bitctr == 2) begin
                    initSM <= state_initdone;
                    serdes_CS <= 1;
                end
            end

            state_initdone: begin
            end

        endcase
    end
end

/****************************************************************************/
//	######   ######   ######          ######      #     #######     #
//	#     #  #     #  #     #         #     #    # #       #       # #
//	#     #  #     #  #     #         #     #   #   #      #      #   #
//	#     #  #     #  ######          #     #  #     #     #     #     #
//	#     #  #     #  #   #           #     #  #######     #     #######
//	#     #  #     #  #    #          #     #  #     #     #     #     #
//	######   ######   #     #         ######   ######      #     #     #

wire [NLANES-1:0] data_true; // undelayed - feeds the EVEN ISERDES directly
wire [NLANES-1:0] data_comp; // complementary copy - the only one that needs IDELAYE2->DDLY, for the ODD ISERDES
wire [NLANES-1:0] data_comp_delayed;

genvar i;
generate for (i = 0; i < NLANES; i = i + 1)
    begin : gen_data_lane

        IBUFDS_DIFF_OUT #(
            .DIFF_TERM("FALSE"), // external 100R on RASBB - see IBUFDS_adc_fclk above
            .IOSTANDARD("DEFAULT")
        ) IBUFDS_adc_data (
            .O(data_true[i]),
            .OB(data_comp[i]),
            .I(i_lvds_d_P[i]),
            .IB(i_lvds_d_N[i])
        );

        IDELAYE2 #(
            .CINVCTRL_SEL("FALSE"),
            .DELAY_SRC("IDATAIN"),
            .HIGH_PERFORMANCE_MODE("TRUE"),
            .IDELAY_TYPE(C_DLYTYPE),
            .IDELAY_VALUE(DATA_DELAY_VALUE),
            .REFCLK_FREQUENCY(C_IODELAY_MASTERCLOCK),
            .PIPE_SEL("FALSE"),
            .SIGNAL_PATTERN("DATA")
        ) IDELAYE2_data_inst (
            .CE(1'b0),
            .INC(1'b0),
            .DATAIN(1'b0),
            .LDPIPEEN(1'b0),
            .CINVCTRL(1'b0),
            .REGRST(1'b0),
            .C(i_ctrlClk),
            .IDATAIN(data_comp[i]),
            .DATAOUT(data_comp_delayed[i]),
            .LD(i_data_delay_load),
            .CNTVALUEIN(i_data_delay_tap),
            .CNTVALUEOUT()
        );
    end
endgenerate

/*******************************************************************************
    ###   #####   #######  ######   ######   #######   #####
     #   #     #  #        #     #  #     #  #        #     #
     #   #        #        #     #  #     #  #        #
     #    #####   #####    ######   #     #  #####     #####
     #         #  #        #   #    #     #  #              #
     #   #     #  #        #    #   #     #  #        #     #
    ###   #####   #######  #     #  ######   #######   #####
*/

localparam DATA_RATE = "SDR";
localparam INTERFACE_TYPE = "NETWORKING";
localparam IOBDELAY = "BOTH";

/* NOTE: the Q1..Q6 port hookup below is written out for DCLKS_PER_WORD = 6
   (1-wire mode). Other serialization modes change the number of Q taps and
   will fail loudly at elaboration - intentional, see the SER_BITS header. */
(* keep = "true", mark_debug = "true" *) wire [NLANES*DCLKS_PER_WORD-1:0] ev12; // EVEN halves, DCLKS_PER_WORD bits per lane
(* keep = "true", mark_debug = "true" *) wire [NLANES*DCLKS_PER_WORD-1:0] od12; // ODD halves, DCLKS_PER_WORD bits per lane

assign wordsync = fclk_shifted;

genvar k;
generate
    for (k = 0; k < NLANES; k = k + 1) begin : gen_data_block

    ISERDESE2 #(
        .DATA_RATE(DATA_RATE),
        .DATA_WIDTH(DCLKS_PER_WORD),
        .INTERFACE_TYPE(INTERFACE_TYPE),
        .NUM_CE(1),
        .OFB_USED("FALSE"),
        .SERDES_MODE("MASTER"),
        .DYN_CLKDIV_INV_EN("TRUE"),
        .DYN_CLK_INV_EN("TRUE"),
        // EVEN ISERDES takes the UNDELAYED serial data on .D (data_true), so its
        // deserialized Q outputs must be sourced from .D - i.e. IOBDELAY="NONE".
        // The shared localparam IOBDELAY="BOTH" (used by the ODD .DDLY instance)
        // routes Q from the DDLY pin; applied here it read the unconnected DDLY
        // and drove ev12 to all-zeros, killing every even bit of the word.
        .IOBDELAY("NONE")
    ) ISERDESE2_EVEN_inst (
        .Q6(ev12[k*DCLKS_PER_WORD+0]), .Q5(ev12[k*DCLKS_PER_WORD+1]), .Q4(ev12[k*DCLKS_PER_WORD+2]),
        .Q3(ev12[k*DCLKS_PER_WORD+3]), .Q2(ev12[k*DCLKS_PER_WORD+4]), .Q1(ev12[k*DCLKS_PER_WORD+5]),
        .BITSLIP(1'b0),
        .DYNCLKSEL(1'b0),
        .DYNCLKDIVSEL(1'b0),
        .CE1(serdes_CS),
        .CE2(1'b0),
        .CLK(lvds_dclk_BUFDS[1]),
        .CLKB(lvds_dclk_BUFDS[0]),
        .CLKDIV(wordsync),
        .CLKDIVP(),
        .D(data_true[k]),
        .OFB(1'b0),
        .RST(serdes_rst)
    );

    ISERDESE2 #(
        .DATA_RATE(DATA_RATE),
        .DATA_WIDTH(DCLKS_PER_WORD),
        .INTERFACE_TYPE(INTERFACE_TYPE),
        .NUM_CE(1),
        .OFB_USED("FALSE"),
        .SERDES_MODE("MASTER"),
        .DYN_CLKDIV_INV_EN("TRUE"),
        .DYN_CLK_INV_EN("TRUE"),
        .IOBDELAY(IOBDELAY)
    ) ISERDESE2_ODD_inst (
        .Q6(od12[k*DCLKS_PER_WORD+0]), .Q5(od12[k*DCLKS_PER_WORD+1]), .Q4(od12[k*DCLKS_PER_WORD+2]),
        .Q3(od12[k*DCLKS_PER_WORD+3]), .Q2(od12[k*DCLKS_PER_WORD+4]), .Q1(od12[k*DCLKS_PER_WORD+5]),
        .BITSLIP(1'b0),
        .DYNCLKSEL(1'b0),
        .DYNCLKDIVSEL(1'b0),
        .CE1(serdes_CS),
        .CE2(1'b0),
        .CLK(lvds_dclk_BUFDS[0]),
        .CLKB(~lvds_dclk_BUFDS[0]),
        .CLKDIV(wordsync),
        .CLKDIVP(),
        .DDLY(data_comp_delayed[k]),
        .OFB(1'b0),
        .RST(serdes_rst)
    );
    end
endgenerate

/* FCLK capture path: a byte-identical clone of one data lane (IDELAYE2 on
   the complementary copy + EVEN/ODD ISERDES on the same clocks, CLKDIV, CE
   and reset), so the deserialized FCLK word has exactly the same word-
   boundary offset as the data words. The IDELAY loads the same tap as the
   data lanes to keep the ODD sampling identical. */
wire fclk_comp_delayed;
wire [DCLKS_PER_WORD-1:0] fclk_ev;
wire [DCLKS_PER_WORD-1:0] fclk_od;

IDELAYE2 #(
    .CINVCTRL_SEL("FALSE"),
    .DELAY_SRC("IDATAIN"),
    .HIGH_PERFORMANCE_MODE("TRUE"),
    .IDELAY_TYPE(C_DLYTYPE),
    .IDELAY_VALUE(DATA_DELAY_VALUE),
    .REFCLK_FREQUENCY(C_IODELAY_MASTERCLOCK),
    .PIPE_SEL("FALSE"),
    .SIGNAL_PATTERN("DATA")
) IDELAYE2_fclk_inst (
    .CE(1'b0),
    .INC(1'b0),
    .DATAIN(1'b0),
    .LDPIPEEN(1'b0),
    .CINVCTRL(1'b0),
    .REGRST(1'b0),
    .C(i_ctrlClk),
    .IDATAIN(fclk_comp),
    .DATAOUT(fclk_comp_delayed),
    .LD(i_data_delay_load),
    .CNTVALUEIN(i_data_delay_tap),
    .CNTVALUEOUT()
);

ISERDESE2 #(
    .DATA_RATE(DATA_RATE),
    .DATA_WIDTH(DCLKS_PER_WORD),
    .INTERFACE_TYPE(INTERFACE_TYPE),
    .NUM_CE(1),
    .OFB_USED("FALSE"),
    .SERDES_MODE("MASTER"),
    .DYN_CLKDIV_INV_EN("TRUE"),
    .DYN_CLK_INV_EN("TRUE"),
    .IOBDELAY("NONE") // undelayed .D path, same as the data EVEN instances
) ISERDESE2_FCLK_EVEN_inst (
    .Q6(fclk_ev[0]), .Q5(fclk_ev[1]), .Q4(fclk_ev[2]),
    .Q3(fclk_ev[3]), .Q2(fclk_ev[4]), .Q1(fclk_ev[5]),
    .BITSLIP(1'b0),
    .DYNCLKSEL(1'b0),
    .DYNCLKDIVSEL(1'b0),
    .CE1(serdes_CS),
    .CE2(1'b0),
    .CLK(lvds_dclk_BUFDS[1]),
    .CLKB(lvds_dclk_BUFDS[0]),
    .CLKDIV(wordsync),
    .CLKDIVP(),
    .D(lvds_fclk_buffered),
    .OFB(1'b0),
    .RST(serdes_rst)
);

ISERDESE2 #(
    .DATA_RATE(DATA_RATE),
    .DATA_WIDTH(DCLKS_PER_WORD),
    .INTERFACE_TYPE(INTERFACE_TYPE),
    .NUM_CE(1),
    .OFB_USED("FALSE"),
    .SERDES_MODE("MASTER"),
    .DYN_CLKDIV_INV_EN("TRUE"),
    .DYN_CLK_INV_EN("TRUE"),
    .IOBDELAY(IOBDELAY)
) ISERDESE2_FCLK_ODD_inst (
    .Q6(fclk_od[0]), .Q5(fclk_od[1]), .Q4(fclk_od[2]),
    .Q3(fclk_od[3]), .Q2(fclk_od[4]), .Q1(fclk_od[5]),
    .BITSLIP(1'b0),
    .DYNCLKSEL(1'b0),
    .DYNCLKDIVSEL(1'b0),
    .CE1(serdes_CS),
    .CE2(1'b0),
    .CLK(lvds_dclk_BUFDS[0]),
    .CLKB(~lvds_dclk_BUFDS[0]),
    .CLKDIV(wordsync),
    .CLKDIVP(),
    .DDLY(fclk_comp_delayed),
    .OFB(1'b0),
    .RST(serdes_rst)
);

/* Frame-boundary alignment.

   bitctr generates wordsync (= the shared ISERDES CLKDIV), i.e. it decides
   how the serial stream is chopped into DCLKS_PER_WORD-cycle groups. The
   previous version sampled lvds_fclk_buffered RAW (no synchronizer, and the
   XDC false-paths FCLK) and re-armed the anchor on EVERY frame - so a
   marginal FCLK sample point made the anchor a power-up lottery and could
   even re-frame mid-run without resetting the ISERDES. That was the real
   source of the "sometimes the stream is bit-shifted" symptom; measured
   inter-pair trace skew (<= ~35ps against a 4.17ns UI) could never be.

   Now:
   - FCLK is 2-FF synchronized before anybody looks at it (the XDC false
     path is then genuinely harmless: FCLK is periodic and only its LEVEL
     is used, one metastable sample can only jitter the observed edge by
     one cycle).
   - The anchor locks ONCE on a synchronized FCLK rising edge and bitctr
     free-runs mod DCLKS_PER_WORD afterwards - FCLK jitter can no longer
     move an established word framing.
   - A real slip (anchor persistently wrong, e.g. the ADC re-started) is
     still caught: only after RE_ANCHOR_N CONSECUTIVE frames with the FCLK
     edge at an unexpected bitctr does it re-anchor, and that path also
     resets/re-inits the ISERDES (see the init FSM above), because a CLKDIV
     phase change without reset leaves undefined bit grouping.
   - The absolute anchor position is deliberately arbitrary (the 2-FF delay
     shifts it by a constant): top.v's word-rotation calibration absorbs any
     constant offset. Only STABILITY matters here.

   NOTE for faster serialization modes (125MSPS => 2-wire, SER_BITS=6): at
   DCLK=375MHz this whole fabric-clocked scheme (non-BUFG'd inverted clock,
   fabric CLKDIV) must move to BUFIO/BUFR with ISERDES DDR mode - see the
   parameter header note. */
localparam RE_ANCHOR_N = 4'd15;

wire fclk_s    = fclk_sync[1];
wire fclk_rise = fclk_s & ~fclk_s_d;

always @(posedge lvds_dclk_BUFDS[1]) begin
    if(i_rst == 1) begin
        fclk_sync      <= 2'b00;
        fclk_s_d       <= 1'b0;
        bitctr         <= 0;
        fclk_shifted   <= 0;
        anchored       <= 1'b0;
        mism_ctr       <= 0;
        reanchor_pulse <= 1'b0;
        reanchor_count <= 0;
    end
    else begin
        fclk_sync      <= {fclk_sync[0], lvds_fclk_buffered};
        fclk_s_d       <= fclk_s;
        reanchor_pulse <= 1'b0;

        if (!anchored) begin
            bitctr       <= 0;
            fclk_shifted <= 0;
            mism_ctr     <= 0;
            if (fclk_rise) begin
                /* this cycle is position 0 of a word; count on from here */
                anchored <= 1'b1;
                bitctr   <= 4'd1;
            end
        end
        else begin
            /* free-running word phase; wordsync = high for the two middle
               positions, giving the CLKDIV waveform the ISERDES expect */
            if(bitctr == DCLKS_PER_WORD/2 - 1 || bitctr == DCLKS_PER_WORD/2)
                fclk_shifted <= 1;
            else
                fclk_shifted <= 0;

            if (bitctr == DCLKS_PER_WORD-1)
                bitctr <= 0;
            else
                bitctr <= bitctr + 1;

            /* slip watchdog: the synchronized FCLK edge must keep appearing
               at position 0. Isolated mismatches (edge jitter through the
               synchronizer) reset the run; only a persistent offset - a true
               slip - triggers the re-anchor. */
            if (fclk_rise) begin
                if (bitctr != 0) begin
                    if (mism_ctr == RE_ANCHOR_N) begin
                        anchored       <= 1'b0;
                        mism_ctr       <= 0;
                        reanchor_pulse <= 1'b1;
                        reanchor_count <= reanchor_count + 1'b1;
                    end
                    else
                        mism_ctr <= mism_ctr + 1'b1;
                end
                else
                    mism_ctr <= 0;
            end
        end
    end
end

/* EVEN and ODD each capture alternating serial bit-times, so the 12 bit word
   is reassembled by interleaving them back together bit by bit, not by
   concatenating the two halves as blocks.

   The ODD ISERDES physically lives in the slave (N-side) IOB of the diff pair,
   whose IDELAYE2 can only source the IBUFDS_DIFF_OUT COMPLEMENT output (.OB /
   data_comp - see the IDELAYE2 .IDATAIN(data_comp[i]) above). So every od12 bit
   is the electrical INVERSE of the true serial bit and must be re-inverted here.
   The RASM2400 ancestor got this inversion for free from that board's P/N swap;
   RASPMO's ADC pins were re-derived to true differential polarity, so it must be
   undone in fabric. Without it a static line reads 0xAAA instead of 0x000 and a
   ramp comes out XOR'd with 0xAAA (uncompensated - ramp_checker has no XOR). */
(* keep = "true" *) wire [NLANES*DCLKS_PER_WORD-1:0] od12_true = ~od12;

genvar m, b;
generate
    for (m = 0; m < NLANES; m = m + 1) begin : gen_interleave
        for (b = 0; b < DCLKS_PER_WORD; b = b + 1) begin : gen_bitpair
            assign o_data[m*SER_BITS + 2*b + 0] = ev12    [m*DCLKS_PER_WORD + b];
            assign o_data[m*SER_BITS + 2*b + 1] = od12_true[m*DCLKS_PER_WORD + b];
        end
    end
endgenerate

/* FCLK word: identical interleave (including the ODD-path re-inversion) so
   it is bit-position-compatible with the data words. */
wire [DCLKS_PER_WORD-1:0] fclk_od_true = ~fclk_od;
genvar fb;
generate
    for (fb = 0; fb < DCLKS_PER_WORD; fb = fb + 1) begin : gen_fclk_bitpair
        assign o_fclk_word[2*fb + 0] = fclk_ev[fb];
        assign o_fclk_word[2*fb + 1] = fclk_od_true[fb];
    end
endgenerate

endmodule
