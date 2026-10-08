//////////////////////////////////////////////////////////////////////////////////
//
// Design Name: OWIFI_RX
// Module Name: div_combine
// Project Name: RA-Sentinel 802.11 receiver + direction finder
// Engineer: Tobias Weber
// Target Devices: Artix 7, XC7A100T (RASBB U10 + RASRF2400WBMC)
// Description:
//   Diversity combiner in front of the single decode chain (2026-09-30):
//   maximum-ratio combining of the four receive channels in the time domain,
//   one complex weight per channel and frame.
//
//       y[n] = sum over k of  w_k * x_k[n - DELAY]          k = 0..3
//
//   ESTIMATE. The 4x4 correlation matrix of the UNDELAYED samples runs as
//   leaky averages (time constant 2^AVG_SHIFT instants):
//
//       R[j][k] = < conj(x_j) * x_k >        4 powers + 6 complex cross terms
//
//   With one transmitter, x_k = h_k * s + n_k, so R[k][r] = conj(h_k) * h_r * P
//   for k != r: column r of R is, up to the common factor h_r * P, exactly the
//   conjugate channel vector - the maximum-ratio weights. r is the channel
//   with the largest power, so the column with the best estimate is used and
//   no channel is a fixed reference. The column is scaled to UNIT NORM
//   (sum |w_k|^2 = 1, weights in Q1.10): the noise power at the output then
//   equals one channel's, and the signal power is the SUM of the four channel
//   powers. A channel that carries no signal gets a weight near zero by
//   itself.
//
//   The phase between the channels includes the per-boot LO offsets of the
//   four MAX2831 (reference-locked, not LO-locked). It does not matter here:
//   the weights are measured on each frame itself.
//
//   DELAY. The weights must be known before the frame reaches the decoder,
//   so all four channels pass a delay line of DELAY = 2^DLOG2 - 1 instants
//   (255 = 12.75 us). While the frame's preamble runs through the estimator
//   the decoder still sees the noise before it. Every consumer of the sample
//   stream (antenna selection, direction finder, IQ capture, phase
//   comparison) takes the DELAYED stream o_iq, so all of them stay aligned
//   with the decoder's events exactly as before.
//
//   FREEZE. The applied weights follow the estimate only while i_freeze is
//   low. The top level raises it from the decoder's short-preamble detect
//   (60..100 instants into the frame in the DELAYED stream) to the end of
//   the frame: the long training field, from which the equalizer takes its
//   channel estimate, and all data symbols see one fixed set of weights.
//   At the detect the estimator has seen the first ~350 instants of the same
//   frame. The weights are NOT frozen in S_SYNC_SHORT, where ant_select
//   already holds the antenna: the power trigger fires on noise too, and
//   weights frozen there would be measured on noise.
//
//   OUTPUT. o_rx is the decoder's input: the combined sample when i_enable
//   is high, else channel i_sel of the delayed stream (plain antenna
//   selection, as before this block existed). Both take the same pipeline,
//   so switching i_enable never moves the sample timing.
//
//   STRONG SIGNALS. The sum of four channel powers can be 6 dB above one
//   channel, which would clip a signal that is near full scale on all four.
//   When the strongest channel's average power reaches 2^HALF_MSB (rms
//   amplitude 256 = -18 dBFS) the weights are scaled to norm 1/2 instead of
//   1: the output is then never larger than the strongest channel itself.
//   The combined sample still saturates at 12 bits instead of wrapping.
//
//   WEIGHT UPDATE. A small sequencer recomputes the weights continuously
//   (one multiplier, about 24 clocks per update): pick r, shift the column so
//   the power R[r][r] fills 11 bits, S = sum of the eight squares, then
//   w = a * LUT(1/sqrt(S)). The cross terms can never exceed R[r][r]
//   (Cauchy-Schwarz holds for the leaky sums too), so that one shift
//   normalises the whole column.
//
// Dependencies: none (multipliers and the delay RAM are inferred)
//
// Additional Comments: https://github.com/Tobias-DG3YEV/RA-Sentinel
//
//////////////////////////////////////////////////////////////////////////////////
// Copyright (C) 2026 Tobias Weber
// License: GNU GPL v3
//////////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps

