//////////////////////////////////////////////////////////////////////////////////
// bin2bcd.v
//
// Sequential binary-to-BCD converter (double dabble). Converts a WIDTH-bit
// binary value into DIGITS BCD nibbles (o_bcd[3:0] = ones digit, [7:4] =
// tens, ... least-significant digit first) over WIDTH clock cycles. Only
// exists to feed a decimal digit display, so speed does not matter here -
// simple and easy to verify beats fast.
//////////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps

module bin2bcd #(
    parameter WIDTH = 32,
    parameter DIGITS = 10
)(
    input  wire                  i_clk,
    input  wire                  i_rst,
    input  wire                  i_start,   // pulse to begin a conversion (ignored while busy)
    input  wire [WIDTH-1:0]      i_value,
    output wire [DIGITS*4-1:0]   o_bcd,     // stable once o_done pulses, holds until next i_start
    output reg                   o_done
);

reg [WIDTH-1:0]     shift_bin;
reg [DIGITS*4-1:0]  shift_bcd;
reg [$clog2(WIDTH+1)-1:0] bit_cnt;
reg                 busy;

assign o_bcd = shift_bcd;

// add-3-if->=5 correction, applied to every digit before each shift
reg [DIGITS*4-1:0] bcd_corrected;
integer d;
always @(*) begin
    bcd_corrected = shift_bcd;
    for (d = 0; d < DIGITS; d = d + 1) begin
        if (bcd_corrected[d*4 +: 4] >= 5)
            bcd_corrected[d*4 +: 4] = bcd_corrected[d*4 +: 4] + 4'd3;
    end
end

always @(posedge i_clk) begin
    if (i_rst) begin
        busy    <= 1'b0;
        o_done  <= 1'b0;
        bit_cnt <= 0;
    end
    else if (i_start && !busy) begin
        shift_bin <= i_value;
        shift_bcd <= {(DIGITS*4){1'b0}};
        bit_cnt   <= 0;
        busy      <= 1'b1;
        o_done    <= 1'b0;
    end
    else if (busy) begin
        {shift_bcd, shift_bin} <= {bcd_corrected, shift_bin} << 1;
        if (bit_cnt == WIDTH-1) begin
            busy   <= 1'b0;
            o_done <= 1'b1;
        end
        bit_cnt <= bit_cnt + 1'b1;
    end
    else begin
        o_done <= 1'b0;
    end
end

endmodule
