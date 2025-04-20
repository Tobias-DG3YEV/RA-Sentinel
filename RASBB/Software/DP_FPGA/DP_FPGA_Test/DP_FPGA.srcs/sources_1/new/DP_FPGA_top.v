`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 02/26/2025 10:31:00 AM
// Design Name: BlinkingLight
// Module Name: DP_FPGA_top
// Project Name: RASBB
// Target Devices: xc7a100Tcsg324i 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module DP_FPGA_top(
    input i_masterClock,
    output reg o_DEBUG_A0
    );

reg [31:0] counter;

always @(posedge i_masterClock) begin
    if(counter > 50000000) begin
        counter <= 0;
    end
    else begin
        counter <= counter + 1; 
    end
    if(counter < 25000000) begin
        o_DEBUG_A0 <= 1;
    end
    else begin
        o_DEBUG_A0 <= 0;
    end
end

endmodule
