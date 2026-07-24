//////////////////////////////////////////////////////////////////////////////////
// waterfall_mem.v
//
// Spectrum-history (waterfall) line store: 256 rows x 1024 columns x 8 bit
// (2Mbit, ~57 RAMB36 - the XC7A100T has headroom at ~35% BRAM before this).
// Simple-dual-port inferred block RAM: the write port runs in the ADC/DCLK
// domain and mirrors every spectrum-RAM write into the current history row
// (see top.v - the row pointer advances once every few video frames, so at
// each advance the row holds the most recent complete FFT frame); the read
// port runs on the inverted pixel clock like the spectrum/peak RAMs in
// screen.v's read path, one registered read = one pixel of latency, which the
// display timing already tolerates for the other two RAMs.
//
// No write/read collision handling: the two ports only ever meet on the same
// address for one in-progress top row of the display, where a stale/fresh
// mix within one frame is invisible.
//////////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps

module waterfall_mem #(
    parameter ROWBITS = 8,  // 256 history rows
    parameter COLBITS = 10, // 1024 spectrum columns
    parameter BITS    = 8
)(
    input  wire                 i_wclk,
    input  wire                 i_we,
    input  wire [ROWBITS-1:0]   i_wrow,
    input  wire [COLBITS-1:0]   i_wcol,
    input  wire [BITS-1:0]      i_wdata,

    input  wire                 i_rclk,
    input  wire [ROWBITS-1:0]   i_rrow,
    input  wire [COLBITS-1:0]   i_rcol,
    output reg  [BITS-1:0]      o_rdata
);

(* ram_style = "block" *) reg [BITS-1:0] mem [0:(1<<(ROWBITS+COLBITS))-1];

always @(posedge i_wclk)
    if (i_we)
        mem[{i_wrow, i_wcol}] <= i_wdata;

always @(posedge i_rclk)
    o_rdata <= mem[{i_rrow, i_rcol}];

endmodule
