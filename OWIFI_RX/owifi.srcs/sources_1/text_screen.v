//////////////////////////////////////////////////////////////////////////////////
//
// Design Name: OWIFI_RX
// Module Name: text_screen
// Project Name: RA-Sentinel 802.11 receiver
// Engineer: Tobias Weber
// Target Devices: Artix 7, XC7A100T (RASBB baseboard)
// Description:
//   1024x768@60 character display: video timing, character RAM, font ROM and
//   pixel output. 128 columns x 48 rows of 8x16 glyphs.
//
//   Character RAM word = { rgb444[11:0], glyph[5:0] }, 18 bits wide, where
//   glyph is (ASCII - 0x20) so the whole printable set 0x20..0x5F fits in 6
//   bits. That is why the font only covers upper case - the log needs no
//   lower case, and it leaves the rest of the word for colour.
//
//   COLOUR IS PER CELL, NOT A PALETTE INDEX. Each character carries its own
//   4:4:4 RGB, expanded to 8:8:8 by nibble replication (0xC -> 0xCC), so
//   this block owns no colours at all - frame_log decides every one of them.
//   That is what lets the station list tint each SA field with a colour
//   hashed from that station's own MAC: 4096 colours, not 8 palette slots.
//
//   18 bits is the natural block RAM width - two bytes plus the parity bit
//   each byte carries - so an 8192x18 memory is 4 RAMB36 where the old
//   8192x9 word was 2. With ~19 of the XC7A100T's 135 blocks in use, buying
//   per-character colour for two blocks is the cheapest thing on the page.
//
//   The write port is a fully independent clock domain (the receiver's
//   100MHz), so this doubles as the data CDC: only the scroll pointer needs
//   synchronising, and it is gray-coded for that.
//
//   This block is deliberately READ-ONLY with respect to the receiver. It
//   observes; it cannot stall or perturb dot11, the frame buffer or the SPI
//   port.
//
// Dependencies: font8x16.mem (tools/gen_font.py), video_define.v
//
// Additional Comments: https://github.com/Tobias-DG3YEV/RA-Sentinel
//
//////////////////////////////////////////////////////////////////////////////////
// Copyright (C) 2026 Tobias Weber
// License: GNU GPL v3
//////////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps

module text_screen #(
    parameter COLS      = 128,   // 1024 / 8
    parameter ROWS      = 48,    // 768 / 16
    parameter HDR_ROWS  = 2,     // fixed header rows at the top
    parameter FONT_FILE = "font8x16.mem"
)(
    /* pixel domain */
    input  wire        i_pixClk,
    input  wire        i_rst,
    output reg         o_hs,
    output reg         o_vs,
    output reg         o_de,
    output reg  [7:0]  o_r,
    output reg  [7:0]  o_g,
    output reg  [7:0]  o_b,

    /* character write port (receiver domain) */
    input  wire        i_wrClk,
    input  wire        i_wr,
    input  wire [12:0] i_wrAddr,   // {row[5:0], col[6:0]}
    input  wire [17:0] i_wrData,   // {rgb444[11:0], glyph[5:0]}

    /* first log row to display, in character-RAM row numbers. Gray-coded
       because it is sampled by a different clock. */
    input  wire [5:0]  i_topRowGray
);

