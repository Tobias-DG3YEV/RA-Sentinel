//////////////////////////////////////////////////////////////////////////////////
// df_amp.v
//
// Amplitude-comparison direction finder for the four RASANT2400 antennas, which
// point outward at 0/90/180/270 deg on a 25cm-radius circle. Produces the angle
// table that polar_view.v renders: len[theta] = strongest signal seen at that
// bearing.
//
// WHY AMPLITUDE AND NOT PHASE. The array is 2.03 lambda in radius at 2.44GHz,
// so the adjacent-element baseline is 2.88 lambda and the diagonal 4.07 lambda -
// phase interferometry there wraps ~6 times and is hopelessly ambiguous, and the
// elements deliberately point in four different directions, which breaks the
// equal-element-pattern assumption interferometry rests on. Amplitude comparison
// is unambiguous over the full 360deg, needs no phase coherence between the four
// MAX2831 LOs (they are reference-locked but not LO-locked, so their relative
// phase is arbitrary and re-randomises on every relock), and does not care that
// the shared FFT gives each channel a different time window. It is also nearly
// free: the four spectrum RAMs already hold absolutely-calibrated amplitudes.
// Phase is added later as a REFINEMENT on top of this coarse bearing.
//
// THE MATH, AND THE TRAP IN IT. With beams at 0/90/180/270 the bearing is the
// argument of the pattern's fundamental Fourier component, which a 4-point DFT
// extracts as simply
//      X = P_east - P_west,  Y = P_north - P_south,  bearing = atan2(Y, X)
// For a pattern G(d) = 1 + a*cos(d) this is exact. BUT IT IS ONLY VALID ON
// LINEAR POWER. The spectrum RAMs hold LOG amplitude (0.376dB per count), and
// differencing logs forms ratios, not differences: for a quadratic-in-dB beam
// both X and Y come out piecewise LINEAR in bearing, so atan2 of them is not the
// bearing at all - merely something that varies with it. So each bin is first
// normalised to its own strongest beam (which also cancels the absolute signal
// level, leaving only the shape) and mapped back to linear power through
// explut() before the differences are taken.
//
// The normalisation window is 64 counts = 24dB, which is far past the useful
// front-to-back ratio of a patch; beyond it the LUT floors at 1 and the beam
// simply stops contributing.
//
// ANGLE CONVENTION matches polar_view.v exactly: X is the east-west difference,
// Y the north-south one, so the CORDIC returns binary turns counter-clockwise
// from east, a northern source lands at 90deg, and the ray points up the screen.
// No offset or flip anywhere in the chain.
//
// TIMING. One sweep per FFT round (4096 samples = 204.8us at 20MSPS) walks all
// 1024 bins at a deliberately lazy 4 clocks per bin: the angle table read-modify
// -write needs 3 clocks on dp_ram's shared-address port A, and at 4 clocks there
// is no hazard to reason about at all. 1024*4 = 4096 clocks = 34us at 120MHz,
// comfortably inside the round. Results accumulate as a max across every round
// between two video frames (~81 of them), so short bursts are caught rather than
// sampled at 60Hz.
//
// WHAT A TABLE ENTRY CARRIES. Not just the ray length: each entry is
// {frequency, length}, the length of the strongest signal at that bearing and
// the FFT bin it came from. The bin rides the whole pipeline alongside the
// amplitude and is written by the same max compare - compared on LENGTH only, so
// the frequency stored is always the winner's and never a mix of two bins. It
// exists so polar_view can colour the ray by frequency (freqmap.v) instead of by
// amplitude, which the ray's own length already shows.
//
// DOUBLE BUFFERED. The table is one 1024x16 RAM split into two 512-entry halves
// by fill_sel. The fill half accumulates; the other is displayed; they swap on
// the video frame tick and the new fill half is then cleared. fill_sel crosses
// to the pixel domain through a 2-FF synchroniser - it only changes once per
// frame, so the worst case is one frame reading the buffer that is about to be
// filled, which is a single-frame flicker, not corruption.
//
// Dependencies: cordic_vec.v, dp_ram.v
//////////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps

