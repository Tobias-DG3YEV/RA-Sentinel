//////////////////////////////////////////////////////////////////////////////////
//
// Design Name: OWIFI_RX
// Module Name: div_regs
// Project Name: RA-Sentinel 802.11 receiver + direction finder
// Engineer: Tobias Weber
// Target Devices: Artix 7, XC7A100T (RASBB U10 + RASRF2400WBMC)
// Description:
//   Registers of the diversity combiner (div_combine.v) and receiver frame
//   counters, on FPGA1's config bus (iq_cap_regs style: 7-bit address,
//   32-bit data, tri-state read mux; STM32 console RR / RW).
//
//   0x1F DIV_CTRL   [0] 1 = the decoder takes the combined signal, 0 = the
//                   selected antenna (default 0); write [4] = 1 clears the
//                   frame counters 0x6A..0x6D (self-clearing)
//   0x61 DIV_STAT   [0] combiner on, [2:1] strongest channel of the applied
//                   weights, [3] weights at norm 1/2 (strong signal),
//                   [31:16] weight sets taken over (wraps) (RO)
//   0x62 DIV_SAT    [15:0] combined samples that saturated (wraps) (RO)
//   0x65 DIV_W0, 0x66 DIV_W1, 0x67 DIV_W2, 0x69 DIV_W3
//                   applied weight of channel k: [23:12] real, [11:0]
//                   imaginary part, signed Q1.10 (1024 = 1.0) (RO)
//   0x6A RX_FCS_OK  frames that ended with a good FCS
//   0x6B RX_FCS_BAD frames that ended with a bad FCS
//   0x6D RX_HDR     valid SIGNAL headers (frames the decoder started on);
//                   all three 32 bits, since the last clear (RO)
//
// Dependencies: none
//
// Additional Comments: https://github.com/Tobias-DG3YEV/RA-Sentinel
//
//////////////////////////////////////////////////////////////////////////////////
// Copyright (C) 2026 Tobias Weber
// License: GNU GPL v3
//////////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps

module div_regs #(
    parameter ADDR_WIDTH = 7
)(
    input  wire        i_clock,
    input  wire        i_reset,

    input  wire [ADDR_WIDTH-1:0] i_SPI_addr,
    input  wire        i_SPI_wrStrobe,
    input  wire [31:0] i_SPIdata,
    inout  wire [31:0] o_SPIdata,

    output reg         o_enable,

    input  wire [95:0] i_weights,     // div_combine o_weights
    input  wire [1:0]  i_ref,
    input  wire        i_half,
    input  wire [15:0] i_sat_count,
    input  wire [15:0] i_upd_count,

    input  wire        i_fcs_stb,
    input  wire        i_fcs_ok,
    input  wire        i_hdr_stb      // SIGNAL decoded and valid
);

wire [6:0] a = i_SPI_addr[6:0];

reg [31:0] cnt_ok, cnt_bad, cnt_hdr;
wire clr = i_SPI_wrStrobe && (a == 7'h1F) && i_SPIdata[4];

always @(posedge i_clock) begin
    if (i_reset) begin
        o_enable <= 1'b0;
        cnt_ok <= 32'd0; cnt_bad <= 32'd0; cnt_hdr <= 32'd0;
    end
    else begin
        if (i_SPI_wrStrobe && (a == 7'h1F))
            o_enable <= i_SPIdata[0];
        if (clr) begin
            cnt_ok <= 32'd0; cnt_bad <= 32'd0; cnt_hdr <= 32'd0;
        end
        else begin
            if (i_fcs_stb &&  i_fcs_ok) cnt_ok  <= cnt_ok  + 32'd1;
            if (i_fcs_stb && !i_fcs_ok) cnt_bad <= cnt_bad + 32'd1;
            if (i_hdr_stb)              cnt_hdr <= cnt_hdr + 32'd1;
        end
    end
end

reg [31:0] rd;
reg        sel;
always @(*) begin
    sel = 1'b1; rd = 32'd0;
    case (a)
        7'h1F: rd = {31'd0, o_enable};
        7'h61: rd = {i_upd_count, 12'd0, i_half, i_ref, o_enable};
        7'h62: rd = {16'd0, i_sat_count};
        7'h65: rd = {8'd0, i_weights[23:0]};
        7'h66: rd = {8'd0, i_weights[47:24]};
        7'h67: rd = {8'd0, i_weights[71:48]};
        7'h69: rd = {8'd0, i_weights[95:72]};
        7'h6A: rd = cnt_ok;
        7'h6B: rd = cnt_bad;
        7'h6D: rd = cnt_hdr;
        default: sel = 1'b0;
    endcase
end
assign o_SPIdata = sel ? rd : 32'bz;

endmodule
