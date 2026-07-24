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
    output wire [NLANES*SER_BITS-1:0] o_data  // parallel data, lane n = o_data[n*SER_BITS +: SER_BITS]
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

IBUFDS #(
    .DIFF_TERM("TRUE"),
    .IOSTANDARD("DEFAULT")
) IBUFDS_adc_fclk (
    .O(lvds_fclk_buffered),
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
    .DIFF_TERM("TRUE"),
    .IOSTANDARD("DEFAULT")
) IBUFDS_adc_dclk (
	.O(lvds_dclk_BUFDS[0]), // 120/60MHz
	.OB(lvds_dclk_BUFDS[1]), // 120/60MHz
    .I(i_lvds_dclk_P),
    .IB(i_lvds_dclk_N)
);

assign o_lvds_dclk = lvds_dclk_BUFDS[0];

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

always @(posedge lvds_dclk_BUFDS[1] or posedge i_rst) // 120MHz driven
begin
    if(i_rst == 1) begin
        initSM <= state_powerOn;
        serdes_rst <= 1;
        serdes_CS <= 0;
        initctr <= 0;
    end
    else if (reanchor_pulse) begin
        /* The frame anchor slipped: wordsync (= ISERDES CLKDIV) is about to
           change phase, which invalidates the ISERDES bit grouping (UG471:
           CLKDIV must be stable; a phase change requires an ISERDES reset).
           Re-run the whole init sequence against the new anchor. */
        initSM <= state_powerOn;
        serdes_rst <= 1;
        serdes_CS <= 0;
        initctr <= 0;
    end
    else begin
        case (initSM)
            state_powerOn: begin
                // wait for a stable stretch of clocks and a high phase of wordsync before releasing reset
                if(initctr >= INIT_DELAY_POR && wordsync == 1) begin
                    serdes_rst <= 0;
                    serdes_CS <= 0;
                    if(initctr >= INIT_DELAY_POR+INIT_DELAY_CS && wordsync == 1) begin
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
            .DIFF_TERM("TRUE"),
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

endmodule