module df_amp #(
    parameter FFTLEN    = 10,       // 1024 FFT bins
    parameter ANGBITS   = 9,        // 512 angle bins (0.703deg each)
    parameter FRQBITS   = 8,        // colour code width; the top FRQBITS of the
                                    // bin index, so 8 keeps 4 bins per code
    parameter CH_E      = 0,        // channel index of the antenna facing east
    parameter CH_N      = 1,        //                                    north
    parameter CH_W      = 2,        //                                    west
    parameter CH_S      = 3,        //                                    south
    parameter [7:0] AMP_FLOOR = 8'd128, // bins at or below this draw nothing
    parameter AMP_SHIFT = 1,        // ray length = (amp - AMP_FLOOR) << this
    parameter [10:0] DIR_MIN = 11'd24,  // min |(X,Y)| for a trustworthy bearing
    parameter STAGES    = 12,   // CORDIC stages; 12 resolves ~0.03deg, far
                                // finer than the 0.703deg angle bin
    parameter CGUARD    = 10    // CORDIC guard bits
)(
    input  wire                  i_clk,        // ADC/DCLK domain
    input  wire                  i_rst,

    // mirror of the spectrum RAM write port
    input  wire                  i_wr_en,
    input  wire [1:0]            i_wr_chan,
    input  wire [FFTLEN-1:0]     i_wr_addr,
    input  wire [7:0]            i_wr_data,

    input  wire                  i_round_done,  // pulse: all 4 channels written
    input  wire                  i_frame_tick,  // video frame, already in i_clk

    // angle table read port, pixel domain
    input  wire                  i_rdClk,
    input  wire [ANGBITS-1:0]    i_rdAddr,
    output wire [7:0]            o_rdLen,
    output wire [FRQBITS-1:0]    o_rdFrq   // bin that won this bearing
);

localparam NBINS = (1 << FFTLEN);

/* Normalised-log -> linear power, 255 * 10^(-0.376*d/10), d in log counts.
   64 entries = a 24dB normalisation window; past that a beam contributes ~0. */
function [7:0] explut;
    input [5:0] d;
    begin
        case (d)
            0: explut = 8'd255; 1: explut = 8'd234; 2: explut = 8'd214; 3: explut = 8'd197;
            4: explut = 8'd180; 5: explut = 8'd165; 6: explut = 8'd152; 7: explut = 8'd139;
            8: explut = 8'd128; 9: explut = 8'd117; 10: explut = 8'd107; 11: explut = 8'd98;
            12: explut = 8'd90; 13: explut = 8'd83; 14: explut = 8'd76; 15: explut = 8'd70;
            16: explut = 8'd64; 17: explut = 8'd59; 18: explut = 8'd54; 19: explut = 8'd49;
            20: explut = 8'd45; 21: explut = 8'd41; 22: explut = 8'd38; 23: explut = 8'd35;
            24: explut = 8'd32; 25: explut = 8'd29; 26: explut = 8'd27; 27: explut = 8'd25;
            28: explut = 8'd23; 29: explut = 8'd21; 30: explut = 8'd19; 31: explut = 8'd17;
            32: explut = 8'd16; 33: explut = 8'd15; 34: explut = 8'd13; 35: explut = 8'd12;
            36: explut = 8'd11; 37: explut = 8'd10; 38: explut = 8'd10; 39: explut = 8'd9;
            40: explut = 8'd8;  41: explut = 8'd7;  42: explut = 8'd7;  43: explut = 8'd6;
            44: explut = 8'd6;  45: explut = 8'd5;  46: explut = 8'd5;  47: explut = 8'd4;
            48: explut = 8'd4;  49: explut = 8'd4;  50: explut = 8'd3;  51: explut = 8'd3;
            52: explut = 8'd3;  53: explut = 8'd3;  54: explut = 8'd2;  55: explut = 8'd2;
            56: explut = 8'd2;  57: explut = 8'd2;  58: explut = 8'd2;  59: explut = 8'd2;
            default: explut = 8'd1;
        endcase
    end
endfunction

/****************************************************************************/
/* Per-channel amplitude snapshot                                           */
/* The spectrum RAMs' own ports are both taken (port A writes from this     */
/* domain, port B is the display read), so the DF sweep gets its own copy - */
/* four 1024x8 mirrors written in lockstep with specMem. 4 x RAMB18.        */
/****************************************************************************/
wire [FFTLEN-1:0] sweep_addr;
wire [7:0] snap_q [0:3];

genvar c;
generate
for (c = 0; c < 4; c = c + 1) begin : gen_snap
    dp_ram #(.ADDRBITS(FFTLEN), .BITS(8)) snapMem (
        .i_clka(i_clk),
        .i_wea(i_wr_en && (i_wr_chan == c[1:0])),
        .i_addra(i_wr_addr),
        .i_dina(i_wr_data),
        .o_douta(),
        .i_clkb(i_clk),
        .i_addrb(sweep_addr),
        .o_doutb(snap_q[c])
    );
