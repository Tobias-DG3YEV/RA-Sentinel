//////////////////////////////////////////////////////////////////////////////////
// iq_balance.v
//
// Blind adaptive I/Q imbalance correction (Moseley/Slump style), one instance
// per receive channel. The zero-IF front end (MAX2831 + board passives + ADC
// channel gain differences) leaves a gain/phase mismatch between I and Q,
// which mirrors every signal to its image frequency at typically only
// 30..40dB down. This stage takes I as the reference and corrects Q:
//
//     Qc = Q + (e_g * Q + w_p * I) >> 15        (e_g, w_p in Q1.15)
//
// with both coefficients adapted continuously by stochastic gradient:
//
//     w_p <- w_p - mu * I * Qc          drives E[I *Qc]      -> 0  (phase)
//     e_g <- e_g - mu * (Qc^2 - I^2)    drives E[Qc^2]-E[I^2]-> 0  (gain)
//
// No divides, no square roots, converges on any non-image-symmetric live
// signal (a CW tone is ideal); on pure circular noise the gradients average
// to zero and the coefficients just hold. Inputs must be DC-free (they come
// from top.v's DC removal - a DC term would bias E[I*Q]).
//
// Implementation notes:
//   - Inputs are captured at i_ce (once per word, >= 6 DCLK cycles apart);
//     all internal stages are free-running registers that settle in the gap,
//     outputs update at the NEXT i_ce - so I and Q leave with the SAME one-
//     word latency and stay sample-aligned (a skew would be a phase error).
//   - Accumulators clamp at +/-0.25 (Q1.15) - far beyond any real imbalance,
//     and bounds the damage if a degenerate input (e.g. the ADC ramp test,
//     where I==Q) temporarily slams the gradients. Recovery is automatic.
//   - Adaptation rate is gear-shifted (see the parameter block): measured
//     on hardware, MU 8 nulls a -18dBFS tone's image in ~2s but its
//     coefficient dither sprays a spur comb; MU 12 is clean but needs the
//     better part of a minute. So: fast gear for the first ~second of
//     accumulated signal, slow gear forever after.
//////////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps

module iq_balance #(
    // Gear-shifted adaptation: MU_FAST until the channel has accumulated
    // 2^LOCK_BIT samples with |I| above SIG_THRESH (i.e. ~a second of real
    // signal), then MU_SLOW permanently (until reset). Fast attack nulls the
    // image within ~2s of signal first appearing; the slow gear removes the
    // coefficient dither that sprayed modulation spurs, and comfortably
    // tracks the quasi-static drift. A signal-free channel simply stays in
    // the fast gear - with no signal there is nothing to modulate spurs
    // onto, and it gets its fast attack whenever signal first shows up.
    parameter MU_FAST    = 8,
    /* MU_SLOW was 12: at RASM2400's weak training levels (peak ~34 LSB,
       gradients swing only +/-1150) the (g + 2^11) >> 12 update NEVER
       crosses the rounding boundary - slow gear was a total freeze, and
       with the old LOCK_BIT=23 it froze after ~1s, mid-convergence
       (hardware-observed 2026-07-31: image WORSE, -16dB, after the gear
       shifted early). 10 keeps updates flowing (boundary 512 < 1150)
       with ~4x less dither than the fast gear. */
    parameter MU_SLOW    = 10,
    /* SIG_THRESH was 128 (tuned on RASPMO with a -18dBFS training tone).
       RASM2400's front end intermods before a tone gets that strong, so
       training happens around -36dBFS (peak ~34 LSB) - below the old
       threshold, which meant the slow gear NEVER engaged and the null
       stayed fast-gear dither-limited at ~-30dB (ILA-verified coefficients
       w_p=-0.067/e_g=-0.339, stable but dithering 2026-07-31). 24 LSB
       counts a -36dBFS sine as signal for ~40% of its samples: the gear
       still shifts after ~1s of accumulated real signal, and circular
       noise (floor ~3.6 LSB rms) still never reaches it. */
    parameter SIG_THRESH = 24,  // |I| that counts as "signal present" (LSB)
    /* LOCK_BIT 23 -> 27: the shift must come AFTER convergence. Fast-gear
       convergence at -36dBFS takes ~6s (E[dp] ~ 0.07/sample toward an acc
       target of ~8M); 2^27 qualifying samples at ~40% duty is ~17s. */
    parameter LOCK_BIT   = 27   // 2^27 signal samples -> shift to slow gear
)(
    input  wire               i_clk,
    input  wire               i_rst,
    input  wire               i_ce,    // one pulse per sample pair
    input  wire signed [11:0] i_i,
    input  wire signed [11:0] i_q,
    output reg  signed [11:0] o_i,     // = i_i, delayed one word (alignment)
    output reg  signed [11:0] o_q,     // corrected Q, same latency
    // diagnostics (quasi-static)
    output wire signed [15:0] o_wp,    // Q1.15 phase coefficient
    output wire signed [15:0] o_eg     // Q1.15 gain-error coefficient
);

localparam signed [29:0] ACC_MAX = 30'sd268435455;  //  2^28-1 -> w = +0.25
localparam signed [29:0] ACC_MIN = -30'sd268435456; // -2^28   -> w = -0.25

/* coefficient accumulators; coefficient = acc >>> 13 interpreted as Q1.15
   (acc bit 28 -> coeff bit 15 region; see clamp above) */
