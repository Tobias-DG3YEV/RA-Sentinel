
//////////////////////////////////////////////////////////////////////////////////
// 
// Design Name: RASM2400
// Module Name: screen
// Project Name: Radio Access Spectrum Monitor 2400MHz
// Engineer: Tobias Weber
// Target Devices: Artix 7, XC7A100T
// Create Date: 25.04.2024 10:29:54
// Tool Versions: Vivado 2024.1
// Description:  HDMI Video generator. Ide based on color_bar.v from
//               ALINX(shanghai) Technology Co.,Ltd
// 
// Dependencies: none
// 
// Revision: 
// Revision 1.00 - File Created
// Additional Comments: https://github.com/Tobias-DG3YEV/RA-Sentinel
// 
//////////////////////////////////////////////////////////////////////////////////
`include "video_define.v"

module screen #(
    parameter SPECTRUMSIZE   = 512, /* th amplitude of the spctrum is 8 bits , so 256 pixel in height are used by it */
    parameter WATERFALLSIZE  = 256
)
(    
    input  wire [7:0]   i_amplitude, /* power in dB */
    output wire         o_ReadStrobe,
    output wire [9:0]   o_addr,
    
    input  wire [7:0]   i_wfPixel,
    output reg          o_wf_sync,
    
	input  wire         clk,           //pixel clock
	input  wire         rst,           //reset signal high active
	output wire         hs,            //horizontal synchronization
	output wire         vs,            //vertical synchronization
	output wire         de,            //video valid
	output wire[7:0]    rgb_r,         //video red data
	output wire[7:0]    rgb_g,         //video green data
	output wire[7:0]    rgb_b          //video blue data
);


//video timing parameter definition
`ifdef  VIDEO_1280_720
parameter H_ACTLINES = 16'd1280;         //horizontal active time (pixels)
parameter H_FP = 16'd110;                //horizontal front porch (pixels)
parameter H_SYNC = 16'd40;               //horizontal sync time(pixels)
parameter H_BP = 16'd220;                //horizontal back porch (pixels)
parameter V_ACTIVE = 16'd720;            //vertical active Time (lines)
parameter V_FP  = 16'd5;                 //vertical front porch (lines)
parameter V_SYNC  = 16'd5;               //vertical sync time (lines)
parameter V_BP  = 16'd20;                //vertical back porch (lines)
parameter HS_POL = 1'b1;                 //horizontal sync polarity, 1 : POSITIVE,0 : NEGATIVE;
parameter VS_POL = 1'b1;                 //vertical sync polarity, 1 : POSITIVE,0 : NEGATIVE;
`endif

//480x272 9Mhz
`ifdef  VIDEO_480_272
parameter H_ACTLINES = 16'd480; 
parameter H_FP = 16'd2;       
parameter H_SYNC = 16'd41;    
parameter H_BP = 16'd2;       
parameter V_ACTIVE = 16'd272; 
parameter V_FP  = 16'd2;     
parameter V_SYNC  = 16'd10;   
parameter V_BP  = 16'd2;     
parameter HS_POL = 1'b0;
parameter VS_POL = 1'b0;
`endif

//640x480 25.175Mhz
`ifdef  VIDEO_640_480
parameter H_ACTLINES = 16'd640; 
parameter H_FP = 16'd16;      
parameter H_SYNC = 16'd96;    
parameter H_BP = 16'd48;      
parameter V_ACTIVE = 16'd480; 
parameter V_FP  = 16'd10;    
parameter V_SYNC  = 16'd2;    
parameter V_BP  = 16'd33;    
parameter HS_POL = 1'b0;
parameter VS_POL = 1'b0;
`endif

//800x480 33Mhz
`ifdef  VIDEO_800_480
parameter H_ACTLINES = 16'd800; 
parameter H_FP = 16'd40;      
parameter H_SYNC = 16'd128;   
parameter H_BP = 16'd88;      
parameter V_ACTIVE = 16'd480; 
parameter V_FP  = 16'd1;     
parameter V_SYNC  = 16'd3;    
parameter V_BP  = 16'd21;    
parameter HS_POL = 1'b0;
parameter VS_POL = 1'b0;
`endif

//800x600 40Mhz
`ifdef  VIDEO_800_600
parameter H_ACTLINES = 16'd800; 
parameter H_FP = 16'd40;      
parameter H_SYNC = 16'd128;   
parameter H_BP = 16'd88;      
parameter V_ACTIVE = 16'd600; 
parameter V_FP  = 16'd1;     
parameter V_SYNC  = 16'd4;    
parameter V_BP  = 16'd23;    
parameter HS_POL = 1'b1;
parameter VS_POL = 1'b1;
`endif

//1024x768 65Mhz
`ifdef  VIDEO_1024_768
parameter H_ACTLINES = 16'd1024;
parameter H_FP = 16'd24;      
parameter H_SYNC = 16'd136;   
parameter H_BP = 16'd160;     
parameter V_ACTIVE = 16'd768; 
parameter V_FP  = 16'd3;      
parameter V_SYNC  = 16'd6;    
parameter V_BP  = 16'd29;     
parameter HS_POL = 1'b0;
parameter VS_POL = 1'b0;
`endif

//1920x1080 148.5Mhz (clk2 742.5MHz)
`ifdef  VIDEO_1920_1080
parameter H_ACTLINES = 16'd1920;
parameter H_FP = 16'd88;
parameter H_SYNC = 16'd44;
parameter H_BP = 16'd148; 
parameter V_ACTIVE = 16'd1080;
parameter V_FP  = 16'd4;
parameter V_SYNC  = 16'd5;
parameter V_BP  = 16'd36;
parameter HS_POL = 1'b1;
parameter VS_POL = 1'b1;
`endif

parameter H_TOTAL = H_ACTLINES + H_FP + H_SYNC + H_BP;//horizontal total time (pixels)
parameter V_TOTAL = V_ACTIVE + V_FP + V_SYNC + V_BP;//vertical total time (lines)
//define the RGB values for 8 colors
parameter WHITE_R       = 8'hff;
parameter WHITE_G       = 8'hff;
parameter WHITE_B       = 8'hff;
parameter YELLOW_R      = 8'hff;
parameter YELLOW_G      = 8'hff;
parameter YELLOW_B      = 8'h00;                                
parameter CYAN_R        = 8'h00;
parameter CYAN_G        = 8'hff;
parameter CYAN_B        = 8'hff;                                
parameter GREEN_R       = 8'h00;
parameter GREEN_G       = 8'hff;
parameter GREEN_B       = 8'h00;
parameter MAGENTA_R     = 8'hff;
parameter MAGENTA_G     = 8'h00;
parameter MAGENTA_B     = 8'hff;
parameter RED_R         = 8'hff;
parameter RED_G         = 8'h00;
parameter RED_B         = 8'h00;
parameter BLUE_R        = 8'h00;
parameter BLUE_G        = 8'h00;
parameter BLUE_B        = 8'hff;
parameter BLACK_R       = 8'h00;
parameter BLACK_G       = 8'h00;
parameter BLACK_B       = 8'h00;


reg hs_reg;                      //horizontal sync register
reg vs_reg;                      //vertical sync register
reg hs_reg_d0;                   //delay 1 clock of 'hs_reg'
reg vs_reg_d0;                   //delay 1 clock of 'vs_reg'
reg[11:0] h_cnt;                 //horizontal counter
reg[11:0] v_cnt;                 //vertical counter
reg[11:0] active_x;              //video x position 
reg[11:0] active_y;              //video y position
wire signed [8:0] scopePos_y;    /* y position in scope window */ 
reg[7:0] rgb_r_reg;              //video red data register
reg[7:0] rgb_g_reg;              //video green data register
reg[7:0] rgb_b_reg;              //video blue data register
reg h_active;                    //horizontal video active
reg v_active;                    //vertical video active
wire video_active;               //video active(horizontal active and vertical active)
reg video_active_d0;             //delay 1 clock of video_active

assign hs = hs_reg_d0;
assign vs = vs_reg_d0;
assign video_active = h_active & v_active;
assign de = video_active_d0;
assign rgb_r = rgb_r_reg;
assign rgb_g = rgb_g_reg;
assign rgb_b = rgb_b_reg;

assign scopePos_y = SPECTRUMSIZE - 1 - active_y; /* should be used in the range from 0 to 511 (9 Bit) */

always@(posedge clk or posedge rst)
begin
	if(rst == 1'b1)
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

always@(posedge clk or posedge rst)
begin
	if(rst == 1'b1)
		h_cnt <= 12'd0;
	else if(h_cnt == H_TOTAL - 1)//horizontal counter maximum value
		h_cnt <= 12'd0;
	else
		h_cnt <= h_cnt + 12'd1;
end

/* Horizontal line handling */
always@(posedge clk or posedge rst)
begin
	if(rst == 1'b1)
	   begin
		  active_x <= 12'd0;
	   end	
	else if(h_cnt >= H_FP + H_SYNC + H_BP - 1) //horizontal video active
		active_x <= h_cnt - (H_FP[11:0] + H_SYNC[11:0] + H_BP[11:0] - 12'd1);
	else
		active_x <= active_x;
end

/* Vertical line handling */
always@(posedge clk or posedge rst)
begin
	if(rst == 1'b1)
	   begin
	       v_cnt <= 12'd0;
	       active_y <= 12'b0;
	   end
	else if(h_cnt == H_FP  - 1)//horizontal sync time
	   begin
            if(v_cnt == V_TOTAL - 1)//vertical counter maximum value
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

always@(posedge clk or posedge rst)
begin
	if(rst == 1'b1)
		hs_reg <= 1'b0;
	else if(h_cnt == H_FP - 1)//horizontal sync begin
		hs_reg <= HS_POL;
	else if(h_cnt == H_FP + H_SYNC - 1)//horizontal sync end
		hs_reg <= ~hs_reg;
	else
		hs_reg <= hs_reg;
end

always@(posedge clk or posedge rst)
begin
	if(rst == 1'b1)
		h_active <= 1'b0;
	else if(h_cnt == H_FP + H_SYNC + H_BP - 1)//horizontal active begin
		h_active <= 1'b1;
	else if(h_cnt == H_TOTAL - 1)//horizontal active end
		h_active <= 1'b0;
	else
		h_active <= h_active;
end

always@(posedge clk or posedge rst)
begin
	if(rst == 1'b1)
		vs_reg <= 1'd0;
	else if((v_cnt == V_FP - 1) && (h_cnt == H_FP - 1))//vertical sync begin
		vs_reg <= HS_POL;
	else if((v_cnt == V_FP + V_SYNC - 1) && (h_cnt == H_FP - 1))//vertical sync end
		vs_reg <= ~vs_reg;  
	else
		vs_reg <= vs_reg;
end

always@(posedge clk or posedge rst)
begin
	if(rst == 1'b1)
		v_active <= 1'd0;
	else if((v_cnt == V_FP + V_SYNC + V_BP - 1) && (h_cnt == H_FP - 1))//vertical active begin
		v_active <= 1'b1;
	else if((v_cnt == V_TOTAL - 1) && (h_cnt == H_FP - 1)) //vertical active end
		v_active <= 1'b0;   
	else
		v_active <= v_active;
end

wire [7:0] wfRed;
wire [7:0] wfGreen;
wire [7:0] wfBlue;

midmap midmap0(
		.i_pixel(i_wfPixel),
		.o_r(wfRed),
		.o_g(wfGreen),
		.o_b(wfBlue)
);


always@(posedge clk or posedge rst)
begin
	if(rst == 1'b1)
    begin /* RESET is active */
        rgb_r_reg <= 8'h00;
        rgb_g_reg <= 8'h00;
        rgb_b_reg <= 8'h00;
    end
    else if(video_active)
	    begin
	        /*** spectrum amplitude ***/
            if(active_y < SPECTRUMSIZE) 
            begin
                if(i_amplitude >= scopePos_y[8:1])
                    rgb_g_reg <= 8'hFF;
                else
                    rgb_g_reg <= 8'h00;

                /* horizontal grid */                    
                if(active_x[4:0] == 0)
                    rgb_b_reg <= BLUE_B;
                else /* vertical grid */
                    if((active_y % 53) == 0)
                        rgb_b_reg <= BLUE_B;
                    else
                        rgb_b_reg <= BLACK_B;

                if(active_y == SPECTRUMSIZE-1) /* we indicate one line before starting the waterfall */ 
                    o_wf_sync <= 1;
            end
            else
            /*** waterfall ***/
            begin
                o_wf_sync <= 0;
                rgb_r_reg <= wfRed;
                rgb_g_reg <= wfGreen;
                rgb_b_reg <= wfBlue;
            end
        end 
        else
		begin
            if(active_y < SPECTRUMSIZE+WATERFALLSIZE) 
            begin
                rgb_r_reg <= 8'h00;
                rgb_g_reg <= 8'h00;
                rgb_b_reg <= 8'h00;
            end
        end
end


assign o_ReadStrobe = ~clk;
assign o_addr = active_x;

endmodule 