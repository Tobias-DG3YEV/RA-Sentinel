//////////////////////////////////////////////////////////////////////////////////
// freqmap.v
//
// False-colour map for FREQUENCY, used to colour the direction finder's rays by
// the FFT bin that produced them. Five anchors across the input range:
//
//     0 blue -> 64 green -> 128 yellow -> 192 red -> 255 violet
//
// so a ray's colour says where along the spectrum its signal sits, and can be
// read straight across to the peak's position in the spectrum panes above.
//
// This is NOT midmap.v. That one maps AMPLITUDE, over the same blue-green-
// yellow-red progression but with a soft low end (its zero is a dark blue, not a
// saturated one) because amplitude 0 has to sink into the background. A frequency
// is never "absent" - every bin is somewhere - so this ramp is saturated end to
// end, and it adds the fifth anchor the amplitude ramp does not have.
//
// ARITHMETIC, NOT A TABLE. midmap carries 3x256 bytes of initial-block ROM. Five
// evenly spaced anchors with only one channel moving per segment need none of
// that: the segment is the top two bits of the input and the interpolation is
// the bottom six. Replicating the top two of those six as the low bits, rather
// than shifting in zeros, is what makes the ramp reach a true 255 at the end of
// each segment - {6'd63, 2'b11} = 255 - so consecutive segments meet exactly on
// their shared anchor with no seam and no discontinuity.
//
// Dependencies: none
//////////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps

module freqmap (
    input  wire [7:0] i_freq,
    output reg  [7:0] o_r, o_g, o_b
);

wire [1:0] seg  = i_freq[7:6];
wire [7:0] frac = {i_freq[5:0], i_freq[5:4]};   // 0 at the anchor, 255 at the next

always @* begin
    case (seg)
    2'd0: begin o_r = 8'h00; o_g = frac;        o_b = 8'hFF - frac; end // blue->green
    2'd1: begin o_r = frac;  o_g = 8'hFF;       o_b = 8'h00;        end // green->yellow
    2'd2: begin o_r = 8'hFF; o_g = 8'hFF - frac; o_b = 8'h00;       end // yellow->red
    2'd3: begin o_r = 8'hFF; o_g = 8'h00;       o_b = frac;         end // red->violet
    endcase
end

endmodule
