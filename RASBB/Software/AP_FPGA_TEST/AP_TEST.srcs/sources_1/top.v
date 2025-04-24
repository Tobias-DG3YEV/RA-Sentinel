//////////////////////////////////////////////////////////////////////////////////
// 
// Design Name: RASM2400
// Module Name: top of RASM2400
// Project Name: Radio Access Spectrum Monitor 2400MHz
// Engineer: Tobias Weber
// Target Devices: Artix 7, XC7A100T
// Create Date: 25.04.2024 10:29:54
// Tool Versions: Vivado 2024.1
// Description:  the top level module
// 
// Dependencies: adc_cequencer.v, screen.v, lvds_rx.v, midmap.v, fft/*.v
// 
// Revision: 1.01 adde peak hold & decay functionality
// Revision 1.00 - File Created
// Additional Comments: https://github.com/Tobias-DG3YEV/RA-Sentinel
// 
// Funded by NGI0 Entrust nlnet foundation
// https://nlnet.nl/project/RA-Sentinel/
//
// Project page: https://github.com/Tobias-DG3YEV/RA-Sentinel^M
///////////////////////////////////////////////////////////////////////////////////
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
`timescale 1ns / 1ps

`include "rasm2400_pre_def.vh"

module top(
    // Master Clock Input (50MHz)
    input wire SYS_clk,
    // HDMI output
    output wire TMDS_clk_n,
    output wire TMDS_clk_p,
    output wire [2:0]TMDS_data_n,
    output wire [2:0]TMDS_data_p,
    // ADC LVDS input
    input wire         ADC_idataH_P, /* ADC I serial Data */
    input wire         ADC_idataH_N, /* ADC I serial Data */
    input wire         ADC_idataL_P, /* ADC I serial Data */
    input wire         ADC_idataL_N, /* ADC I serial Data */
    input wire         ADC_qdataH_P, /* ADC I serial Data */
    input wire         ADC_qdataH_N, /* ADC I serial Data */
    input wire         ADC_qdataL_P, /* ADC I serial Data */
    input wire         ADC_qdataL_N, /* ADC I serial Data */
    input wire         ADC_frame_P, /* ADC frame clock */
    input wire         ADC_frame_N,
    input wire         ADC_bitclk_P, /* ADC bit clock*/
    input wire         ADC_bitclk_N, /* ADC bit clock*/
    // Debug output (optional)
    output wire [11:0]  dbgOutI,
    output wire [11:0]  dbgOutQ,
    output wire         dbgFrameRdy,
	output wire			dbgBitClk,
    // keys / buttons
	// jumpers
	input wire [5:0]    Jumpers
);


// -----------------------------------------------------------------------------
// Parameters
// -----------------------------------------------------------------------------
parameter FFTLEN = 10; //FFT length in bits
parameter ADCBITS = 12;
parameter SCREENWIDTH = 1024; //must match 2^FFTLEN
parameter WATERFALLHEIGHT = 256;
parameter WFMEMWIDTH = 18; /* number of bits the waterfall memory address uses */
parameter C_IODELAY_GROUP = "adc_if_delay_group";

localparam DATA_DELAY_VALUE_DR0 = 31; /* data line delay */
localparam DATA_DELAY_VALUE_DR1 = 28;
localparam DATA_DELAY_VALUE_DI0 = 28;
localparam DATA_DELAY_VALUE_DI1 = 28;
localparam DCLK_DELAY = 0; // Bit Clock Delay
localparam FS_DELAY = 0;  // Frame Sync delay
localparam DLYTYPE = "FIXED";

assign dbgFrameRdy = sampleStrobe;
assign dbgBitClk = 0;

//------------------------------------------------------------------------------
// Signals
//------------------------------------------------------------------------------
wire Key0; /* Wukong board key 0 - RESET */
wire Key1;  /* Wukong board key 1 */

assign Key0 = Jumpers[0:0];
assign Key1 = Jumpers[1:1];

wire global_rst;
assign global_rst = ~Key0;

// LVDS ADC signals
(* keep = "true" *) wire [ADCBITS-1:0] adc_ipar; // ADC I paralell data
(* keep = "true" *) wire [ADCBITS-1:0] adc_qpar; // ADC Q paralell data
wire adc_frameStrobe; // a frame from the ADC deserializer is ready
(* keep = "true" *) wire sampleStrobe;