reg signed [29:0] acc_p, acc_g;
wire signed [15:0] w_p = acc_p[28:13];
wire signed [15:0] e_g = acc_g[28:13];
assign o_wp = w_p;
assign o_eg = e_g;

/* input capture (stable for the whole word period) */
reg signed [11:0] I_r, Q_r;

/* correction pipeline - free-running, settles between CEs */
reg signed [27:0] p_wpI, p_egQ;      // 16x12 products
wire signed [28:0] corr_sum = p_wpI + p_egQ;
wire signed [13:0] corr     = corr_sum[28:15]; // >> 15
wire signed [14:0] qc_full  = Q_r + corr;
wire signed [11:0] qc_sat   = (qc_full > 15'sd2047)  ? 12'sd2047  :
                              (qc_full < -15'sd2048) ? -12'sd2048 : qc_full[11:0];
reg signed [11:0] qc_r;

/* Gradient pipeline: normalized products. Originally I_r[11:4] (a plain
   >>4), which quantizes weak signals to nothing: at -26dBFS (peak ~106
   LSB, measured 2026-07-31 on RASM2400) the products never exceed ~49,
   the (g + 2^(MU-1)) >> MU update rounds every step to exactly 0 and the
   coefficients freeze - the corrector could only train above roughly
   -20dBFS, and this front end intermods before a tone gets that strong.
   Normalize with a saturating +/-127 clamp instead of a shift: weak
   signals keep full gradient resolution (a -42dBFS/17-LSB tone still
   nudges dp=1), strong signals bound at products <= 127^2 = 16129, which
   still fits g_p/g_g's signed 16 bits and just means a faster (still
   clamp-bounded) attack. */
wire signed [7:0] I_n  = (I_r  >  12'sd127) ?  8'sd127 :
                         (I_r  < -12'sd127) ? -8'sd127 : I_r[7:0];
wire signed [7:0] Qc_n = (qc_r >  12'sd127) ?  8'sd127 :
                         (qc_r < -12'sd127) ? -8'sd127 : qc_r[7:0];
reg signed [15:0] g_p;  // I_n * Qc_n
reg signed [15:0] g_g;  // Qc_n^2 - I_n^2 (built from two squares)
reg signed [15:0] sq_qc, sq_i;

/* gear state */
reg [LOCK_BIT:0] sig_cnt;
reg              slow_gear;

/* round-to-nearest on the gradient shift: plain >>> truncates toward -inf,
   whose -0.5LSB bias would integrate up on zero-mean noise and slowly walk
   the coefficients into the clamp. Two constant shifts muxed by the gear. */
wire signed [15:0] dp = slow_gear
    ? ((g_p + (16'sd1 <<< (MU_SLOW-1))) >>> MU_SLOW)
    : ((g_p + (16'sd1 <<< (MU_FAST-1))) >>> MU_FAST);
wire signed [15:0] dg = slow_gear
    ? ((g_g + (16'sd1 <<< (MU_SLOW-1))) >>> MU_SLOW)
    : ((g_g + (16'sd1 <<< (MU_FAST-1))) >>> MU_FAST);

wire sig_present = (I_r > $signed({4'd0, SIG_THRESH[7:0]})) ||
                   (I_r < -$signed({4'd0, SIG_THRESH[7:0]}));

always @(posedge i_clk) begin
    if (i_rst) begin
        acc_p <= 30'sd0;
        acc_g <= 30'sd0;
        I_r   <= 12'sd0;
        Q_r   <= 12'sd0;
        qc_r  <= 12'sd0;
        p_wpI <= 28'sd0;
        p_egQ <= 28'sd0;
        g_p   <= 16'sd0;
        g_g   <= 16'sd0;
        sq_qc <= 16'sd0;
        sq_i  <= 16'sd0;
        o_i   <= 12'sd0;
        o_q   <= 12'sd0;
        sig_cnt   <= 0;
        slow_gear <= 1'b0;
    end
    else begin
        /* free-running stages (inputs only move at CE, so these are settled
           long before the next CE samples them) */
        p_wpI <= w_p * I_r;
        p_egQ <= e_g * Q_r;
        qc_r  <= qc_sat;
        sq_qc <= Qc_n * Qc_n;
        sq_i  <= I_n * I_n;
        g_p   <= I_n * Qc_n;
        g_g   <= sq_qc - sq_i;

        if (i_ce) begin
            /* emit the finished pair, capture the next one */
            o_i <= I_r;
            o_q <= qc_r;
            I_r <= i_i;
            Q_r <= i_q;

            /* gear shift: enough accumulated signal -> slow, dither-free */
            if (!slow_gear && sig_present) begin
                if (sig_cnt[LOCK_BIT])
                    slow_gear <= 1'b1;
                else
                    sig_cnt <= sig_cnt + 1'b1;
            end

            /* coefficient update with clamped accumulators */
            if      (acc_p - dp > ACC_MAX) acc_p <= ACC_MAX;
            else if (acc_p - dp < ACC_MIN) acc_p <= ACC_MIN;
            else    acc_p <= acc_p - dp;

            if      (acc_g - dg > ACC_MAX) acc_g <= ACC_MAX;
            else if (acc_g - dg < ACC_MIN) acc_g <= ACC_MIN;
            else    acc_g <= acc_g - dg;
        end
    end
end

endmodule