module div_combine #(
    parameter DLOG2     = 8,   // delay line depth 2^DLOG2, delay = 2^DLOG2 - 1 instants
    parameter AVG_SHIFT = 6,   // correlation averages: time constant 2^N instants
    parameter HALF_MSB  = 16   // strongest channel's power >= 2^N: weights at norm 1/2
)(
    input  wire        i_clk,       // receiver domain (100MHz)
    input  wire        i_rst,

    /* undelayed sample stream, ch c: I at [24c+12 +: 12], Q at [24c +: 12] */
    input  wire        i_strobe,
    input  wire [95:0] i_iq,

    input  wire        i_enable,    // 1: o_rx = combined, 0: o_rx = channel i_sel
    input  wire [1:0]  i_sel,       // antenna selection (on the delayed stream)
    input  wire        i_freeze,    // decoder busy: hold the applied weights

    /* delayed stream for every other consumer */
    output reg         o_strobe,
    output wire [95:0] o_iq,

    /* decoder input */
    output reg                o_rx_strobe,
    output reg  signed [11:0] o_rx_i,
    output reg  signed [11:0] o_rx_q,

    /* diagnostics */
    output wire [95:0] o_weights,   // applied weights, ch c: re at [24c+12 +: 12], im at [24c +: 12], Q1.10
    output reg  [1:0]  o_ref,       // column (strongest channel) of the applied weights
    output reg         o_half,      // applied weights are at norm 1/2 (strong signal)
    output reg  [15:0] o_sat_count, // combined samples that saturated (wraps)
    output reg  [15:0] o_upd_count  // weight sets taken over (wraps)
);

localparam DEPTH = (1 << DLOG2);
localparam ACCW  = 25 + AVG_SHIFT;        // product sums are 25 bits signed

/****************************************************************************/
/* Delay line: write the new instant, read the oldest in the same clock.    */
/****************************************************************************/
(* ram_style = "block" *) reg [95:0] dl_mem [0:DEPTH-1];
reg  [DLOG2-1:0] dl_wptr;
reg  [95:0]      dl_q;
wire [DLOG2-1:0] dl_rptr = dl_wptr + 1'b1;

integer di;
initial begin
    for (di = 0; di < DEPTH; di = di + 1) dl_mem[di] = 96'd0;
end

always @(posedge i_clk) begin
    if (i_strobe) begin
        dl_mem[dl_wptr] <= i_iq;
        dl_q            <= dl_mem[dl_rptr];
    end
