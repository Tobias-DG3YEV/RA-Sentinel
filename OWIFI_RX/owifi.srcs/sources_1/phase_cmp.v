//////////////////////////////////////////////////////////////////////////////////
//
// Design Name: OWIFI_RX
// Module Name: phase_cmp
// Project Name: RA-Sentinel 802.11 receiver + direction finder
// Engineer: Tobias Weber
// Target Devices: Artix 7, XC7A100T (RASBB U10 + RASRF2400WBMC)
// Description:
//   Real-time four-channel PHASE comparison, one measurement per received
//   frame. Runs on the same 96-bit sample tap as iq_capture (4 x {I,Q}
//   12-bit at 20 MSPS): i_start instants after the arm (the STF detect) it
//   accumulates the complex cross products of channel 0 with channels 1..3
//
//       A_k = sum over i_len instants of  conj(x0[n]) * xk[n]      k = 1..3
//
//   and hands the three accumulators, one per clock, to cordic_vec. The angle
//   of A_k is the phase of channel k relative to channel 0 (binary turns,
//   65536 = 360 deg, CCW positive: arg(xk) - arg(x0)); its magnitude is the
//   coherence. With the defaults (start 96, len 128) the window sits on the
//   LTF: dot11 raises short_preamble_detected 60..100 instants into the STF,
//   so arm+96 .. arm+224 is STF+156 .. STF+324 at worst, i.e. the 160-instant
//   long training field plus a little of SIGNAL. Any part of the frame gives
//   the same inter-channel phase for a plane wave, so the exact placement
//   only matters for SNR (the LTF is the strongest, flattest part).
//
//   NORMALISATION. The accumulators are 36 bits (24-bit products, 2^10
//   instants of headroom). Before the CORDIC each pair (re,im) is shifted
//   left by the number of redundant sign bits common to both, so the larger
//   component fills bits [15:0] of the CORDIC input. The shift count is
//   reported as a magnitude EXPONENT: mag_exp = 35 - shift is the bit
//   position of the accumulator's MSB (0..35). A full-scale coherent LTF on
//   two channels gives 2^11 * 2^11 * 128 = 2^29 -> mag_exp 29; ADC noise
//   floor (RMS ~ 10 LSB) -> 2^7 * 128 = 2^14 -> mag_exp ~ 14. Anything
//   below WEAK_EXP is flagged weak (o_weak).
//
//   Only one measurement is ever in flight: i_arm while busy is ignored
//   (iq_capture only arms this block for an arm the slot buffer takes) and
//   the trigger-to-result latency is i_start + i_len instants (11.2 us at the
//   defaults) plus ~25 clocks, far below the 51.2 us publish time of a full
//   snapshot, so the result reaches the descriptor of the frame it belongs to.
//   i_abort discards a running measurement (the old result stays on the
//   outputs; o_done marks each new one).
//
//   WHAT THE NUMBER MEANS ON THIS HARDWARE. The four MAX2831 LOs are
//   reference-locked, not LO-locked: the inter-channel phase includes an
//   arbitrary per-boot LO phase offset that re-randomises on every relock.
//   The measurement is therefore a RELATIVE one - the difference between two
//   frames within one lock period is the physical bearing information, and
//   an absolute bearing needs a per-boot calibration (a transmitter at a
//   known bearing) applied on the PC. The RASANT2400 array (2.03 lambda
//   radius) wraps the interferometer several times, so this output is a
//   diagnostic / refinement next to df_frame's unambiguous amplitude bearing,
//   not a replacement for it. Tested on air with the two working channels of
//   RASRF2400WBMC; the block is 4-channel throughout.
//
// Dependencies: cordic_vec.v (RASPMO repo)
//
// Additional Comments: https://github.com/Tobias-DG3YEV/RA-Sentinel
//
//////////////////////////////////////////////////////////////////////////////////
// Copyright (C) 2026 Tobias Weber
// License: GNU GPL v3
//////////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps

module phase_cmp #(
    parameter ACCW     = 36,            // accumulator width, 24-bit product + 12 bits
    parameter [5:0] WEAK_EXP = 6'd18    // mag_exp below this -> o_weak
)(
    input  wire        i_clk,
    input  wire        i_rst,

    /* sample tap */
    input  wire        i_smp_strobe,
    input  wire [95:0] i_smp,           // ch c: I at [24c+12 +: 12], Q at [24c +: 12]

    /* control */
    input  wire        i_arm,           // start a measurement (ignored while busy)
    input  wire        i_abort,         // discard the running measurement
    input  wire [15:0] i_start,         // instants after the arm before the window (>= 1)
    input  wire [15:0] i_len,           // instants in the window, 1..1024

    /* result, held until the next o_done */
    output reg         o_busy,
    output reg         o_done,          // one clock, result registers updated
    output reg  [15:0] o_ph1,           // arg(ch1) - arg(ch0), binary turns
    output reg  [15:0] o_ph2,
    output reg  [15:0] o_ph3,
    output reg  [5:0]  o_exp1,          // MSB position of |A_k| (0..35)
    output reg  [5:0]  o_exp2,
    output reg  [5:0]  o_exp3,
    output reg         o_weak           // any pair below WEAK_EXP
);

