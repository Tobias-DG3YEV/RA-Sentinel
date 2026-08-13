//////////////////////////////////////////////////////////////////////////////////
// polar_view.v
//
// Pixel-domain renderer for the direction-finding polar indicator. Draws a ray
// from the centre of a rectangular region for every populated entry of the angle
// table: the ray's direction is the bearing, its length is the signal amplitude
// at that bearing, and its colour is the FREQUENCY of the bin that produced it,
// through freqmap.v - blue at the low edge of the span, then green, yellow, red,
// violet at the high edge.
//
// Colour used to be the amplitude ramp (midmap.v, as the spectrum and waterfall
// use), which said nothing the ray's own length did not already say. Frequency
// is the axis the polar display otherwise throws away: it collapses 1024 bins
// onto one bearing, so without it a ray tells you a signal is over there but not
// which one it is. Colour reads straight across to the peak's position in the
// spectrum panes above.
//
// The region is the whole 1920x1080 screen in this design, which puts the
// indicator dead centre, over the point where the four spectrum panes meet, and
// spreads it across all four of them. Nothing in here assumes that - the region
// is just a bounding box, and the four-pane grid below it is screen.v's business
// entirely.
//
// HOW IT DRAWS RAYS WITHOUT A FRAMEBUFFER. Even a 960x540x8 framebuffer would be
// 4Mbit against ~26 free RAMB36 on the XC7A100T, so nothing is ever rasterised.
// Instead the polar transform is inverted: for each pixel the renderer computes
// its own (r, theta) from the centre with a CORDIC, looks up len[theta], and
// lights the pixel when r <= len. Cost is one CORDIC and a 512-entry table
// instead of a framebuffer, and it is exactly one pass over the pixels the
// video scan is walking anyway.
//
// TWO MASKS, NO OPAQUE REGION. This module never owns the pixels it sits on; it
// hands top.v two masks and lets it composite over whatever the spectra draw:
//
//   o_active  the pixels actually DRAWN - a ray, a range ring, the crosshair.
//             top.v alpha-blends the colour outputs here.
//   o_shade   everything out to the outer ring. top.v darkens the spectra here,
//             which is what lifts the indicator off a busy background. Strictly
//             wider than o_active, so a drawn pixel is always a shaded one and
//             the two never disagree about a pixel.
//
// Off both masks the colour outputs are driven black, but they are don't-care -
// nothing downstream looks at them. Claiming a whole pane opaque, which is what
// this module used to do, blanked a spectrum to black.
//
// ANGLE CONVENTION. The CORDIC's binary-turn angle is measured counter-clockwise
// from +x, and screen dy is built as (centre_y - active_y) so that +y is up. The
// DF engine feeds the table with X = A_east - A_west and Y = A_north - A_south,
// which lands in the SAME convention - so a source to the north gives Y>0, X~0,
// theta = 90deg, and the ray points up the screen. No offset or flip anywhere;
// the display reads like a map with north up.
//
// PIPELINE / LOOKAHEAD. The CORDIC plus the table read is LOOKAHEAD pixels deep,
// so the renderer is fed coordinates LOOKAHEAD pixels AHEAD of the beam and its
// result emerges exactly as the beam arrives.
//
// That feed is only meaningful while the beam is in active video. Through
// blanking active_x sits at 0, so the pipeline is primed with the coordinates of
// pixel LOOKAHEAD over and over, and those stale results emerge across the FIRST
// LOOKAHEAD pixels of the next line. Left alone that paints a LOOKAHEAD-wide
// stripe down the left edge of the screen wherever the stale radius happens to
// fall inside the disc. It is easy to miss because it depends on where the
// centre is: at CX = 1440 (the old bottom-right pane) the stale radius was 1419
// and nothing showed, at CX = 64 in the testbench it is 47 against an R_MAX of
// 48 and the whole stripe lights up. Both masks are therefore qualified with
// i_video_de as it was AT FEED TIME rather than with an argument about the
// geometry, and the module draws nothing instead of garbage - see de_fed_sr.
// The cost is that the leftmost
// LOOKAHEAD columns of the screen can never be drawn, which no sane centre and
// R_MAX come near.
//
// Dependencies: cordic_vec.v, freqmap.v
//////////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps

module polar_view #(
    parameter REG_X0  = 0,    // region origin on the 1920x1080 screen; the
    parameter REG_Y0  = 0,    // indicator is centred in this rectangle
    parameter REG_W   = 1920,
    parameter REG_H   = 1080,
    parameter R_MAX   = 256,  // full-scale ray length in pixels (amplitude 255)
    parameter STAGES  = 12,   // CORDIC stages; sets LOOKAHEAD, keep in step
    parameter CGUARD  = 10    // CORDIC guard bits
)(
    input  wire        i_pixClk,
    input  wire        i_rst,
    input  wire        i_video_hs,
    input  wire        i_video_vs,
    input  wire        i_video_de,

    output wire [8:0]  o_angAddr,  // angle table read address (512 bins)
    input  wire [7:0]  i_angLen,   // table data, REGISTERED (1 clock after addr)
    input  wire [7:0]  i_angFrq,   // ...and the winning bin's colour code

    output wire        o_active,   // drawn pixels: blend the colours here
    output wire        o_shade,    // inside the outer ring: darken the background
    output wire [7:0]  o_r, o_g, o_b
);

