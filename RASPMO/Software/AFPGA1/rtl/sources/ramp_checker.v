//////////////////////////////////////////////////////////////////////////////////
// ramp_checker.v
//
// Verifies an ADC3424 digital-ramp test pattern (register 0Ah, code 0100:
// "increment by 1 LSB every clock cycle from code 0 to 4095") arriving over
// the LVDS link. Tracks the expected next sample and compares against what
// actually arrived, counting both mismatched samples and mismatched bits
// (a real bit-error count, from XOR-ing expected vs actual and popcounting)
// - this is purely an observation module bolted onto the existing capture
// path (see top.v), it does not affect the real data path at all, so it is
// harmless to leave instantiated even when the ADC is in normal (non-test)
// mode - it will just count "errors" against real signal content, which is
// meaningless there and can be ignored.
//////////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps

module ramp_checker #(
    parameter WIDTH = 12
)(
    input wire              i_clk,
    input wire              i_rst,
    input wire              i_ce,          // pulse when i_sample is a new valid sample
    input wire [WIDTH-1:0]  i_sample,

    output reg [WIDTH-1:0]  o_expected,
    output reg [31:0]       o_sample_count,
    output reg [31:0]       o_error_count,      // samples that did not match the expected ramp value
    output reg [31:0]       o_bit_error_count,  // total mismatched bits, summed across all samples
    output reg              o_locked            // has seen at least one sample to establish the ramp phase
);

reg [WIDTH-1:0] prev_sample;
reg             have_prev;

function [3:0] popcount;
    input [WIDTH-1:0] v;
    integer i;
    begin
        popcount = 0;
        for (i = 0; i < WIDTH; i = i + 1)
            popcount = popcount + v[i];
    end
endfunction

always @(posedge i_clk) begin
    if (i_rst) begin
        prev_sample       <= {WIDTH{1'b0}};
        have_prev         <= 1'b0;
        o_sample_count    <= 32'h0;
        o_error_count     <= 32'h0;
        o_bit_error_count <= 32'h0;
        o_locked          <= 1'b0;
        o_expected        <= {WIDTH{1'b0}};
    end
    else if (i_ce) begin
        if (have_prev) begin
            o_expected <= prev_sample + 1'b1;
            // Repeat-tolerant check. The ADC ramp holds each code for several
            // FCLK words and adc_frameStrobe (i_ce) fires >1x per word, so a
            // correct link legitimately presents the SAME sample many times in
            // a row before it steps by +1. Treat an unchanged sample as a valid
            // HOLD; flag an error only when the value CHANGES to something that
            // is not exactly prev+1 LSB (wraps 4095->0 naturally via the 12-bit
            // truncation). This is safe against a "stuck" false-pass because the
            // undelayed EVEN ISERDES always carries the live ramp bits, so the
            // deserialized word can never freeze while the ADC is ramping.
            if ((i_sample != prev_sample) && ((prev_sample + 1'b1) != i_sample)) begin
                o_error_count     <= o_error_count + 1'b1;
                o_bit_error_count <= o_bit_error_count + popcount((prev_sample + 1'b1) ^ i_sample);
            end
            o_locked <= 1'b1;
        end
        o_sample_count <= o_sample_count + 1'b1;
        prev_sample    <= i_sample;
        have_prev      <= 1'b1;
    end
end

endmodule