// HDMI video signals
wire clk_65M;
wire clk_120M;
wire clk_325M;
wire master_clk;
`ifdef USE_SPECTRUM
wire video_hs;
wire video_vs;
wire video_de;
wire[7:0] video_r;
wire[7:0] video_g;
wire[7:0] video_b;

// spectrum to Screen transfer wires
wire[7:0]   scr_rdSpecAmpl;
wire        scr_rdStrobe;
wire[9:0]   scr_rdAddr;

wire                fft_lineSync; /* goes high if a new line of 2^FFTLEN points is ready to be written out */
wire[31:0]          fft_result; /* the result of one fft process step, cosinst of {imaginary[], real[]}*/
// LOG function

// Waterfall
wire [7:0]          wf_rdSpecAmpl; /* one value of the spectrum read from the waterfall memory */
`endif

/*******************/
/* Video Clock Gen */
/*******************/
wire clk_195M;

Video_clk video_clk0 (
    .i_clk_50M(SYS_clk),
    .o_clk_65M(clk_65M),
    .o_clk_325M(clk_325M),
    .o_clk_195M(clk_195M),
    .o_clk_120M(clk_120M),
    .reset(1'b0),
    .locked()
);

assign master_clk = clk_120M;


/****************************************************************************
    
       #     ######    #####          #        #     #  ######    #####
      # #    #     #  #     #         #        #     #  #     #  #     #
     #   #   #     #  #               #        #     #  #     #  #
    #     #  #     #  #               #        #     #  #     #   #####
    #######  #     #  #               #         #   #   #     #        #
    #     #  #     #  #     #         #          # #    #     #  #     #
    #     #  ######    #####          #######     #     ######    #####
    
/****************************************************************************/


// decoding from serial to parallel
lvds_rx #(
	12
) lvds_irx0 (
    .i_lvds_dclk_P(ADC_bitclk_P), // 120/60 MHz
    .i_lvds_dclk_N(ADC_bitclk_N), // 120/60 MHz
    .i_lvds_fclk_P(ADC_frame_P), // 40/20 MHz
    .i_lvds_fclk_N(ADC_frame_N), // 40/20 MHz
    .i_lvds_dr0_P(ADC_qdataL_P),  // data lane 0 real part, lower bits
    .i_lvds_dr0_N(ADC_qdataL_N),  // data lane 0 real part, lower bits
    .i_lvds_di0_P(ADC_idataL_P),  // data lane 0 imaginary part, higher 6 bits
    .i_lvds_di0_N(ADC_idataL_N),  // data lane 0 imaginary part, higher 6 bits
    .i_lvds_dr1_P(ADC_qdataH_P),  // data lane 1 real part, lower 6 bits
    .i_lvds_dr1_N(ADC_qdataH_N),  // data lane 1 real part, lower 6 bits
    .i_lvds_di1_P(ADC_idataH_P),  // data lane 1 imaginary part, higher 6 bits
    .i_lvds_di1_N(ADC_idataH_N),  // data lane 1 imaginary part, higher 6 bits
    .i_masterClk(master_clk),
    .i_delayClk(clk_195M),
	.i_rst(global_rst),
    .o_sampleStrobe(sampleStrobe),
	.o_dataOut_I(adc_ipar),
	.o_dataOut_R(adc_qpar)
);



`ifdef USE_PAR_DBG_OUT
assign dbgOutI[ADCBITS-1:0] = adc_ipar[ADCBITS-1:0];
assign dbgOutQ[ADCBITS-1:0] = adc_qpar[ADCBITS-1:0];
`else
assign dbgOutI[ADCBITS-1:0] = 0;
assign dbgOutQ[ADCBITS-1:0] = 0;
`endif


`ifdef USE_SPECTRUM

/***************************************************************************************
	 #####   #######   #####   #     #  #######  #     #   #####   #######  ######
	#     #  #        #     #  #     #  #        ##    #  #     #  #        #     #
	#        #        #     #  #     #  #        # #   #  #        #        #     #
	 #####   #####    #     #  #     #  #####    #  #  #  #        #####    ######
		  #  #        #   # #  #     #  #        #   # #  #        #        #   #
	#     #  #        #    #   #     #  #        #    ##  #     #  #        #    #
	 #####   #######   #### #   #####   #######  #     #   #####   #######  #     #
****************************************************************************************/

wire fft_frameStrobe;
wire mem_wordWrStrobe;

/* we buffer the clock here for firther blocks to avoid that the synth. Tool
   inserts its own BUFG which would lead to unpredictive line delay. */
wire lvds_dclk_buffered; 

BUFG BUFG_lvds_dclk_1 (
	.I(lvds_dclk),
	.O(lvds_dclk_buffered)
);

