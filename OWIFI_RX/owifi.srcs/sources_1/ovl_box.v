//////////////////////////////////////////////////////////////////////////////////
//
// Design Name: OWIFI_RX
// Module Name: ovl_box
// Project Name: RA-Sentinel 802.11 receiver + direction finder
// Engineer: Tobias Weber
// Target Devices: Artix 7, XC7A100T (RASBB U10 + RASRF2400WBMC)
// Description:
//   Pop-up box in the lower right corner of the 1080p HDMI picture: a white
//   window with a thin grey/red frame (the logo's two colours), the project
//   logo centred at the top and, below it, a text the ECU sends over the SPI
//   config bus, plus up to N_RECT filled rectangles the ECU places under the
//   text (menu highlight bars, separators, value boxes - the FPGA is only
//   the text and rectangle drawer, the ECU runs the menu). The box grows
//   with the text: as wide as its longest line (at least the logo), as tall
//   as the logo plus the lines. 0x0D (CR) in the text starts a new line (a
//   following 0x0A is swallowed, a lone 0x0A also breaks). The glyphs are
//   the Terminus 8x16 console font (font8x16_96.mem, tools/gen_font.py, SIL
//   OFL - drawn for this cell size, so the stems stay even when magnified;
//   the TrueType-derived station-list font did not) magnified SCALE_DEF
//   times, 1..SCALE_MAX at run time.
//
//   LOGO ROM: tools/gen_logo.py downscales the 600x138 GIF to LOGO_W x LOGO_H
//   (240x55) and quantises it to a 4-colour palette, 2 bits per pixel: 26.4
//   kbit = one RAMB36 instead of the 2.5 MB of the original. Palette index 0
//   is "transparent" (the box background shows), 1..3 are red, grey, pink.
//
//   TEXT RAM: two banks of TEXT_ROWS x TEXT_COLS characters (2 x 16 x 64 x 8
//   bits = one RAMB18). The ECU fills the back bank, then COMMIT swaps: the
//   picture never shows a half-written text. Each line's length is kept in a
//   small table, so cells the new text did not write are blank without any
//   clearing pass, and lines can be centred. The rectangles are double
//   buffered the same way and swap with the text.
//
//   REGISTERS (config bus, iq_cap_regs style: 7-bit address, 32-bit word,
//   tri-state read mux; STM32 console OT / OS / OZ / OA / OC, RR / RW raw):
//   BASE+0 OVL_CTRL   W: [0] show, [1] centre the lines (else left-aligned),
//                     [7:4] font scale 1..SCALE_MAX (0 = SCALE_DEF),
//                     [8] BEGIN (pulse): start a new text in the back bank,
//                     [9] COMMIT (pulse): display the text and rectangles
//                     written since BEGIN (the back bank becomes the front
//                     bank; the writer is reset for the next text, so BEGIN
//                     is optional).
//                     R: [0] show, [1] centre, [7:4] scale field, [15:8] lines
//                     and [23:16] columns (longest line) of the displayed
//                     text, [31] displayed bank
//   BASE+1 OVL_TEXT   W: four text bytes, [7:0] first. 0x20..0x7E glyphs,
//                     0x0D / 0x0A line break (CR LF = one break), 0x00 padding
//                     (ignored), everything else ignored. Beyond TEXT_COLS in
//                     a line or TEXT_ROWS lines the text is cut.
//   BASE+2 OVL_COLOR  RW: [11:0] text colour, [23:12] box colour, both RGB 4:4:4
//                     (defaults 0x444 dark grey on 0xFFF white)
//   BASE+3 OVL_STAT   R: writer state: [7:0] column, [15:8] line, [23:16]
//                     columns so far, [31:24] lines so far (of the text being
//                     written)
//   (BASE+4 belongs to disp_regs, DISP_CTRL)
//   BASE+5 OVL_RECT_PTR RW: [4:2] rectangle 0..N_RECT-1, [1:0] word 0..2 of
//                     the next OVL_RECT_DATA write; advances by itself (word
//                     2 -> next rectangle's word 0); BEGIN / COMMIT reset it
//   BASE+6 OVL_RECT_DATA W: word 0 {y[23:12], x[11:0]}: top left corner in
//                     pixels relative to the text origin (the first text
//                     line's top left), both signed 12-bit, so a bar may
//                     start in the padding (x = -PAD); word 1 {h[23:12],
//                     w[11:0]}: size in pixels, 0xFFF = up to the inner edge
//                     of the frame; word 2 {[24] enable, [23:12] colour of
//                     text pixels inside, [11:0] fill}, RGB 4:4:4. Rectangles
//                     are clipped to the inside of the frame, lie under the
//                     text and over the logo and background, the lowest index
//                     wins where they overlap. A rectangle filled in the box
//                     colour with another text colour is a plain text-colour
//                     change (title lines). All disabled at BEGIN / COMMIT.
//   Defaults after reset: show = 0 (nothing drawn until the ECU says so),
//   scale SCALE_DEF, left-aligned, empty text, no rectangles.
//
//   PIXEL SIDE: like polar_labels, coordinates are recovered from the timing
//   master's DE/VS. The register state crosses into the pixel domain through
//   a request/acknowledge handshake and a shadow copy taken at vsync (a write
//   landing exactly in that cycle tears one video frame, the accepted
//   single-frame-tear class; the handshake re-copies afterwards). The
//   geometry (box, logo, text origins, rectangle corners) is recomputed once
//   per frame during vertical blanking, the per-line state at the end of the
//   previous line, and the per-pixel pipeline (text RAM -> font ROM -> bit,
//   logo ROM -> palette, rectangle hit -> colour) is 5 stages deep, which the
//   horizontal LOOKAHEAD cancels so everything lands on its nominal pixels.
//
// Dependencies: font8x16_96.mem, logo.mem + logo.vh
//   (tools/gen_font.py, tools/gen_logo.py), xpm_memory_sdpram
//
// Additional Comments: https://github.com/Tobias-DG3YEV/RA-Sentinel
//
//////////////////////////////////////////////////////////////////////////////////
// Copyright (C) 2026 Tobias Weber
// License: GNU GPL v3
//////////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps
`include "logo.vh"

module ovl_box #(
    parameter [6:0] BASE_ADDR = 7'h08,     // OVL_CTRL; +1 TEXT, +2 COLOR, +3 STAT, +5 RECT_PTR, +6 RECT_DATA
    parameter SCREEN_W   = 1920,
    parameter SCREEN_H   = 1080,
    parameter MARGIN     = 24,             // box to screen edge
    parameter PAD        = 16,             // frame to content
    parameter GAP        = 10,             // logo to first text line
    parameter BORDER_OUT = 2,              // outer frame line (grey)
    parameter BORDER_IN  = 2,              // inner frame line (red)
    parameter SCALE_DEF  = 2,              // font magnification when OVL_CTRL[7:4] = 0
    parameter SCALE_MAX  = 4,
    parameter TEXT_COLS  = 64,             // characters per line (power of two)
    parameter TEXT_ROWS  = 16,             // lines (power of two)
    parameter N_RECT     = 8,              // rectangles (power of two)
    parameter FONT_FILE  = "font8x16_96.mem",
    parameter LOGO_FILE  = "logo.mem",
    parameter LOGO_W     = `LOGO_W,
    parameter LOGO_H     = `LOGO_H,
    parameter [23:0] LOGO_PAL1 = `LOGO_PAL1,
    parameter [23:0] LOGO_PAL2 = `LOGO_PAL2,
    parameter [23:0] LOGO_PAL3 = `LOGO_PAL3,
    parameter [23:0] RGB_BORDER_OUT  = 24'h7E7D7D,   // the logo's grey
    parameter [23:0] RGB_BORDER_IN   = 24'hE31E25,   // the logo's red
    parameter [11:0] RGB444_TEXT_DEF = 12'h444,
    parameter [11:0] RGB444_BOX_DEF  = 12'hFFF
)(
    /* config bus domain */
    input  wire        i_clk,
    input  wire        i_rst,
    input  wire [6:0]  i_SPI_addr,
    input  wire        i_SPI_wrStrobe,
    input  wire [31:0] i_SPIdata,
    inout  wire [31:0] o_SPIdata,

    /* pixel domain */
    input  wire        i_pixClk,
    input  wire        i_rst_pix,
    input  wire        i_video_vs,
    input  wire        i_video_de,
    output reg         o_active,
    output reg  [7:0]  o_r,
    output reg  [7:0]  o_g,
    output reg  [7:0]  o_b
);

