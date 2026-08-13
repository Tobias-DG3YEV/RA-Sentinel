//////////////////////////////////////////////////////////////////////////////////
// scope_view.v
//
// Four-channel time-domain oscilloscope view, drawn in place of pane 4
// (bottom-right 960x540) when top.v's SCOPE_VIEW compile switch is on.
//
//   - One horizontal pixel = one ADC sample: 960 samples per sweep, so the
//     visible window is 960/fS (40us at 24MSPS). A 100kHz CW tone shows ~4
//     cycles, 20MHz shows the sampled envelope (~1.2 samples/cycle).
//   - Trigger: CH1 (i_s1) rising edge through i_trig_level (the caller feeds
//     50% of CH1's averaged peak amplitude, so the point tracks the signal).
//     A capture arms only after CH1 has been BELOW the level, so every sweep
//     starts on a true rising crossing - stationary CW input gives a
//     stationary picture. With no trigger for AUTO_TIMEOUT words the sweep
//     free-runs (auto mode), so noise/no-signal still paints live traces.
//   - Traces are drawn as vertical segments spanning consecutive samples
//     (min..max), so steep slopes stay connected instead of decaying into
//     dots. Amplitude mapping: +/-2048 -> +/-256 pixels around the pane
//     center line (drawn faintly).
//   - Colors: CH1 yellow, CH2 green, CH3 blue-cyan, CH4 light red; priority
//     in that order where traces overlap.
//   - Dark grey graticule: vertical lines every 96 samples (10 divisions),
//     horizontal lines every 64px = 512 LSB (full scale +/-2048 = +/-4 div),
//     the center line slightly brighter.
//
// Capture runs in the ADC word domain into four dual-clock BRAMs (dp_ram);
// the pixel side only ever reads. A sweep that lands mid-frame tears one
// video frame; consecutive triggered sweeps of a stationary signal write
// near-identical data, so the tearing is invisible in practice.
//
// Rendering is a 3-stage pixel pipeline like pane_overlay.v (position ->
// span -> compare/color), which shifts the traces 3px right - invisible.
//////////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps

module scope_view #(
    parameter PANE_X0 = 960,
    parameter PANE_Y0 = 540,
    parameter W       = 960,   // samples per sweep = pane width
    parameter H       = 540,
    parameter AUTO_TIMEOUT = 21'd1500000 // words without trigger -> free-run sweep
)(
    // pixel domain
    input  wire        i_pixClk,
    input  wire        i_rst,
    input  wire        i_video_hs,
    input  wire        i_video_vs,
    input  wire        i_video_de,
    output wire        o_active,  // high: this pixel belongs to the scope pane
    output wire [7:0]  o_r, o_g, o_b,

    // ADC word domain
    input  wire        i_adcClk,
    input  wire        i_ce,          // one pulse per sample
    input  wire signed [11:0] i_s1,   // CH1 (trigger source)
    input  wire signed [11:0] i_s2,
    input  wire signed [11:0] i_s3,
    input  wire signed [11:0] i_s4,
    input  wire [11:0] i_trig_level   // rising-edge threshold (unsigned, ~50% peak)
);

/****************************************************************************/
/* Capture: trigger FSM + four 1024x12 dual-clock BRAMs                     */
/****************************************************************************/
localparam S_ARM = 2'd0, S_WAIT = 2'd1, S_CAP = 2'd2;

reg [1:0]  cap_state;
reg [9:0]  wr_addr;
reg        wr_en;
reg [20:0] auto_ctr;
reg signed [11:0] s1_prev;

