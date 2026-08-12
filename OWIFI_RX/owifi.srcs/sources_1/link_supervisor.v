//////////////////////////////////////////////////////////////////////////////////
// link_supervisor.v
//
// Per-ADC LVDS link supervisor: owns the data-path IDELAY tap and keeps the
// link locked ACROSS MASTER-CLOCK CHANGES, using the continuously available
// FCLK-word decode as the health metric (i_hit: "the deserialized FCLK word
// matched the frame pattern at some window base this word" - see top.v).
// No ADC test pattern involved, so this works during normal operation.
//
// Why retraining is needed at all: the ADC bit clock reaches the ISERDES
// through general fabric routing whose insertion delay is constant in ns,
// while the serial UI scales with the front-end's master clock. Tuning the
// TCXO/external reference from 40MHz towards 38 or 42MHz therefore slides
// the ODD-path sampling point across (and eventually past) the data eye -
// the link then "loses bit lock" and the panes fill with full-scale noise.
// The IDELAY tap can pull the sampling point back; this FSM notices the
// degradation (FCLK decode misses) and re-sweeps automatically.
//
//   SWEEP  try all 32 taps; per tap, count decode misses over WIN_CE words
//          after SETTLE_CE settle. A tap is "good" if misses <= GOOD_MAX.
//          Commit the CENTER of the longest run of good taps (max margin
//          both directions -> max tolerated frequency excursion before the
//          next retrain). No good tap at all -> commit the minimum-miss tap
//          and retry after the long FAIL_HOLD_CE backoff.
//   MON    count misses per WIN_CE window. BAD_WINS consecutive windows
//          above MISS_MAX -> back to SWEEP. A GRACE_WINS grace period after
//          each sweep lets the rotation decode re-lock and the counters
//          flush before monitoring resumes.
//
// One sweep is 32 x (SETTLE_CE+WIN_CE) words ~= 27ms at 20MSPS - and it only
// runs when the link is already broken, so the disturbance is irrelevant.
// The FCLK-miss metric is rotation-independent (a hit at ANY base counts),
// so the sweep needs no rotation re-lock per tap.
//
// Everything is sized in CE (word-strobe) events, not clock cycles, so the
// behavior is sample-rate-proportional and survives the 125MSPS target.
//////////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps

module link_supervisor #(
    parameter TAPS         = 32,     // IDELAY taps to sweep
    parameter SETTLE_CE    = 256,    // words to settle after a tap load
    parameter WIN_CE       = 16384,  // words per measurement/monitor window
    parameter GOOD_MAX     = 32,     // sweep: max misses/window for a "good" tap
    parameter MISS_MAX     = 64,     // monitor: misses/window that count as bad
    parameter BAD_WINS     = 4,      // consecutive bad windows -> retrain
    parameter GRACE_WINS   = 8,      // post-sweep windows ignored by the monitor
    parameter FAIL_HOLD_CE = 2097152 // backoff before re-trying a failed sweep (~105ms)
)(
    input  wire        i_clk,
    input  wire        i_rst,
    input  wire        i_ce,          // one pulse per deserialized word
    input  wire        i_hit,         // FCLK word decoded OK this word

    output reg  [4:0]  o_tap,         // IDELAY tap (to lvds_rx)
    output reg         o_load,        // 1-cycle pulse: load o_tap
    output reg         o_healthy,     // last sweep found a good plateau
    output reg  [7:0]  o_retrain_count // sweeps run since reset (diagnostic)
);

localparam ST_LOAD=3'd0, ST_SETTLE=3'd1, ST_MEAS=3'd2, ST_JUDGE=3'd3,
           ST_APPLY=3'd4, ST_MON=3'd5, ST_HOLD=3'd6;

reg [2:0]  state;
reg [4:0]  tap_i;
reg [21:0] ce_ctr;
reg [17:0] miss_ctr;
reg [17:0] best_miss;
reg [4:0]  best_tap;
// longest run of good taps (plateau) tracking
reg [4:0]  run_len, run_start;
reg [4:0]  bestrun_len, bestrun_start;
reg [3:0]  bad_wins;
reg [3:0]  grace;

