//////////////////////////////////////////////////////////////////////////////////
//
// Design Name: OWIFI_RX
// Module Name: polar_labels
// Project Name: RA-Sentinel 802.11 receiver + direction finder
// Target Devices: Artix 7, XC7A100T (RASBB U10)
// Description:
//   MAC-address labels around the polar DF disc: each listed station's SA is
//   drawn as 12 hex glyphs just OUTSIDE the outer range ring, at that
//   station's AVERAGED bearing, tinted with the station's own hashed colour
//   from the station list - so ray, list line and rim label all read as one
//   transmitter. A station not heard for EXPIRE_S seconds fades out (its
//   slot frees).
//
//   RECEIVER SIDE (i_clk): frame_log pulses one station event per admitted
//   frame ({SA, colour, bearing, FCS verdict}); the event updates a small
//   slot table - matched by MAC, else it takes a free slot, else it evicts
//   the oldest.
//
//   BEARING SMOOTHING. The per-frame amplitude bearing is noisy (several
//   degrees even on a strong station), and a label that jumps with every
//   frame is unreadable. Each slot therefore keeps an exponential moving
//   average of its bearing in Q9.3 (12 bits = one full circle, so the
//   plain mod-4096 subtraction IS the shortest-way circular difference -
//   359 deg -> 1 deg averages through 0, never the long way round). A slot
//   folds in at most ONE sample per EMA_TICK (312.5ms) with weight 1/2^k
//   (k = i_brg_shift for the bearing, i_ph_shift for the phase dot -
//   DISP_CTRL [6:4] / [14:12]; 4 = the historical 1/16),
//   so a chatty station converges with tau ~= 5s of wall time and a quiet
//   one with tau = 16 of its frames. FCS: with BAD_FCS=1 (default since
//   2026-09-25) every event with a confident bearing (brg_ok) moves the
//   average, FCS-bad ones included - the bearing and the phase come from
//   the preamble, which a payload bit error does not touch, and frame_log
//   only passes an FCS-bad frame on when its SA is already in the list
//   (seen with a good FCS), so the MAC it is filed under is a valid one.
//   BAD_FCS=0 restores the old rule: only FCS-OK frames move the average,
//   a bad one just refreshes the label's age. A station's FIRST appearance
//   seeds the average directly.
//
//   The averaged bearing indexes a 512-entry sin/cos ROM (Q1.8,
//   sincos512.mem) and the label anchor lands at radius R_LAB from the
//   disc centre; the text box hangs off the anchor away from the disc
//   (right of it on the east half, left of it on the west half), so it
//   can never cross the rings.
//   With the geometry of system_top_wbmc (centre 960,620, R_LAB 340, box
//   96x16) every box provably stays inside x 518..1402, y 272..984 - on
//   screen and clear of the station list (y < 160) - so no clipping logic
//   is needed or present.
//
//   PIXEL SIDE: the slot table is sampled into shadow registers once per
//   frame at vsync; a slot updating in exactly that cycle can tear ONE
//   video frame's label - the same accepted single-frame-tear class as
//   RASPMO's wf_row_snap. Rendering is sprite-style: per pixel, an 8-way
//   box test picks the (lowest-index) hit slot, then nibble -> glyph ->
//   font row -> pixel bit, in a 3-stage pipeline. The 3px constant right
//   shift this gives a free-floating label is invisible; nothing else on
//   screen is aligned to it.
//
//   PHASE DOTS (2026-09-25). Each slot also keeps its station's J2-vs-J1
//   phase (the frame's calibrated phase from the capture engine, as an
//   angle bin - what the single rim marker used to show for whichever frame
//   came last) as the same kind of circular EMA, updated by frames with a
//   valid phase (FCS-bad ones too unless BAD_FCS=0), seeded by the first
//   one. A (2*DOT_HALF+1)^2
//   square in the station's colour sits at radius R_DOT at that angle, so
//   every listed station has its own steady dot. The single marker could
//   never show a client: the AP's ACK follows every client frame within
//   microseconds and moved it straight back; ACKs carry no SA and never
//   reach the station list, so they cannot move anyone's dot. Dots win
//   over label text where the two overlap.
//   The font is text_screen's font8x16.mem, read into its own ROM here
//   (glyph = ASCII - 0x20; hex digits live at 0x10..0x19 and 0x21..0x26).
//   Both $readmem files resolve against the TOOL's working directory - the
//   build passes OWIFI_SRC-based paths, same trap as everywhere else.
//
// Dependencies: font8x16.mem, sincos512.mem (tools/gen via python, checked in)
//
// Additional Comments: https://github.com/Tobias-DG3YEV/RA-Sentinel
//
//////////////////////////////////////////////////////////////////////////////////
// Copyright (C) 2026 Tobias Weber
// License: GNU GPL v3
//////////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps

