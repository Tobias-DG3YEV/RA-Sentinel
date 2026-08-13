//////////////////////////////////////////////////////////////////////////////////
// cordic_vec.v
//
// Pipelined CORDIC in VECTORING mode: takes a cartesian vector (x,y) and
// returns its magnitude and its angle. Fully pipelined - one result per clock,
// STAGES+1 clocks of latency, no handshake.
//
// Three users in this design, which is why it is parameterised rather than
// hand-fitted to any one of them:
//   - FFT phase extraction: (re,im) of a bin -> that channel's phase
//   - amplitude DF:         (A90-A270, A0-A180) -> coarse bearing
//   - polar renderer:       (dx,dy) of a pixel from screen centre -> (r,theta)
//
// ANGLE FORMAT: unsigned 16-bit binary turns. 65536 = 360deg, LSB = 0.00549deg,
// counter-clockwise from the +x axis, and it wraps naturally on overflow - so
// angle arithmetic (differences, calibration offsets) is plain modular addition
// with no explicit range folding anywhere. Downstream users truncate the top
// bits they need; o_ang[15:7] is a 512-entry angle bin, o_ang[15:8] a 256-entry
// one, etc.
//
// MAGNITUDE IS NOT GAIN-COMPENSATED. o_mag = K*sqrt(x^2+y^2) with the usual
// CORDIC processing gain K = 1.6467602578 (for STAGES >= 16; it converges from
// below). Compensating would cost a multiplier per instance for nothing: every
// consumer here already scales the magnitude by some constant of its own
// (pixels-per-dB, table scaling), so K folds into that constant for free.
// Whoever needs a true magnitude multiplies by 1/K = 0.60725 (39797/65536).
//
// Accuracy: the residual angle error after N stages is atan(2^-(N-1)), so the
// default 16 stages resolve to ~0.0017deg - far below the 0.0055deg angle LSB,
// i.e. the LUT quantisation dominates, not the iteration count. STAGES > 16 is
// pointless (atan(2^-16) rounds to 0 turns) and is silently useless, not wrong.
//
// MEASURED (792 vectors: full angle sweeps at |v| = 5/37/1000/32000, the axis
// and full-scale corner cases, and 300 random) with STAGES=16, GUARD=12:
//   |v| >= 100 : angle <= 0.016deg, magnitude <= 0.03%
//   |v| >= 16  : angle <= 0.016deg, magnitude <= 0.79%
//   |v| >= 4   : angle <= 0.016deg, magnitude <= 4.95%
// The angle error is flat over the whole magnitude range - it is set by the
// atan LUT, not by convergence - while the residual magnitude error on tiny
// vectors is just integer output rounding (|v|=1 -> 2 instead of 1.65).
//
// A ZERO INPUT VECTOR returns magnitude 0 and an UNDEFINED angle (whatever the
// accumulator happened to sum to). That is deliberate - forcing it would cost a
// comparator and a flag through the whole pipe for nothing, since every
// consumer here gates on magnitude: the renderer's centre pixel passes
// "r <= len[theta]" for any theta, which is the wanted behaviour anyway.
//
// Dependencies: none
//////////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps

// GUARD BITS ARE NOT OPTIONAL. The iteration shifts x and y right by up to
// STAGES-1; on plain integer inputs those shifts truncate to 0 or -1 long
// before the last stage, y stops converging and the result is garbage - input
// (1,0) came back as magnitude 16 instead of 1.65, and (4,2) was 20deg out.
// So the datapath carries GUARD fractional bits below the input LSB. Full
// convergence needs |input| >= 2^(STAGES-1-GUARD); below that accuracy degrades
// gracefully instead of collapsing. Two of the three users here (pixel offsets
// from screen centre, dB differences between channels) live at magnitudes of a
// few tens, so this is the normal operating point, not a corner case.

module cordic_vec #(
    parameter XYW    = 16,  // input x/y width, SIGNED two's complement
    parameter STAGES = 16,  // rotation stages, 1..16 (see accuracy note above)
    parameter GUARD  = 12   // fractional guard bits (see note above)
)(
    input  wire                  i_clk,
    input  wire                  i_ce,     // pipeline advance
    input  wire                  i_valid,  // tags i_x/i_y as a real sample
    input  wire signed [XYW-1:0] i_x,
    input  wire signed [XYW-1:0] i_y,

    output wire [XYW+1:0]        o_mag,    // K*sqrt(x^2+y^2), K = 1.64676
    output wire [15:0]           o_ang,    // binary turns, 65536 = 360deg
    output wire                  o_valid
);

/* Internal datapath: the input width, 2 bits of headroom (one for the
   pre-rotation, since negating the full negative range needs it, and one for
   the CORDIC gain - |x| grows by K*sqrt(2) = 2.33 worst case), plus GUARD
   fractional bits at the bottom so the per-stage right shifts keep resolving. */
