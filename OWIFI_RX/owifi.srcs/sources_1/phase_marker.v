//////////////////////////////////////////////////////////////////////////////////
//
// Design Name: OWIFI_RX
// Module Name: phase_marker
// Project Name: RA-Sentinel 802.11 receiver + direction finder
// Engineer: Tobias Weber
// Target Devices: Artix 7, XC7A100T (RASBB U10 + RASRF2400WBMC)
// Description:
//   Rim marker for the phase comparison (deliverable 4.b): a small filled
//   square drawn just outside the polar disc at the angle of the LAST
//   committed frame's inter-channel phase (ch1 vs ch0 by default, 16-bit
//   binary turns from phase_cmp, taken at df_frame's commit so it belongs to
//   the same frame that painted the last green ray). The marker is NOT a
//   bearing - it is the raw phase difference drawn on the compass so the
//   amplitude bearing (ray) and the phase (marker) can be compared by eye on
//   air; with the per-boot LO offset it sits at an arbitrary rotation, and
//   on the 2.4 lambda baseline it wraps several times per revolution.
//
//   Geometry as polar_labels.v: angle bin (9 bit, CCW from east) -> sin/cos
//   ROM (Q1.8) -> anchor at radius R_MARK from (CX, CY), screen y grows
//   downward. The anchor is recomputed once per video frame, and the marker
//   is the HALF-sized box around it - four comparators per pixel.
//
//   CLOCK DOMAINS. The angle comes from the receiver domain. Once per video
//   frame the pixel side requests a snapshot (toggle), the receiver side
//   copies its live value into a holding register, and the pixel side reads
//   the holding register a fixed number of clocks later - the register is
//   guaranteed stable by then and stays so until the next frame.
//
// Dependencies: sincos512.mem (same file as polar_labels)
//
// Additional Comments: https://github.com/Tobias-DG3YEV/RA-Sentinel
//
//////////////////////////////////////////////////////////////////////////////////
// Copyright (C) 2026 Tobias Weber
// License: GNU GPL v3
//////////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps

module phase_marker #(
    parameter CX          = 960,
    parameter CY          = 620,
    parameter R_MARK      = 332,     // R_MAX 324 + 8: between the ring and the labels
    parameter HALF        = 4,       // box half-size in pixels
    parameter [7:0] COL_R = 8'd0,    // default cyan; system_top_wbmc passes the FCS-good ray colour
    parameter [7:0] COL_G = 8'd255,
    parameter [7:0] COL_B = 8'd255,
    parameter SINCOS_FILE = "sincos512.mem"
)(
    /* receiver domain */
    input  wire        i_clk,
    input  wire        i_rst,
    input  wire [8:0]  i_ang,        // phase as an angle bin, CCW from east
    input  wire        i_valid,      // a value has been latched since reset

    /* pixel domain */
    input  wire        i_pixClk,
    input  wire        i_rst_pix,
    input  wire        i_video_vs,
    input  wire        i_video_de,
    output reg         o_active,
    output wire [7:0]  o_r, o_g, o_b
);

assign o_r = COL_R; assign o_g = COL_G; assign o_b = COL_B;

(* rom_style = "block" *) reg [19:0] sincos [0:511];
initial $readmemh(SINCOS_FILE, sincos);

/*------------------------------------------------------------------*/
/* frame timing (as polar_labels)                                   */
/*------------------------------------------------------------------*/
reg vs_prev, de_prev;
always @(posedge i_pixClk) begin vs_prev <= i_video_vs; de_prev <= i_video_de; end
wire frame_start = ~vs_prev & i_video_vs;
wire line_start  = i_video_de & ~de_prev;

reg [11:0] active_x, active_y;
always @(posedge i_pixClk) begin
    if (i_rst_pix) begin active_x <= 12'd0; active_y <= 12'd0; end
    else begin
        if (!i_video_de) active_x <= 12'd0; else active_x <= active_x + 12'd1;
        if (frame_start) active_y <= 12'hFFF; else if (line_start) active_y <= active_y + 12'd1;
    end