localparam CX = REG_X0 + REG_W/2;     // polar centre, screen coordinates
localparam CY = REG_Y0 + REG_H/2;

/* CORDIC magnitude carries the processing gain K = 1.64676 (see cordic_vec.v),
   so every radius compared against it is pre-scaled by K here rather than
   dividing the CORDIC output per pixel. K ~= 105/64 to 0.4%, which is a 4-term
   shift-add, no DSP. Amplitude maps 1:1 to pixels: 255 counts -> 255 px. */
localparam integer KNUM = 105;
localparam integer KDEN = 64;
localparam [13:0] R_MAX_K = (R_MAX * KNUM) / KDEN;

/* 1 (dx/dy into the CORDIC) + STAGES+1 (CORDIC) + 1 (table address register)
   + 1 (registered table output) + 1 (len scaling) + 1 (output register).
   The len-scaling stage exists purely for timing: the table read, the len*105
   add, the ray/ring compares, the colour map and the output mux together missed
   the 148.75MHz pixel clock. Splitting them costs one more pixel of constant
   horizontal shift, which is invisible. */
localparam LOOKAHEAD = STAGES + 5;

/****************************************************************************/
/* Local active-pixel tracking, same derivation as pane_overlay.v           */
/****************************************************************************/
reg de_prev, vs_prev;
always @(posedge i_pixClk) begin
    de_prev <= i_video_de;
    vs_prev <= i_video_vs;
end
wire line_start  = i_video_de & ~de_prev;
wire frame_start = ~vs_prev & i_video_vs;   // 1080p uses VS_POL=1, see video_define.v

reg [11:0] active_x, active_y;
always @(posedge i_pixClk) begin
    if (i_rst) begin
        active_x <= 12'd0;
        active_y <= 12'd0;
    end
    else begin
        if (!i_video_de) active_x <= 12'd0;
        else             active_x <= active_x + 12'd1;

        /* Reset to -1, not 0: frame_start fires during vertical blanking and
           the FIRST active line then increments into 0. Resetting to 0 would
           make the first active line read 1 and put the polar centre a line
           off. (pane_overlay.v has that one-line offset; it is harmless there
           and is left alone rather than perturbed.) */
        if (frame_start)     active_y <= 12'hFFF;
        else if (line_start) active_y <= active_y + 12'd1;
    end
end