end
endgenerate

/****************************************************************************/
/* Sweep sequencer                                                          */
/****************************************************************************/
localparam ST_IDLE  = 2'd0,
           ST_SWEEP = 2'd1,
           ST_DRAIN = 2'd2,
           ST_CLEAR = 2'd3;

reg [1:0]        state;
reg [FFTLEN-1:0] bin_ctr;
reg [1:0]        phase;        // 4-clock cadence within a bin
reg [ANGBITS:0]  clr_ctr;
reg [5:0]        drain_ctr;
reg              fill_sel;
reg              frame_pending;

assign sweep_addr = bin_ctr;

wire bin_issue = (state == ST_SWEEP) && (phase == 2'd0);

always @(posedge i_clk) begin
    if (i_rst) begin
        state         <= ST_IDLE;
        bin_ctr       <= {FFTLEN{1'b0}};
        phase         <= 2'd0;
        clr_ctr       <= {(ANGBITS+1){1'b0}};
        drain_ctr     <= 6'd0;
        fill_sel      <= 1'b0;
        frame_pending <= 1'b0;
    end
    else begin
        /* Latch the frame tick; it is serviced at the next quiet point rather
           than interrupting a sweep mid-flight. */
        if (i_frame_tick)
            frame_pending <= 1'b1;

        case (state)
        ST_IDLE: begin
            phase   <= 2'd0;
            bin_ctr <= {FFTLEN{1'b0}};
            if (frame_pending) begin
                frame_pending <= 1'b0;
                fill_sel      <= ~fill_sel;   // swap, then clear the new fill half
                clr_ctr       <= {(ANGBITS+1){1'b0}};
                state         <= ST_CLEAR;
            end
            else if (i_round_done)
                state <= ST_SWEEP;
        end

        ST_SWEEP: begin
            phase <= phase + 2'd1;
            if (phase == 2'd3) begin
                if (bin_ctr == {FFTLEN{1'b1}}) begin
                    drain_ctr <= 6'd0;
                    state     <= ST_DRAIN;
                end
                else
                    bin_ctr <= bin_ctr + 1'b1;
            end
        end

        ST_DRAIN: begin
            /* let the CORDIC and the table RMW empty before touching fill_sel */
            drain_ctr <= drain_ctr + 6'd1;
            if (drain_ctr == 6'd40)
                state <= ST_IDLE;
        end

        ST_CLEAR: begin
            clr_ctr <= clr_ctr + 1'b1;
            if (clr_ctr == {1'b0, {ANGBITS{1'b1}}})
                state <= ST_IDLE;
        end
        endcase
    end
end

/****************************************************************************/
/* Bin pipeline: normalise -> linear -> differences -> CORDIC               */
/* snap_q is valid one clock after sweep_addr, i.e. at phase 1.             */
/****************************************************************************/
reg        s1_vld;
reg [7:0]  s1_a [0:3];
/* The bin's own colour code, latched with its amplitudes and carried the whole
   way down rather than recomputed at the far end. bin_ctr only advances on
   phase 3, so it still reads the issued bin here on phase 1. Everything below
   this point is a fixed-latency pipeline, so the code arriving at the table
   write is by construction the bin whose amplitudes produced that bearing -
   there is no re-derivation to get out of step. */
reg [FRQBITS-1:0] s1_f;
always @(posedge i_clk) begin
    s1_vld <= i_rst ? 1'b0 : bin_issue;
    s1_f    <= sweep_addr[FFTLEN-1 -: FRQBITS];
    s1_a[0] <= snap_q[0];
    s1_a[1] <= snap_q[1];
    s1_a[2] <= snap_q[2];
    s1_a[3] <= snap_q[3];
end

/* FOUR SEPARATE STAGES, one operation each. Collapsing max -> subtract ->
   clamp -> LUT -> subtract into a single cycle is 14 logic levels and 6 carry
   chains, which measured 9.24ns against this domain's 8.33ns budget and was
   the whole reason an early build missed timing by 0.885ns. The sweep spends
   4 clocks per bin and 1024 bins per 204.8us round, so pipeline latency here
   is free - only the amp delay line has to track it. */

/* stage 2: strongest beam of the four - both the normalisation reference and
   the ray length source */
wire [7:0] m01 = (s1_a[0] > s1_a[1]) ? s1_a[0] : s1_a[1];
wire [7:0] m23 = (s1_a[2] > s1_a[3]) ? s1_a[2] : s1_a[3];

reg        s2_vld;
reg [7:0]  s2_amax;
reg [7:0]  s2_a [0:3];
reg [FRQBITS-1:0] s2_f;
always @(posedge i_clk) begin
    s2_vld  <= i_rst ? 1'b0 : s1_vld;
    s2_f    <= s1_f;
    s2_amax <= (m01 > m23) ? m01 : m23;
    s2_a[0] <= s1_a[0];
    s2_a[1] <= s1_a[1];
    s2_a[2] <= s1_a[2];
    s2_a[3] <= s1_a[3];
end

/* stage 3: normalised log difference per channel, clamped to the LUT window */
wire [7:0] dd0 = s2_amax - s2_a[0];
wire [7:0] dd1 = s2_amax - s2_a[1];
wire [7:0] dd2 = s2_amax - s2_a[2];
wire [7:0] dd3 = s2_amax - s2_a[3];

reg       s3_vld;
reg [7:0] s3_amp;
reg [5:0] s3_c [0:3];
reg [FRQBITS-1:0] s3_f;
always @(posedge i_clk) begin
    s3_vld  <= i_rst ? 1'b0 : s2_vld;
    s3_f    <= s2_f;
    s3_amp  <= s2_amax;
    s3_c[0] <= (dd0 > 8'd63) ? 6'd63 : dd0[5:0];
    s3_c[1] <= (dd1 > 8'd63) ? 6'd63 : dd1[5:0];
    s3_c[2] <= (dd2 > 8'd63) ? 6'd63 : dd2[5:0];
    s3_c[3] <= (dd3 > 8'd63) ? 6'd63 : dd3[5:0];
end

/* stage 4: back to linear power through the LUT */
reg       s4_vld;
reg [7:0] s4_amp;
reg [7:0] s4_lin [0:3];
reg [FRQBITS-1:0] s4_f;
always @(posedge i_clk) begin
    s4_vld    <= i_rst ? 1'b0 : s3_vld;
    s4_f      <= s3_f;
    s4_amp    <= s3_amp;
    s4_lin[0] <= explut(s3_c[0]);
    s4_lin[1] <= explut(s3_c[1]);
    s4_lin[2] <= explut(s3_c[2]);
    s4_lin[3] <= explut(s3_c[3]);
end

/* stage 5: the two Fourier differences. Indexing by the CH_* map keeps the
   compass assignment in one place. */
reg  signed [9:0] s5_x, s5_y;
reg  [7:0]        s5_amp;
reg  [FRQBITS-1:0] s5_f;
reg               s5_vld;
always @(posedge i_clk) begin
    s5_vld <= i_rst ? 1'b0 : s4_vld;
    s5_f   <= s4_f;
    s5_amp <= s4_amp;
    s5_x   <= $signed({2'b00, s4_lin[CH_E]}) - $signed({2'b00, s4_lin[CH_W]});
    s5_y   <= $signed({2'b00, s4_lin[CH_N]}) - $signed({2'b00, s4_lin[CH_S]});
end

wire [11:0] cd_mag;
wire [15:0] cd_ang;
wire        cd_vld;

cordic_vec #(.XYW(10), .STAGES(STAGES), .GUARD(CGUARD)) cordic_df (
    .i_clk(i_clk),
    .i_ce(1'b1),
    .i_valid(s5_vld),
    .i_x(s5_x),
    .i_y(s5_y),
    .o_mag(cd_mag),
    .o_ang(cd_ang),
    .o_valid(cd_vld)
);

/* The ray length and its colour code both have to arrive with the CORDIC
   result, so they ride matched delay lines rather than being recomputed. */
localparam CDLAT = STAGES + 1;
reg [7:0]         amp_dly [0:CDLAT-1];
reg [FRQBITS-1:0] frq_dly [0:CDLAT-1];
integer q;
always @(posedge i_clk) begin
    amp_dly[0] <= s5_amp;
    frq_dly[0] <= s5_f;
    for (q = 0; q < CDLAT-1; q = q + 1) begin
        amp_dly[q+1] <= amp_dly[q];
        frq_dly[q+1] <= frq_dly[q];
    end
end
wire [7:0]         amp_at_out = amp_dly[CDLAT-1];
wire [FRQBITS-1:0] frq_at_out = frq_dly[CDLAT-1];

/* Ray length: floor-subtract then gain, saturating. Below the floor nothing is
   drawn at all - without it the noise floor would paint a ray at every bearing
   and the display would be a filled disc. */
wire        above_floor = (amp_at_out > AMP_FLOOR);
wire [8:0]  len_raw     = {1'b0, (amp_at_out - AMP_FLOOR)} << AMP_SHIFT;
wire [7:0]  len_sat     = len_raw[8] ? 8'hFF : len_raw[7:0];

/* A bearing is only meaningful if the four beams actually disagree. cd_mag is
   |(X,Y)| and therefore exactly that confidence measure, free of charge - an
   omnidirectional or pure-noise bin has X ~ Y ~ 0 and would otherwise scatter a
   ray in a random direction. */
wire draw_ok = cd_vld && above_floor && (cd_mag > {1'b0, DIR_MIN});

/****************************************************************************/
/* Angle table: 2 x 512 x {frq,len} in one RAM, read-modify-write for the max*/
/****************************************************************************/
localparam TBLW = 8 + FRQBITS;      // {frequency code, ray length}

reg  [ANGBITS:0] tbl_addr;
reg  [TBLW-1:0]  tbl_din;
reg              tbl_we;
wire [TBLW-1:0]  tbl_douta;

reg [1:0]         rmw_st;   // 0 idle, 1 address presented, 2 read data valid
reg [ANGBITS-1:0] rmw_idx;
reg [7:0]         rmw_len;
reg [FRQBITS-1:0] rmw_frq;

wire [ANGBITS-1:0] ang_idx = cd_ang[15 -: ANGBITS];

/* THREE phases, not two. dp_ram registers its port A read: an address presented
   during cycle n only produces o_douta during cycle n+1, so the value has to be
   consumed a full cycle after the address settles. Collapsing this into two
   phases silently compares each entry against the PREVIOUS address's data - the
   max accumulate then keeps the wrong value everywhere, and on the very first
   sweep it latches X. The 4-clock bin cadence leaves room for all three phases,
   which is exactly why that cadence was chosen. */
always @(posedge i_clk) begin
    if (i_rst) begin
        tbl_we   <= 1'b0;
        rmw_st   <= 2'd0;
        tbl_addr <= {(ANGBITS+1){1'b0}};
        tbl_din  <= 8'd0;
    end
    else begin
        tbl_we <= 1'b0;

        if (state == ST_CLEAR) begin
            tbl_addr <= {fill_sel, clr_ctr[ANGBITS-1:0]};
            tbl_din  <= {TBLW{1'b0}};
            tbl_we   <= 1'b1;
            rmw_st   <= 2'd0;
        end
        else begin
            case (rmw_st)
            2'd0: if (draw_ok) begin              // present the read address
                      tbl_addr <= {fill_sel, ang_idx};
                      rmw_idx  <= ang_idx;
                      rmw_len  <= len_sat;
                      rmw_frq  <= frq_at_out;
                      rmw_st   <= 2'd1;
                  end
            2'd1: rmw_st <= 2'd2;                 // RAM is reading this cycle
            2'd2: begin                           // tbl_douta is valid now
                      tbl_addr <= {fill_sel, rmw_idx};
                      /* Compared on LENGTH ONLY. Comparing the whole word would
                         let the frequency code, which sits above the length,
                         decide the max - a high-frequency weak bin would then
                         evict a low-frequency strong one and both the ray and
                         its colour would be wrong. */
                      tbl_din  <= (tbl_douta[7:0] > rmw_len) ? tbl_douta
                                                             : {rmw_frq, rmw_len};
                      tbl_we   <= 1'b1;
                      rmw_st   <= 2'd0;
                  end
            default: rmw_st <= 2'd0;
            endcase
        end
    end
end

/* fill_sel into the pixel domain; the display always reads the OTHER half. */
reg [1:0] fillsel_sync;
always @(posedge i_rdClk)
    fillsel_sync <= {fillsel_sync[0], fill_sel};

dp_ram #(.ADDRBITS(ANGBITS+1), .BITS(TBLW)) angTbl (
    .i_clka(i_clk),
    .i_wea(tbl_we),
    .i_addra(tbl_addr),
    .i_dina(tbl_din),
    .o_douta(tbl_douta),
    .i_clkb(i_rdClk),
    .i_addrb({~fillsel_sync[1], i_rdAddr}),
    .o_doutb({o_rdFrq, o_rdLen})
);

endmodule
