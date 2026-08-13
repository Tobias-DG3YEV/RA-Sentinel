//////////////////////////////////////////////////////////////////////////////////
// dp_ram.v
//
// Inferred dual-clock block RAM, drop-in for the blk_mem_gen_0 / blk_PeakMem
// IP cores (1024 x 8 simple dual port with a read path on the write port).
// Replacing the IPs with RTL because the quad-split design needs four spectrum
// + four peak RAMs and stamping out IP instances buys nothing over inference.
//
// Port A (ADC/DCLK domain): synchronous write plus a registered read of the
// same address - top.v's write FSM reads the old peak value one cycle before
// writing the new one (read-first behavior, matching the original IP config).
// Port B (pixel domain): registered read only, clocked on the inverted pixel
// clock like the original cores, one cycle of latency.
//////////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps

module dp_ram #(
    parameter ADDRBITS = 10,
    parameter BITS     = 8
)(
    input  wire                i_clka,
    input  wire                i_wea,
    input  wire [ADDRBITS-1:0] i_addra,
    input  wire [BITS-1:0]     i_dina,
    output reg  [BITS-1:0]     o_douta,

    input  wire                i_clkb,
    input  wire [ADDRBITS-1:0] i_addrb,
    output reg  [BITS-1:0]     o_doutb
);

(* ram_style = "block" *) reg [BITS-1:0] mem [0:(1<<ADDRBITS)-1];

integer j;
initial for (j = 0; j < (1<<ADDRBITS); j = j + 1) mem[j] = {BITS{1'b0}};

always @(posedge i_clka) begin
    if (i_wea)
        mem[i_addra] <= i_dina;
    o_douta <= mem[i_addra]; // read-first
end

always @(posedge i_clkb)
    o_doutb <= mem[i_addrb];

endmodule
