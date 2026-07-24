//////////////////////////////////////////////////////////////////////////////////
// sample_cdc.v
//
// Small asynchronous FIFO carrying ADC2's deserialized sample words from its
// own DCLK domain into ADC1's DCLK domain, so the whole processing pipeline
// (DC removal, AGC, the time-multiplexed FFT) runs in one clock domain.
//
// The two DCLKs both come from the front-end's single 40MHz TCXO (one PLL per
// ADC3424), so they are frequency-locked with unknown phase: in steady state
// exactly one word is written and one read per 20MSPS sample period and the
// fill level never drifts. The gray-coded pointers only have to survive the
// startup transient and the unknown phase. On an empty read (startup, or an
// unterminated/dead ADC2 link) the output simply holds its last value -
// downstream that just means a frozen pane, never corruption.
//////////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps

module sample_cdc #(
    parameter W = 48
)(
    input  wire         i_wclk,
    input  wire         i_wrst,
    input  wire         i_wen,
    input  wire [W-1:0] i_wdata,

    input  wire         i_rclk,
    input  wire         i_rrst,
    input  wire         i_ren,
    output reg  [W-1:0] o_rdata
);

reg [W-1:0] mem [0:7];

// write side
reg  [3:0] wptr_bin;
wire [3:0] wptr_gray = wptr_bin ^ (wptr_bin >> 1);
reg  [3:0] wptr_gray_r;

always @(posedge i_wclk) begin
    if (i_wrst) begin
        wptr_bin    <= 4'd0;
        wptr_gray_r <= 4'd0;
    end
    else begin
        if (i_wen) begin
            mem[wptr_bin[2:0]] <= i_wdata;
            wptr_bin <= wptr_bin + 4'd1;
        end
        wptr_gray_r <= wptr_gray;
    end
end

// read side
reg  [3:0] rptr_bin;
wire [3:0] rptr_gray = rptr_bin ^ (rptr_bin >> 1);
reg  [3:0] wptr_gray_s0, wptr_gray_s1; // 2FF sync of the write pointer

wire empty = (wptr_gray_s1 == rptr_gray);

always @(posedge i_rclk) begin
    if (i_rrst) begin
        rptr_bin     <= 4'd0;
        wptr_gray_s0 <= 4'd0;
        wptr_gray_s1 <= 4'd0;
        o_rdata      <= {W{1'b0}};
    end
    else begin
        wptr_gray_s0 <= wptr_gray_r;
        wptr_gray_s1 <= wptr_gray_s0;
        if (i_ren && !empty) begin
            o_rdata  <= mem[rptr_bin[2:0]];
            rptr_bin <= rptr_bin + 4'd1;
        end
    end
end

endmodule
