`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Design Name: SPI Perihperal
// Module Name: top
// Engineer: Tobias Weber
// Project Name: SPI Perihperal
// Target Devices: AMD XILINX ARTIX 7
// Tool Versions: Vivado 2024.1
// Description: A simple SPI Peripheral that allows read and write access to
// 				internal registers. The adressing is done in I2C scheme,
//				means the lowest address bit is the Read/Write Bit.
// 				With this it is possible to read the previous content of register
//				
// Dependencies: 
// Requirements: sysclk >= 2.5 * SPI_clk
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

module SPI_Peripheral #(
    parameter REG_WIDTH = 32, // in Bits
    parameter ADDR_WIDTH = 8 // in Bits incl. the RW bit. 3 means 2^3 = 8 possbile addresses
)(
    // system control
    input wire i_sysclk, //system clock for state machine processing 
    input wire i_reset,
    // SPI bus 
    input wire i_ncs,
    input wire i_sclk, //serial clock
    input wire i_copi,
    output wire o_cipo,
    // register bus
    output reg o_dataRdy, // data are ready int he o_regData register, it is high for one sysclk rise.
    output wire [ADDR_WIDTH-1:0] o_addr,
    output reg [REG_WIDTH-1:0] o_regData,
    input wire [REG_WIDTH-1:0] i_regData
);

localparam WRITE_REGS = 2; //number of writable registers
localparam READ_REGS = 5;   //number of readable registers
// number of bits used for addressing resgister. It is ADDR_WIDTH+1 for the RW bit.
localparam ADDR_BITS = ADDR_WIDTH + 1; 

// Internal signals
reg [5:0] bit_cnt;
reg [ADDR_BITS-1:0] addr_reg;
//reg [1:0] reg_addr;
//reg [REG_WIDTH-1:0] data_out;
reg [REG_WIDTH-1:0] data_mask;
reg [REG_WIDTH-1:0] data_out; // -2 because the MSB has alread been sent
reg [1:0] state, next_state;

// State encoding
localparam IDLE          = 2'b00;
localparam RX_ADDR       = 2'b01;
localparam XFR_DATA      = 2'b10;
localparam XFR_END       = 2'b11;

assign  o_addr  = addr_reg[ADDR_BITS-1:1];

wire    rwbit;
assign  rwbit   = addr_reg[0];

assign o_cipo = (bit_cnt < 8) ? 0 : ((i_regData & data_mask) ? 1 : 0 );

wire sysclk_delayed;

BUFG bufg_inst (
    .I(i_sysclk),   // Input clock signal
    .O(sysclk_delayed)    // Output buffered clock signal
);

// *** State machine ***
always @(posedge i_sysclk or posedge i_reset) begin
    if (i_reset) begin
        state <= IDLE;
    end
    else if(!i_ncs) begin  // chip select active
        if(state == IDLE && next_state != RX_ADDR) begin 
            //from IDLE we only allow RX_ADDR to be the next state
        end
        else begin
            state <= next_state;
        end
    end
    else begin // chip select deasserted
        state <= IDLE;
    end
end

// *** write strobe generation ***
always @(negedge sysclk_delayed or posedge i_reset) begin
    if (i_reset) begin
        o_dataRdy <= 0;
    end
    else if(state == XFR_END) begin  // chip select active
        if(rwbit == 0)
            o_dataRdy <= 1;
    end
    else
        o_dataRdy <= 0;
end

// *** Bit receive ***
always @(posedge i_sclk or posedge i_reset) begin
  if(i_reset == 1'b1) begin
    data_mask <= 0;
    next_state <= IDLE;
    bit_cnt <= 0;
  end
  else begin // rising edge of the data clock
    if(!i_ncs) begin // precondition, Chip must be selected
        if (state == IDLE) begin
            bit_cnt <= 1;
            next_state <= RX_ADDR;
            data_out <= 0;
            data_mask <= 32'h80000000;
        end
        else begin
                bit_cnt <= bit_cnt + 1;
        end

        if (state == IDLE || state == RX_ADDR || state == XFR_END) begin
            if (bit_cnt == ADDR_BITS-1) begin
                next_state <= XFR_DATA;     
                //data_mask <= data_mask >> 1;
            end
        end
        else begin
            if(bit_cnt > 8) begin
                data_mask <= data_mask >> 1;
            end
        end
        if(bit_cnt == (ADDR_BITS + REG_WIDTH - 1)) begin
            next_state <= XFR_END;
        end
    end
  end
end

// *** Bit transmit ***
always @(negedge i_sclk or posedge i_reset) begin
  if(i_reset == 1'b1) begin
    o_regData <= 0;
    addr_reg <= 0;
  end
  else begin
    if (bit_cnt <= 8) begin
        addr_reg <= { addr_reg[ADDR_BITS-2:0], i_copi }; // address is big endian
    end
    else begin
        o_regData <= { o_regData[REG_WIDTH-2:0], i_copi };
    end
  end
end

endmodule
