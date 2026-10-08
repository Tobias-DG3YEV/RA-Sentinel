////////////////////////////////////////////////////////////////////////////////
// Design Name: OWIFI_RX
// Module Name: SPI_Peripheral.v
// Project Name: Radio Access Sentinel
// Engineer: Tobias Weber
// Target Devices: Artix-7 XC7A100T (RASBB U10)
// Tool Versions: Vivado 2025.2
// Description:  RA-Sentinel is a WiFi activity and threat detection platform
//
// Additional Comments: https://github.com/Tobias-DG3YEV/RA-Sentinel
//
// This project was funded through the NGI0 Entrust Fund, a fund established
// by NLnet with financial support from the European Commission's
// Next Generation Internet programme, under the aegis of DG Communications
// Networks, Content and Technology under grant agreement No 101069594.
// https://nlnet.nl/project/RA-Sentinel/
//
// SPDX-FileCopyrightText: 2024 Tobias Weber
// SPDX-License-Identifier: GPL-3.0-only
//
// This project is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
// See the GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see
// <http://www.gnu.org/licenses/> for a copy.
////////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Tobias Weber
// 
// Create Date: 18.07.2024 10:47:01
// Design Name: 
// Module Name: SPI_Peripheral
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: This SPI perihperal allows registers either to be read or written.
//              Like in I2C, the lowest bit defines if a register is being written or read
// Dependencies: 
//
// Requirements: sysclk > sclk
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module SPI_Peripheral #(
    parameter REG_SIZE = 32, // in Bits
    parameter ADDR_SIZE = 3 // in Bits incl. the RW bit. 3 means 2^3 = 8 possbile addresses
)(
    input i_sysclk, //system clock for state machine processing 
    input i_ncs,
    input i_sclk, //serial clock
    input i_copi,
    //output reg regUpdate,
    output reg i_cipo,
    /* read-only registers */  
    input [REG_SIZE-1:0] reg_r0,
    input [REG_SIZE-1:0] reg_r1,
    input [REG_SIZE-1:0] reg_r2,
    input [REG_SIZE-1:0] reg_r3,
    input [REG_SIZE-1:0] reg_r4,
    input [REG_SIZE-1:0] reg_r5,
    input [REG_SIZE-1:0] reg_r6,
    input [REG_SIZE-1:0] reg_r7,
    /* write-only registers */
    output reg [REG_SIZE-1:0] reg_w0,
    output reg [REG_SIZE-1:0] reg_w1,
    output reg [REG_SIZE-1:0] reg_w2,
    output reg [REG_SIZE-1:0] reg_w3,
    output reg [REG_SIZE-1:0] reg_w4,
    output reg [REG_SIZE-1:0] reg_w5,
    output reg [REG_SIZE-1:0] reg_w6,
    output reg [REG_SIZE-1:0] reg_w7,
    /* */
    input i_reset
);

localparam WRITE_REGS = 2; //number of writable registers
localparam READ_REGS = 5;   //number of readable registers
// number of bits used for addressing. In this case we have 7 registers
// which can be addressed by 3 bits
localparam ADDR_BITS = 8; 

// Internal signals
reg [5:0] bit_cnt;
reg [ADDR_BITS-1:0] addr_reg;
//reg [1:0] reg_addr;
reg [REG_SIZE-1:0] data_out;
reg [REG_SIZE-1:0] data_in;
reg [1:0] state, next_state;

// State encoding
localparam IDLE          = 2'b00;
localparam RX_ADDR       = 2'b01;
localparam XFR_DATA      = 2'b10;
localparam XFR_END       = 2'b11;

// *** State machine ***
always @(posedge i_sysclk or posedge i_reset) begin
    if (i_reset) begin
        state <= IDLE;
        i_cipo <= 0;
        reg_w0 <= 0;
        reg_w1 <= 0;
    end
    else if(!i_ncs) begin
        state <= next_state;
        i_cipo <= data_out[REG_SIZE-1];
        if (next_state == XFR_END) begin
            case (addr_reg[ADDR_BITS-1:1])
                0: reg_w0 <= data_in;
                1: reg_w1 <= data_in;
            endcase
        end
    end
    else begin
        state <= IDLE;
        i_cipo <= 0;
    end
end

wire rwbit;

assign rwbit = addr_reg[0];

always @(posedge i_reset or posedge i_sclk) begin
  if(i_reset == 1'b1) begin
    data_in <= 0;
    addr_reg <= 0;
    data_out <= 0;
    next_state <= IDLE;
    bit_cnt <= 0;
  end
  else begin // rising edge of the data clock
    if(!i_ncs) begin // precondition, Chip must be selected
        if (state == IDLE) begin
            bit_cnt <= 1;
            next_state <= RX_ADDR;
        end
        if (state == IDLE || state == RX_ADDR || state == XFR_END) begin
            addr_reg <= { addr_reg[ADDR_BITS-2:0], i_copi }; // address is big endian
            if (bit_cnt == ADDR_BITS-1) begin
                case (addr_reg[ADDR_BITS-2:0])
                    0: data_out <= reg_r0;
                    1: data_out <= reg_r1;
                    2: data_out <= reg_r2;
                    3: data_out <= reg_r3;
                    4: data_out <= reg_r4;
                    5: data_out <= reg_r5;
                    6: data_out <= reg_r6;
                    7: data_out <= reg_r7;
                    default: data_out <= 0;
                endcase
                next_state <= XFR_DATA;
            end
        end
        else begin
            data_in <= { data_in[REG_SIZE-2:0], i_copi };
            if(rwbit)
                data_out <= { data_out[REG_SIZE-2:0], 1'b0 };
        end
        bit_cnt <= bit_cnt + 1;
        if(bit_cnt == (ADDR_BITS + REG_SIZE - 1)) begin
            bit_cnt <= 0;
            addr_reg <= 0;
            next_state <= XFR_END;
        end
    end
  end
end

endmodule