wire signed [12:0] trig_thr = {1'b0, i_trig_level}; // always positive

always @(posedge i_adcClk) begin
    if (i_rst) begin
        cap_state <= S_ARM;
        wr_addr   <= 10'd0;
        wr_en     <= 1'b0;
        auto_ctr  <= 21'd0;
        s1_prev   <= 12'sd0;
    end
    else if (i_ce) begin
        s1_prev <= i_s1;
        wr_en   <= 1'b0;
        case (cap_state)
            S_ARM: begin // wait below the level so the crossing is a real edge
                if (auto_ctr >= AUTO_TIMEOUT) begin
                    auto_ctr  <= 21'd0;
                    wr_addr   <= 10'd0;
                    wr_en     <= 1'b1;
                    cap_state <= S_CAP;
                end
                else begin
                    auto_ctr <= auto_ctr + 21'd1;
                    if (i_s1 < trig_thr)
                        cap_state <= S_WAIT;
                end
            end
            S_WAIT: begin // armed: fire on the rising crossing
                if (auto_ctr >= AUTO_TIMEOUT) begin
                    auto_ctr  <= 21'd0;
                    wr_addr   <= 10'd0;
                    wr_en     <= 1'b1;
                    cap_state <= S_CAP;
                end
                else begin
                    auto_ctr <= auto_ctr + 21'd1;
                    if (s1_prev < trig_thr && i_s1 >= trig_thr) begin
                        auto_ctr  <= 21'd0;
                        wr_addr   <= 10'd0;
                        wr_en     <= 1'b1;
                        cap_state <= S_CAP;
                    end
                end
            end
            S_CAP: begin // one sample per CE into all four RAMs
                if (wr_addr == W[9:0]-10'd1) begin
                    wr_en     <= 1'b0;
                    cap_state <= S_ARM;
                end
                else begin
                    wr_addr <= wr_addr + 10'd1;
                    wr_en   <= 1'b1;
                end
            end
            default: cap_state <= S_ARM;
        endcase
    end
end

wire [9:0]  rd_addr;
wire [11:0] rd_s [0:3];

dp_ram #(.ADDRBITS(10), .BITS(12)) scope_mem1 (
    .i_clka(i_adcClk), .i_wea(wr_en && i_ce), .i_addra(wr_addr),
    .i_dina(i_s1), .o_douta(),
    .i_clkb(i_pixClk), .i_addrb(rd_addr), .o_doutb(rd_s[0])
);
dp_ram #(.ADDRBITS(10), .BITS(12)) scope_mem2 (
    .i_clka(i_adcClk), .i_wea(wr_en && i_ce), .i_addra(wr_addr),
    .i_dina(i_s2), .o_douta(),
    .i_clkb(i_pixClk), .i_addrb(rd_addr), .o_doutb(rd_s[1])
);
dp_ram #(.ADDRBITS(10), .BITS(12)) scope_mem3 (
    .i_clka(i_adcClk), .i_wea(wr_en && i_ce), .i_addra(wr_addr),
    .i_dina(i_s3), .o_douta(),
    .i_clkb(i_pixClk), .i_addrb(rd_addr), .o_doutb(rd_s[2])
);
dp_ram #(.ADDRBITS(10), .BITS(12)) scope_mem4 (
    .i_clka(i_adcClk), .i_wea(wr_en && i_ce), .i_addra(wr_addr),
    .i_dina(i_s4), .o_douta(),
    .i_clkb(i_pixClk), .i_addrb(rd_addr), .o_doutb(rd_s[3])
);

/****************************************************************************/
/* Pixel-side: active-pixel tracking (pane_overlay.v pattern)               */
/****************************************************************************/
reg [11:0] active_x, active_y;
reg        de_d;
always @(posedge i_pixClk) begin
    de_d <= i_video_de;
    if (i_video_vs)
        active_y <= 12'd0;
    else if (de_d && !i_video_de) // falling DE edge = end of an active line
        active_y <= active_y + 12'd1;
    if (!i_video_de)
        active_x <= 12'd0;
    else
        active_x <= active_x + 12'd1;
end

wire [11:0] lx = active_x - PANE_X0[11:0];
wire [11:0] ly = active_y - PANE_Y0[11:0];
wire in_pane = (active_x >= PANE_X0) && (active_x < PANE_X0 + W) &&
               (active_y >= PANE_Y0) && (active_y < PANE_Y0 + H);

