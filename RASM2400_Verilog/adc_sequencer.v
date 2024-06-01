`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// 
// 
// Create Date: 25.04.2024 10:29:54
// Design Name: RASM2400
// Module Name: adc_sequencer
// Project Name: Radio Access Spectrum Monitor 2400MHz
// Engineer: Tobias Weber
// Target Devices: Artix 7, XC7A100T
// Tool Versions: Vivado 2024.1
// Description: 
// 
// Dependencies: 
// 
// Revision: 
// Revision 1.00 - File Created
// Additional Comments: https://github.com/Tobias-DG3YEV/RA-Sentinel
// 
//////////////////////////////////////////////////////////////////////////////////


module adc_sequencer #(
    parameter MEMORYWIDTH = 10
)(
    input wire i_lvds_frameClk, /* the frame clock from ADC LVDS port, 40MHz @ 40MSPS */
    input wire i_lvds_bitClk,   /* the bit clock from ADC LVDS port, 120MHz @ 40MSPS */
    input wire i_fft_lineSync,  /* */
    input wire i_rst, /* reset, high active */
    output reg o_adc_frameStrobe, /* goes high for one bitClk phase when a FFT parallel ADC result is valid. */
    output reg o_fft_frameStrobe, /* goes high when an FFT calculatin result is ready */
    output reg [MEMORYWIDTH-1:0] o_frameCounter, /* counts up frames (sample pairs) untill a fft_lineSync strobe come in. This is used to fil up the 1024 wide spectrum point memory */
    output reg o_mem_sampleStrobe /* goues high when a processed spectrum word is ready to be written into the memory */
);

(* keep = "true" *) reg [3:0] CKPCEdiv; /* the sequencer has 8 phases, I "keep" it for debugging purposes */
initial CKPCEdiv = 0;
reg [1:0] preSync;
initial preSync = 0;

/* The following registers are temporary so at the end all get transferred at the same time. */
/* Not sure, if this pipelining is stell needed in the latest design. */
reg adc_frameStrobe_tmp;
reg adc_processClock_tmp;
reg fft_frameStrobe_tmp;
reg [MEMORYWIDTH-1:0] frameCounter_tmp;
reg mem_sampleStrobe_tmp;

/*

				  _________         ___
Frame FCLK		_|        |________|
                  ______      ___
Data			_|     |_____|  |______
				   ___   ___   ___   __
Data DCLK		__|  |__|  |__|  |__|  
Bit #			  0  1  2  3  4  5  0  
Value (LSB first) 1  1  0  0  1  0  0 => reversed 10011 = 


*/

always @(posedge i_lvds_bitClk) /* 120MHz driven */
begin
    if(i_rst == 1'b1) begin
        preSync <= 0;
        CKPCEdiv <= 0;
        adc_frameStrobe_tmp <= 0;
        fft_frameStrobe_tmp <= 0;
        frameCounter_tmp <= 0;
        mem_sampleStrobe_tmp <= 0;
    end
    else if(preSync == 0) begin  // A: wait for low phase of lvds_frame
        if(i_lvds_frameClk == 0) // after start, frameClock must be in a 0 phase first
            preSync <= 1;
    end
	else if(preSync == 1) begin
        if(i_lvds_frameClk == 1) // B: wait for first high phase
            preSync <= 2;
	end
    else if(preSync == 2) begin  // b: wait for second high - else this wont work! 
        if(i_lvds_frameClk == 1) begin
            preSync <= 3;
            //adc_processClock_tmp <= 1;
			CKPCEdiv <= 0;
        end
		else
            preSync <= 0;
    end
    else begin /* this else is only entered if CKPCEdiv his higher than 1 */

        /* Loop handling */
        if(CKPCEdiv == 2) /* we're running from 0 to 5 */
           CKPCEdiv <= 0;
        else
          CKPCEdiv <= CKPCEdiv + 1;

        /* generate the CE for ADC -> FFT */
        if(CKPCEdiv == 2)
          adc_frameStrobe_tmp <= 1;
        else
          adc_frameStrobe_tmp <= 0;

        /* generate CE for FFT -> logfn */
        if(CKPCEdiv == 1)
            fft_frameStrobe_tmp <= 1;
        else
            fft_frameStrobe_tmp <= 0;

        /* generate CE for Logfn -> Memory */
        if(CKPCEdiv == 1)
            mem_sampleStrobe_tmp <= 1;
        else
            mem_sampleStrobe_tmp <= 0;
			            
        /* sync the sample write counter to logfn output */
        if(CKPCEdiv == 0)
            if(i_fft_lineSync == 1'b1) 
                frameCounter_tmp <= 0;
            else
                frameCounter_tmp <= frameCounter_tmp + 1;
	end
end

always @(posedge i_lvds_bitClk) /* 120MHz driven */
begin
     if(i_rst == 1'b1)
     begin
        o_adc_frameStrobe <= 0;
        o_fft_frameStrobe <= 0;
        o_frameCounter <= 0;
        o_mem_sampleStrobe <= 0;
     end
     else
     begin
        o_adc_frameStrobe <= adc_frameStrobe_tmp;
        o_fft_frameStrobe <= fft_frameStrobe_tmp;
        o_frameCounter <= frameCounter_tmp;
        o_mem_sampleStrobe <= mem_sampleStrobe_tmp;
     end
end

endmodule