`include "video_define.v"

/* H_TOTAL / V_TOTAL come from video_define.v - do not redeclare them here */
localparam LOG_ROWS = ROWS - HDR_ROWS;

/*------------------------------------------------------------------*/
/* video timing                                                     */
/*------------------------------------------------------------------*/
reg [11:0] h_cnt, v_cnt;

always @(posedge i_pixClk) begin
    if (i_rst) begin
        h_cnt <= 12'd0;
        v_cnt <= 12'd0;
    end
    else if (h_cnt == H_TOTAL - 1) begin
        h_cnt <= 12'd0;
        v_cnt <= (v_cnt == V_TOTAL - 1) ? 12'd0 : v_cnt + 12'd1;
    end
    else
        h_cnt <= h_cnt + 12'd1;
end

wire h_act = (h_cnt >= H_FP + H_SYNC + H_BP);
wire v_act = (v_cnt >= V_FP + V_SYNC + V_BP);
wire [11:0] act_x = h_cnt - (H_FP + H_SYNC + H_BP);
wire [11:0] act_y = v_cnt - (V_FP + V_SYNC + V_BP);

wire hs_raw = (h_cnt >= H_FP && h_cnt < H_FP + H_SYNC) ? HS_POL : ~HS_POL;
wire vs_raw = (v_cnt >= V_FP && v_cnt < V_FP + V_SYNC) ? VS_POL : ~VS_POL;
wire de_raw = h_act && v_act;

/*------------------------------------------------------------------*/
/* scroll pointer: gray -> binary in the pixel domain                */
/*------------------------------------------------------------------*/
(* ASYNC_REG = "true" *) reg [5:0] top_g0, top_g1;
always @(posedge i_pixClk) begin
    top_g0 <= i_topRowGray;
    top_g1 <= top_g0;
end

reg [5:0] top_bin;
integer gi;
always @(*) begin
    top_bin[5] = top_g1[5];
    for (gi = 4; gi >= 0; gi = gi - 1)
        top_bin[gi] = top_bin[gi+1] ^ top_g1[gi];
end

/*------------------------------------------------------------------*/
/* address generation                                                */
/*------------------------------------------------------------------*/
wire [6:0] col      = act_x[9:3];
wire [5:0] scr_row  = act_y[9:4];
wire [3:0] char_y   = act_y[3:0];

/* Header rows address themselves; log rows walk the ring starting at
   top_bin, so the newest line sits directly under the header. */
wire [5:0] log_i   = scr_row - HDR_ROWS[5:0];
wire [6:0] ring    = {1'b0, top_bin} + {1'b0, log_i};
wire [5:0] ring_m  = (ring >= LOG_ROWS) ? (ring - LOG_ROWS) : ring[5:0];
wire [5:0] ram_row = (scr_row < HDR_ROWS) ? scr_row : (HDR_ROWS[5:0] + ring_m);

wire [12:0] rd_addr = {ram_row, col};

/*------------------------------------------------------------------*/
/* character RAM - simple dual port, independent clocks.              */
/*                                                                    */
/* XPM, NOT an inferred array. The obvious two-always-block version    */
/* with (* ram_style = "block" *) was inferred as DISTRIBUTED RAM      */
/* (RAMD64E) instead, which is wrong twice over: 8192x8 bits costs     */
/* ~1024 LUTs, and LUTRAM reads combinationally out of the array, so   */
/* Vivado timed a real path from the 100MHz write clock into the 65MHz */
/* pixel domain and reported WNS -10.5ns. A hard block RAM has         */
/* genuinely independent ports, so no such arc exists.                 */
/*------------------------------------------------------------------*/
wire [17:0] char_q;

xpm_memory_sdpram #(
    .ADDR_WIDTH_A(13),
    .ADDR_WIDTH_B(13),
    .BYTE_WRITE_WIDTH_A(18),
    .CLOCKING_MODE("independent_clock"),
    .MEMORY_PRIMITIVE("block"),
    .MEMORY_SIZE(147456),         // 8192 x 18 bit = 4 RAMB36, see header
    .READ_DATA_WIDTH_B(18),
    .READ_LATENCY_B(1),
    .WRITE_DATA_WIDTH_A(18),
    .WRITE_MODE_B("read_first"),
    .USE_MEM_INIT(0)
) char_ram (
    .clka(i_wrClk),
    .ena(i_wr),
    .wea(1'b1),
    .addra(i_wrAddr),
    .dina(i_wrData),
    .clkb(i_pixClk),
    .enb(1'b1),
    .addrb(rd_addr),
    .doutb(char_q),
    .rstb(1'b0),
    .regceb(1'b1),
    .sleep(1'b0)
    /* no ECC ports: with the default ECC_MODE("no_ecc") xpm_memory_sdpram
       does not declare injectsbiterr/injectdbiterr/sbiterr/dbiterr at all,
       and connecting them by name is an error rather than a no-op. */
);

/*------------------------------------------------------------------*/
/* font ROM                                                          */
/*------------------------------------------------------------------*/
(* rom_style = "block" *) reg [7:0] font [0:1023];
initial $readmemh(FONT_FILE, font);

reg [7:0] font_q;
reg [3:0] char_y_d1;
always @(posedge i_pixClk) char_y_d1 <= char_y;
always @(posedge i_pixClk) font_q <= font[{char_q[5:0], char_y_d1}];

/*------------------------------------------------------------------*/
/* pixel pipeline: address -> char (1) -> font (1) -> bit (1)        */
/* Syncs are delayed by the same 3 stages so everything lines up.    */
/*------------------------------------------------------------------*/
reg [2:0]  hs_d, vs_d, de_d;
reg [2:0]  cx_d0, cx_d1;
reg [11:0] rgb_d1, rgb_d2;

always @(posedge i_pixClk) begin
    hs_d <= {hs_d[1:0], hs_raw};
    vs_d <= {vs_d[1:0], vs_raw};
    de_d <= {de_d[1:0], de_raw};

    cx_d0 <= act_x[2:0];
    cx_d1 <= cx_d0;

    rgb_d1 <= char_q[17:6];
    rgb_d2 <= rgb_d1;
end

/* cx_d1 matches font_q's 2-cycle latency; registering pix here is the
   third stage, aligned with hs_d[2]/de_d[2] at the output registers. */
reg pix;
always @(posedge i_pixClk) pix <= font_q[3'd7 - cx_d1];

always @(posedge i_pixClk) begin
    o_hs <= hs_d[2];
    o_vs <= vs_d[2];
    o_de <= de_d[2];
    if (!de_d[2] || !pix) begin
        o_r <= 8'h00; o_g <= 8'h00; o_b <= 8'h00;
    end
    else begin
        /* 4:4:4 -> 8:8:8 by nibble replication, NOT a left shift: replication
           maps 0xF to 0xFF where {nib,4'd0} would stop at 0xF0 and no colour
           could ever reach full white. Black stays black either way. */
        o_r <= {rgb_d2[11:8], rgb_d2[11:8]};
        o_g <= {rgb_d2[7:4],  rgb_d2[7:4]};
        o_b <= {rgb_d2[3:0],  rgb_d2[3:0]};
    end
end

endmodule
