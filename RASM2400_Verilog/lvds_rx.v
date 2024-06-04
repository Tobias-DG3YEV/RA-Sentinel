//////////////////////////////////////////////////////////////////////////////////
// 
// Design Name: RASM2400
// Module Name: LVDS_RX
// Project Name: Radio Access Spectrum Monitor 2400MHz
// Engineer: Tobias Weber
// Target Devices: Artix 7, XC7A100T
// Create Date: 25.04.2024 10:29:54
// Tool Versions: Vivado 2024.1
// Description:  Receives and deserializes sample data coming from
//               the ADC via 2x2 LVDS data lines.
// 
// Dependencies: none
// 
// Revision 1.01
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

/* this depicts the input data stream we get from the ADC322x
				  _________         ___
Frame FCLK		_|        |________|
                  ______      ___
Data			_|     |_____|  |______
				   ___   ___   ___   __
Data DCLK		__|  |__|  |__|  |__|  
Bit #			  0  1  2  3  4  5  0  
Value (LSB first) 1  1  0  0  1  0  0 => reversed to 10011 = 13 hex.
*/

module lvds_rx #(
	parameter WORDWIDTH = 12 //sample width in bits
)
(
    input wire i_lvds_dclk, // 120MHz
    input wire i_lvds_fclk, // 40MHz
    input wire i_lvds_dr0,  // data lane real part, lower bits
    input wire i_lvds_di0,  // data lane imaginary part, higher 6 bits
    input wire i_lvds_dr1,  // data lane real part, lower 6 bits
    input wire i_lvds_di1,  // data lane imaginary part, higher 6 bits
	input wire i_rst,       // module reset, active high
    output wire o_parFrameRdy, // paralell frame can be read when this goes high.
    output wire [11:0] o_dataOut_R  // parallel data, real part
    output wire [11:0] o_dataOut_I, // parallel data, imaginary part
);

// sync states
localparam state_powerOn 	= 2'b00;
localparam state_syncing 	= 2'b01;
localparam state_init       = 2'b10;
localparam state_initdone   = 2'b11;
	
reg fclk_delayed;
reg [2:0] ctr;
reg trig;
initial trig = 0;

reg [1:0] initSM; // sync state machine counter
initial initSM = 0;
reg serdesNreset;
initial serdesNreset = 1'b0;
reg serdesCS;
initial serdesCS = 1'b0;

// sync state machine. It syncs the ISERDESE2 modules to the ADC frame clock