end

/*------------------------------------------------------------------*/
/* cross-domain snapshot: pix requests, rx looks the ROM up and holds  */
/* {valid, sin, cos}, pix samples the hold register 64 clocks later    */
/*------------------------------------------------------------------*/
/* The ROM lookup is done HERE, in the receiver domain, on purpose: a
   first version kept the angle and read the ROM on the pixel side, and
   full-design synthesis retimed that lookup back across the clock
   boundary into a BRAM clocked by i_clk with the pixel-side register
   trimmed - functionally murky and never seen on screen. Doing it
   explicitly leaves nothing for the tool to move. */
reg        req_tog;                     // pix domain
always @(posedge i_pixClk) if (i_rst_pix) req_tog <= 1'b0; else if (frame_start) req_tog <= ~req_tog;

(* ASYNC_REG = "TRUE" *) reg [2:0] req_sync;   // rx domain
reg [19:0] rom_q;                        // registered ROM read, rx domain
reg        rom_v;
reg [8:0]  ang_q;
reg [20:0] hold;                         // {valid, sin[9:0], cos[9:0]}, rx domain, stable between frames
reg        rom_v_d;                      // rom_q valid one clock after ang_q
always @(posedge i_clk) begin
    req_sync <= {req_sync[1:0], req_tog};
    rom_v    <= 1'b0;
    if (req_sync[2] != req_sync[1]) begin ang_q <= i_ang; rom_v <= 1'b1; end
    rom_q    <= sincos[ang_q];           // free-running synchronous read
    if (i_rst) hold <= 21'd0;
    else if (rom_v_d) hold <= {i_valid, rom_q};
end
always @(posedge i_clk) rom_v_d <= rom_v;

/* read the hold register 64 pixel clocks after the request (the copy
   completes within ~6 rx clocks = 60 ns; 64 pixel clocks = 430 ns) */
reg [6:0]  rd_cnt;
reg        rd_now;
always @(posedge i_pixClk) begin
    rd_now <= 1'b0;
    if (frame_start) rd_cnt <= 7'd1;
    else if (rd_cnt != 7'd0) begin
        rd_cnt <= rd_cnt + 7'd1;
        if (rd_cnt == 7'd64) begin rd_now <= 1'b1; rd_cnt <= 7'd0; end
    end
end

/*------------------------------------------------------------------*/
/* anchor: Q1.8 * R_MARK (pixel domain)                              */
/*------------------------------------------------------------------*/
(* ASYNC_REG = "TRUE" *) reg [20:0] sc;  // pixel-domain sample of hold
reg        sc_v, sc_v2;
reg signed [11:0] ax, ay;
reg [11:0] x0, x1, y0, y1;
reg        mk_valid;
wire signed [9:0] sc_sin = sc[19:10];
wire signed [9:0] sc_cos = sc[9:0];
always @(posedge i_pixClk) begin
    sc_v <= 1'b0; sc_v2 <= sc_v;
    if (rd_now) begin sc <= hold; sc_v <= 1'b1; end
    if (sc_v) begin
        ax <= 12'sd0 + CX + ((sc_cos * R_MARK) >>> 8);
        ay <= 12'sd0 + CY - ((sc_sin * R_MARK) >>> 8);
    end
    if (sc_v2) begin
        x0 <= ax - HALF; x1 <= ax + HALF + 1;
        y0 <= ay - HALF; y1 <= ay + HALF + 1;
        mk_valid <= sc[20];
    end
    if (i_rst_pix) mk_valid <= 1'b0;
end

/*------------------------------------------------------------------*/
/* per-pixel test, one register stage (matches the label pipeline   */
/* closely enough: a one-pixel shift of a 9x9 box is invisible)      */
/*------------------------------------------------------------------*/
always @(posedge i_pixClk)
    o_active <= mk_valid & i_video_de &
                (active_x >= x0) & (active_x < x1) &
                (active_y >= y0) & (active_y < y1);

endmodule
