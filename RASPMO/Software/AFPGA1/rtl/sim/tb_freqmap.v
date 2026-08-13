`timescale 1ns / 1ps

/* Sweeps all 256 codes through freqmap and prints the RGB, so a reference model
   can confirm the five anchors and, more to the point, that the four segments
   join without a seam - the failure mode of a hand-written piecewise ramp is a
   one-count discontinuity at a boundary, which is invisible on screen and
   obvious in the numbers. Purely combinational, so no clock is involved. */
module tb_freqmap;

reg  [7:0] code;
wire [7:0] r, g, b;

freqmap dut (.i_freq(code), .o_r(r), .o_g(g), .o_b(b));

integer i;
initial begin
    for (i = 0; i < 256; i = i + 1) begin
        code = i[7:0];
        #1;
        $display("FM %0d %0d %0d %0d", code, r, g, b);
    end
    $display("TB_DONE");
    $finish;
end

endmodule