always @(posedge i_lvds_dclk or posedge i_rst) // 60MHz driven
begin
    if(i_rst == 1'b1) begin
       ctr <= 0;
	   fclk_delayed <= 0;
	   trig <= 0;
    end
    // sync everything with frame start
    else begin
		// work signal generator
        if(i_lvds_fclk == 1 && trig == 0) begin
            trig <= 1;
            ctr <= 0;
            fclk_delayed <= 0;
		end
        else begin
            ctr <= ctr + 1;
            trig <= 0;
        end
		  
	   if(ctr >= 1 && ctr <= 2)
	       fclk_delayed <= 0;
	   else
	       fclk_delayed <= 1;
    end
end

always @(negedge i_lvds_dclk or posedge i_rst) // 60MHz driven
begin
    if(i_rst == 1'b1) begin
       initSM <= state_powerOn;
       serdesNreset <= 0;
       serdesCS <= 1'b0;
    end
    // sync everything with frame start
    else begin
		case (initSM)
			state_powerOn: begin
				if (i_lvds_fclk == 0) begin
					initSM <= state_syncing;
					serdesCS <= 1'b0;
				end
			end

			state_syncing: begin
				if (i_lvds_fclk == 1) begin
					initSM <= state_init;
					serdesNreset <= 1'b1;
				end
			end

			state_init: begin
                initSM <= state_initdone;
			end

			state_initdone: begin
				if(ctr == 0) begin
					serdesCS <= 1'b1;
				end
			end
			
		endcase
	end
end 


/*********************************

 ISERDES instantiation

**********************************/

    // Parameters for the ISERDESE2 configuration
    localparam SERDES_MODE = "MASTER";
    localparam DATA_RATE = "DDR";
    localparam DATA_WIDTH = 6;
    localparam INTERFACE_TYPE = "NETWORKING";

        // Intermediate signals
    wire [3:0] din;
	assign din[0] = i_lvds_dr0;
	assign din[1] = i_lvds_dr1;
	assign din[2] = i_lvds_di0;
	assign din[3] = i_lvds_di1;
	
	wire [3:0] q1;
	wire [3:0] q2;
	wire [3:0] q3;
	wire [3:0] q4;
	wire [3:0] q5;
	wire [3:0] q6;

    genvar i;
    generate
        for (i = 0; i < 4; i = i + 1) begin : gen_idelaye2_iserdese2

            // Instantiate ISERDESE2
            ISERDESE2 #(
                .DATA_RATE(DATA_RATE),       // Data rate (SDR or DDR)
                .DATA_WIDTH(DATA_WIDTH),     // Parallel data width (2 to 8)
                .INTERFACE_TYPE(INTERFACE_TYPE), // Interface type (NETWORKING, RETIMED)
                .NUM_CE(1),                  // Number of clock enables
                .OFB_USED("FALSE"),          // OFB usage
                .SERDES_MODE(SERDES_MODE),   // Master or Slave mode
				.DYN_CLKDIV_INV_EN("FALSE"),
				.DYN_CLK_INV_EN("FALSE"),
				.IOBDELAY("BOTH")
            ) ISERDESE2_inst (
                .Q1(q1[i]),       // 1-bit output: First parallel data output
                .Q2(q2[i]),       // 1-bit output: Second parallel data output
                .Q3(q3[i]),       // 1-bit output: Third parallel data output
                .Q4(q4[i]),       // 1-bit output: Fourth parallel data output
				.Q5(q5[i]),
				.Q6(q6[i]),
                .SHIFTOUT1(),     // 1-bit output: Connects to SHIFTOUT1 of another ISERDESE2 for chaining
                .SHIFTOUT2(),     // 1-bit output: Connects to SHIFTOUT2 of another ISERDESE2 for chaining
                .BITSLIP(1'b0),   // 1-bit input: Bitslip pin for word alignment
				.DYNCLKSEL(1'b0), // Dynamically select CLK and CLKB inversion. 
				.DYNCLKDIVSEL(1'b0), // Dynamically select CLKDIV inversion. 
                .CE1( serdesCS ),   // 1-bit input: Clock enable input
                .CE2(1'b0),         // 1-bit input: Clock enable input
                .CLK( i_lvds_dclk ),     // 1-bit input: High-speed clock input
                .CLKB( ~i_lvds_dclk ),   // 1-bit input: Inverted high-speed clock input
                .CLKDIV( fclk_delayed ), // 1-bit input: Divided clock input
                .CLKDIVP(1'b0),          // 1-bit input: Phase-aligned divided clock input
                .D(1'b0),         // 1-bit input: Serial data input
                .DDLY(din[i]),    // 1-bit input: Delayed serial data input
                .OFB(1'b0),       // 1-bit input: Feedback path
                .RST( ~serdesNreset ), // 1-bit input: Reset input
                .SHIFTIN1(1'b0),  // 1-bit input: Connects to SHIFTIN1 of another ISERDESE2 for chaining
                .SHIFTIN2(1'b0)   // 1-bit input: Connects to SHIFTIN2 of another ISERDESE2 for chaining
            );
        end
    endgenerate

	assign o_dataOut_R = { q1[1], q2[1], q3[1], q4[1], q5[1], q6[1], q1[0], q2[0], q3[0], q4[0], q5[0], q6[0] };
	assign o_dataOut_I = { q1[3], q2[3], q3[3], q4[3], q5[3], q6[3], q1[2], q2[2], q3[2], q4[2], q5[2], q6[2] };
	
	assign o_parFrameRdy = ~fclk_delayed;

endmodule