/*------------------------------------------------------------------*/
/* sample unpack                                                    */
/*------------------------------------------------------------------*/
wire signed [11:0] i0 = i_smp[23:12], q0 = i_smp[11:0];
wire signed [11:0] i1 = i_smp[47:36], q1 = i_smp[35:24];
wire signed [11:0] i2 = i_smp[71:60], q2 = i_smp[59:48];
wire signed [11:0] i3 = i_smp[95:84], q3 = i_smp[83:72];

/* conj(x0) * xk = (i0 - j q0)(ik + j qk) = (i0 ik + q0 qk) + j (i0 qk - q0 ik) */
reg  signed [ACCW-1:0] acc_re [1:3];
reg  signed [ACCW-1:0] acc_im [1:3];

/* registered products (one DSP each, 6 total), taken at the strobe */
reg signed [24:0] p_re [1:3];
reg signed [24:0] p_im [1:3];
reg               p_stb;

always @(posedge i_clk) begin
    p_stb   <= i_smp_strobe;
    p_re[1] <= i0 * i1 + q0 * q1;  p_im[1] <= i0 * q1 - q0 * i1;
    p_re[2] <= i0 * i2 + q0 * q2;  p_im[2] <= i0 * q2 - q0 * i2;
    p_re[3] <= i0 * i3 + q0 * q3;  p_im[3] <= i0 * q3 - q0 * i3;
end

/*------------------------------------------------------------------*/
/* window sequencer                                                 */
/*------------------------------------------------------------------*/
localparam S_IDLE = 3'd0, S_WAIT = 3'd1, S_ACC = 3'd2, S_NORM = 3'd3, S_OUT = 3'd4;
reg [2:0]  st;
reg [15:0] cnt;
reg [1:0]  out_k;                       // which pair is being issued to the CORDIC
integer k;

/* normalisation: redundant sign bits common to re and im */
function [5:0] sign_bits;               // number of leading bits equal to the sign, minus 1
    input signed [ACCW-1:0] v;
    integer b; reg found; reg [5:0] r;
    begin
        r = 6'd0; found = 1'b0;
        for (b = ACCW-2; b >= 0; b = b - 1)
            if (!found) begin
                if (v[b] == v[ACCW-1]) r = r + 6'd1;
                else found = 1'b1;
            end
        sign_bits = r;
    end
endfunction

reg signed [ACCW-1:0] n_re, n_im;
reg [5:0]  n_sh;
reg        n_valid;
reg [1:0]  n_k;
/* per-pair shift counts, registered every clock from the (stable after
   S_ACC) accumulators - S_NORM gives them one clock to settle, so the S_OUT
   path is only mux + barrel shift (the single-cycle version was 15 LUT
   levels and missed 100 MHz by 0.2 ns) */
reg [5:0]  shk [1:3];
integer j;
always @(posedge i_clk)
    for (j = 1; j <= 3; j = j + 1)
        shk[j] <= (sign_bits(acc_re[j]) < sign_bits(acc_im[j])) ? sign_bits(acc_re[j]) : sign_bits(acc_im[j]);
