//////////////////////////////////////////////////////////////////////////////////
// pane_overlay.v
//
// Per-pane readout overlay for the quad-split display (successor of the
// full-screen digit_overlay.v). One instance per 960x540 pane renders, in
// 7-segment-style glyphs:
//
//   - the averaged ADC level "PPPP -DD" (white) in the pane's top-left corner:
//     PPPP is the linear amplitude of the largest |sample| of an FFT frame,
//     averaged over that channel's last 4096 frames, in ADC LSB (0..2047);
//     -DD is the same value as a level below full scale, 20*log10(2048/PPPP),
//     i.e. 0 dB = a sample hitting the 12-bit 2's-complement rail. Both come
//     from top.v (adc_avg_peak / adc_db_mag). The panes are identified by
//     their position in the 2x2 grid, so no channel-ID digit is drawn.
//   - two bit-errors-per-second numbers (orange) along the bottom of the
//     spectrum band: left = this channel's I lane, right = Q lane. Rates are
//     derived here as deltas between successive 1s-latched ramp-checker
//     bit-error counts, leading-zero blanked. Only meaningful during
//     RASRF2400BMC's ADC ramp-test mode, harmless noise otherwise - and
//     normally compiled out (see SHOW_BER_RATES in top.v).
//
// Rendering is a 3-stage pixel pipeline (position -> zone/digit/segments ->
// segment rasterization) and all slow-changing values (BCD digits, blanking
// masks) are pre-registered - the naive combinational version missed timing
// at the 148.75MHz 1080p pixel clock by several ns. The pipeline shifts the
// glyphs 3 pixels right of their nominal coordinates, which is invisible.
//
// Self-contained: derives its own active-pixel (x,y) position from
// video_hs/vs/de rather than touching screen.v; top.v ORs the four instances'
// outputs over the video. The counter inputs live in the ADC clock domain
// while this runs on the pixel clock; they are only sampled once per second,
// so occasional single-update CDC tearing is cosmetic and self-correcting.
//////////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps

module pane_overlay #(
    parameter PIXCLK_HZ       = 148_750_000,
    parameter UPDATE_PERIOD_S = 1,    // how often the displayed numbers refresh
    parameter PANE_X0         = 0,    // pane origin on screen
    parameter PANE_Y0         = 0,
    parameter SPEC_H          = 283,  // rows of spectrum above the separator
    parameter SHOW_RATES      = 1'b1  // 0: hide the bit-error-rate numbers
                                      // (their whole render path gets stripped)
)(
    input  wire        i_pixClk,
    input  wire        i_rst,
    input  wire        i_video_hs,
    input  wire        i_video_vs,
    input  wire        i_video_de,

    input  wire [31:0] i_biterrors_I, // ramp-checker bit-error count, I lane
    input  wire [31:0] i_biterrors_Q, // ramp-checker bit-error count, Q lane

    input  wire [11:0] i_adc_peak, // averaged ADC wave amplitude, 0..2047
    input  wire [6:0]  i_adc_db,   // same in -dBFS (magnitude of a negative dB value)

    output wire         o_active,   // high when this pixel should be overridden
    output wire [7:0]   o_r, o_g, o_b
);

localparam DIGITS = 10;

// glyph metrics: 32px cells, 24x24 glyph, 3px strokes
localparam CELL_W = 32;
localparam GW     = 24;
localparam GH     = 24;
localparam ST     = 3;

// in-pane layout
localparam AMP_CELLS = 8;                       // "PPPP -DD"
localparam AMP_X0    = 8;                       // top-left corner of the pane
localparam AMP_Y0    = 8;
// The status strip is gone (1px separator now), so the rate numbers sit inside
// the spectrum band, just above the separator, drawn over the trace.
localparam RATE_Y0   = SPEC_H - GH - 4;
localparam RATE_I_X0 = 32;                      // I-lane rate, 10 cells
localparam RATE_Q_X0 = 512;                     // Q-lane rate, 10 cells

/****************************************************************************/
/* Local active-pixel (x,y) tracking, derived from video_hs/vs/de           */
/****************************************************************************/
reg de_prev, vs_prev;
always @(posedge i_pixClk) begin
    de_prev <= i_video_de;
    vs_prev <= i_video_vs;
