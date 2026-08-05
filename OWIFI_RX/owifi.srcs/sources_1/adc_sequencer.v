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
`timescale 1ns / 1ps

module adc_sequencer #(
    parameter MEMORYWIDTH = 10,
    // DCLK cycles per deserialized word: 6 for ADC3424 1-wire/12x DDR
    // (120MHz DCLK / 20MSPS). A 2-wire/6x build (125MSPS target) divides by
    // SER_BITS/2 = 3 - change together with lvds_rx's SER_BITS.
    parameter DCLKS_PER_WORD = 6
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

/* i_lvds_frameClk is an async input (the XDC false-paths FCLK): 2-FF
   synchronize it before the preSync FSM looks at it, so a marginal sample
   can at most shift the observed edge by one cycle instead of tearing the
   FSM. The absolute lock phase is arbitrary anyway (top.v's word-rotation
   calibration absorbs any constant offset) - only stability matters.
   fclk_expect: learned CKPCEdiv position of the FCLK rising edge after
   lock; a persistent (RESYNC_N consecutive frames) offset means a true
   slip and forces a re-lock. Isolated jitter must not. */
localparam RESYNC_N = 4'd15;
reg  [1:0] fclk_sync;   initial fclk_sync = 0;
reg        fclk_s_d;    initial fclk_s_d = 0;
reg  [3:0] fclk_expect; initial fclk_expect = 0;
reg        expect_valid; initial expect_valid = 0;
reg  [3:0] resync_ctr;  initial resync_ctr = 0;
wire fclk_s    = fclk_sync[1];
wire fclk_rise = fclk_s & ~fclk_s_d;

/* The following registers are temporary so at the end all get transferred at the same time. */
/* Not sure, if this pipelining is stell needed in the latest design. */
reg adc_frameStrobe_tmp;
reg adc_processClock_tmp;
reg fft_frameStrobe_tmp;
reg [MEMORYWIDTH-1:0] frameCounter_tmp;
reg mem_sampleStrobe_tmp;

always @(posedge i_lvds_bitClk) /* 120MHz driven */
begin
    fclk_sync <= {fclk_sync[0], i_lvds_frameClk};
    fclk_s_d  <= fclk_s;

    if(i_rst == 1'b1) begin
        preSync <= 0;
        CKPCEdiv <= 0;
        adc_frameStrobe_tmp <= 0;
        fft_frameStrobe_tmp <= 0;
        frameCounter_tmp <= 0;
        mem_sampleStrobe_tmp <= 0;
        adc_processClock_tmp <= 0;
        expect_valid <= 0;
        resync_ctr <= 0;
    end
    else if(preSync == 0) begin  // A: wait for low phase of lvds_frame
        expect_valid <= 0;
        resync_ctr <= 0;
        if(fclk_s == 0)          // after start, frameClock must be in a 0 phase first
            preSync <= 1;
    end
	else if(preSync == 1) begin
        if(fclk_s == 1)          // B: wait for first high phase
            preSync <= 2;
	end
    else if(preSync == 2) begin  // b: wait for second high - else this wont work!
        if(fclk_s == 1) begin
            preSync <= 3;
			CKPCEdiv <= 0;
        end
		else
            preSync <= 0;
    end
    else begin /* this else is only entered if CKPCEdiv his higher than 1 */

        /* slip watchdog: learn where the synchronized FCLK edge sits in the
           divider cycle, then require it to stay there. Only RESYNC_N
           CONSECUTIVE mismatches (a true slip, e.g. ADC restart) force a
           re-lock - a single jittered edge sample through the synchronizer
           must not (and a re-lock shifts all strobes by whole word periods
           only, which the word-rotation calibration in top.v is immune to). */
        if (fclk_rise) begin
            if (!expect_valid) begin
                fclk_expect  <= CKPCEdiv;
                expect_valid <= 1;
                resync_ctr   <= 0;
            end
            else if (CKPCEdiv != fclk_expect) begin
                if (resync_ctr == RESYNC_N)
                    preSync <= 0; // re-lock (expect_valid/resync_ctr clear in state 0)
                else
                    resync_ctr <= resync_ctr + 1'b1;
            end
            else
                resync_ctr <= 0;
        end

        /* Loop handling. RASPMO: ADC3424 runs 12-bit one-wire DDR at 20MSPS on a
           120MHz DCLK -> a NEW deserialized word every 120/20 = 6 DCLK, so the
           sequencer must divide by 6 (count 0..5, as the comment always said).
           The former terminal count of 2 (div-by-3) was inherited from RASM2400's
           40MSPS (120/40=3) and made every strobe fire TWICE per word - the FFT
           ingested each sample twice (confirmed on ILA: adc_frameStrobe at two
           bitctr phases per word), producing a spectral image + ~6dB peak split. */
        if(CKPCEdiv == DCLKS_PER_WORD-1) /* we're running from 0 to DCLKS_PER_WORD-1 */
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