wire lvds_fclk_buffered;

BUFG BUFG_lvds_fclk_1 (
	.I(lvds_fclk),
	.O(lvds_fclk_buffered)
);

wire [FFTLEN-1:0] adc_frameCounter;

adc_sequencer adc_sequencer0
(
    .i_lvds_frameClk(lvds_fclk_buffered),
    .i_lvds_bitClk(lvds_dclk_buffered),
    .i_fft_lineSync(logfn_lineSync),
    .i_rst(global_rst),
    .o_adc_frameStrobe(adc_frameStrobe),
    .o_fft_frameStrobe(fft_frameStrobe),
    .o_frameCounter(adc_frameCounter),
    .o_mem_sampleStrobe(mem_wordWrStrobe)
);

/* reform the spectrum parts so the upper and lower parts fit */
wire[FFTLEN-1:0]    mem_wrAddr;
assign mem_wrAddr = {~adc_frameCounter[FFTLEN-1], adc_frameCounter[FFTLEN-2:0]};

/**********************************************************************************
	######      #     #     #   ###    #####          #######  #######  #######
	#     #    # #    ##    #   ###   #     #         #        #           #
	#     #   #   #   # #   #    #    #               #        #           #
	#     #  #     #  #  #  #   #      #####          #####    #####       #
	#     #  #######  #   # #               #         #        #           #
	#     #  #     #  #    ##         #     #         #        #           #
	######   #     #  #     #          #####          #        #           #
***********************************************************************************/
fftmain fft0(
    .i_clk(lvds_dclk_buffered),
    .i_reset(global_rst),
    .i_ce(adc_frameStrobe),
    .i_sample({adc_qpar, adc_ipar}),
    .o_result(fft_result),
    .o_sync(fft_lineSync)
);

/***************************/
/*  Calculate the log of the squared output  */
/***************************/
localparam logfn_ow = 9; //witdh of the output of the log() module

wire                logfn_lineSync; /* goes high if a new sequence of log() processed points is ready to be written out */
wire[logfn_ow-1:0]  logfn_result; /* the result of one log() process step, equals about 2.66dB per step */

logfn #(
    16, 8
) logfn_0 (

    .i_clk(lvds_dclk_buffered),
    .i_reset(global_rst),
    .i_ce(fft_frameStrobe),
    .i_sync(fft_lineSync),
    .i_real(fft_result[31:16]),
    .i_imag(fft_result[15:0]),
    .o_sample(logfn_result),
    .o_sync(logfn_lineSync)
);

/***********************************************************************************************************
     #####   ######   #######   #####   #######  ######   #     #  #     #       ######      #     #     #
    #     #  #     #  #        #     #     #     #     #  #     #  ##   ##       #     #    # #    ##   ##
    #        #     #  #        #           #     #     #  #     #  # # # #       #     #   #   #   # # # #
     #####   ######   #####    #           #     ######   #     #  #  #  #       ######   #     #  #  #  #
          #  #        #        #           #     #   #    #     #  #     #       #   #    #######  #     #
    #     #  #        #        #     #     #     #    #   #     #  #     #       #    #   #     #  #     #
     #####   #        #######   #####      #     #     #   #####   #     #       #     #  #     #  #     #
***********************************************************************************************************/

wire spectrumActive;

(* keep = "true" *) reg [1:0] wrSpec_state;
localparam state_wrSpec_read  = 2'b00;
localparam state_wrSpec_write = 2'b01;
localparam state_wrSpec_wait  = 2'b10;
initial wrSpec_state = state_wrSpec_read;

(* keep = "true" *) reg wrSpec_wea;
initial wrSpec_wea = 0;
(* keep = "true" *) reg wrPeak_wea;
initial wrPeak_wea = 0;
(* keep = "true" *) reg [7:0] wrSpec_new;
(* keep = "true" *) reg [7:0] wrSpec_peak;
wire [7:0] wrSpec_old;
wire [7:0] wrPeak_old;
reg [2:0] wrPeak_decCtr; //decline counter

always@(posedge wf_RdScreenSync)
begin
    wrPeak_decCtr <= wrPeak_decCtr - 1;
end

wire peakDec;
assign peakDec = (wrPeak_decCtr == 0);