localparam IW = XYW + 2 + GUARD;

/* atan(2^-i) in binary turns. Rounded from atan(2^-i)*65536/(2*pi); see the
   generator in the commit message. Entry 15 rounds to zero, which is exactly
   why STAGES > 16 buys nothing. */
function [15:0] atan_turns;
    input integer i;
    begin
        case (i)
            0:  atan_turns = 16'd8192;  // 45.000000 deg
            1:  atan_turns = 16'd4836;  // 26.565051 deg
            2:  atan_turns = 16'd2555;  // 14.036243 deg
            3:  atan_turns = 16'd1297;  //  7.125016 deg
            4:  atan_turns = 16'd651;   //  3.576334 deg
            5:  atan_turns = 16'd326;   //  1.789911 deg
            6:  atan_turns = 16'd163;   //  0.895174 deg
            7:  atan_turns = 16'd81;    //  0.447614 deg
            8:  atan_turns = 16'd41;    //  0.223811 deg
            9:  atan_turns = 16'd20;    //  0.111906 deg
            10: atan_turns = 16'd10;    //  0.055953 deg
            11: atan_turns = 16'd5;     //  0.027976 deg
            12: atan_turns = 16'd3;     //  0.013988 deg
            13: atan_turns = 16'd1;     //  0.006994 deg
            14: atan_turns = 16'd1;     //  0.003497 deg
            15: atan_turns = 16'd0;     //  0.001749 deg
            default: atan_turns = 16'd0;
        endcase
    end
endfunction

reg signed [IW-1:0] xs [0:STAGES];
reg signed [IW-1:0] ys [0:STAGES];
reg        [15:0]   zs [0:STAGES];
reg                 vs [0:STAGES];

/* Pre-rotation into the right half-plane. CORDIC vectoring only converges for
   x >= 0, so a left half-plane vector is negated (a 180deg rotation) and the
   accumulator starts at 180deg instead of 0. Because the angle is binary turns
   this needs no wrap handling - the final add overflows mod 65536 and lands on
   the right answer. x == 0 is handled by the x >= 0 branch: the first iteration
   rotates it onto the axis and the accumulated angle comes out +/-90deg. */
/* Sign-extended to IW and left-shifted into the guard bits. The shift's left
   operand is context-sized to IW by the assignment, so this sign-extends first
   and shifts after - no truncation of the input's top bit. */
wire signed [IW-1:0] x_sh = $signed(i_x) <<< GUARD;
wire signed [IW-1:0] y_sh = $signed(i_y) <<< GUARD;

always @(posedge i_clk) begin
    if (i_ce) begin
        if (!i_x[XYW-1]) begin          // x >= 0
            xs[0] <= x_sh;
            ys[0] <= y_sh;
            zs[0] <= 16'd0;
        end
        else begin                      // x < 0: rotate 180deg, start at 180deg
            xs[0] <= -x_sh;
            ys[0] <= -y_sh;
            zs[0] <= 16'd32768;
        end
        vs[0] <= i_valid;
    end
end

/* Rotation stages. Each drives y towards zero and accumulates the angle it
   rotated by; when y reaches 0 the whole vector sits on the +x axis, so x is
   the (gain-scaled) magnitude and z is the original angle. */
genvar s;
generate
for (s = 0; s < STAGES; s = s + 1) begin : gen_stage
    localparam [15:0] ATANV = atan_turns(s);

    wire signed [IW-1:0] xshift = xs[s] >>> s;
    wire signed [IW-1:0] yshift = ys[s] >>> s;
    wire                 yneg   = ys[s][IW-1];

    always @(posedge i_clk) begin
        if (i_ce) begin
            if (yneg) begin             // y < 0: rotate counter-clockwise
                xs[s+1] <= xs[s] - yshift;
                ys[s+1] <= ys[s] + xshift;
                zs[s+1] <= zs[s] - ATANV;
            end
            else begin                  // y >= 0: rotate clockwise
                xs[s+1] <= xs[s] + yshift;
                ys[s+1] <= ys[s] - xshift;
                zs[s+1] <= zs[s] + ATANV;
            end
            vs[s+1] <= vs[s];
        end
    end
end
endgenerate

/* xs[STAGES] is non-negative by construction (the pre-rotation guarantees
   x >= 0 and the iteration only ever grows it), so the raw bits are the
   unsigned magnitude - shifted back out of the guard bits, with a half-LSB
   added first so it rounds rather than always truncating down. */
wire [IW-1:0] mag_g = xs[STAGES] + {{(IW-GUARD){1'b0}}, 1'b1, {(GUARD-1){1'b0}}};

assign o_mag   = mag_g[GUARD +: (XYW+2)];
assign o_ang   = zs[STAGES];
assign o_valid = vs[STAGES];

endmodule
