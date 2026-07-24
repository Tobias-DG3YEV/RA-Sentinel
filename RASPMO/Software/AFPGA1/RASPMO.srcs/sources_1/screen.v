//////////////////////////////////////////////////////////////////////////////////
//
// Design Name: RASM2400
// Module Name: screen
// Project Name: Radio Access Spectrum Monitor 2400MHz
// Engineer: Tobias Weber
// Target Devices: Artix 7, XC7A100T
// Create Date: 25.04.2024 10:29:54
// Tool Versions: Vivado 2024.1
// Description:  Video screen generator. Based on color_bar.v from
//               ALINX(shanghai) Technology Co.,Ltd (details see video_define.v)
//
//               Quad-split version: 1920x1080 divided into a 2x2 grid of
//               960x540 panes, one per RASRF2400BMC receive channel. Each pane
//               is, top to bottom:
//                 rows   0..282  live spectrum + peak dots (1px per logfn
//                                count = 0.376dB/px, full 96dB span). The
//                                trace occupies the BOTTOM 256 rows (27..282);
//                                rows 0..26 are one grid division of blank
//                                headroom above amplitude 255, which is where
//                                the 27 rows freed by the 1px separator went.
//                 row  283       1px black separator (was a 28px status strip;
//                                pane_overlay now renders its readouts in the
//                                pane's top-left corner instead)
//                 rows 284..539  waterfall (128 stored rows shown 2px tall)
//               Horizontally a pane shows FFT bins BIN_OFS..BIN_OFS+959 of the
//               1024-bin spectrum (the outermost 32 bins per edge are filter
//               rolloff); the waterfall stores 2-bin-decimated columns, so
//               stored column k covers bins 2k/2k+1 and is drawn 2px wide -
//               exactly under the same bins in the spectrum above it.
//
//               This module only steers addresses/coordinates; the four
//               spectrum/peak/waterfall RAMs live in top.v, which muxes their
//               read data by o_pane back into i_amplitude/i_peak/i_wfPixel.
//               Those inputs are re-registered here (one extra pixel of
//               latency, invisible) so the pane mux never lands in the
//               half-cycle path from the inverted-clock RAM read.
//
// Dependencies: none
//
// Revision 1.03 - status strip shrunk to a 1px separator, its 27 rows added
//                 to the spectrum band as headroom
// Revision 1.02 - quad split + 1080p
// Additional Comments: https://github.com/Tobias-DG3YEV/RA-Sentinel
//
//////////////////////////////////////////////////////////////////////////////////
// Copyright (C) 2024 Tobias Weber
// License: GNU GPL v3
//
// This project is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTIBILITY or FITNESS FOR A PARTICULAR PURPOSE.
// See the GNU General Public License for more details.
//
// You should have received a copy of the GNU Lesser General Public License
// along with this program. If not, see
// <http://www.gnu.org/licenses/> for a copy.
//////////////////////////////////////////////////////////////////////////////////

module screen #(
    parameter PANE_W  = 960,  // pane width  (H_ACTIVE/2)
    parameter PANE_H  = 540,  // pane height (V_ACTIVE/2)
    parameter SPEC_H  = 283,  // spectrum rows per pane, 1px per logfn count;
                              // amplitudes 0..255 use the bottom 256 rows, the
                              // remaining SPEC_H-256 rows are blank headroom
    parameter STRIP_H = 1,    // black separator under the spectrum
    parameter WF_ROWS = 128,  // stored waterfall rows (drawn 2px tall each)
    parameter BIN_OFS = 32    // first displayed FFT bin ((1024-PANE_W)/2)
)
(
    input wire [7:0]   	i_amplitude, /* power in dB, pane-muxed in top.v */
	input wire [7:0]	i_peak, // peak power, pane-muxed in top.v
    output wire         o_ReadStrobe,
    output wire [9:0]   o_addr,  // FFT bin to read (same for all panes)
    output wire [1:0]   o_pane,  // pane under the beam: {bottom, right}
    output wire         o_spectrumActive, // high while any pane's spectrum band is active

    input  wire [7:0]   i_wfPixel, // pane-muxed in top.v
    output reg          o_wf_sync, // high for one line per frame (frame tick)
    output wire         o_wfActive,   // high while any pane's waterfall band is active
    output wire [6:0]   o_wfRow,      // pane-local waterfall row, 0 = top history line

	input  wire         i_pixClk,        //pixel clock
	input  wire         i_rst,           //reset signal high active
	output wire         o_hs,            //horizontal synchronization
	output wire         o_vs,            //vertical synchronization
	output wire         o_de,            //video valid
	output reg[7:0]    o_rgb_r,         //video red data
	output reg[7:0]    o_rgb_g,         //video green data
	output reg[7:0]    o_rgb_b          //video blue data
);

