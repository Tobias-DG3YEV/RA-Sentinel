//////////////////////////////////////////////////////////////////////////////////
// 
// Design Name: RASM2400
// Module Name: adc_sequencer
// Project Name: Radio Access Spectrum Monitor 2400MHz
// Engineer: Tobias Weber
// Target Devices: Artix 7, XC7A100T
// Create Date: 25.04.2024 10:29:54
// Tool Versions: Vivado 2024.1
// Description: this sycnronises the pipeline between the signal
//              processing blocks.
// Dependencies: none
// 
// Revision: 
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

module adc_sequencer #(
    parameter MEMORYWIDTH = 10
)(
    input wire i_lvds_frameClk, // the frame clock from ADC LVDS port, 40MHz @ 40MSPS
    input wire i_lvds_bitClk,   // the bit clock from ADC LVDS port, 120MHz @ 40MSPS
    input wire i_fft_lineSync,  // must strobe when a complete fft line has been processed
    input wire i_rst,           // reset, high active
    output reg o_adc_frameStrobe, // goes high for one bitClk phase when a FFT parallel ADC result is valid.
    output reg o_fft_frameStrobe, // goes high when an FFT calculatin result is ready
    output reg [MEMORYWIDTH-1:0] o_frameCounter, // counts up frames (sample pairs) untill a fft_lineSync strobe come in. This is used to fil up the 1024 wide spectrum point memory
    output reg o_mem_sampleStrobe // goues high when a processed spectrum word is ready to be written into the memory */
);

reg [3:0] CKPCEdiv; // the sequencer has 8 phases, I "keep" it for debugging purposes
initial CKPCEdiv = 0;
reg [1:0] preSync; //The pre-sync state machine. It runs at start to sync this module to the ADC frame clock
initial preSync = 0;

/* The following registers are temporary so at the end all get transferred at the same time. */
/* Not sure, if this pipelining is stell needed in the latest design. */
reg adc_frameStrobe_tmp;
reg adc_processClock_tmp;
reg fft_frameStrobe_tmp;
reg [MEMORYWIDTH-1:0] frameCounter_tmp;
reg mem_sampleStrobe_tmp;

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
        if(CKPCEdiv == 1 /*|| CKPCEdiv == 2*/)
            mem_sampleStrobe_tmp <= 1;
        else
            mem_sampleStrobe_tmp <= 0;
			            
        /* sync the sample write counter to logfn output */
        if(CKPCEdiv == 2)
            if(i_fft_lineSync == 1'b1) 
                frameCounter_tmp <= 0;
            else
                frameCounter_tmp <= frameCounter_tmp + 1;
	end
end

// we pipeline all output regs, maybe not even needed anymore...
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

