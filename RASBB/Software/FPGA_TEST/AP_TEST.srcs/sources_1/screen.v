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
// Dependencies: none
// 
// Revision 1.01 - File Created
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
    parameter SPECTRUMSIZE   = 512, // number of lines for the spectrum display
    parameter WATERFALLSIZE  = 256	// number of lines for the spectrogram/history display
)
(    
    input wire [7:0]   	i_amplitude, /* power in dB */
	input wire [7:0]	i_peak, // peak power
    output wire         o_ReadStrobe,
    output wire [9:0]   o_addr,
    output wire         o_spectrumActive, // high while spectrum dispay is active
    
    input  wire [7:0]   i_wfPixel,
    output reg          o_wf_sync,
    output wire         o_wfActive,   // high while waterfall dispay is active
    
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
wire signed [8:0] scopePos_y;    // y position in scope window
wire [7:0] scopeAmpLime; //current amplitude line, from 255 (top line) to 0 (bottom line)
reg h_active;                    //horizontal video active
reg v_active;                    //vertical video active
wire video_active;               //video active(horizontal active and vertical active)
reg video_active_d0;             //delay 1 clock of video_active

assign o_hs = hs_reg_d0;
assign o_vs = vs_reg_d0;
assign video_active = h_active & v_active;
assign o_de = video_active_d0;

assign scopePos_y = SPECTRUMSIZE - 1 - active_y; /* should be used in the range from 0 to 511 (9 Bit) */
assign scopeAmpLime = scopePos_y[8:1];

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

wire [7:0] wfRed;
wire [7:0] wfGreen;
wire [7:0] wfBlue;

midmap midmap0(
		.i_pixel(i_wfPixel),
		.o_r(wfRed),
		.o_g(wfGreen),
		.o_b(wfBlue)
);

wire [7:0] specRed;
wire [7:0] specGreen;
wire [7:0] specBlue;

midmap midmap1(
		.i_pixel(i_amplitude),
		.o_r(specRed),
		.o_g(specGreen),
		.o_b(specBlue)
);

wire [7:0] peakRed;
wire [7:0] peakGreen;
wire [7:0] peakBlue;

midmap midmap2(
		.i_pixel(i_peak),
		.o_r(peakRed),
		.o_g(peakGreen),
		.o_b(peakBlue)
);


assign o_spectrumActive = active_y < SPECTRUMSIZE;
assign o_wfActive = active_y >= SPECTRUMSIZE;
wire gridActive;
assign gridActive = (active_x[4:0] == 0) || ((active_y % 53) == 0);

always@(posedge i_pixClk or posedge i_rst)
begin
	if(i_rst == 1'b1) begin /* RESET is active */    
        o_rgb_r <= 8'h00;
        o_rgb_g <= 8'h00;
        o_rgb_b <= 8'h00;
    end
    else if(video_active) begin // screen generation is active
		//*** spectrum amplitude ***
		if(o_spectrumActive) begin
			o_rgb_r <= (i_peak == scopeAmpLime) ? 255 : 0;
			if(i_amplitude >= scopeAmpLime) begin //current spectrum
				//o_rgb_r <= (i_peak == scopePos_y[8:1]) ? 255 : specRed;
				o_rgb_g <= specGreen;
				o_rgb_b <= specBlue | (gridActive << 7);
			end
			else begin // peak spectrum
				if(i_peak == scopeAmpLime)
				begin
					//o_rgb_r <= peakRed;
					o_rgb_g <= peakGreen;
					o_rgb_b <= peakBlue | (gridActive << 7);
				end
				else begin // background (black & grid)
					//o_rgb_r <= 0;
					o_rgb_g <= 0;
					o_rgb_b <= gridActive << 7;
				end
			end
			// peak display
			//the sync is produced even outside 
			if(active_y == SPECTRUMSIZE-1) /* we strobe this one line before starting the waterfall */ 
				o_wf_sync <= 1;
		end
		else begin //*** waterfall ***
			o_wf_sync <= 0;
			o_rgb_r <= wfRed;
			o_rgb_g <= wfGreen;
			o_rgb_b <= wfBlue;
		end
	end 
	else begin // outside the visible content, we blank the video output
		if(active_y < SPECTRUMSIZE + WATERFALLSIZE) begin
			o_rgb_r <= 8'h00;
			o_rgb_g <= 8'h00;
			o_rgb_b <= 8'h00;
		end
	end
end

assign o_ReadStrobe = ~i_pixClk;
assign o_addr = active_x;

endmodule