end
always @(posedge i_clk) begin
    if (i_rst) begin
        dl_wptr  <= {DLOG2{1'b0}};
        o_strobe <= 1'b0;
    end
    else begin
        if (i_strobe) dl_wptr <= dl_wptr + 1'b1;
        o_strobe <= i_strobe;
    end
end
assign o_iq = dl_q;

/****************************************************************************/
/* Correlation matrix of the undelayed stream.                              */
/*   stage 1 (strobe):   products, registered in the multipliers            */
/*   stage 2 (strobe_d): sums of two products                               */
/*   stage 3 (strobe_d2): leaky averages                                    */
/****************************************************************************/
reg strobe_d, strobe_d2;
always @(posedge i_clk) begin
    strobe_d  <= i_rst ? 1'b0 : i_strobe;
    strobe_d2 <= i_rst ? 1'b0 : strobe_d;
end

wire signed [11:0] xi [0:3];
wire signed [11:0] xq [0:3];
genvar c;
generate for (c = 0; c < 4; c = c + 1) begin : gen_x
    assign xi[c] = i_iq[24*c + 12 +: 12];
    assign xq[c] = i_iq[24*c      +: 12];
end endgenerate

/* powers */
reg signed [23:0] pp_ii [0:3];
reg signed [23:0] pp_qq [0:3];
reg signed [24:0] pw_s  [0:3];
reg signed [ACCW-1:0] acc_p [0:3];

generate for (c = 0; c < 4; c = c + 1) begin : gen_pwr
    always @(posedge i_clk) begin
        if (i_strobe) begin
            pp_ii[c] <= xi[c] * xi[c];
            pp_qq[c] <= xq[c] * xq[c];
        end
        if (strobe_d)
            pw_s[c] <= pp_ii[c] + pp_qq[c];
        if (i_rst)
            acc_p[c] <= {ACCW{1'b0}};
        else if (strobe_d2)
            acc_p[c] <= acc_p[c] + pw_s[c] - (acc_p[c] >>> AVG_SHIFT);
    end
end endgenerate

/* cross terms, pair p = (j,k), j < k:  conj(x_j) * x_k
     re = xi_j*xi_k + xq_j*xq_k      im = xi_j*xq_k - xq_j*xi_k            */
reg signed [23:0] pc_ii [0:5];
reg signed [23:0] pc_qq [0:5];
reg signed [23:0] pc_iq [0:5];
reg signed [23:0] pc_qi [0:5];
reg signed [24:0] cr_s  [0:5];
reg signed [24:0] ci_s  [0:5];
reg signed [ACCW-1:0] acc_re [0:5];
reg signed [ACCW-1:0] acc_im [0:5];

genvar p;
generate for (p = 0; p < 6; p = p + 1) begin : gen_cross
    localparam [1:0] J = (p < 3) ? 2'd0 : (p < 5) ? 2'd1 : 2'd2;
    localparam [1:0] K = (p == 0) ? 2'd1 : (p == 1 || p == 3) ? 2'd2 : 2'd3;
    always @(posedge i_clk) begin
        if (i_strobe) begin
            pc_ii[p] <= xi[J] * xi[K];
            pc_qq[p] <= xq[J] * xq[K];
            pc_iq[p] <= xi[J] * xq[K];
            pc_qi[p] <= xq[J] * xi[K];
        end
        if (strobe_d) begin
            cr_s[p] <= pc_ii[p] + pc_qq[p];
            ci_s[p] <= pc_iq[p] - pc_qi[p];
        end
        if (i_rst) begin
            acc_re[p] <= {ACCW{1'b0}};
            acc_im[p] <= {ACCW{1'b0}};
        end
        else if (strobe_d2) begin
            acc_re[p] <= acc_re[p] + cr_s[p] - (acc_re[p] >>> AVG_SHIFT);
            acc_im[p] <= acc_im[p] + ci_s[p] - (acc_im[p] >>> AVG_SHIFT);
        end
    end
end endgenerate

/* pair index of (a,b), a != b, in either order */
function [2:0] pair_of; input [1:0] a; input [1:0] b;
    reg [1:0] lo, hi;
    begin
        lo = (a < b) ? a : b;
        hi = (a < b) ? b : a;
        case ({lo, hi})
            4'b00_01: pair_of = 3'd0;
            4'b00_10: pair_of = 3'd1;
            4'b00_11: pair_of = 3'd2;
            4'b01_10: pair_of = 3'd3;
            4'b01_11: pair_of = 3'd4;
            default:  pair_of = 3'd5;
        endcase
    end
endfunction

/****************************************************************************/
/* Weight sequencer.                                                        */
/*   w_k = R[k][r] = < conj(x_k) * x_r >:  k < r stored, k > r conjugate,   */
/*   k = r the power. Column snapshot, shift, squares, 1/sqrt, scale.       */
/****************************************************************************/
/* strongest channel */
wire               c01 = (acc_p[1] > acc_p[0]);
wire               c23 = (acc_p[3] > acc_p[2]);
wire [1:0]         m01 = c01 ? 2'd1 : 2'd0;
wire [1:0]         m23 = c23 ? 2'd3 : 2'd2;
wire signed [ACCW-1:0] v01 = c01 ? acc_p[1] : acc_p[0];
wire signed [ACCW-1:0] v23 = c23 ? acc_p[3] : acc_p[2];
wire [1:0]         best = (v23 > v01) ? m23 : m01;

/* 1/sqrt table: m in 64..255 -> round(2^15 / sqrt(m)), 2052..4096 */
reg [12:0] rsq_lut [0:255];
integer li;
initial begin
    for (li = 0; li < 256; li = li + 1)
        rsq_lut[li] = (li < 64) ? 13'd4096
                                : $rtoi(32768.0 / $sqrt(li * 1.0) + 0.5);
end

localparam [2:0] Q_SNAP = 3'd0, Q_SHIFT = 3'd1, Q_SQR = 3'd2, Q_RSQ = 3'd3,
                 Q_MUL = 3'd4, Q_DONE = 3'd5;
reg [2:0] q_st;
reg [1:0] q_ref;
reg signed [ACCW-1:0] col [0:7];       // column r: [2k] = re, [2k+1] = im
reg [5:0]  q_lz;                       // redundant sign bits of the power
reg signed [11:0] a_n [0:7];           // normalised column, 12 bits
reg [3:0]  q_i;                        // element counter
reg [25:0] q_sum;                      // sum of squares
reg [12:0] q_rsq;
reg [1:0]  q_e;
reg        q_zero;
reg        q_half;

/* the one sequencer multiplier: 12 x 14 signed */
reg  signed [11:0] m_a;
reg  signed [13:0] m_b;
reg  signed [25:0] m_p;
always @(posedge i_clk) m_p <= m_a * m_b;

reg signed [11:0] w_next [0:7];
reg        w_valid;                    // a complete new set is in w_next
reg [1:0]  w_next_ref;
reg        w_next_half;
wire       w_take;                     // the applied weights take w_next over (below)

/* leading redundant sign bits of a positive value (the power): position of
   the MSB. ACCW bits; the power is never negative. */
function [5:0] msb_pos; input [ACCW-1:0] v;
    integer k;
    begin
        msb_pos = 6'd0;
        for (k = 0; k < ACCW; k = k + 1)
            if (v[k]) msb_pos = k[5:0];
    end
endfunction

wire [5:0] pw_msb = msb_pos(col[{q_ref, 1'b0}]);
/* shift so the power's MSB lands on bit 10: a_r in 1024..2047 */
wire signed [ACCW-1:0] col_cur = col[q_i[2:0]];
wire signed [ACCW-1:0] col_shl = col_cur <<< (6'd10 - q_lz);      // MSB below bit 10
wire signed [ACCW-1:0] col_shr = col_cur >>> (q_lz - 6'd10);      // MSB at or above bit 10
wire signed [ACCW-1:0] col_n   = (q_lz < 6'd10) ? col_shl : col_shr;
/* clamp to 12 bits (a cross term can reach the power's own magnitude) */
wire signed [11:0] col_c = (col_n >  $signed({{(ACCW-12){1'b0}}, 12'sd2047})) ? 12'sd2047 :
                           (col_n < -$signed({{(ACCW-12){1'b0}}, 12'sd2047})) ? -12'sd2047 :
                           col_n[11:0];

/* 1/sqrt argument: m in 64..255 and an even shift */
wire [7:0] rs_m = (q_sum[25:24] != 2'd0) ? q_sum[25:18] :
                  (q_sum[23:22] != 2'd0) ? q_sum[23:16] : q_sum[21:14];
wire [1:0] rs_e = (q_sum[25:24] != 2'd0) ? 2'd2 :
                  (q_sum[23:22] != 2'd0) ? 2'd1 : 2'd0;

/* product a * rsq -> weight in Q1.10, rounded */
wire [3:0]         w_sh  = 4'd12 + q_e + q_half;
wire signed [25:0] m_rnd = m_p + (26'sd1 <<< (w_sh - 4'd1));
wire signed [25:0] m_shf = m_rnd >>> w_sh;
wire signed [11:0] w_q   = (m_shf >  26'sd1024) ? 12'sd1024 :
                           (m_shf < -26'sd1024) ? -12'sd1024 : m_shf[11:0];

integer ci2;
always @(posedge i_clk) begin
    if (i_rst) begin
        q_st    <= Q_SNAP;
        w_valid <= 1'b0;
        q_i     <= 4'd0;
    end
    else begin
        case (q_st)
            /* take the column of the strongest channel, all eight values in
               one clock so they belong to the same instant */
            Q_SNAP: begin
                q_ref <= best;
                for (ci2 = 0; ci2 < 4; ci2 = ci2 + 1) begin
                    if (ci2[1:0] == best) begin
                        col[2*ci2]   <= acc_p[ci2];
                        col[2*ci2+1] <= {ACCW{1'b0}};
                    end
                    else begin
                        col[2*ci2]   <= acc_re[pair_of(ci2[1:0], best)];
                        /* stored pair is conj(x_lo)*x_hi; w_k = conj(x_k)*x_r:
                           as stored for k < r, conjugate for k > r */
                        col[2*ci2+1] <= (ci2[1:0] < best) ?  acc_im[pair_of(ci2[1:0], best)]
                                                          : -acc_im[pair_of(ci2[1:0], best)];
                    end
                end
                q_st <= Q_SHIFT;
            end
            Q_SHIFT: begin
                q_lz   <= pw_msb;
                q_zero <= (col[{q_ref, 1'b0}] <= 0);
                q_half <= (pw_msb >= HALF_MSB + AVG_SHIFT);
                q_i    <= 4'd0;
                q_sum  <= 26'd0;
                q_st   <= Q_SQR;
            end
            /* normalise element q_i, square it: q_i 0..7 feeds the multiplier,
               the product of element i arrives two clocks later */
            Q_SQR: begin
                if (q_i <= 4'd7) begin
                    a_n[q_i[2:0]] <= col_c;
                    m_a <= col_c;
                    m_b <= {{2{col_c[11]}}, col_c};
                end
                if (q_i >= 4'd2)
                    q_sum <= q_sum + m_p[25:0];
                q_i <= q_i + 4'd1;
                if (q_i == 4'd9) q_st <= Q_RSQ;
            end
            Q_RSQ: begin
                w_valid <= 1'b0;           // w_next is rewritten from here on
                q_rsq <= rsq_lut[rs_m];
                q_e   <= rs_e;
                q_i   <= 4'd0;
                q_st  <= Q_MUL;
            end
            Q_MUL: begin
                if (q_i <= 4'd7) begin
                    m_a <= a_n[q_i[2:0]];
                    m_b <= {1'b0, q_rsq};
                end
                if (q_i >= 4'd2)
                    w_next[q_i[2:0] - 3'd2] <= w_q;
                q_i <= q_i + 4'd1;
                if (q_i == 4'd9) q_st <= Q_DONE;
            end
            default: begin   // Q_DONE
                if (q_zero) begin
                    /* no signal at all (reset, blanked front end): channel r alone */
                    for (ci2 = 0; ci2 < 8; ci2 = ci2 + 1)
                        w_next[ci2] <= (ci2 == {q_ref, 1'b0}) ? 12'sd1024 : 12'sd0;
                end
                w_next_ref  <= q_ref;
                w_next_half <= q_half & ~q_zero;
                w_valid    <= 1'b1;
                q_st       <= Q_SNAP;
            end
        endcase
        /* a set is consumed when the applied weights take it (below) */
        if (w_take) w_valid <= 1'b0;
    end
end

/****************************************************************************/
/* Applied weights: follow the estimate between frames, hold during one.    */
/* Taken over on an output strobe only, so a sample never sees half a set.  */
/****************************************************************************/
reg signed [11:0] w_re [0:3];
reg signed [11:0] w_im [0:3];
assign w_take = w_valid && o_strobe && !i_freeze;

integer wi;
always @(posedge i_clk) begin
    if (i_rst) begin
        for (wi = 0; wi < 4; wi = wi + 1) begin
            w_re[wi] <= (wi == 0) ? 12'sd1024 : 12'sd0;
            w_im[wi] <= 12'sd0;
        end
        o_ref       <= 2'd0;
        o_half      <= 1'b0;
        o_upd_count <= 16'd0;
    end
    else if (w_take) begin
        for (wi = 0; wi < 4; wi = wi + 1) begin
            w_re[wi] <= w_next[2*wi];
            w_im[wi] <= w_next[2*wi+1];
        end
        o_ref       <= w_next_ref;
        o_half      <= w_next_half;
        o_upd_count <= o_upd_count + 16'd1;
    end
end

generate for (c = 0; c < 4; c = c + 1) begin : gen_wout
    assign o_weights[24*c + 12 +: 12] = w_re[c];
    assign o_weights[24*c      +: 12] = w_im[c];
end endgenerate

/****************************************************************************/
/* Combiner on the delayed stream.                                          */
/*   stage 1 (o_strobe):  16 products                                       */
/*   stage 2:             sums per channel                                  */
/*   stage 3:             sum of four, round, saturate, mux -> o_rx         */
/****************************************************************************/
wire signed [11:0] di_ [0:3];
wire signed [11:0] dq_ [0:3];
generate for (c = 0; c < 4; c = c + 1) begin : gen_d
    assign di_[c] = dl_q[24*c + 12 +: 12];
    assign dq_[c] = dl_q[24*c      +: 12];
end endgenerate

reg signed [23:0] y_rr [0:3];
reg signed [23:0] y_ii [0:3];
reg signed [23:0] y_ri [0:3];
reg signed [23:0] y_ir [0:3];
reg signed [24:0] y_re [0:3];
reg signed [24:0] y_im [0:3];
reg signed [11:0] s_i1, s_q1, s_i2, s_q2;   // selected channel, same pipeline
reg               st1, st2;

generate for (c = 0; c < 4; c = c + 1) begin : gen_comb
    always @(posedge i_clk) begin
        if (o_strobe) begin
            y_rr[c] <= w_re[c] * di_[c];
            y_ii[c] <= w_im[c] * dq_[c];
            y_ri[c] <= w_re[c] * dq_[c];
            y_ir[c] <= w_im[c] * di_[c];
        end
        if (st1) begin
            y_re[c] <= y_rr[c] - y_ii[c];
            y_im[c] <= y_ri[c] + y_ir[c];
        end
    end
end endgenerate

wire signed [26:0] sum_re = y_re[0] + y_re[1] + y_re[2] + y_re[3];
wire signed [26:0] sum_im = y_im[0] + y_im[1] + y_im[2] + y_im[3];
wire signed [16:0] rnd_re = (sum_re + 27'sd512) >>> 10;
wire signed [16:0] rnd_im = (sum_im + 27'sd512) >>> 10;
wire sat_re = (rnd_re > 17'sd2047) || (rnd_re < -17'sd2047);
wire sat_im = (rnd_im > 17'sd2047) || (rnd_im < -17'sd2047);
wire signed [11:0] cmb_i = (rnd_re >  17'sd2047) ? 12'sd2047 :
                           (rnd_re < -17'sd2047) ? -12'sd2047 : rnd_re[11:0];
wire signed [11:0] cmb_q = (rnd_im >  17'sd2047) ? 12'sd2047 :
                           (rnd_im < -17'sd2047) ? -12'sd2047 : rnd_im[11:0];

/* The saturation flag is registered before it counts: the compare sits
   behind the DSP sum and the rounding carry chain, and driving the
   counter's 16 enables straight from it missed 100 MHz by 0.1 ns once the
   placement moved (2026-10-02). The count lags one cycle, nobody notices. */
reg sat_q;
always @(posedge i_clk) begin
    if (i_rst) begin
        st1 <= 1'b0; st2 <= 1'b0; o_rx_strobe <= 1'b0;
        o_sat_count <= 16'd0; sat_q <= 1'b0;
    end
    else begin
        st1 <= o_strobe;
        st2 <= st1;
        o_rx_strobe <= st2;
        sat_q <= st2 && i_enable && (sat_re || sat_im);
        if (sat_q)
            o_sat_count <= o_sat_count + 16'd1;
    end
    if (o_strobe) begin
        s_i1 <= di_[i_sel];
        s_q1 <= dq_[i_sel];
    end
    if (st1) begin
        s_i2 <= s_i1;
        s_q2 <= s_q1;
    end
    if (st2) begin
        o_rx_i <= i_enable ? cmb_i : s_i2;
        o_rx_q <= i_enable ? cmb_q : s_q2;
    end
end

endmodule