module polar_labels #(
    parameter CX          = 448,   // disc centre, screen coordinates
    parameter CY          = 540,
    parameter R_LAB       = 272,   // label anchor radius (outside the rings)
    parameter NSLOT       = 8,
    parameter R_DOT       = 264,   // phase dot centre radius (between the rings and the labels)
    parameter DOT_HALF    = 4,     // dot = (2*DOT_HALF+1) pixels square
    parameter [3:0] EXPIRE_S = 4'd10,
    parameter BAD_FCS     = 1,     // 1: FCS-bad events move bearing and phase too; 0: FCS-OK only
    parameter FONT_FILE   = "font8x16.mem",
    parameter SINCOS_FILE = "sincos512.mem"
)(
    /* receiver domain */
    input  wire        i_clk,
    input  wire        i_rst,
    input  wire        i_us_tick,
    input  wire        i_sta_stb,     // one pulse per admitted frame
    input  wire [47:0] i_sta_mac,
    input  wire [11:0] i_sta_rgb,
    input  wire [8:0]  i_sta_brg,     // angle table index, CCW from east
    input  wire        i_sta_brg_ok,
    input  wire        i_sta_fcs,     // frame's FCS verdict (see smoothing)
    input  wire [8:0]  i_sta_ph,      // frame's calibrated J2-vs-J1 phase, angle bin CCW from east
    input  wire        i_sta_ph_ok,
    input  wire        i_bad_fcs,     // run-time switch of BAD_FCS (1 = as BAD_FCS, 0 = FCS-OK frames only)
    input  wire [2:0]  i_brg_shift,   // bearing (label position) EMA weight 1/2^k (4 = the historical 1/16, 0 = none)
    input  wire [2:0]  i_ph_shift,    // the same for the phase dot

    /* pixel domain */
    input  wire        i_pixClk,
    input  wire        i_rst_pix,
    input  wire        i_video_vs,
    input  wire        i_video_de,
    output wire        o_active,
    output wire [7:0]  o_r, o_g, o_b
);

localparam BOX_W = 96;   // 12 glyphs x 8px
localparam BOX_H = 16;

/****************************************************************************/
/* sin/cos ROM: {sin[9:0], cos[9:0]} signed Q1.8 per angle bin              */
/****************************************************************************/
(* rom_style = "block" *) reg [19:0] sincos [0:511];
initial $readmemh(SINCOS_FILE, sincos);

/****************************************************************************/
/* Slot table, receiver domain                                              */
/****************************************************************************/
reg [47:0] slot_mac [0:NSLOT-1];
reg [11:0] slot_rgb [0:NSLOT-1];
reg [11:0] slot_x0  [0:NSLOT-1];
reg [11:0] slot_y0  [0:NSLOT-1];
reg [11:0] slot_brg [0:NSLOT-1];    // averaged bearing, Q9.3 circular
reg [NSLOT-1:0] slot_valid;
reg [3:0]  slot_age [0:NSLOT-1];
reg [11:0] slot_ph  [0:NSLOT-1];    // averaged phase, Q9.3 circular
reg [11:0] slot_dx0 [0:NSLOT-1];    // phase dot, top-left corner
reg [11:0] slot_dy0 [0:NSLOT-1];
reg [NSLOT-1:0] slot_ph_ok;         // the slot has a phase (and a dot)