wire [5:0] sh_min = shk[out_k == 2'd0 ? 1 : out_k];
/* shift so that the top 16 bits hold the value with one sign bit: the
   accumulator has ACCW-16 = 20 bits above the CORDIC input width */
wire [5:0] sh_use = (sh_min > (ACCW-16)) ? (ACCW-16) : sh_min;

always @(posedge i_clk) begin
    n_valid <= 1'b0;
    if (i_rst) begin
        st <= S_IDLE; cnt <= 16'd0; out_k <= 2'd0; o_busy <= 1'b0;
        for (k = 1; k <= 3; k = k + 1) begin acc_re[k] <= 0; acc_im[k] <= 0; end
        n_re <= 0; n_im <= 0; n_sh <= 6'd0; n_k <= 2'd0;
    end
    else begin
        case (st)
        S_IDLE: begin
            o_busy <= 1'b0;
            if (i_arm) begin
                /* a strobe in the arm clock is the arm instant itself (as in
                   iq_snapshot), so it already counts as one instant seen */
                st <= S_WAIT; cnt <= {15'd0, i_smp_strobe}; o_busy <= 1'b1;
                for (k = 1; k <= 3; k = k + 1) begin acc_re[k] <= 0; acc_im[k] <= 0; end
            end
        end
        S_WAIT: begin
            if (i_abort) st <= S_IDLE;
            else if (i_smp_strobe) begin
                /* the strobe that ends the wait is instant i_start after the
                   arm (the arm's own instant is 0); its product enters the
                   accumulator first. Verified on air 2026-09-22 against the
                   snapshot instants [pretrig+start, pretrig+start+len). */
                if (cnt >= i_start) begin st <= S_ACC; cnt <= 16'd0; end
                else cnt <= cnt + 16'd1;
            end
        end
        S_ACC: begin
            if (i_abort) st <= S_IDLE;
            else begin
                if (p_stb) begin
                    for (k = 1; k <= 3; k = k + 1) begin
                        acc_re[k] <= acc_re[k] + p_re[k];
                        acc_im[k] <= acc_im[k] + p_im[k];
                    end
                    if (cnt + 16'd1 >= i_len) begin st <= S_NORM; out_k <= 2'd1; end
                    else cnt <= cnt + 16'd1;
                end
            end
        end
        S_NORM: st <= S_OUT;            /* shk settles */
        S_OUT: begin                    /* issue pairs 1,2,3 on consecutive clocks */
            n_re    <= acc_re[out_k] <<< sh_use;
            n_im    <= acc_im[out_k] <<< sh_use;
            n_sh    <= sh_min;             /* exponent from the uncapped count */
            n_k     <= out_k;
            n_valid <= 1'b1;
            if (out_k == 2'd3) st <= S_IDLE;
            else out_k <= out_k + 2'd1;
        end
        endcase
    end
end

/*------------------------------------------------------------------*/
/* CORDIC, shared by the three pairs (pipelined, one per clock)     */
/*------------------------------------------------------------------*/
localparam STAGES = 16;
wire [15:0] c_ang;
wire        c_valid;
wire [17:0] c_mag;
cordic_vec #(.XYW(16), .STAGES(STAGES), .GUARD(4)) u_cordic (
    .i_clk(i_clk), .i_ce(1'b1), .i_valid(n_valid),
    .i_x(n_re[ACCW-1 -: 16]), .i_y(n_im[ACCW-1 -: 16]),
    .o_mag(c_mag), .o_ang(c_ang), .o_valid(c_valid)
);

/* tag pipeline alongside the CORDIC: pair index and exponent */
reg [1:0] tag_k   [0:STAGES];
reg [5:0] tag_exp [0:STAGES];
integer t;
always @(posedge i_clk) begin
    tag_k[0]   <= n_k;
    /* MSB position: bit ACCW-1 is the sign. An empty accumulator (all bits
       equal the sign, n_sh = ACCW-1: a zeroed channel, e.g. blanked by a
       fast link heal) is exponent 0, i.e. weak - it used to wrap to 63 and
       pass as the strongest possible result. */
    tag_exp[0] <= (n_sh > ACCW - 2) ? 6'd0 : (ACCW - 2) - n_sh;
    for (t = 0; t < STAGES; t = t + 1) begin
        tag_k[t+1]   <= tag_k[t];
        tag_exp[t+1] <= tag_exp[t];
    end
end

always @(posedge i_clk) begin
    o_done <= 1'b0;
    if (i_rst) begin
        o_ph1 <= 16'd0; o_ph2 <= 16'd0; o_ph3 <= 16'd0;
        o_exp1 <= 6'd0; o_exp2 <= 6'd0; o_exp3 <= 6'd0; o_weak <= 1'b1;
    end
    else if (c_valid) begin
        case (tag_k[STAGES])
            2'd1: begin o_ph1 <= c_ang; o_exp1 <= tag_exp[STAGES];
                        o_weak <= (tag_exp[STAGES] < WEAK_EXP); end
            2'd2: begin o_ph2 <= c_ang; o_exp2 <= tag_exp[STAGES];
                        o_weak <= o_weak | (tag_exp[STAGES] < WEAK_EXP); end
            default: begin o_ph3 <= c_ang; o_exp3 <= tag_exp[STAGES];
                        o_weak <= o_weak | (tag_exp[STAGES] < WEAK_EXP); o_done <= 1'b1; end
        endcase
    end
end

endmodule