/****************************************************************************/
/* Stage 1: offsets from the polar centre, LOOKAHEAD pixels ahead of the beam*/
/****************************************************************************/
wire signed [12:0] dx_la = $signed({1'b0, active_x}) + LOOKAHEAD - CX;
wire signed [12:0] dy_la = CY - $signed({1'b0, active_y});

wire [13:0] cd_mag;
wire [15:0] cd_ang;

cordic_vec #(.XYW(13), .STAGES(STAGES), .GUARD(CGUARD)) cordic_pix (
    .i_clk(i_pixClk),
    .i_ce(1'b1),
    .i_valid(1'b1),
    .i_x(dx_la),
    .i_y(dy_la),
    .o_mag(cd_mag),
    .o_ang(cd_ang),
    .o_valid()
);

/****************************************************************************/
/* Stage 2: issue the table read, carrying the radius alongside it          */
/****************************************************************************/
reg [8:0]  ang_idx_r;
reg [13:0] mag_r1, mag_r2;
always @(posedge i_pixClk) begin
    ang_idx_r <= cd_ang[15:7];   // 512 angle bins, 0.703deg each
    mag_r1    <= cd_mag;
    mag_r2    <= mag_r1;         // realigns with the registered table output
end
assign o_angAddr = ang_idx_r;

/****************************************************************************/
/* Stage 3: ray / graticule test and colour                                 */
/****************************************************************************/
/* len * 105 >> 6, i.e. the ray length scaled into CORDIC magnitude units.
   255 * 105 = 26775 fits in 16 bits; >> 6 gives 418, matching K * 255 = 420.
   Registered into its own stage - see the LOOKAHEAD note above. */
wire [15:0] len_k16 = ({8'd0, i_angLen} << 6) + ({8'd0, i_angLen} << 5) +
                      ({8'd0, i_angLen} << 3) +  {8'd0, i_angLen};

reg  [13:0] len_k;
reg  [7:0]  len_r;
reg  [7:0]  frq_r;
reg  [13:0] mag_r3;
always @(posedge i_pixClk) begin
    len_k  <= {4'd0, len_k16[15:6]};
    len_r  <= i_angLen;
    frq_r  <= i_angFrq;    // same stage as len_r, so it stays in step with it
    mag_r3 <= mag_r2;
end

wire in_circle = (mag_r3 <= R_MAX_K);
wire on_ray    = in_circle && (len_r != 8'd0) && (mag_r3 <= len_k);

/* Graticule: four range rings at 1/4, 1/2, 3/4 and full scale plus a centred
   crosshair. The ring test uses a 2-unit window on the K-scaled radius, which
   is ~1.2 pixels wide - thin, and it never disappears through quantisation. */
localparam [13:0] RING1 = (R_MAX * KNUM) / (KDEN * 4);
localparam [13:0] RING2 = (R_MAX * KNUM) / (KDEN * 2);
localparam [13:0] RING3 = (R_MAX * 3 * KNUM) / (KDEN * 4);

wire on_ring = ((mag_r3 >= RING1)   && (mag_r3 < RING1   + 14'd2)) ||
               ((mag_r3 >= RING2)   && (mag_r3 < RING2   + 14'd2)) ||
               ((mag_r3 >= RING3)   && (mag_r3 < RING3   + 14'd2)) ||
               ((mag_r3 >= R_MAX_K) && (mag_r3 < R_MAX_K + 14'd2));

/* The crosshair needs the pixel's own dx/dy, delayed to line up with mag_r2.
   Only the zero test survives the delay, so carry the comparisons, not the
   values. Depth: dx_la is computed during the cycle where active_x = t and
   describes position t+LOOKAHEAD; it must be combinationally available in the
   cycle that FEEDS the output register, i.e. t+LOOKAHEAD-1. A shift register
   entry sr[j] is valid j+1 cycles after its input, so j = LOOKAHEAD-2. */
reg [LOOKAHEAD-2:0] dx_zero_sr, dy_zero_sr;
always @(posedge i_pixClk) begin
    dx_zero_sr <= {dx_zero_sr[LOOKAHEAD-3:0], (dx_la == 13'sd0)};
    dy_zero_sr <= {dy_zero_sr[LOOKAHEAD-3:0], (dy_la == 13'sd0)};
end
wire on_cross = in_circle && (dx_zero_sr[LOOKAHEAD-2] | dy_zero_sr[LOOKAHEAD-2]);

/* Was the beam in active video when THIS pixel's coordinates were fed? If not,
   active_x was parked at 0 and the CORDIC re-computed pixel LOOKAHEAD instead
   (see the lookahead note in the header). Same depth argument as the crosshair
   shift registers above: sampled in the cycle dx_la is computed, read back in
   the cycle that feeds the output register, so index LOOKAHEAD-2. */
reg [LOOKAHEAD-2:0] de_fed_sr;
always @(posedge i_pixClk)
    de_fed_sr <= {de_fed_sr[LOOKAHEAD-3:0], i_video_de};
wire fed_active = de_fed_sr[LOOKAHEAD-2];

/* Frequency, not amplitude - see the header. freqmap is arithmetic rather than
   midmap's 3x256-byte ROM, so this also takes logic out of the pixel path. */
wire [7:0] rayR, rayG, rayB;
freqmap freqmap_ray (
    .i_freq(frq_r),
    .o_r(rayR), .o_g(rayG), .o_b(rayB)
);

/* The shaded disc: everything the background is darkened under. Taken out to
   the far edge of the outermost ring rather than to R_MAX_K, so the ring sits
   ON the veil instead of half a pixel off it - which also makes o_shade a
   strict superset of the drawn pixels, so top.v never has to composite a drawn
   pixel over an unshaded background. */
wire in_shade = (mag_r3 < R_MAX_K + 14'd2);

/* Region membership needs NO lookahead delay - active_x already tracks the
   beam, so it is only the output register that has to be compensated for.
   Evaluating membership at active_x+1 and registering it once lands it on
   exactly the pixel the colour registers describe, in step with the mask terms
   it is ANDed with below. */
wire [11:0] ax_next = active_x + 12'd1;

/* A guard, not a feature: every mask term below is already gated on the CORDIC
   radius, and R_MAX is inset far inside the region (256 against a 1920x1080
   screen), so this never actually clips anything. It is what makes that
   containment a property of the module instead of a coincidence of the
   geometry someone instantiates it with. */
wire in_region_next = (ax_next  >= REG_X0) && (ax_next  < REG_X0 + REG_W) &&
                      (active_y >= REG_Y0) && (active_y < REG_Y0 + REG_H);

wire      drawn = on_ray | on_ring | on_cross;

reg [7:0] px_r, px_g, px_b;
reg       px_active, px_shade;
always @(posedge i_pixClk) begin
    /* Drawn pixels only - everything else belongs to the spectra underneath,
       either darkened (px_shade) or untouched. */
    px_active <= in_region_next & fed_active & drawn;
    px_shade  <= in_region_next & fed_active & in_shade;
    if (on_ray) begin                  // rays draw over the graticule
        px_r <= rayR;
        px_g <= rayG;
        px_b <= rayB;
    end
    else if (on_ring || on_cross) begin
        px_r <= 8'h30;
        px_g <= 8'h30;
        px_b <= 8'h30;
    end
    else begin
        px_r <= 8'h00;
        px_g <= 8'h00;
        px_b <= 8'h00;
    end
end

assign o_active = px_active;
assign o_shade  = px_shade;
assign o_r = px_r;
assign o_g = px_g;
assign o_b = px_b;

endmodule