/* 1Hz tick for ageing */
reg [19:0] sec_div;
reg        sec_tick;
always @(posedge i_clk) begin
    if (i_rst) begin
        sec_div  <= 20'd0;
        sec_tick <= 1'b0;
    end
    else begin
        sec_tick <= 1'b0;
        if (i_us_tick) begin
            if (sec_div == 20'd999999) begin
                sec_div  <= 20'd0;
                sec_tick <= 1'b1;
            end
            else
                sec_div <= sec_div + 20'd1;
        end
    end
end

/* EMA sample gate: every EMA_TICK_US the whole table re-arms, and each slot
   folds in at most one bearing sample until the next arm - so the average's
   time constant is wall-clock (16 x 312.5ms ~= 5s) for stations heard
   faster than the tick, and 16 own-frames for slower ones. */
localparam [18:0] EMA_TICK_US = 19'd312499;
reg [18:0] ema_div;
reg [NSLOT-1:0] tick_ok;
reg [NSLOT-1:0] ph_tick_ok;         // the phase EMA's own arm, same tick

/* event pipeline: latch -> MAC match -> slot resolve -> bearing EMA ->
   ROM read -> position -> slot write. One event in flight is enough -
   frames are tens of microseconds apart at minimum, the pipeline is 7. */
reg        e1_v, e2_v, e3_v, e4_v, e5_v, e6_v, e7_v;
reg [47:0] e_mac;
reg [11:0] e_rgb;
reg        e_brg_ok;
reg        e_fcs;
reg [8:0]  e_brg;
reg [8:0]  e_ph;
reg        e_ph_ok;
reg [19:0] e_sc;                    // ROM data
reg [19:0] e_sc2;                   // ROM data, phase angle (second read port)
reg signed [11:0] e_dx, e_dy;       // phase dot corner
reg [11:0] ph_avg_r;                // this event's (possibly updated) phase average
reg        ph_wr_r;                 // and whether it may write phase/dot
reg signed [11:0] e_ax, e_ay;       // anchor
reg        e_cos_pos;
reg [11:0] avg_r;                   // this event's (possibly updated) average
reg        brg_wr_r;                // and whether it may write position/bearing

wire signed [9:0] sc_sin = e_sc[19:10];
wire signed [9:0] sc_cos = e_sc[9:0];
wire signed [9:0] sc2_sin = e_sc2[19:10];
wire signed [9:0] sc2_cos = e_sc2[9:0];

always @(posedge i_clk) begin
    if (i_rst) begin
        e1_v <= 1'b0; e2_v <= 1'b0; e3_v <= 1'b0; e4_v <= 1'b0;
        e5_v <= 1'b0; e6_v <= 1'b0; e7_v <= 1'b0;
    end
    else begin
        /* s1: latch the event */
        e1_v <= i_sta_stb;
        if (i_sta_stb) begin
            e_mac    <= i_sta_mac;
            e_rgb    <= i_sta_rgb;
            e_brg_ok <= i_sta_brg_ok;
            e_fcs    <= i_sta_fcs;
            e_brg    <= i_sta_brg;
            e_ph     <= i_sta_ph;
            e_ph_ok  <= i_sta_ph_ok;
        end

        /* s2: match_v registers (own block below) */
        e2_v <= e1_v;

        /* s3: wr_idx_r/hit_any_r register (own block below) */
        e3_v <= e2_v;

        /* s4: avg_r/brg_wr_r register (own block below) */
        e4_v <= e3_v;

        /* s5: ROM data registered; the address (avg_r) holds from s4 */
        e5_v <= e4_v;
        e_sc <= sincos[avg_r[11:3]];
        e_sc2 <= sincos[ph_avg_r[11:3]];    // second read port of the same ROM

        /* s6: anchor from the Q1.8 pair; constant-by-R_LAB multiplies reduce
           to shift-adds. Screen y grows downward, angle convention has +y
           up, hence the subtraction - same as polar_view. */
        e6_v <= e5_v;
        e_ax <= 12'sd0 + CX + ((sc_cos * R_LAB) >>> 8);
        e_ay <= 12'sd0 + CY - ((sc_sin * R_LAB) >>> 8);
        e_cos_pos <= ~sc_cos[9];
        e_dx <= 12'sd0 + CX + ((sc2_cos * R_DOT) >>> 8) - DOT_HALF;
        e_dy <= 12'sd0 + CY - ((sc2_sin * R_DOT) >>> 8) - DOT_HALF;

        /* s7: box_x0_r/box_y0_r register (below); commit happens at e7_v */
        e7_v <= e6_v;
    end
end

/* box position: hang the text off the anchor, away from the disc */
wire [11:0] box_x0 = e_cos_pos ? (e_ax + 12'sd6) : (e_ax - 12'sd6 - BOX_W);
wire [11:0] box_y0 = e_ay - 12'sd8;

/* Slot match / allocation, PIPELINED alongside the event pipeline - the
   single-cycle scan (8x 48-bit equality + a serial oldest-age chain) was 17
   logic levels and missed 100MHz by 1.3ns. An event has microseconds of
   slack, so: the MAC match vector registers with s2, the allocation
   decision with s3, and the commit happens at s7 (after the bearing EMA,
   trig lookup and anchor stages in between). Only one event is
   ever in flight, so nothing can move under the pipeline; an age tick
   landing between decision and commit at worst re-crowns the same oldest
   slot one second early - harmless. */
reg [NSLOT-1:0] match_v;      // registered with e2_v
reg [2:0]       wr_idx_r;     // registered with e3_v
reg             hit_any_r;
reg [11:0]      box_x0_r, box_y0_r;

integer k;
always @(posedge i_clk) begin
    for (k = 0; k < NSLOT; k = k + 1)
        match_v[k] <= slot_valid[k] && (slot_mac[k] == e_mac);
end

/* s3 companions: encode the match vector, else a free slot, else the oldest
   (pairwise max tree, index carried alongside) */
reg [2:0] hit_idx,  free_idx;
reg       free_any;
integer m;
always @* begin
    hit_idx  = 3'd0;
    free_any = 1'b0; free_idx = 3'd0;
    for (m = NSLOT-1; m >= 0; m = m - 1) begin
        if (match_v[m])      hit_idx  = m[2:0];
        if (!slot_valid[m]) begin
            free_any = 1'b1; free_idx = m[2:0];
        end
    end
end

wire [3:0] a01 = (slot_age[1] > slot_age[0]) ? slot_age[1] : slot_age[0];
wire [2:0] i01 = (slot_age[1] > slot_age[0]) ? 3'd1 : 3'd0;
wire [3:0] a23 = (slot_age[3] > slot_age[2]) ? slot_age[3] : slot_age[2];
wire [2:0] i23 = (slot_age[3] > slot_age[2]) ? 3'd3 : 3'd2;
wire [3:0] a45 = (slot_age[5] > slot_age[4]) ? slot_age[5] : slot_age[4];
wire [2:0] i45 = (slot_age[5] > slot_age[4]) ? 3'd5 : 3'd4;
wire [3:0] a67 = (slot_age[7] > slot_age[6]) ? slot_age[7] : slot_age[6];
wire [2:0] i67 = (slot_age[7] > slot_age[6]) ? 3'd7 : 3'd6;
wire [3:0] a03 = (a23 > a01) ? a23 : a01;
wire [2:0] i03 = (a23 > a01) ? i23 : i01;
wire [3:0] a47 = (a67 > a45) ? a67 : a45;
wire [2:0] i47 = (a67 > a45) ? i67 : i45;
wire [2:0] old_idx = (a47 > a03) ? i47 : i03;

always @(posedge i_clk) begin
    hit_any_r <= |match_v;
    wr_idx_r  <= (|match_v) ? hit_idx : (free_any ? free_idx : old_idx);
end

/* s4: circular EMA on the resolved slot's bearing. Both operands are Q9.3
   with 4096 = one full turn, so the plain mod-4096 subtraction, read as
   signed, is already the shortest-way angular difference; >>> 4 is the
   1/16 weight. A miss (new/evicted slot) seeds the average with the raw
   measurement; a hit folds the sample in only when the bearing passed its
   confidence gate, this slot's tick is armed AND (BAD_FCS=0 only) the
   frame's FCS was OK - otherwise the average (and the label position)
   stays put. */
wire [11:0]        cur_avg  = slot_brg[wr_idx_r];
wire [11:0]        tgt_q3   = {e_brg, 3'b000};
wire signed [11:0] brg_diff = tgt_q3 - cur_avg;
wire signed [11:0] brg_step = brg_diff >>> i_brg_shift;     // 1/2^k weight, DISP_CTRL [6:4]
wire [11:0]        ema_next = cur_avg + brg_step;
wire               fcs_use  = e_fcs || (BAD_FCS != 0 && i_bad_fcs);
wire               ema_upd  = e_brg_ok && fcs_use && tick_ok[wr_idx_r];

always @(posedge i_clk) begin
    if (e3_v) begin
        avg_r    <= hit_any_r ? (ema_upd ? ema_next : cur_avg) : tgt_q3;
        brg_wr_r <= hit_any_r ? ema_upd : e_brg_ok;
    end
end

/* s4, phase: the same circular EMA on the slot's phase. A slot without a
   phase yet (new, evicted, or never had a valid one) is seeded by the
   first frame that carries a phase (an FCS-OK one if BAD_FCS=0). */
wire [11:0]        cur_ph   = slot_ph[wr_idx_r];
wire [11:0]        ph_q3    = {e_ph, 3'b000};
wire signed [11:0] ph_diff  = ph_q3 - cur_ph;
wire signed [11:0] ph_step  = ph_diff >>> i_ph_shift;        // DISP_CTRL [14:12]
wire [11:0]        ph_next  = cur_ph + ph_step;
wire               ph_have  = hit_any_r && slot_ph_ok[wr_idx_r];
wire               ph_upd   = e_ph_ok && fcs_use && ph_tick_ok[wr_idx_r];

always @(posedge i_clk) begin
    if (e3_v) begin
        ph_avg_r <= ph_have ? (ph_upd ? ph_next : cur_ph) : ph_q3;
        ph_wr_r  <= ph_have ? ph_upd : (e_ph_ok && fcs_use);
    end
end

always @(posedge i_clk) begin
    if (i_rst) begin
        ema_div <= 19'd0;
        tick_ok <= {NSLOT{1'b1}};
        ph_tick_ok <= {NSLOT{1'b1}};
    end
    else begin
        if (i_us_tick) begin
            if (ema_div == EMA_TICK_US) begin
                ema_div <= 19'd0;
                tick_ok <= {NSLOT{1'b1}};
                ph_tick_ok <= {NSLOT{1'b1}};
            end
            else
                ema_div <= ema_div + 19'd1;
        end
        /* consume this slot's arm the moment its sample is accepted (the
           later assignment wins over a same-cycle re-arm, which only means
           that slot waits one extra tick - harmless) */
        if (e3_v && hit_any_r && ema_upd)
            tick_ok[wr_idx_r] <= 1'b0;
        if (e3_v && ph_have && ph_upd)
            ph_tick_ok[wr_idx_r] <= 1'b0;
    end
end

integer k2;
always @(posedge i_clk) begin
    if (i_rst) begin
        slot_valid <= {NSLOT{1'b0}};
        slot_ph_ok <= {NSLOT{1'b0}};
    end
    else begin
        box_x0_r <= box_x0;
        box_y0_r <= box_y0;

        if (e7_v) begin
            /* a known station refreshes even without an accepted bearing
               sample (position keeps its averaged value); an unknown one
               needs a valid bearing to earn a slot at all. */
            if (hit_any_r || e_brg_ok) begin
                slot_mac[wr_idx_r]   <= e_mac;
                slot_rgb[wr_idx_r]   <= e_rgb;
                slot_age[wr_idx_r]   <= 4'd0;
                slot_valid[wr_idx_r] <= 1'b1;
                if (brg_wr_r) begin
                    slot_brg[wr_idx_r] <= avg_r;
                    slot_x0[wr_idx_r]  <= box_x0_r;
                    slot_y0[wr_idx_r]  <= box_y0_r;
                end
                /* a new occupant starts without a phase unless this frame
                   brings one (the later assignment wins) */
                if (!hit_any_r)
                    slot_ph_ok[wr_idx_r] <= 1'b0;
                if (ph_wr_r) begin
                    slot_ph[wr_idx_r]    <= ph_avg_r;
                    slot_dx0[wr_idx_r]   <= e_dx;
                    slot_dy0[wr_idx_r]   <= e_dy;
                    slot_ph_ok[wr_idx_r] <= 1'b1;
                end
            end
        end
        else if (sec_tick) begin
            for (k2 = 0; k2 < NSLOT; k2 = k2 + 1) begin
                if (slot_valid[k2]) begin
                    if (slot_age[k2] >= EXPIRE_S)
                        slot_valid[k2] <= 1'b0;
                    else
                        slot_age[k2] <= slot_age[k2] + 4'd1;
                end
            end
        end
    end
end

/****************************************************************************/
/* Pixel domain: per-frame shadow of the slots (single-frame tear accepted, */
/* see header), coordinate tracking, sprite pipeline.                       */
/****************************************************************************/
reg vs_prev, de_prev;
always @(posedge i_pixClk) begin
    vs_prev <= i_video_vs;
    de_prev <= i_video_de;
end
wire frame_start = ~vs_prev & i_video_vs;   // VS_POL=1 at 1080p
wire line_start  = i_video_de & ~de_prev;

reg [11:0] active_x, active_y;
always @(posedge i_pixClk) begin
    if (i_rst_pix) begin
        active_x <= 12'd0;
        active_y <= 12'd0;
    end
    else begin
        if (!i_video_de) active_x <= 12'd0;
        else             active_x <= active_x + 12'd1;
        if (frame_start)     active_y <= 12'hFFF;   // first line increments to 0
        else if (line_start) active_y <= active_y + 12'd1;
    end
end

/* Shadow of the slots, with the box END coordinates precomputed here so the
   per-pixel test is four bare comparators, no adders. */
reg [47:0] sh_mac [0:NSLOT-1];
reg [11:0] sh_rgb [0:NSLOT-1];
reg [11:0] sh_x0  [0:NSLOT-1];
reg [11:0] sh_x1  [0:NSLOT-1];
reg [11:0] sh_y0  [0:NSLOT-1];
reg [11:0] sh_y1  [0:NSLOT-1];
reg [NSLOT-1:0] sh_valid;
reg [11:0] sh_dx0 [0:NSLOT-1];
reg [11:0] sh_dx1 [0:NSLOT-1];
reg [11:0] sh_dy0 [0:NSLOT-1];
reg [11:0] sh_dy1 [0:NSLOT-1];
reg [NSLOT-1:0] sh_ph_ok;
localparam DOT_W = 2 * DOT_HALF + 1;
integer s;
always @(posedge i_pixClk) begin
    if (frame_start) begin
        sh_valid <= slot_valid;
        sh_ph_ok <= slot_ph_ok;
        for (s = 0; s < NSLOT; s = s + 1) begin
            sh_mac[s] <= slot_mac[s];
            sh_rgb[s] <= slot_rgb[s];
            sh_x0[s]  <= slot_x0[s];
            sh_x1[s]  <= slot_x0[s] + BOX_W;
            sh_y0[s]  <= slot_y0[s];
            sh_y1[s]  <= slot_y0[s] + BOX_H;
            sh_dx0[s] <= slot_dx0[s];
            sh_dx1[s] <= slot_dx0[s] + DOT_W;
            sh_dy0[s] <= slot_dy0[s];
            sh_dy1[s] <= slot_dy0[s] + DOT_W;
        end
    end
end

/* Stage 0: per-slot in-box bits, registered - the single-cycle version of
   the 8-way test plus the 48-bit winner mux missed the pixel clock. The
   extra stage just shifts every label one more pixel right; free-floating
   text does not care. */
reg [NSLOT-1:0] inbox_r;
reg [NSLOT-1:0] indot_r;
reg [6:0]  ax_d;
reg [3:0]  ay_d;
reg        de_d0;
integer b;
always @(posedge i_pixClk) begin
    for (b = 0; b < NSLOT; b = b + 1) begin
        inbox_r[b] <= sh_valid[b] &&
                      (active_x >= sh_x0[b]) && (active_x < sh_x1[b]) &&
                      (active_y >= sh_y0[b]) && (active_y < sh_y1[b]);
        indot_r[b] <= sh_valid[b] && sh_ph_ok[b] &&
                      (active_x >= sh_dx0[b]) && (active_x < sh_dx1[b]) &&
                      (active_y >= sh_dy0[b]) && (active_y < sh_dy1[b]);
    end
    ax_d  <= active_x[6:0];
    ay_d  <= active_y[3:0];
    de_d0 <= i_video_de;
end

/* stage 1: lowest hit slot wins; relative coordinates via mod-128/16
   subtraction of the winner's origin (difference is < box size on a hit) */
reg        p1_hit;
reg [47:0] p1_mac;
reg [11:0] p1_rgb;
reg [6:0]  p1_rx;
reg [3:0]  p1_ry;
reg        p1_de;

reg [2:0]  c_idx;
integer c;
always @* begin
    c_idx = 3'd0;
    for (c = NSLOT-1; c >= 0; c = c - 1)
        if (inbox_r[c]) c_idx = c[2:0];
end

always @(posedge i_pixClk) begin
    p1_hit <= (|inbox_r) & de_d0;
    p1_mac <= sh_mac[c_idx];
    p1_rgb <= sh_rgb[c_idx];
    p1_rx  <= ax_d - sh_x0[c_idx][6:0];
    p1_ry  <= ay_d - sh_y0[c_idx][3:0];
    p1_de  <= de_d0;
end

/* stage 2: nibble -> glyph -> font address */
wire [3:0] nib_idx = p1_rx[6:3];                       // 0..11
wire [3:0] nib     = p1_mac[(4'd11 - nib_idx)*4 +: 4]; // first SA byte first

/* glyph = ASCII-0x20: '0'..'9' -> 0x10.., 'A'..'F' -> 0x21.. */
wire [5:0] glyph = (nib < 4'd10) ? (6'h10 + {2'd0, nib})
                                 : (6'h21 + {2'd0, nib} - 6'd10);

reg        p2_hit;
reg [11:0] p2_rgb;
reg [2:0]  p2_px;
reg [9:0]  font_addr;
always @(posedge i_pixClk) begin
    p2_hit    <= p1_hit & p1_de;
    p2_rgb    <= p1_rgb;
    p2_px     <= p1_rx[2:0];
    font_addr <= {glyph, p1_ry};
end

/* stage 3: font row */
(* rom_style = "block" *) reg [7:0] font [0:1023];
initial $readmemh(FONT_FILE, font);

reg [7:0]  font_q;
reg        p3_hit;
reg [11:0] p3_rgb;
reg [2:0]  p3_px;
always @(posedge i_pixClk) begin
    font_q <= font[font_addr];
    p3_hit <= p2_hit;
    p3_rgb <= p2_rgb;
    p3_px  <= p2_px;
end

/* phase dots: lowest hit slot wins, delayed through three stages to line up
   with the label pipeline's stage 3 */
reg [2:0]  d_idx;
integer dd;
always @* begin
    d_idx = 3'd0;
    for (dd = NSLOT-1; dd >= 0; dd = dd - 1)
        if (indot_r[dd]) d_idx = dd[2:0];
end
reg        d1_hit, d2_hit, d3_hit;
reg [11:0] d1_rgb, d2_rgb, d3_rgb;
always @(posedge i_pixClk) begin
    d1_hit <= (|indot_r) & de_d0;
    d1_rgb <= sh_rgb[d_idx];
    d2_hit <= d1_hit; d2_rgb <= d1_rgb;
    d3_hit <= d2_hit; d3_rgb <= d2_rgb;
end

/* output: pixel bit + nibble-replicated colour, registered; a dot wins */
wire      txt_px = p3_hit & font_q[3'd7 - p3_px];
wire [11:0] px_rgb = d3_hit ? d3_rgb : p3_rgb;
reg       out_active;
reg [7:0] out_r, out_g, out_b;
always @(posedge i_pixClk) begin
    out_active <= d3_hit | txt_px;
    out_r <= {px_rgb[11:8], px_rgb[11:8]};
    out_g <= {px_rgb[7:4],  px_rgb[7:4]};
    out_b <= {px_rgb[3:0],  px_rgb[3:0]};
end

assign o_active = out_active;
assign o_r = out_r;
assign o_g = out_g;
assign o_b = out_b;

endmodule