/* Read ahead one sample: address lx+1 while pixel lx is on screen, so the
   registered BRAM output holds sample lx at the next pixel. Outside the pane
   the address parks at 0, priming sample 0 for the first pane pixel. */
assign rd_addr = in_pane ? (lx[9:0] + 10'd1) : 10'd0;

/****************************************************************************/
/* Render pipeline. P1: per-channel prev/cur -> vertical span (min,max).    */
/* P2: span vs. current line -> per-channel hit. P3: priority color mux.    */
/****************************************************************************/
localparam [11:0] MID = H[11:0]/2; // pane-local center line

reg signed [11:0] cur [0:3];
reg signed [11:0] prv [0:3];
reg [11:0] span_min [0:3];
reg [11:0] span_max [0:3];
reg        p1_valid, p2_valid;
reg [3:0]  p2_hit;
reg        p2_mid;
reg        p3_act;
reg [7:0]  p3_r, p3_g, p3_b;
reg [11:0] ya, yb; // P1 scratch (blocking-assigned)

/* graticule: 96px column counter (mod-96 of the pane-local x) + fixed rows */
reg [6:0]  gcnt;
reg        p1_vgrid;
reg        p2_grid;
wire hgrid = (ly == 12'd14)  || (ly == 12'd78)  || (ly == 12'd142) ||
             (ly == 12'd206) || (ly == 12'd334) || (ly == 12'd398) ||
             (ly == 12'd462) || (ly == 12'd526);

integer c;
always @(posedge i_pixClk) begin
    /* P1: latch samples; amplitude -> pane-local line: MID - v/8 */
    for (c = 0; c < 4; c = c + 1) begin
        cur[c] <= rd_s[c];
        prv[c] <= cur[c];
    end
    for (c = 0; c < 4; c = c + 1) begin
        /* +/-2048 -> +/-256 px around the center line (v >>> 3) */
        ya = MID - {{3{cur[c][11]}}, cur[c][11:3]};
        yb = MID - {{3{prv[c][11]}}, prv[c][11:3]};
        span_min[c] <= (ya < yb) ? ya : yb;
        span_max[c] <= (ya < yb) ? yb : ya;
    end
    if (!in_pane)
        gcnt <= 7'd0;
    else
        gcnt <= (gcnt == 7'd95) ? 7'd0 : gcnt + 7'd1;
    p1_vgrid <= in_pane && (gcnt == 7'd0);
    p1_valid <= in_pane;

    /* P2: does this scanline cross the span? */
    for (c = 0; c < 4; c = c + 1)
        p2_hit[c] <= p1_valid && (ly >= span_min[c]) && (ly <= span_max[c]);
    p2_mid   <= p1_valid && (ly == MID);
    p2_grid  <= p1_valid && (p1_vgrid || hgrid);
    p2_valid <= p1_valid;

    /* P3: priority color */
    p3_act <= p2_valid;
    if (p2_hit[0])      begin p3_r <= 8'hFF; p3_g <= 8'hFF; p3_b <= 8'h00; end // CH1 yellow
    else if (p2_hit[1]) begin p3_r <= 8'h00; p3_g <= 8'hFF; p3_b <= 8'h00; end // CH2 green
    else if (p2_hit[2]) begin p3_r <= 8'h00; p3_g <= 8'hA0; p3_b <= 8'hFF; end // CH3 blue-cyan
    else if (p2_hit[3]) begin p3_r <= 8'hFF; p3_g <= 8'h50; p3_b <= 8'h50; end // CH4 light red
    else if (p2_mid)    begin p3_r <= 8'h40; p3_g <= 8'h40; p3_b <= 8'h40; end // center line
    else if (p2_grid)   begin p3_r <= 8'h28; p3_g <= 8'h28; p3_b <= 8'h28; end // graticule
    else                begin p3_r <= 8'h00; p3_g <= 8'h00; p3_b <= 8'h00; end // background
end

assign o_active = p3_act;
assign o_r = p3_r;
assign o_g = p3_g;
assign o_b = p3_b;

endmodule
