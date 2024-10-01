`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Design Name: configuration and statusw registers
// Module Name: registers.v
// Project Name: RA Sentinel
// Target Devices: AMD XILINX ARTIX 7
// Tool Versions: Vivado 2024.1
// Description: A simple SPI Peripheral that allows read and write access to
// 				internal registers. The adressing is done in I2C scheme,
//				means the lowest address bit is the Read/Write Bit.
// 				With this it is possible to read the previous content of register
//				
// Dependencies: SPI_Peripheral
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
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
	output [REG_WIDTH-1:0] o_regPowerThreshold,
    output [31:0] o_reg_num_sample_to_skip,
    output o_num_sample_to_skip_stb,
    output [15:0] o_reg_window_size,
	// register input
	input [REG_WIDTH-1:0] i_reg // register provided for a readout
);

`include "openwifi/common_params.v"

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

conf_reg #(
    .MY_ADDRESS(CR_POWER_THRES),
    .ADDR_WIDTH(ADDR_WIDTH),
    .INIT_VAL(100)
) reg_PowerThreshold_inst (
    .i_clock(i_clock),
    .i_reset(i_reset),
    .i_wrStrobe(i_SPI_wrStrobe),
    .i_addr(i_SPI_addr),
    .i_data(i_SPIdata),
    .o_data(o_SPIdata),
    .o_reg(o_regPowerThreshold),
    .i_reg(o_regPowerThreshold)
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
    .i_reg(o_reg_window_size)
    //.o_regUpdate(updRegStrobe3)
) ;


endmodule // conf_registers
