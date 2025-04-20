//////////////////////////////////////////////////////////////////////////////////
// 
// Design Name: RASM2400
// Module Name: video_define
// Project Name: Radio Access Spectrum Monitor 2400MHz
// Engineer: Tobias Weber
// Target Devices: Artix 7, XC7A100T
// Create Date: 25.04.2024 10:29:54
// Tool Versions: Vivado 2024.1
// Description:  HDMI Video definitions. Also set your wanted resolution in here!
//               Adapted version if the code of ALINX(shanghai) Technology Co.,Ltd
// 
// Dependencies: none
// 
// Revision: 
// Revision 1.00 - File Created
// Additional Comments:
// 
// Project page: https://github.com/Tobias-DG3YEV/RA-Sentinel^M
///////////////////////////////////////////////////////////////////////////////////
//                                                                              //
// Copyright (c) 2017,ALINX(shanghai) Technology Co.,Ltd                        //
//                    All rights reserved                                       //
//                                                                              //
// This source file may be used and distributed without restriction provided    //
// that this copyright statement is not removed from the file and that any      //
// derivative work contains the original copyright notice and the associated    //
// disclaimer.                                                                  //
//                                                                              //
//                                                                              //
//////////////////////////////////////////////////////////////////////////////////

/*  this is the resoltion the project will use. Change it to your needs. */
`define	VIDEO_1024_768

//video timing localparam definition
`ifdef  VIDEO_1280_720
localparam H_ACTIVE = 16'd1280;           //horizontal active time (pixels)
localparam H_FP = 16'd110;                //horizontal front porch (pixels)
localparam H_SYNC = 16'd40;               //horizontal sync time(pixels)
localparam H_BP = 16'd220;                //horizontal back porch (pixels)
localparam V_ACTIVE = 16'd720;            //vertical active Time (lines)
localparam V_FP  = 16'd5;                 //vertical front porch (lines)
localparam V_SYNC  = 16'd5;               //vertical sync time (lines)
localparam V_BP  = 16'd20;                //vertical back porch (lines)
localparam HS_POL = 1'b1;                 //horizontal sync polarity, 1 : POSITIVE,0 : NEGATIVE;
localparam VS_POL = 1'b1;                 //vertical sync polarity, 1 : POSITIVE,0 : NEGATIVE;
`endif

//480x272 9Mhz
`ifdef  VIDEO_480_272
localparam H_ACTIVE = 16'd480; 
localparam H_FP = 16'd2;       
localparam H_SYNC = 16'd41;    
localparam H_BP = 16'd2;       
localparam V_ACTIVE = 16'd272; 
localparam V_FP  = 16'd2;     
localparam V_SYNC  = 16'd10;   
localparam V_BP  = 16'd2;     
localparam HS_POL = 1'b0;
localparam VS_POL = 1'b0;
`endif

//640x480 25.175Mhz
`ifdef  VIDEO_640_480
localparam H_ACTIVE = 16'd640; 
localparam H_FP = 16'd16;      
localparam H_SYNC = 16'd96;    
localparam H_BP = 16'd48;      
localparam V_ACTIVE = 16'd480; 
localparam V_FP  = 16'd10;    
localparam V_SYNC  = 16'd2;    
localparam V_BP  = 16'd33;    
localparam HS_POL = 1'b0;
localparam VS_POL = 1'b0;
`endif

//800x480 33Mhz
`ifdef  VIDEO_800_480
localparam H_ACTIVE = 16'd800; 
localparam H_FP = 16'd40;      
localparam H_SYNC = 16'd128;   
localparam H_BP = 16'd88;      
localparam V_ACTIVE = 16'd480; 
localparam V_FP  = 16'd1;     
localparam V_SYNC  = 16'd3;    
localparam V_BP  = 16'd21;    
localparam HS_POL = 1'b0;
localparam VS_POL = 1'b0;
`endif

//800x600 40Mhz
`ifdef  VIDEO_800_600
localparam H_ACTIVE = 16'd800; 
localparam H_FP = 16'd40;      
localparam H_SYNC = 16'd128;   
localparam H_BP = 16'd88;      
localparam V_ACTIVE = 16'd600; 
localparam V_FP  = 16'd1;     
localparam V_SYNC  = 16'd4;    
localparam V_BP  = 16'd23;    
localparam HS_POL = 1'b1;
localparam VS_POL = 1'b1;
`endif

//1024x768 65Mhz
`ifdef  VIDEO_1024_768
localparam H_ACTIVE = 16'd1024;
localparam H_FP = 16'd24;      
localparam H_SYNC = 16'd136;   
localparam H_BP = 16'd160;     
localparam V_ACTIVE = 16'd768; 
localparam V_FP  = 16'd3;      
localparam V_SYNC  = 16'd6;    
localparam V_BP  = 16'd29;     
localparam HS_POL = 1'b0;
localparam VS_POL = 1'b0;
`endif

//1920x1080 148.5Mhz (clk2 742.5MHz)
`ifdef  VIDEO_1920_1080
localparam H_ACTIVE = 16'd1920;
localparam H_FP = 16'd88;
localparam H_SYNC = 16'd44;
localparam H_BP = 16'd148; 
localparam V_ACTIVE = 16'd1080;
localparam V_FP  = 16'd4;
localparam V_SYNC  = 16'd5;
localparam V_BP  = 16'd36;
localparam HS_POL = 1'b1;
localparam VS_POL = 1'b1;
`endif
localparam H_TOTAL = H_ACTIVE + H_FP + H_SYNC + H_BP;//horizontal total time (pixels)
localparam V_TOTAL = V_ACTIVE + V_FP + V_SYNC + V_BP;//vertical total time (lines)
//define the RGB values for 8 colors
localparam WHITE_R       = 8'hff;
localparam WHITE_G       = 8'hff;
localparam WHITE_B       = 8'hff;
localparam YELLOW_R      = 8'hff;
localparam YELLOW_G      = 8'hff;
localparam YELLOW_B      = 8'h00;                                
localparam CYAN_R        = 8'h00;
localparam CYAN_G        = 8'hff;
localparam CYAN_B        = 8'hff;                                
localparam GREEN_R       = 8'h00;
localparam GREEN_G       = 8'hff;
localparam GREEN_B       = 8'h00;
localparam MAGENTA_R     = 8'hff;
localparam MAGENTA_G     = 8'h00;
localparam MAGENTA_B     = 8'hff;
localparam RED_R         = 8'hff;
localparam RED_G         = 8'h00;
localparam RED_B         = 8'h00;
localparam BLUE_R        = 8'h00;
localparam BLUE_G        = 8'h00;
localparam BLUE_B        = 8'hff;
localparam BLACK_R       = 8'h00;
localparam BLACK_G       = 8'h00;
localparam BLACK_B       = 8'h00;