localparam COL_W  = $clog2(TEXT_COLS);
localparam ROW_W  = $clog2(TEXT_ROWS);
localparam LEN_W  = COL_W + 1;                 // 0..TEXT_COLS
localparam RAM_AW = 1 + ROW_W + COL_W;         // {bank, row, col}
localparam RI_W   = $clog2(N_RECT);
localparam BORDER = BORDER_OUT + BORDER_IN;
localparam EDGE   = BORDER + PAD;              // frame + padding
localparam CONTENT_W_MAX = SCREEN_W - 2 * MARGIN - 2 * EDGE;
localparam CONTENT_H_MAX = SCREEN_H - 2 * MARGIN - 2 * EDGE;
localparam LOOKAHEAD = 5;                      // pipeline depth, see header
/* sized copies for the arithmetic below */
localparam [2:0]  SCALE_DEF_W  = SCALE_DEF;
localparam [12:0] LOGO_W_13    = LOGO_W;
localparam [12:0] LOGO_H_13    = LOGO_H;
localparam [12:0] CONTENT_W_13 = CONTENT_W_MAX;
localparam [12:0] CONTENT_H_13 = CONTENT_H_MAX;
localparam [12:0] LOGO_GAP_13  = LOGO_H + GAP;

/****************************************************************************/
/* Config bus side: registers and the text / rectangle writer               */
/****************************************************************************/
wire [6:0] a = i_SPI_addr;
wire wr_ctrl  = i_SPI_wrStrobe && (a == BASE_ADDR);
wire wr_text  = i_SPI_wrStrobe && (a == BASE_ADDR + 7'd1);
wire wr_color = i_SPI_wrStrobe && (a == BASE_ADDR + 7'd2);
wire wr_rptr  = i_SPI_wrStrobe && (a == BASE_ADDR + 7'd5);
wire wr_rdata = i_SPI_wrStrobe && (a == BASE_ADDR + 7'd6);

/* cf_*, cm_* and the pixel-domain sh_* copies are DONT_TOUCH: the constraints
   waive the crossing between them by name (rasbb_wbmc.xdc), and synthesis
   otherwise retimes logic across the shadow registers and renames them. */
(* dont_touch = "true" *) reg        cf_show, cf_center;
(* dont_touch = "true" *) reg [3:0]  cf_scale;
(* dont_touch = "true" *) reg [11:0] cf_text_rgb, cf_box_rgb;

/* text writer */
reg [ROW_W:0]   wr_line;                       // TEXT_ROWS = full, further chars dropped
reg [LEN_W-1:0] wr_col;
reg [LEN_W-1:0] wr_maxcol;
reg [ROW_W:0]   wr_lines;
reg             wr_cr;                         // last byte was CR: swallow an LF
reg             wr_bank;                       // bank being written
reg [LEN_W-1:0] wl_len [0:TEXT_ROWS-1];
reg [31:0]      wq;                            // bytes still to process
reg [2:0]       wq_n;

wire [7:0] wb      = wq[7:0];
wire       byte_go = (wq_n != 3'd0);
wire       is_cr   = (wb == 8'h0D);
wire       is_lf   = (wb == 8'h0A);
wire       is_chr  = (wb >= 8'h20) && (wb < 8'h7F);
wire       fits    = (wr_line < TEXT_ROWS) && (wr_col < TEXT_COLS);
wire       brk     = byte_go && (is_cr || (is_lf && !wr_cr));
wire       put     = byte_go && is_chr && fits;

wire                ram_we    = put;
wire [RAM_AW-1:0]   ram_waddr = {wr_bank, wr_line[ROW_W-1:0], wr_col[COL_W-1:0]};
wire [7:0]          ram_wdata = {1'b0, wb[6:0] - 7'h20};

/* rectangle writer: back buffer, filled through RECT_PTR / RECT_DATA */
reg [RI_W+1:0]      rp;                        // {rect, word}
reg signed [11:0]   wr_rx [0:N_RECT-1];
reg signed [11:0]   wr_ry [0:N_RECT-1];
reg [11:0]          wr_rw [0:N_RECT-1];
reg [11:0]          wr_rh [0:N_RECT-1];
reg [11:0]          wr_rfill [0:N_RECT-1];
reg [11:0]          wr_rtext [0:N_RECT-1];
reg [N_RECT-1:0]    wr_ren;
wire [RI_W-1:0]     rp_idx  = rp[RI_W+1:2];
wire [1:0]          rp_word = rp[1:0];

/* committed (displayed) state */
(* dont_touch = "true" *) reg             cm_bank;
(* dont_touch = "true" *) reg [ROW_W:0]   cm_lines;
(* dont_touch = "true" *) reg [LEN_W-1:0] cm_cols;
(* dont_touch = "true" *) reg [LEN_W-1:0] cm_len [0:TEXT_ROWS-1];
(* dont_touch = "true" *) reg signed [11:0] cm_rx [0:N_RECT-1];
(* dont_touch = "true" *) reg signed [11:0] cm_ry [0:N_RECT-1];
(* dont_touch = "true" *) reg [11:0]      cm_rw [0:N_RECT-1];
(* dont_touch = "true" *) reg [11:0]      cm_rh [0:N_RECT-1];
(* dont_touch = "true" *) reg [11:0]      cm_rfill [0:N_RECT-1];
(* dont_touch = "true" *) reg [11:0]      cm_rtext [0:N_RECT-1];
(* dont_touch = "true" *) reg [N_RECT-1:0] cm_ren;
/* change handshake to the pixel domain: any register write marks the state
   dirty; once the previous copy is acknowledged (and the data has been stable
   for a cycle) the request toggles, and the pixel side copies at its next
   vsync. Two writes inside one frame therefore never cancel out. */
reg             cm_dirty, cm_req;
(* ASYNC_REG = "true" *) reg [1:0] ack_sync;
reg             sh_ack;                        // pixel domain, synchronised back

integer li;
always @(posedge i_clk) begin
    if (i_rst) begin
        cf_show <= 1'b0; cf_center <= 1'b0; cf_scale <= 4'd0;
        cf_text_rgb <= RGB444_TEXT_DEF; cf_box_rgb <= RGB444_BOX_DEF;
        wr_line <= 0; wr_col <= 0; wr_maxcol <= 0; wr_lines <= 0; wr_cr <= 1'b0;
        wr_bank <= 1'b1; wq <= 32'd0; wq_n <= 3'd0;
        rp <= 0; wr_ren <= 0;
        cm_bank <= 1'b0; cm_lines <= 0; cm_cols <= 0; cm_ren <= 0;
        cm_dirty <= 1'b0; cm_req <= 1'b0; ack_sync <= 2'b00;
        for (li = 0; li < TEXT_ROWS; li = li + 1) begin
            wl_len[li] <= 0; cm_len[li] <= 0;
        end
        for (li = 0; li < N_RECT; li = li + 1) begin
            wr_rx[li] <= 0; wr_ry[li] <= 0; wr_rw[li] <= 0; wr_rh[li] <= 0;
            wr_rfill[li] <= 0; wr_rtext[li] <= 0;
            cm_rx[li] <= 0; cm_ry[li] <= 0; cm_rw[li] <= 0; cm_rh[li] <= 0;
            cm_rfill[li] <= 0; cm_rtext[li] <= 0;
        end
    end
    else begin
        ack_sync <= {ack_sync[0], sh_ack};
        if (wr_ctrl | wr_color) cm_dirty <= 1'b1;
        else if (cm_dirty && (cm_req == ack_sync[1])) begin
            cm_req <= ~cm_req; cm_dirty <= 1'b0;
        end

        if (wr_color) begin
            cf_text_rgb <= i_SPIdata[11:0];
            cf_box_rgb  <= i_SPIdata[23:12];
        end

        /* text bytes, one per cycle */
        if (wr_text) begin
            wq <= i_SPIdata; wq_n <= 3'd4;
        end
        else if (byte_go) begin
            wq <= {8'h00, wq[31:8]}; wq_n <= wq_n - 3'd1;
            if (brk) begin
                if (wr_line < TEXT_ROWS) wr_line <= wr_line + 1'b1;
                wr_col <= 0;
            end
            if (put) begin
                wr_col <= wr_col + 1'b1;
                wl_len[wr_line[ROW_W-1:0]] <= wr_col + 1'b1;
                if (wr_col + 1'b1 > wr_maxcol) wr_maxcol <= wr_col + 1'b1;
                if (wr_line + 1'b1 > wr_lines) wr_lines <= wr_line + 1'b1;
            end
            if (is_cr || is_lf || is_chr) wr_cr <= is_cr;   // padding leaves it alone
        end

        /* rectangles */
        if (wr_rptr)
            rp <= i_SPIdata[RI_W+1:0];
        else if (wr_rdata) begin
            case (rp_word)
                2'd0: begin wr_rx[rp_idx] <= i_SPIdata[11:0]; wr_ry[rp_idx] <= i_SPIdata[23:12]; end
                2'd1: begin wr_rw[rp_idx] <= i_SPIdata[11:0]; wr_rh[rp_idx] <= i_SPIdata[23:12]; end
                default: begin
                    wr_rfill[rp_idx] <= i_SPIdata[11:0];
                    wr_rtext[rp_idx] <= i_SPIdata[23:12];
                    wr_ren[rp_idx]   <= i_SPIdata[24];
                end
            endcase
            rp <= (rp_word == 2'd2) ? {rp_idx + 1'b1, 2'b00} : rp + 1'b1;
        end

        if (wr_ctrl) begin
            cf_show   <= i_SPIdata[0];
            cf_center <= i_SPIdata[1];
            cf_scale  <= i_SPIdata[7:4];
            if (i_SPIdata[9]) begin                  // COMMIT: swap, then reset the writer
                cm_bank  <= wr_bank;
                cm_lines <= wr_lines;
                cm_cols  <= wr_maxcol;
                for (li = 0; li < TEXT_ROWS; li = li + 1) cm_len[li] <= wl_len[li];
                for (li = 0; li < N_RECT; li = li + 1) begin
                    cm_rx[li] <= wr_rx[li]; cm_ry[li] <= wr_ry[li];
                    cm_rw[li] <= wr_rw[li]; cm_rh[li] <= wr_rh[li];
                    cm_rfill[li] <= wr_rfill[li]; cm_rtext[li] <= wr_rtext[li];
                end
                cm_ren   <= wr_ren;
                wr_bank  <= ~wr_bank;
            end
            if (i_SPIdata[9] | i_SPIdata[8]) begin   // COMMIT or BEGIN
                wr_line <= 0; wr_col <= 0; wr_maxcol <= 0; wr_lines <= 0; wr_cr <= 1'b0;
                wq_n <= 3'd0;
                rp <= 0; wr_ren <= 0;
                for (li = 0; li < TEXT_ROWS; li = li + 1) wl_len[li] <= 0;
            end
        end
    end
end

/* read mux */
reg [31:0] rd;
reg        sel;
always @(*) begin
    sel = 1'b1; rd = 32'd0;
    case (a)
        BASE_ADDR:         rd = {cm_bank, 7'd0, {{(8-LEN_W){1'b0}}, cm_cols}, {{(7-ROW_W){1'b0}}, cm_lines},
                                 cf_scale, 2'b00, cf_center, cf_show};
        BASE_ADDR + 7'd2:  rd = {8'd0, cf_box_rgb, cf_text_rgb};
        BASE_ADDR + 7'd3:  rd = {{{(7-ROW_W){1'b0}}, wr_lines}, {{(8-LEN_W){1'b0}}, wr_maxcol},
                                 {{(7-ROW_W){1'b0}}, wr_line}, {{(8-LEN_W){1'b0}}, wr_col}};
        BASE_ADDR + 7'd5:  rd = {{(30-RI_W){1'b0}}, rp};
        default: sel = 1'b0;
    endcase
end
assign o_SPIdata = sel ? rd : 32'bz;

/****************************************************************************/
/* Text RAM: two banks, written at i_clk, read at the pixel clock.          */
/* XPM for the same reason as text_screen's character RAM: an inferred      */
/* array may land in LUTRAM with a timing arc between the two clocks.       */
/****************************************************************************/
reg  [RAM_AW-1:0] ram_raddr;
wire [7:0]        ram_q;

xpm_memory_sdpram #(
    .ADDR_WIDTH_A(RAM_AW),
    .ADDR_WIDTH_B(RAM_AW),
    .BYTE_WRITE_WIDTH_A(8),
    .CLOCKING_MODE("independent_clock"),
    .MEMORY_PRIMITIVE("block"),
    .MEMORY_SIZE(8 * (1 << RAM_AW)),
    .READ_DATA_WIDTH_B(8),
    .READ_LATENCY_B(1),
    .WRITE_DATA_WIDTH_A(8),
    .WRITE_MODE_B("read_first"),
    .USE_MEM_INIT(0)
) text_ram (
    .clka(i_clk),
    .ena(ram_we),
    .wea(1'b1),
    .addra(ram_waddr),
    .dina(ram_wdata),
    .clkb(i_pixClk),
    .enb(1'b1),
    .addrb(ram_raddr),
    .doutb(ram_q),
    .rstb(1'b0),
    .regceb(1'b1),
    .sleep(1'b0)
);

/****************************************************************************/
/* Pixel domain                                                             */
/****************************************************************************/
reg vs_prev, de_prev;
always @(posedge i_pixClk) begin
    vs_prev <= i_video_vs;
    de_prev <= i_video_de;
end
wire frame_start = ~vs_prev & i_video_vs;      // VS_POL = 1 at 1080p
wire line_start  = i_video_de & ~de_prev;
wire line_end    = ~i_video_de & de_prev;

reg [11:0] active_x, active_y;
always @(posedge i_pixClk) begin
    if (i_rst_pix) begin
        active_x <= 12'd0;
        active_y <= 12'd0;
    end
    else begin
        if (!i_video_de) active_x <= 12'd0;
        else             active_x <= active_x + 12'd1;
        if (frame_start)     active_y <= 12'hFFF;   // the first line increments to 0
        else if (line_start) active_y <= active_y + 12'd1;
    end
end

/* shadow of the committed state, taken at vsync after a change */
(* ASYNC_REG = "true" *) reg [1:0] req_sync;
(* dont_touch = "true" *) reg             sh_show, sh_center, sh_bank;
(* dont_touch = "true" *) reg [2:0]       sh_scale;                      // effective 1..SCALE_MAX
(* dont_touch = "true" *) reg [ROW_W:0]   sh_lines;
(* dont_touch = "true" *) reg [LEN_W-1:0] sh_cols;
(* dont_touch = "true" *) reg [LEN_W-1:0] sh_len [0:TEXT_ROWS-1];
(* dont_touch = "true" *) reg [11:0]      sh_text_rgb, sh_box_rgb;
(* dont_touch = "true" *) reg signed [11:0] sh_rx [0:N_RECT-1];
(* dont_touch = "true" *) reg signed [11:0] sh_ry [0:N_RECT-1];
(* dont_touch = "true" *) reg [11:0]      sh_rw [0:N_RECT-1];
(* dont_touch = "true" *) reg [11:0]      sh_rh [0:N_RECT-1];
(* dont_touch = "true" *) reg [11:0]      sh_rfill [0:N_RECT-1];
(* dont_touch = "true" *) reg [11:0]      sh_rtext [0:N_RECT-1];
(* dont_touch = "true" *) reg [N_RECT-1:0] sh_ren;

wire [3:0] scale_req = cf_scale;
wire [2:0] scale_eff = (scale_req == 4'd0 || scale_req > SCALE_MAX) ? SCALE_DEF_W : scale_req[2:0];

integer si;
always @(posedge i_pixClk) begin
    req_sync <= {req_sync[0], cm_req};
    if (i_rst_pix) begin
        sh_ack <= 1'b0;
        sh_show <= 1'b0; sh_center <= 1'b0; sh_bank <= 1'b0; sh_scale <= SCALE_DEF_W;
        sh_lines <= 0; sh_cols <= 0; sh_ren <= 0;
        sh_text_rgb <= RGB444_TEXT_DEF; sh_box_rgb <= RGB444_BOX_DEF;
        for (si = 0; si < TEXT_ROWS; si = si + 1) sh_len[si] <= 0;
        for (si = 0; si < N_RECT; si = si + 1) begin
            sh_rx[si] <= 0; sh_ry[si] <= 0; sh_rw[si] <= 0; sh_rh[si] <= 0;
            sh_rfill[si] <= 0; sh_rtext[si] <= 0;
        end
    end
    else if (frame_start && (req_sync[1] != sh_ack)) begin
        sh_ack    <= req_sync[1];
        sh_show   <= cf_show;
        sh_center <= cf_center;
        sh_bank   <= cm_bank;
        sh_scale  <= scale_eff;
        sh_lines  <= cm_lines;
        sh_cols   <= cm_cols;
        sh_text_rgb <= cf_text_rgb;
        sh_box_rgb  <= cf_box_rgb;
        sh_ren    <= cm_ren;
        for (si = 0; si < TEXT_ROWS; si = si + 1) sh_len[si] <= cm_len[si];
        for (si = 0; si < N_RECT; si = si + 1) begin
            sh_rx[si] <= cm_rx[si]; sh_ry[si] <= cm_ry[si];
            sh_rw[si] <= cm_rw[si]; sh_rh[si] <= cm_rh[si];
            sh_rfill[si] <= cm_rfill[si]; sh_rtext[si] <= cm_rtext[si];
        end
    end
end

/* per-frame geometry, a few cycles after vsync (the first active line is
   41 lines away): the box first, then the rectangles, three cycles each */
reg [5:0]  gstep;
reg [12:0] g_text_w, g_text_h;                 // text block, pixels
reg [12:0] g_content_w, g_content_h;
reg [12:0] g_w, g_h;
reg [11:0] g_x0, g_x1, g_y0, g_y1;             // box
reg [11:0] g_bo_x0, g_bo_x1, g_bo_y0, g_bo_y1; // inside the outer line
reg [11:0] g_bi_x0, g_bi_x1, g_bi_y0, g_bi_y1; // inside the inner line
reg [11:0] g_logo_x0, g_logo_x1, g_logo_y0, g_logo_y1;
reg [11:0] g_text_x0, g_text_y0, g_text_y1;

wire [12:0] text_w_raw = ({3'd0, sh_cols, 3'd0}) * sh_scale;    // cols * 8 * scale
wire [12:0] text_h_raw = ({4'd0, sh_lines, 4'd0}) * sh_scale;   // lines * 16 * scale

always @(posedge i_pixClk) begin
    if (frame_start) gstep <= 6'd1;
    else if (gstep != 6'd0 && gstep != 6'd63) gstep <= gstep + 6'd1;
    case (gstep)
        6'd2: begin       // one cycle after the shadow copy
            g_text_w <= text_w_raw;
            g_text_h <= text_h_raw;
        end
        6'd3: begin
            g_content_w <= (g_text_w > LOGO_W_13) ? ((g_text_w > CONTENT_W_13) ? CONTENT_W_13 : g_text_w)
                                                  : LOGO_W_13;
            g_content_h <= (sh_lines == 0) ? LOGO_H_13
                         : ((LOGO_GAP_13 + g_text_h > CONTENT_H_13) ? CONTENT_H_13
                                                                    : LOGO_GAP_13 + g_text_h);
        end
        6'd4: begin
            g_w <= g_content_w + 2 * EDGE;
            g_h <= g_content_h + 2 * EDGE;
        end
        6'd5: begin
            g_x1 <= SCREEN_W - MARGIN;
            g_x0 <= SCREEN_W - MARGIN - g_w;
            g_y1 <= SCREEN_H - MARGIN;
            g_y0 <= SCREEN_H - MARGIN - g_h;
        end
        6'd6: begin
            g_bo_x0 <= g_x0 + BORDER_OUT;  g_bo_x1 <= g_x1 - BORDER_OUT;
            g_bo_y0 <= g_y0 + BORDER_OUT;  g_bo_y1 <= g_y1 - BORDER_OUT;
            g_bi_x0 <= g_x0 + BORDER;      g_bi_x1 <= g_x1 - BORDER;
            g_bi_y0 <= g_y0 + BORDER;      g_bi_y1 <= g_y1 - BORDER;
            g_logo_x0 <= g_x0 + EDGE + ((g_content_w - LOGO_W) >> 1);
            g_logo_x1 <= g_x0 + EDGE + ((g_content_w - LOGO_W) >> 1) + LOGO_W;
            g_logo_y0 <= g_y0 + EDGE;
            g_logo_y1 <= g_y0 + EDGE + LOGO_H;
            g_text_x0 <= g_x0 + EDGE;
            g_text_y0 <= g_y0 + EDGE + LOGO_H + GAP;
            g_text_y1 <= g_y1 - EDGE;                  // text rows end at the padding (clamps tall texts)
        end
        default: ;
    endcase
end

/* rectangles: absolute corners, clipped to the inside of the frame. Three
   cycles per rectangle: origin, far corner, clamp. */
reg [11:0]        r_x0 [0:N_RECT-1];
reg [11:0]        r_x1 [0:N_RECT-1];
reg [11:0]        r_y0 [0:N_RECT-1];
reg [11:0]        r_y1 [0:N_RECT-1];
reg               rect_run;
reg [RI_W-1:0]    rr;
reg [1:0]         rs;
reg signed [14:0] a_x0, a_y0, a_x1, a_y1;

function [11:0] clamp12;
    input signed [14:0] v;
    input [11:0] lo;
    input [11:0] hi;
    begin
        clamp12 = (v < $signed({3'b000, lo})) ? lo :
                  (v > $signed({3'b000, hi})) ? hi : v[11:0];
    end
endfunction

integer ri;
always @(posedge i_pixClk) begin
    if (i_rst_pix) begin
        rect_run <= 1'b0; rr <= 0; rs <= 2'd0;
        for (ri = 0; ri < N_RECT; ri = ri + 1) begin
            r_x0[ri] <= 12'd0; r_x1[ri] <= 12'd0; r_y0[ri] <= 12'd0; r_y1[ri] <= 12'd0;
        end
    end
    else if (gstep == 6'd7) begin
        rect_run <= 1'b1; rr <= 0; rs <= 2'd0;
    end
    else if (rect_run) begin
        case (rs)
            2'd0: begin
                a_x0 <= $signed({3'b000, g_text_x0}) + sh_rx[rr];
                a_y0 <= $signed({3'b000, g_text_y0}) + sh_ry[rr];
                rs <= 2'd1;
            end
            2'd1: begin
                a_x1 <= (sh_rw[rr] == 12'hFFF) ? $signed({3'b000, g_bi_x1}) : a_x0 + $signed({3'b000, sh_rw[rr]});
                a_y1 <= (sh_rh[rr] == 12'hFFF) ? $signed({3'b000, g_bi_y1}) : a_y0 + $signed({3'b000, sh_rh[rr]});
                rs <= 2'd2;
            end
            default: begin
                r_x0[rr] <= sh_ren[rr] ? clamp12(a_x0, g_bi_x0, g_bi_x1) : 12'd0;
                r_x1[rr] <= sh_ren[rr] ? clamp12(a_x1, g_bi_x0, g_bi_x1) : 12'd0;
                r_y0[rr] <= sh_ren[rr] ? clamp12(a_y0, g_bi_y0, g_bi_y1) : 12'd0;
                r_y1[rr] <= sh_ren[rr] ? clamp12(a_y1, g_bi_y0, g_bi_y1) : 12'd0;
                rs <= 2'd0;
                if (rr == N_RECT - 1) rect_run <= 1'b0;
                else rr <= rr + 1'b1;
            end
        endcase
    end
end

/* per-line state, prepared at the end of the previous line for line ynext */
wire [11:0] ynext = frame_start ? 12'd0 : active_y + 12'd1;
wire        line_prep = line_end | frame_start;

reg             ly_box, ly_bo, ly_bi, ly_logo, ly_text;
reg [N_RECT-1:0] ly_rect;
reg [14:0]      logo_base;                     // ROM address of the logo row
reg [ROW_W-1:0] trow;                          // text line
reg [3:0]       ty;                            // glyph row
reg [2:0]       sy;                            // magnification counter
reg [2:0]       lstep;
reg [LEN_W-1:0] line_len;
reg [12:0]      line_w;
reg [11:0]      line_x0, line_x1;

integer lr;
always @(posedge i_pixClk) begin
    if (line_prep) begin
        ly_box  <= (ynext >= g_y0) && (ynext < g_y1);
        ly_bo   <= (ynext < g_bo_y0) || (ynext >= g_bo_y1);
        ly_bi   <= (ynext < g_bi_y0) || (ynext >= g_bi_y1);
        ly_logo <= (ynext >= g_logo_y0) && (ynext < g_logo_y1);
        ly_text <= (ynext >= g_text_y0) && (ynext < g_text_y1) && (sh_lines != 0);
        for (lr = 0; lr < N_RECT; lr = lr + 1)
            ly_rect[lr] <= (ynext >= r_y0[lr]) && (ynext < r_y1[lr]);
        if (ynext == g_logo_y0) logo_base <= 15'd0;
        else if (ynext > g_logo_y0 && ynext < g_logo_y1) logo_base <= logo_base + LOGO_W;
        if (ynext == g_text_y0) begin
            trow <= 0; ty <= 4'd0; sy <= 3'd0;
        end
        else if (ynext > g_text_y0 && ynext < g_text_y1) begin
            if (sy + 1'b1 == sh_scale) begin
                sy <= 3'd0;
                if (ty == 4'd15) begin ty <= 4'd0; trow <= trow + 1'b1; end
                else ty <= ty + 1'b1;
            end
            else sy <= sy + 1'b1;
        end
        lstep <= 3'd1;
    end
    else if (lstep != 3'd0 && lstep != 3'd7) lstep <= lstep + 3'd1;

    case (lstep)
        3'd1: line_len <= sh_len[trow];
        3'd2: line_w   <= ({3'd0, line_len, 3'd0}) * sh_scale;
        3'd3: line_x0  <= g_text_x0 + ((sh_center && line_w <= g_content_w) ? ((g_content_w - line_w) >> 1) : 13'd0);
        3'd4: line_x1  <= line_x0 + line_w;
        default: ;
    endcase
end

/* per-pixel: everything is computed for X = active_x + LOOKAHEAD so that the
   pipeline's output lands on the master's pixel X */
wire [11:0] X  = active_x + LOOKAHEAD;
wire [11:0] Xn = X + 12'd1;

/* text column counters, describing pixel X in the cycle where active_x = X - LOOKAHEAD */
reg [COL_W-1:0] tcol;
reg [2:0]       gx, sx;
always @(posedge i_pixClk) begin
    if (Xn == line_x0) begin
        tcol <= 0; gx <= 3'd0; sx <= 3'd0;
    end
    else if (sx + 1'b1 == sh_scale) begin
        sx <= 3'd0;
        if (gx == 3'd7) begin gx <= 3'd0; tcol <= tcol + 1'b1; end
        else gx <= gx + 1'b1;
    end
    else sx <= sx + 1'b1;
end

/* stage 0 */
reg        p0_box, p0_bo, p0_bi, p0_logo, p0_text;
reg [N_RECT-1:0] p0_rhit;
reg [2:0]  p0_gx;
reg [3:0]  p0_ty;
reg [14:0] logo_addr;
integer pr;
always @(posedge i_pixClk) begin
    p0_box  <= i_video_de && ly_box && (X >= g_x0) && (X < g_x1);
    p0_bo   <= ly_box && (ly_bo || (X < g_bo_x0) || (X >= g_bo_x1));
    p0_bi   <= ly_box && (ly_bi || (X < g_bi_x0) || (X >= g_bi_x1));
    p0_logo <= ly_logo && (X >= g_logo_x0) && (X < g_logo_x1);
    p0_text <= ly_text && (X >= line_x0) && (X < line_x1) && (X < g_bi_x1);
    for (pr = 0; pr < N_RECT; pr = pr + 1)
        p0_rhit[pr] <= ly_rect[pr] && (X >= r_x0[pr]) && (X < r_x1[pr]);
    p0_gx   <= gx;
    p0_ty   <= ty;
    logo_addr <= logo_base + {3'd0, X - g_logo_x0};
    ram_raddr <= {sh_bank, trow, tcol};
end

/* stage 1: text RAM and logo ROM read, rectangle priority (lowest index) */
(* rom_style = "block" *) reg [1:0] logo [0:LOGO_W*LOGO_H-1];
initial $readmemh(LOGO_FILE, logo);
reg [1:0] logo_q;
always @(posedge i_pixClk) logo_q <= logo[logo_addr];

reg [RI_W-1:0] rhit_idx;
integer hi;
always @(*) begin
    rhit_idx = 0;
    for (hi = N_RECT - 1; hi >= 0; hi = hi - 1)
        if (p0_rhit[hi]) rhit_idx = hi[RI_W-1:0];
end

reg        p1_box, p1_bo, p1_bi, p1_logo, p1_text, p1_rhit;
reg [RI_W-1:0] p1_ridx;
reg [2:0]  p1_gx;
reg [3:0]  p1_ty;
always @(posedge i_pixClk) begin
    p1_box <= p0_box; p1_bo <= p0_bo; p1_bi <= p0_bi; p1_logo <= p0_logo; p1_text <= p0_text;
    p1_rhit <= |p0_rhit; p1_ridx <= rhit_idx;
    p1_gx <= p0_gx; p1_ty <= p0_ty;
end

/* stage 2: glyph -> font address, logo index -> palette, rectangle colours */
(* rom_style = "block" *) reg [7:0] font [0:1535];
initial $readmemh(FONT_FILE, font);
reg [10:0] font_addr;
reg        p2_box, p2_bo, p2_bi, p2_logo, p2_text, p2_logo_px, p2_rhit;
reg [2:0]  p2_gx;
reg [23:0] p2_pal;
reg [11:0] p2_rfill, p2_rtext;
always @(posedge i_pixClk) begin
    font_addr <= {ram_q[6:0], p1_ty};
    p2_box <= p1_box; p2_bo <= p1_bo; p2_bi <= p1_bi; p2_logo <= p1_logo; p2_text <= p1_text;
    p2_gx <= p1_gx;
    p2_logo_px <= p1_logo && (logo_q != 2'd0);
    case (logo_q)
        2'd1: p2_pal <= LOGO_PAL1;
        2'd2: p2_pal <= LOGO_PAL2;
        default: p2_pal <= LOGO_PAL3;
    endcase
    p2_rhit  <= p1_rhit;
    p2_rfill <= sh_rfill[p1_ridx];
    p2_rtext <= sh_rtext[p1_ridx];
end

/* stage 3: font row */
reg [7:0]  font_q;
reg        p3_box, p3_bo, p3_bi, p3_text, p3_logo_px, p3_rhit;
reg [2:0]  p3_gx;
reg [23:0] p3_pal;
reg [11:0] p3_rfill, p3_rtext;
always @(posedge i_pixClk) begin
    font_q <= font[font_addr];
    p3_box <= p2_box; p3_bo <= p2_bo; p3_bi <= p2_bi; p3_text <= p2_text;
    p3_logo_px <= p2_logo_px; p3_gx <= p2_gx; p3_pal <= p2_pal;
    p3_rhit <= p2_rhit; p3_rfill <= p2_rfill; p3_rtext <= p2_rtext;
end

/* output */
function [23:0] rgb888;
    input [11:0] c;
    begin
        rgb888 = {c[11:8], c[11:8], c[7:4], c[7:4], c[3:0], c[3:0]};
    end
endfunction

wire        text_px = p3_text & font_q[3'd7 - p3_gx];
wire [23:0] px_rgb = p3_bo      ? RGB_BORDER_OUT :
                     p3_bi      ? RGB_BORDER_IN  :
                     text_px    ? (p3_rhit ? rgb888(p3_rtext) : rgb888(sh_text_rgb)) :
                     p3_rhit    ? rgb888(p3_rfill) :
                     p3_logo_px ? p3_pal         : rgb888(sh_box_rgb);
always @(posedge i_pixClk) begin
    o_active <= sh_show & p3_box;
    o_r <= px_rgb[23:16];
    o_g <= px_rgb[15:8];
    o_b <= px_rgb[7:0];
end

endmodule