always@(negedge lvds_dclk_buffered)
begin

    case(wrSpec_state)

        state_wrSpec_read:
        begin
            if(mem_wordWrStrobe == 1'b1) begin
                
                wrSpec_peak <= (wrSpec_old < wrPeak_old) ? (wrPeak_old - peakDec) : wrSpec_old;
                if(wf_RdScreenSync == 1) begin
                    wrSpec_new <= 0;
                    wrPeak_wea <= 1;
                end
                else begin
                    wrSpec_new <= (wrSpec_old < logfn_result) ? logfn_result : wrSpec_old;
                end
                wrSpec_wea <= 1;
                wrSpec_state <= state_wrSpec_write;
            end
        end

        state_wrSpec_write:
        begin
            wrSpec_wea <= 0;
            wrPeak_wea <= 0;
            wrSpec_state <= state_wrSpec_wait;
        end

        state_wrSpec_wait:
        begin
            wrSpec_state <= state_wrSpec_read;
        end

    endcase

end

blk_mem_gen_0
#(
)
blk_specMemory(
    //RAM input
    .clka(lvds_dclk_buffered),
    .addra(mem_wrAddr),
    .dina(wrSpec_new),
    .douta(wrSpec_old),
    .ena(1'b1),
    .wea(wrSpec_wea),
    //RAM output
    .enb(1'b1),
    .clkb(scr_rdStrobe),
    .addrb(scr_rdAddr),
    .doutb(scr_rdSpecAmpl),
    .dinb(0),
    .web(1'b0)
);


wire [7:0] scr_rdPeak;

blk_PeakMem 
#(
)
blk_specPeakMemory(
    //RAM input
    .clka(lvds_dclk_buffered),
    .addra(mem_wrAddr),
    .dina(wrSpec_peak),
    .douta(wrPeak_old),
    .ena(1'b1),
    .wea(wrPeak_wea),
    //RAM output
    .clkb(scr_rdStrobe),
    .addrb(scr_rdAddr),
    .doutb(scr_rdPeak),
    .dinb(1'b0),
    .web(1'b0)
);

/* waterfall to Screen transfer wires */
reg signed [7:0]                wf_RdLinePtr;
wire [WFMEMWIDTH-1:0]           wf_RdAddr; // read adress pointer 18 bits wide to address 256*1024
assign                          wf_RdAddr = { wf_RdLinePtr, scr_rdAddr };
(* keep = "true" *) reg [11:0]  wf_timeDivider;
initial                         wf_timeDivider = 0;
wire                            wf_RdScreenSync; // goes high when the screen starts with the first line of the waterfall
reg [7:0]                       wf_wrLinePtr;
initial                         wf_wrLinePtr = 0;
reg [WFMEMWIDTH-1:0]            wf_pixelWrPointer;
initial                         wf_pixelWrPointer = 0;
reg                             wf_CE;
initial                         wf_CE = 0;

/*********************************************************************************************************************
    #     #     #     #######  #######  ######   #######     #     #        #            ######      #     #     #
    #  #  #    # #       #     #        #     #  #          # #    #        #            #     #    # #    ##   ##
    #  #  #   #   #      #     #        #     #  #         #   #   #        #            #     #   #   #   # # # #
    #  #  #  #     #     #     #####    ######   #####    #     #  #        #            ######   #     #  #  #  #
    #  #  #  #######     #     #        #   #    #        #######  #        #            #   #    #######  #     #
    #  #  #  #     #     #     #        #    #   #        #     #  #        #            #    #   #     #  #     #
     ## ##   #     #     #     #######  #     #  #        #     #  #######  #######      #     #  #     #  #     #
**********************************************************************************************************************/

wire wfActive;

`ifdef USE_WATERFALL
waterfallMem wfMem0(
    //RAM input
    //.clka(mem_wordWrStrobe),
    .clka(lvds_dclk_buffered),
    .addra(wf_pixelWrPointer),
    //.dina(logfn_result),
    .dina(wrSpec_new),
    .wea(wrSpec_wea),
    //RAM output
    .enb(wfActive),
    .clkb(scr_rdStrobe),
    .addrb(wf_RdAddr),
    .doutb(wf_rdSpecAmpl),
    //control signals
    .rstb(global_rst),
    .rsta_busy(),
    .rstb_busy()
);

/* prepare write address register */
always @(negedge mem_wordWrStrobe)
begin
    wf_pixelWrPointer <= (wf_wrLinePtr << 10) + mem_wrAddr;
end

/* waterfall WRITE */
always @(posedge logfn_lineSync)
begin
    if(global_rst == 1'b1) begin // if reset is active:
        wf_CE <= 0;
        wf_timeDivider <= 0;
        wf_wrLinePtr <= 0;
    end
    else if(wf_timeDivider == 2048) /* is it time to add another line to the WF mem? */
    begin
        wf_CE <= 1; /* enable write access */
        wf_wrLinePtr <= wf_wrLinePtr + 1; /* advance to the next line in memory */
        wf_timeDivider <= 0;
    end
    else /* standby for next waterfall update */
    begin
        wf_timeDivider <= wf_timeDivider + 1;
        wf_CE <= 0; /* disable write access */
    end
end

/* Waterfall READ */
always @(posedge video_hs) /* pixel clock */
begin
    if(global_rst == 1'b1)
        wf_RdLinePtr <= 0;
    else
    begin
        if(wf_RdScreenSync == 1) /* end of line */
            wf_RdLinePtr <= wf_wrLinePtr - 1; /* when waterfall starts new, we rest read pointer to last pixel line written */
        else            
            wf_RdLinePtr <= wf_RdLinePtr - 1;
    end
end
`else

`endif //USE_WATERFALL

/***********************************************************
     #####    #####   ######   #######  #######  #     #
    #     #  #     #  #     #  #        #        ##    #
    #        #        #     #  #        #        # #   #
     #####   #        ######   #####    #####    #  #  #
          #  #        #   #    #        #        #   # #
    #     #  #     #  #    #   #        #        #    ##
     #####    #####   #     #  #######  #######  #     #
************************************************************/
screen #(
    .SPECTRUMSIZE(512), /* th amplitude of the spctrum is 8 bits , so 256 pixel in height are used by it */
    .WATERFALLSIZE(WATERFALLHEIGHT)
)
screen_0 (
    /* spectrum ports */
    .i_amplitude(scr_rdSpecAmpl),
    .i_peak(scr_rdPeak),
    .o_ReadStrobe(scr_rdStrobe),
    .o_addr(scr_rdAddr),
    .o_spectrumActive(spectrumActive),
    /* waterfall ports */
    .i_wfPixel(wf_rdSpecAmpl),
    .o_wf_sync(wf_RdScreenSync),
    .o_wfActive(wfActive),
    /* HDMI access */
	.i_pixClk(clk_65M), // Pixel clock = 65MHz @ 1024x768
	.i_rst(global_rst),
	.o_hs(video_hs),
	.o_vs(video_vs),
	.o_de(video_de),
	.o_rgb_r(video_r),
	.o_rgb_g(video_g),
	.o_rgb_b(video_b)
);

`else
`endif //USE_SPECTRUM

rgb2dvi
#(
      .kGenerateSerialClk(1'b0),
      .kClkRange(1),     
      .kRstActiveHigh(1'b1)
)
rgb2dvi_m0 (
     // DVI 1.0 TMDS video interface
      .TMDS_Clk_p(TMDS_clk_p),
      .TMDS_Clk_n(TMDS_clk_n),
      .TMDS_Data_p(TMDS_data_p),
      .TMDS_Data_n(TMDS_data_n),
      
     //Auxiliary signals 
      .aRst(global_rst), //asynchronous reset; must be reset when RefClk is not within spec
      .aRst_n(~global_rst), //-asynchronous reset; must be reset when RefClk is not within spec
      
      // Video in
      .vid_pData( { video_r, video_b, video_g } ),
      .vid_pVDE(video_de),
      .vid_pHSync(video_hs),
      .vid_pVSync(video_vs),
      .PixelClk(clk_65M),
      .SerialClk(clk_325M)// 5x PixelClk
);


/*****************************

 Jumper handling 
 
****************************/
/*
reg key_active;
reg key1_temp;
reg [15:0] keyCtr;
initial key_active = 1'b0;
initial key1_temp = 0;
initial keyCtr = 0;

//assign lineDelayCS[0] = Jumper[0:0];

assign lineDelayInc = ~Key0;

integer j;

always @(posedge clk_65M)
begin

    if(Key0 == 1'b0 || Key1 == 1'b0) begin
        if(key_active == 1'b0) //already activated?
        begin // not yet
            keyCtr <= keyCtr - 1; // count down
            if(keyCtr == 16'd1)
            begin // time to trigger
                key_active <= 1'b1;
                for (j = 0; j < 6; j = j + 1) begin //transfer the inverted jumper settings (PullDown) to the chip selects 
                    lineDelayCS[j] <= ~Jumpers[j];
                end
            end
        end
     end
    else begin
        keyCtr <= 16'h0;
        key_active <= 1'b0;
        for (j = 0; j < 6; j = j + 1) begin
            lineDelayCS[j] <= 1'b0;
        end
    end
end
*/
endmodule