end
wire line_start = i_video_de & ~de_prev;
// 1080p uses VS_POL=1 (positive polarity, see video_define.v): i_video_vs
// idles LOW and pulses HIGH for the sync lines - so the one-shot-per-frame
// reset is its RISING edge (the 1024x768 predecessor keyed on the falling
// edge because that mode's polarity was negative).
wire frame_start = ~vs_prev & i_video_vs;

reg [11:0] active_x;
reg [11:0] active_y;
always @(posedge i_pixClk) begin
    if (i_rst) begin
        active_x <= 12'd0;
        active_y <= 12'd0;
    end
    else begin
        if (!i_video_de)
            active_x <= 12'd0;
        else
            active_x <= active_x + 12'd1;

        if (frame_start)
            active_y <= 12'd0;
        else if (line_start)
            active_y <= active_y + 12'd1;
    end
end

/****************************************************************************/
/* Slow update tick + rate BCD conversion sequencer                         */
/****************************************************************************/
localparam [31:0] TICKS_PER_UPDATE = PIXCLK_HZ * UPDATE_PERIOD_S;
reg [31:0] tick_ctr;
wire update_tick = (tick_ctr == TICKS_PER_UPDATE - 1);
always @(posedge i_pixClk) begin
    if (i_rst)
        tick_ctr <= 32'd0;
    else if (update_tick)
        tick_ctr <= 32'd0;
    else
        tick_ctr <= tick_ctr + 32'd1;
end

reg [31:0] latched [0:1];   // 0: I-lane biterrors/s, 1: Q-lane biterrors/s
reg [11:0] amp_val;         // 1s-latched ADC level readout
reg [6:0]  db_val;
reg [31:0] prev_biterrors_I, prev_biterrors_Q;
reg        conv_idx;
reg        conv_running;

reg bcd_start;
wire bcd_done;
wire [DIGITS*4-1:0] bcd_result;
reg bcd_busy_d;

bin2bcd #(.WIDTH(32), .DIGITS(DIGITS)) bcd_conv (
    .i_clk(i_pixClk),
    .i_rst(i_rst),
    .i_start(bcd_start),
    .i_value(latched[conv_idx]),
    .o_bcd(bcd_result),
    .o_done(bcd_done)
);

reg [DIGITS*4-1:0] display_digits [0:1];

