//////////////////////////////////////////////////////////////////////////////////
// 
// Project Name: RA-Sentinel
// 
// Module Name: conf_registers
//
// Engineer: Tobias Weber
// Target Devices: Artix 7, XC7A100T
// Tool Versions: Vivado 2024.1
// Description: A simple SPI Peripheral that allows read and write access to
// 				internal registers. The adressing is done in I2C scheme,
//				means the lowest address bit is the Read/Write Bit.
// 				With this it is possible to read the previous content of register
// 
// Fork of the openofdm project
// https://github.com/jhshi/openofdm
// 
// Dependencies: SPI_Peripheral
// 
// Revision 1.00 - File Created
// Project: https://github.com/Tobias-DG3YEV/RA-Sentinel
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

module conf_registers #(
	parameter ADDR_WIDTH = 7,
	parameter BUS_WIDTH = 32,
	parameter REG_WIDTH = 32
)(
	input i_clock,
	input i_reset,
	//input wire i_rdStrobe,
	input [ADDR_WIDTH-1:0] i_SPI_addr,
	input i_SPI_wrStrobe,
    input [BUS_WIDTH-1:0] i_SPIdata,
	inout [BUS_WIDTH-1:0] o_SPIdata,
	// register output
	output [15:0] o_regPowerThreshold,
    output [31:0] o_reg_num_sample_to_skip,
    output o_num_sample_to_skip_stb,
    output [15:0] o_reg_window_size,
    output [31:0] o_reg_minPlateau
	// register input
	//input [REG_WIDTH-1:0] i_reg // register provided for a readout
);

`include "common_params.v"

conf_reg #(
    .MY_ADDRESS(CR_SKIP_SAMPLE),
    .ADDR_WIDTH(ADDR_WIDTH),
    .INIT_VAL(50)
) reg_num_sample_to_skip_inst (
    .i_clock(i_clock),
    .i_reset(i_reset),
    .i_wrStrobe(i_SPI_wrStrobe),
    .i_addr(i_SPI_addr),
    .i_data(i_SPIdata),
    .o_data(o_SPIdata),
    .o_reg(o_reg_num_sample_to_skip),
    .i_reg(o_reg_num_sample_to_skip),
    .o_regUpdate(o_num_sample_to_skip_stb)
) ;

/* Power threshold: 150, not openwifi's 100.
   MEASURED on RASBB+RASRF 2026-07-31, 6M frame every 400ms at -30dBm
   (target 2.5 frames/s): 150 -> 97.8% capture (46 frames, 44 gaps of 400.0ms
   and one 800ms), 100 -> 31%, 200/300/450 -> a flat 50%, 600 -> 30%.
   TREAT THIS AS A SNAPSHOT, NOT A CONSTANT. Two sessions at the SAME nominal
   -30dBm produced different curves: earlier, 200-500 gave 100% and 100 gave
   78%; later, 150 gave 98% while 200-450 collapsed to exactly 50% and 100 to
   31%. So the optimum moved 200 -> 150 with nothing knowingly changed. At
   -45dBm nothing reached even 40%. The odd flat 50% shelf is a DETERMINISTIC
   every-other-frame lock (ILA gap histogram: 44 gaps of 800ms, i.e. exactly
   double the generator period) - it is not random loss, and its mechanism is
   NOT understood.
   The real robustness mechanism is the runtime override: the host can write
   CR_POWER_THRES over SPI at any time (see the sweep tooling in
   RASECU/STM32H743_Test/tools). Re-sweep whenever the RF conditions change,
   and prefer measuring gap histograms over rate alone - a rate of half looks
   like "marginal detection" but is actually a hard lock. */
conf_reg #(
    .MY_ADDRESS(CR_POWER_THRES),
    .ADDR_WIDTH(ADDR_WIDTH),
    .INIT_VAL(150)
) reg_PowerThreshold_inst (
    .i_clock(i_clock),
    .i_reset(i_reset),
    .i_wrStrobe(i_SPI_wrStrobe),
    .i_addr(i_SPI_addr),
    .i_data(i_SPIdata),
    .o_data(o_SPIdata),
    .o_reg(o_regPowerThreshold),
    .i_reg({ 16'h0000, o_regPowerThreshold[15:0] })
    //.o_regUpdate(updRegStrobe3)
) ;

conf_reg #(
    .MY_ADDRESS(CR_POWER_WINDOW),
    .ADDR_WIDTH(ADDR_WIDTH),
    .INIT_VAL(80)
) reg_window_size_inst (
    .i_clock(i_clock),
    .i_reset(i_reset),
    .i_wrStrobe(i_SPI_wrStrobe),
    .i_addr(i_SPI_addr),
    .i_data(i_SPIdata),
    .o_data(o_SPIdata),
    .o_reg(o_reg_window_size),
    .i_reg( { 16'h0000, o_reg_window_size } )
    //.o_regUpdate(updRegStrobe3)
) ;

conf_reg #(
    .MY_ADDRESS(CR_MIN_PLATEAU),
    .ADDR_WIDTH(ADDR_WIDTH),
    .INIT_VAL(100)
) reg_nimPlateau_size_inst (
    .i_clock(i_clock),
    .i_reset(i_reset),
    .i_wrStrobe(i_SPI_wrStrobe),
    .i_addr(i_SPI_addr),
    .i_data(i_SPIdata),
    .o_data(o_SPIdata),
    .o_reg(o_reg_minPlateau),
    .i_reg(o_reg_minPlateau)
    //.o_regUpdate(updRegStrobe3)
) ;

endmodule // conf_registers
