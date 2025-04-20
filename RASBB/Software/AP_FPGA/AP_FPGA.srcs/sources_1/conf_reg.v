//////////////////////////////////////////////////////////////////////////////////
// 
// Design Name: configuration register prototype
// Module Name: conf_reg
// Project Name: Radio Access Spectrum Monitor 2400MHz
// Engineer: Tobias Weber
// Target Devices: Artix 7, XC7A100T
// Create Date: 27.06.2024
// Tool Versions: Vivado 2024.1
// Description:  Receives and writes values into local registers
//               and informs the containing module about the update.
// 
// Dependencies: none
// 
// Funded by NGI0 Entrust nlnet foundation
// https://nlnet.nl/project/RA-Sentinel/
//
// Revision 1.0
// Additional Comments: Part of https://github.com/Tobias-DG3YEV/RA-Sentinel
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

module conf_reg #(
	parameter MY_ADDRESS = 0, 
	parameter ADDR_WIDTH = 8,
    parameter BUS_WIDTH = 32,
	parameter REG_WIDTH = 32,
    parameter INIT_VAL  = 32'h00000000
) (
	input wire i_clock,
	input wire i_reset,
	input wire i_wrStrobe,
	//input wire i_rdStrobe,
	input wire [ADDR_WIDTH-1:0] i_addr,
    input wire [BUS_WIDTH-1:0] i_data,
	inout wire [BUS_WIDTH-1:0] o_data,
	input wire [REG_WIDTH-1:0] i_reg, // register provided for a readout
	output reg [REG_WIDTH-1:0] o_reg, // the register that contains the data written over SPI
	output reg o_regUpdate
);

assign o_data = (i_addr == MY_ADDRESS) ? i_reg : {REG_WIDTH{1'bz}};
   
always @(posedge i_clock)
    if(i_reset == 1'b1) begin
		o_reg <= INIT_VAL;
		o_regUpdate <= 1'b1; // after reset we inform ab out a register update
		end
	else
		if(i_wrStrobe & (MY_ADDRESS == i_addr)) begin
			o_reg[REG_WIDTH-1:0] <= i_data[REG_WIDTH-1:0];
			o_regUpdate <= 1'b1;
		end
        else begin
			o_regUpdate <= 1'b0;
		end
endmodule // myReg
