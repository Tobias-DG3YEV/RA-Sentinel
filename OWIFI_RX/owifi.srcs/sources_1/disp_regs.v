//////////////////////////////////////////////////////////////////////////////////
//
// Design Name: OWIFI_RX
// Module Name: disp_regs
// Project Name: RA-Sentinel 802.11 receiver + direction finder
// Engineer: Tobias Weber
// Target Devices: Artix 7, XC7A100T (RASBB U10 + RASRF2400WBMC)
// Description:
//   Run-time switches of the HDMI display (station list, polar DF indicator,
//   labels), one register on FPGA1's config bus (iq_cap_regs style: 7-bit
//   address, 32-bit word, tri-state read mux). The ECU's on-screen menu
//   (buttons on its J8 header) writes it; console RR / RW reach it raw.
//
//   0x0C DISP_CTRL  RW  [0] pause: the station list, the rays and the
//                       labels stop taking new frames and stop ageing /
//                       decaying (the receiver and the capture run on)
//                       [1] show FCS-bad frames (df_frame SHOW_BAD rays,
//                       polar_labels BAD_FCS moves), default 1
//                       [2] solo (2026-10-04): only frames whose source MAC
//                       is in the capture MAC filter list (0x20..0x5F,
//                       enabled slots) draw rays, labels and phase dots; the
//                       station list still shows everybody. Default 0
//                       [3] pin (2026-10-07): the station whose source MAC
//                       is in capture filter slot 0 (enabled) keeps the top
//                       row of the station list once heard (frame_log).
//                       Default 0
//                       [6:4] label position averaging: the bearing EMA
//                       weight 1/2^k, k = 0 (every frame moves the label)
//                       .. 7, default 4 (1/16, the historical value)
//                       [8] clear (write 1): one-cycle pulse that resets the
//                       station list (frame_log), the label slots
//                       (polar_labels) and the ray table (df_frame); reads 0
//                       [14:12] phase dot averaging, same scale, default 4
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

module disp_regs #(
    parameter [6:0] ADDR = 7'h0C
)(
    input  wire        i_clock,
    input  wire        i_reset,

    input  wire [6:0]  i_SPI_addr,
    input  wire        i_SPI_wrStrobe,
    input  wire [31:0] i_SPIdata,
    inout  wire [31:0] o_SPIdata,

    output reg         o_pause,
    output reg         o_show_bad,
    output reg         o_solo,
    output reg         o_pin,
    output reg  [2:0]  o_brg_shift,
    output reg  [2:0]  o_ph_shift,
    output reg         o_clear         // one-cycle pulse
);

wire hit = i_SPI_wrStrobe && (i_SPI_addr == ADDR);

always @(posedge i_clock) begin
    if (i_reset) begin
        o_pause <= 1'b0; o_show_bad <= 1'b1; o_solo <= 1'b0; o_pin <= 1'b0; o_brg_shift <= 3'd4; o_ph_shift <= 3'd4; o_clear <= 1'b0;
    end
    else begin
        o_clear <= hit & i_SPIdata[8];
        if (hit) begin
            o_pause     <= i_SPIdata[0];
            o_show_bad  <= i_SPIdata[1];
            o_solo      <= i_SPIdata[2];
            o_pin       <= i_SPIdata[3];
            o_brg_shift <= i_SPIdata[6:4];
            o_ph_shift  <= i_SPIdata[14:12];
        end
    end
end

assign o_SPIdata = (i_SPI_addr == ADDR) ? {17'd0, o_ph_shift, 5'd0, o_brg_shift, o_pin, o_solo, o_show_bad, o_pause} : 32'bz;

endmodule