always @(posedge i_clk) begin
    if (i_rst) begin
        state           <= ST_LOAD;
        tap_i           <= 5'd0;
        o_tap           <= 5'd0;
        o_load          <= 1'b0;
        o_healthy       <= 1'b0;
        o_retrain_count <= 8'd0;
        ce_ctr          <= 22'd0;
        miss_ctr        <= 18'd0;
        best_miss       <= {18{1'b1}};
        best_tap        <= 5'd0;
        run_len         <= 5'd0;
        run_start       <= 5'd0;
        bestrun_len     <= 5'd0;
        bestrun_start   <= 5'd0;
        bad_wins        <= 4'd0;
        grace           <= 4'd0;
    end
    else begin
        o_load <= 1'b0; // load is a one-cycle pulse; default deasserted
        case (state)
            ST_LOAD: begin              // apply tap_i for measurement
                o_tap   <= tap_i;
                o_load  <= 1'b1;
                ce_ctr  <= 22'd0;
                state   <= ST_SETTLE;
            end
            ST_SETTLE: begin
                if (i_ce) begin
                    if (ce_ctr >= SETTLE_CE[21:0]) begin
                        ce_ctr   <= 22'd0;
                        miss_ctr <= 18'd0;
                        state    <= ST_MEAS;
                    end
                    else ce_ctr <= ce_ctr + 22'd1;
                end
            end
            ST_MEAS: begin              // count decode misses for this tap
                if (i_ce) begin
                    if (!i_hit && miss_ctr != {18{1'b1}})
                        miss_ctr <= miss_ctr + 18'd1;
                    if (ce_ctr >= WIN_CE[21:0]) begin
                        state <= ST_JUDGE;
                    end
                    else ce_ctr <= ce_ctr + 22'd1;
                end
            end
            ST_JUDGE: begin
                // minimum-miss fallback
                if (miss_ctr < best_miss) begin
                    best_miss <= miss_ctr;
                    best_tap  <= tap_i;
                end
                // good-plateau tracking
                if (miss_ctr <= GOOD_MAX[17:0]) begin
                    if (run_len == 5'd0)
                        run_start <= tap_i;
                    run_len <= run_len + 5'd1;
                    if (run_len + 5'd1 > bestrun_len) begin
                        bestrun_len   <= run_len + 5'd1;
                        bestrun_start <= (run_len == 5'd0) ? tap_i : run_start;
                    end
                end
                else run_len <= 5'd0;

                if (tap_i == TAPS[4:0]-5'd1)
                    state <= ST_APPLY;
                else begin
                    tap_i <= tap_i + 5'd1;
                    state <= ST_LOAD;
                end
            end
            ST_APPLY: begin             // commit plateau center (or fallback)
                o_healthy <= (bestrun_len != 5'd0);
                o_tap     <= (bestrun_len != 5'd0)
                             ? bestrun_start + {1'b0, bestrun_len[4:1]} // +len/2
                             : best_tap;
                o_load    <= 1'b1;
                o_retrain_count <= o_retrain_count + 8'd1;
                ce_ctr    <= 22'd0;
                miss_ctr  <= 18'd0;
                bad_wins  <= 4'd0;
                grace     <= (bestrun_len != 5'd0) ? GRACE_WINS[3:0] : 4'd0;
                state     <= (bestrun_len != 5'd0) ? ST_MON : ST_HOLD;
            end
            ST_MON: begin               // watch the live link
                if (i_ce) begin
                    if (!i_hit && miss_ctr != {18{1'b1}})
                        miss_ctr <= miss_ctr + 18'd1;
                    if (ce_ctr >= WIN_CE[21:0]) begin
                        ce_ctr   <= 22'd0;
                        miss_ctr <= 18'd0;
                        if (grace != 4'd0)
                            grace <= grace - 4'd1;
                        else if (miss_ctr > MISS_MAX[17:0]) begin
                            if (bad_wins >= BAD_WINS[3:0]-4'd1) begin
                                // link degraded (e.g. master clock moved):
                                // full re-sweep, starting from tap 0
                                tap_i         <= 5'd0;
                                best_miss     <= {18{1'b1}};
                                run_len       <= 5'd0;
                                bestrun_len   <= 5'd0;
                                state         <= ST_LOAD;
                            end
                            else bad_wins <= bad_wins + 4'd1;
                        end
                        else bad_wins <= 4'd0;
                    end
                    else ce_ctr <= ce_ctr + 22'd1;
                end
            end
            ST_HOLD: begin              // failed sweep: back off, then retry
                if (i_ce) begin
                    if (ce_ctr >= FAIL_HOLD_CE[21:0]) begin
                        tap_i       <= 5'd0;
                        best_miss   <= {18{1'b1}};
                        run_len     <= 5'd0;
                        bestrun_len <= 5'd0;
                        state       <= ST_LOAD;
                    end
                    else ce_ctr <= ce_ctr + 22'd1;
                end
            end
            default: state <= ST_LOAD;
        endcase
    end
end

endmodule