// get the resolution depending definitions
`include "video_define.v"

reg hs_reg;                      //horizontal sync register
reg vs_reg;                      //vertical sync register
reg hs_reg_d0;                   //delay 1 clock of 'hs_reg'
reg vs_reg_d0;                   //delay 1 clock of 'vs_reg'
reg[11:0] h_cnt;                 //horizontal counter
reg[11:0] v_cnt;                 //vertical counter
reg[11:0] active_x;              //video x position
reg[11:0] active_y;              //video y position
reg h_active;                    //horizontal video active
reg v_active;                    //vertical video active
wire video_active;               //video active(horizontal active and vertical active)
reg video_active_d0;             //delay 1 clock of video_active

assign o_hs = hs_reg_d0;
assign o_vs = vs_reg_d0;
assign video_active = h_active & v_active;
assign o_de = video_active_d0;

always@(posedge i_pixClk or posedge i_rst)
begin
	if(i_rst == 1'b1)
		begin
			hs_reg_d0 <= 1'b0;
			vs_reg_d0 <= 1'b0;
			video_active_d0 <= 1'b0;
		end
	else
		begin
			hs_reg_d0 <= hs_reg;
			vs_reg_d0 <= vs_reg;
			video_active_d0 <= video_active;
		end
end

always@(posedge i_pixClk or posedge i_rst)
begin
	if(i_rst == 1'b1)
		h_cnt <= 12'd0;
	else if(h_cnt == H_TOTAL - 1) //horizontal counter maximum value
		h_cnt <= 12'd0;
	else
		h_cnt <= h_cnt + 12'd1;
end

// Horizontal line handling
always@(posedge i_pixClk or posedge i_rst)
begin
	if(i_rst == 1'b1)
	   begin
		  active_x <= 12'd0;
	   end
	else if(h_cnt >= H_FP + H_SYNC + H_BP - 1) //horizontal video active
		active_x <= h_cnt - (H_FP[11:0] + H_SYNC[11:0] + H_BP[11:0] - 12'd1);
	else
		active_x <= active_x;
end

// Vertical line handling
always@(posedge i_pixClk or posedge i_rst)
begin
	if(i_rst == 1'b1)
	   begin
	       v_cnt <= 12'd0;
	       active_y <= 12'b0;
	   end
	else if(h_cnt == H_FP  - 1) //horizontal sync time
	   begin
            if(v_cnt == V_TOTAL - 1) //vertical counter maximum value
                v_cnt <= 12'd0;
            else
                v_cnt <= v_cnt + 12'd1;
       end
    else if(h_cnt >= V_FP + V_SYNC + V_BP - 1)
        begin
            active_y <= v_cnt - (V_FP[11:0] + V_SYNC[11:0] + V_BP[11:0] - 12'd1);
        end
	else
		v_cnt <= v_cnt;
end

always@(posedge i_pixClk or posedge i_rst)
begin
	if(i_rst == 1'b1)
		hs_reg <= 1'b0;
	else if(h_cnt == H_FP - 1) //horizontal sync begin
		hs_reg <= HS_POL;
	else if(h_cnt == H_FP + H_SYNC - 1) //horizontal sync end
		hs_reg <= ~hs_reg;
	else
		hs_reg <= hs_reg;
end

always@(posedge i_pixClk or posedge i_rst)
begin
	if(i_rst == 1'b1)
		h_active <= 1'b0;
	else if(h_cnt == H_FP + H_SYNC + H_BP - 1) //horizontal active begin
		h_active <= 1'b1;
	else if(h_cnt == H_TOTAL - 1) //horizontal active end
		h_active <= 1'b0;
	else
		h_active <= h_active;
end

always@(posedge i_pixClk or posedge i_rst)
begin
	if(i_rst == 1'b1)
		vs_reg <= 1'd0;
	else if((v_cnt == V_FP - 1) && (h_cnt == H_FP - 1)) //vertical sync begin
		vs_reg <= HS_POL;
	else if((v_cnt == V_FP + V_SYNC - 1) && (h_cnt == H_FP - 1)) //vertical sync end
		vs_reg <= ~vs_reg;
	else
		vs_reg <= vs_reg;
end

always@(posedge i_pixClk or posedge i_rst)
begin
	if(i_rst == 1'b1)
		v_active <= 1'd0;
	else if((v_cnt == V_FP + V_SYNC + V_BP - 1) && (h_cnt == H_FP - 1)) //vertical active begin
		v_active <= 1'b1;
	else if((v_cnt == V_TOTAL - 1) && (h_cnt == H_FP - 1)) //vertical active end
		v_active <= 1'b0;
	else
		v_active <= v_active;
end

/****************************************************************************
	 #####   ######   #######   #####   #######  ######   #     #  #     #
	#     #  #     #  #        #     #     #     #     #  #     #  ##   ##
	#        #     #  #        #           #     #     #  #     #  # # # #
	 #####   ######   #####    #           #     ######   #     #  #  #  #
		  #  #        #        #           #     #   #    #     #  #     #
	#     #  #        #        #     #     #     #    #   #     #  #     #
	 #####   #        #######   #####      #     #     #   #####   #     #
*****************************************************************************/

/* Pane decomposition: {bottom, right} quadrant index plus pane-local coords */
wire pane_right  = (active_x >= PANE_W);
wire pane_bottom = (active_y >= PANE_H);
wire [11:0] pane_x = pane_right  ? (active_x - PANE_W) : active_x;
wire [11:0] pane_y = pane_bottom ? (active_y - PANE_H) : active_y;

/* Registered read address/pane/waterfall-row: the address fans out to twelve
   physically spread BRAMs, which does not fit in a half cycle of arithmetic +
   routing at 148.75MHz. With the address registered and the RAMs read on the
   plain (non-inverted) pixel clock every RAM hop is a clean full-cycle path;
   together with the input re-registering below the displayed traces end up 3px
   right of their nominal position - a constant, invisible pan. The pane index
   used for the data mux is the address-issue-time one; the 2px mismatch
   window at the pane seam is hidden under the pane border. */
reg [9:0] addr_r;
reg [1:0] pane_r;
always @(posedge i_pixClk) begin
    addr_r  <= pane_x[9:0] + BIN_OFS[9:0];
    pane_r  <= {pane_bottom, pane_right};
end
assign o_pane = pane_r;
assign o_addr = addr_r;

wire in_spec  = (pane_y < SPEC_H);
wire in_strip = (pane_y >= SPEC_H) && (pane_y < SPEC_H + STRIP_H);
wire in_wf    = (pane_y >= SPEC_H + STRIP_H);

assign o_spectrumActive = in_spec;
assign o_wfActive       = in_wf;

/* Waterfall display row: 2 screen lines per stored row, 0 = newest (top);
   registered like addr_r so row and column arrive at the RAM together. */
wire [11:0] wf_y = pane_y - (SPEC_H[11:0] + STRIP_H[11:0]);
reg [6:0] wfrow_r;
always @(posedge i_pixClk)
    wfrow_r <= wf_y[7:1];
assign o_wfRow = wfrow_r;

/* Amplitude threshold for the spectrum trace: the pane's spectrum baseline
   (row SPEC_H-1) is amplitude 0 and each row up is one more logfn count, so
   amplitude 255 sits SPEC_H-256 rows below the top of the band. Full logfn
   resolution - 1px per count (the 1024x768 version halved it). 9 bits wide
   since SPEC_H > 256: in the headroom rows ampThresh exceeds 255 and the
   8-bit amp/peak can never reach it, so those rows show grid only - no
   clamping needed. The subtract chain and the grid-row test get ONE PIPELINE
   STAGE EACH: sharing a stage missed the 148.75MHz pixel clock, so gridRow_r
   is derived from the registered ampThresh_r rather than from the
   combinational ampThresh. Both are row constants, so ampThresh_r's one-pixel
   lag and gridRow_r's two-pixel lag only ever disagree with the true row
   value on the leftmost column(s) of a line - which is the pane border, drawn
   before either is consulted. */
/* ampThresh is derived from active_y directly, NOT from pane_y: pane_y already
   costs a subtract (active_y - PANE_H in the bottom row of panes), and feeding
   that into a second subtract put two 9-bit carry chains in series on what
   became the pixel domain's critical path. Since pane_y = active_y - PANE_H
   there, (SPEC_H-1) - pane_y is just (SPEC_H-1+PANE_H) - active_y - the same
   single subtract with a different constant, selected by pane_bottom. The
   constants are taken mod 512, which is exact: wherever ampThresh is actually
   used (in_spec) the true value is 0..SPEC_H-1, well inside 9 bits. */
localparam [8:0] AMP_BASE_T = (SPEC_H - 1) % 512;          // top row of panes
localparam [8:0] AMP_BASE_B = (SPEC_H - 1 + PANE_H) % 512; // bottom row of panes
wire [8:0] ampThresh = (pane_bottom ? AMP_BASE_B : AMP_BASE_T) - active_y[8:0];
reg [8:0] ampThresh_r;
reg       gridRow_r;

/* Grid rows sit at ampThresh = 0, 27, 54, ... - a handful of fixed row
   constants, so this is a constant-decode comparator tree (~3 LUT levels).
   It used to be "(ampThresh % 27) == 0", which at 1080p synthesized to a
   divider network of 4 carry chains and made this the design's critical path
   (WNS -0.43ns) once ampThresh widened to 9 bits for the headroom rows. The
   loop bound is derived from SPEC_H, so the grid follows the pane geometry. */
localparam GRID_STEP = 27; // 10.15dB per division at 0.376dB/px
localparam GRID_DIVS = (SPEC_H + GRID_STEP - 1) / GRID_STEP;

reg gridRow_c;
integer gi;
always @* begin
    gridRow_c = 1'b0;
    for (gi = 0; gi < GRID_DIVS; gi = gi + 1)
        if (ampThresh_r == gi*GRID_STEP)
            gridRow_c = 1'b1;
end

always @(posedge i_pixClk) begin
    ampThresh_r <= ampThresh;
    gridRow_r   <= gridRow_c;
end

/* One-pixel input pipeline: the three RAM read datas arrive through top.v's
   pane mux off the inverted-clock RAM ports; re-register them so the mux and
   colormap never share the half-cycle window. Costs one pixel of horizontal
   shift of the traces vs the grid - invisible. */
reg [7:0] amp_r, peak_r, wf_r;
always @(posedge i_pixClk) begin
    amp_r  <= i_amplitude;
    peak_r <= i_peak;
    wf_r   <= i_wfPixel;
end

wire [7:0] wfRed;
wire [7:0] wfGreen;
wire [7:0] wfBlue;

midmap midmap0(
		.i_pixel(wf_r),
		.o_r(wfRed),
		.o_g(wfGreen),
		.o_b(wfBlue)
);

wire [7:0] specRed;
wire [7:0] specGreen;
wire [7:0] specBlue;

midmap midmap1(
		.i_pixel(amp_r),
		.o_r(specRed),
		.o_g(specGreen),
		.o_b(specBlue)
);

wire [7:0] peakRed;
wire [7:0] peakGreen;
wire [7:0] peakBlue;

midmap midmap2(
		.i_pixel(peak_r),
		.o_r(peakRed),
		.o_g(peakGreen),
		.o_b(peakBlue)
);

wire gridActive;
/* Horizontal grid rows every 27 px = 10.15 dB per division at 1px per logfn
   count (0.376 dB/px; the 1024x768 version used 53px at 2px/count = the same
   divisions). Anchored to the BOTTOM of each pane's spectrum (ampThresh, not
   pane_y) so the baseline row itself is a grid line and the divisions read as
   0/10/20/... dB above it. ampThresh is an unsigned 9-bit row-constant here -
   no signed-wrap hazard like the old scopePos_y version had. Vertical grid
   columns every 32 px, pane-local so all four panes match. */
assign gridActive = (pane_x[4:0] == 0) || gridRow_r;

/* 1px pane border: outer edge of every pane -> a neutral gray cross + frame
   separating the four channels. */
wire paneBorder = (pane_x == 12'd0) || (pane_x == PANE_W - 1) ||
                  (pane_y == 12'd0) || (pane_y == PANE_H - 1);

always@(posedge i_pixClk or posedge i_rst)
begin
	if(i_rst == 1'b1) begin /* RESET is active */
        o_rgb_r <= 8'h00;
        o_rgb_g <= 8'h00;
        o_rgb_b <= 8'h00;
        o_wf_sync <= 1'b0;
    end
    else if(video_active) begin // screen generation is active
        /* frame tick: the last active line, once per frame (used by top.v for
           peak decay pacing, waterfall row advance and the row snapshot) */
        o_wf_sync <= (active_y == (2*PANE_H) - 1);

		if(paneBorder) begin
			o_rgb_r <= 8'h50;
			o_rgb_g <= 8'h50;
			o_rgb_b <= 8'h50;
		end
		else if(in_spec) begin //*** spectrum amplitude ***
			o_rgb_r <= ({1'b0, peak_r} == ampThresh_r) ? 8'hFF : 8'h00;
			if({1'b0, amp_r} >= ampThresh_r) begin //current spectrum
				o_rgb_g <= specGreen;
				o_rgb_b <= specBlue | (gridActive << 7);
			end
			else begin
				if({1'b0, peak_r} == ampThresh_r) begin // peak dot
					o_rgb_g <= peakGreen;
					o_rgb_b <= peakBlue | (gridActive << 7);
				end
				else begin // background (black & grid)
					o_rgb_g <= 8'h00;
					o_rgb_b <= gridActive << 7;
				end
			end
		end
		else if(in_strip) begin //*** 1px black spectrum/waterfall separator ***
			o_rgb_r <= 8'h00;
			o_rgb_g <= 8'h00;
			o_rgb_b <= 8'h00;
		end
		else begin //*** waterfall ***
			o_rgb_r <= wfRed;
			o_rgb_g <= wfGreen;
			o_rgb_b <= wfBlue;
		end
	end
	else begin // outside the visible content, we blank the video output
		o_rgb_r <= 8'h00;
		o_rgb_g <= 8'h00;
		o_rgb_b <= 8'h00;
	end
end

/* RAM read clock: the plain pixel clock (the pre-quad design used the
   inverted clock to hide read latency; with the registered address and
   re-registered read data above, all RAM paths are full-cycle instead). */
assign o_ReadStrobe = i_pixClk;

endmodule