always @(posedge i_pixClk) begin
    if (i_rst) begin
        conv_idx     <= 1'b0;
        conv_running <= 1'b0;
        bcd_start    <= 1'b0;
        bcd_busy_d   <= 1'b0;
        prev_biterrors_I <= 32'd0;
        prev_biterrors_Q <= 32'd0;
        amp_val          <= 12'd0;
        db_val           <= 7'd99;
    end
    else begin
        bcd_start <= 1'b0;

        if (update_tick && !conv_running) begin
            amp_val <= i_adc_peak;
            db_val  <= i_adc_db;
            latched[0] <= i_biterrors_I - prev_biterrors_I;
            latched[1] <= i_biterrors_Q - prev_biterrors_Q;
            prev_biterrors_I <= i_biterrors_I;
            prev_biterrors_Q <= i_biterrors_Q;
            conv_idx     <= 1'b0;
            conv_running <= 1'b1;
        end
        else if (conv_running) begin
            if (!bcd_busy_d) begin
                bcd_start  <= 1'b1;
                bcd_busy_d <= 1'b1;
            end
            else if (bcd_done) begin
                display_digits[conv_idx] <= bcd_result;
                bcd_busy_d <= 1'b0;
                if (conv_idx == 1'b1)
                    conv_running <= 1'b0;
                else
                    conv_idx <= 1'b1;
            end
        end
    end
end

/****************************************************************************/
/* Pre-registered display values: the amplitude BCD digits (constant-divisor */
/* divides - kept in their own single-cycle path, they only change once per  */
/* second) and the rates' per-digit leading-zero blank masks.                */
/****************************************************************************/
reg [3:0] amp_d3_r, amp_d2_r, amp_d1_r, amp_d0_r, db_d1_r, db_d0_r;
reg amp_blank3_r, amp_blank2_r, amp_blank1_r, db_blank1_r;
always @(posedge i_pixClk) begin
    amp_d3_r <= amp_val / 12'd1000;
    amp_d2_r <= (amp_val / 12'd100) % 4'd10;
    amp_d1_r <= (amp_val / 12'd10) % 4'd10;
    amp_d0_r <= amp_val % 4'd10;
    db_d1_r  <= db_val / 7'd10;
    db_d0_r  <= db_val % 7'd10;
    amp_blank3_r <= (amp_val < 12'd1000);              // leading-zero blanking,
    amp_blank2_r <= (amp_val < 12'd100);               // ones digit always shown
    amp_blank1_r <= (amp_val < 12'd10);
    db_blank1_r  <= (db_val < 7'd10);
end

// blank_mask[x][i] = digit cell i of rate number x renders blank (it and all
// digits above it are zero; the ones digit always shows)
reg [DIGITS-1:0] blank_mask [0:1];
integer bd;
always @(posedge i_pixClk) begin
    for (bd = 0; bd < DIGITS-1; bd = bd + 1) begin
        blank_mask[0][bd] <= ((display_digits[0] >> ((DIGITS-1-bd)*4)) == 0);
        blank_mask[1][bd] <= ((display_digits[1] >> ((DIGITS-1-bd)*4)) == 0);
    end
    blank_mask[0][DIGITS-1] <= 1'b0; // ones digit always shows
    blank_mask[1][DIGITS-1] <= 1'b0;
end

/****************************************************************************/
/* 7-segment glyph helpers                                                  */
/****************************************************************************/
function [6:0] seg_pattern; // {a,b,c,d,e,f,g}, 1 = segment lit
    input [3:0] v;
    begin
        case (v)
            4'd0: seg_pattern = 7'b1111110;
            4'd1: seg_pattern = 7'b0110000;
            4'd2: seg_pattern = 7'b1101101;
            4'd3: seg_pattern = 7'b1111001;
            4'd4: seg_pattern = 7'b0110011;
            4'd5: seg_pattern = 7'b1011011;
            4'd6: seg_pattern = 7'b1011111;
            4'd7: seg_pattern = 7'b1110000;
            4'd8: seg_pattern = 7'b1111111;
            4'd9: seg_pattern = 7'b1111011;
            default: seg_pattern = 7'b0000000;
        endcase
    end
endfunction

/****************************************************************************/
/* Render pipeline stage 1: pane-local position                             */
/****************************************************************************/
reg [11:0] lx_r, ly_r;
reg        in_pane_r;
always @(posedge i_pixClk) begin
    lx_r <= active_x - PANE_X0[11:0];
    ly_r <= active_y - PANE_Y0[11:0];
    in_pane_r <= (active_x >= PANE_X0) && (active_x < PANE_X0 + 960) &&
                 (active_y >= PANE_Y0) && (active_y < PANE_Y0 + 540);
end

/****************************************************************************/
/* Render pipeline stage 2: zone decode + digit/segment selection           */
/* The three zones are disjoint; merge to one {segs, cx, cy, white} set.    */
/****************************************************************************/

// ADC level readout "PPPP -DD", top-left (white)
wire in_amp_band = in_pane_r && (ly_r >= AMP_Y0) && (ly_r < AMP_Y0 + GH) &&
                   (lx_r >= AMP_X0);
wire [11:0] amp_x = lx_r - AMP_X0[11:0];
wire [4:0] amp_cell_idx = amp_x[9:5]; // /32
wire [4:0] amp_cell_x   = amp_x[4:0];

reg  [3:0] amp_digit;
reg        amp_is_minus;
always @* begin
    amp_digit    = 4'hF; // blank
    amp_is_minus = 1'b0;
    case (amp_cell_idx)
        5'd0: amp_digit = amp_blank3_r ? 4'hF : amp_d3_r;
        5'd1: amp_digit = amp_blank2_r ? 4'hF : amp_d2_r;
        5'd2: amp_digit = amp_blank1_r ? 4'hF : amp_d1_r;
        5'd3: amp_digit = amp_d0_r;
        5'd5: amp_is_minus = 1'b1;
        5'd6: amp_digit = db_blank1_r ? 4'hF : db_d1_r;
        5'd7: amp_digit = db_d0_r;
        default: ;
    endcase
end
wire z_amp = in_amp_band && (amp_cell_idx < AMP_CELLS[4:0]) && (amp_cell_x < GW);

// bit-errors-per-second, bottom of the spectrum: I lane left, Q lane right (orange)
wire in_rate_band = in_pane_r && (ly_r >= RATE_Y0) && (ly_r < RATE_Y0 + GH);
wire rate_is_q  = (lx_r >= RATE_Q_X0);
wire [11:0] rate_x = rate_is_q ? (lx_r - RATE_Q_X0[11:0]) : (lx_r - RATE_I_X0[11:0]);
wire in_rate_x  = rate_is_q ? 1'b1 : (lx_r >= RATE_I_X0);
wire [4:0] rate_cell_idx = rate_x[9:5]; // /32
wire [4:0] rate_cell_x   = rate_x[4:0];

// clamp the cell index before it feeds any array/part select - cells >= 10
// are render-invalid (z_rate is false there) but the selects still exist
wire [3:0] rate_idx_c = (rate_cell_idx < DIGITS) ? rate_cell_idx[3:0] : 4'd0;
wire rate_blank = blank_mask[rate_is_q][rate_idx_c];
// !SHOW_RATES forces a constant blank here (not just z_rate=0): that makes
// the digit source provably dead so the BCD converter, digit registers and
// blank masks all get swept - a mere valid-gate would leave them inferred.
wire [3:0] rate_digit = (!SHOW_RATES || rate_blank) ? 4'hF :
    display_digits[rate_is_q][(DIGITS-1-rate_idx_c)*4 +: 4];
wire z_rate = SHOW_RATES && in_rate_band && in_rate_x &&
              (rate_cell_idx < DIGITS) && (rate_cell_x < GW);

// merge (zones are disjoint by layout)
reg       s2_valid, s2_white;
reg [6:0] s2_segs;
reg [4:0] s2_cx, s2_cy;
always @(posedge i_pixClk) begin
    s2_valid <= z_amp | z_rate;
    s2_white <= z_amp;
    if (z_amp) begin
        s2_segs <= amp_is_minus ? 7'b0000001 : seg_pattern(amp_digit); // '-' = g only
        s2_cx   <= amp_cell_x;
        s2_cy   <= ly_r[4:0] - AMP_Y0[4:0];
    end
    else begin
        s2_segs <= seg_pattern(rate_digit);
        s2_cx   <= rate_cell_x;
        s2_cy   <= ly_r[4:0] - RATE_Y0[4:0];
    end
end

/****************************************************************************/
/* Render pipeline stage 3: segment rasterization                           */
/****************************************************************************/
wire seg_a = (s2_cy < ST) && (s2_cx >= ST) && (s2_cx < GW-ST);
wire seg_d = (s2_cy >= GH-ST) && (s2_cx >= ST) && (s2_cx < GW-ST);
wire seg_g = (s2_cy >= GH/2-ST/2) && (s2_cy < GH/2+ST/2) && (s2_cx >= ST) && (s2_cx < GW-ST);
wire seg_f = (s2_cx < ST) && (s2_cy >= ST) && (s2_cy < GH/2);
wire seg_b = (s2_cx >= GW-ST) && (s2_cy >= ST) && (s2_cy < GH/2);
wire seg_e = (s2_cx < ST) && (s2_cy >= GH/2) && (s2_cy < GH-ST);
wire seg_c = (s2_cx >= GW-ST) && (s2_cy >= GH/2) && (s2_cy < GH-ST);

reg s3_lit, s3_white;
always @(posedge i_pixClk) begin
    s3_lit <= s2_valid && (
        (s2_segs[6] & seg_a) | (s2_segs[5] & seg_b) | (s2_segs[4] & seg_c) |
        (s2_segs[3] & seg_d) | (s2_segs[2] & seg_e) | (s2_segs[1] & seg_f) |
        (s2_segs[0] & seg_g)
    );
    s3_white <= s2_white;
end

assign o_active = s3_lit;
assign o_r = 8'hFF;
assign o_g = s3_white ? 8'hFF : 8'hA0; // level readout: white; rate column: orange
assign o_b = s3_white ? 8'hFF : 8'h00;

endmodule
