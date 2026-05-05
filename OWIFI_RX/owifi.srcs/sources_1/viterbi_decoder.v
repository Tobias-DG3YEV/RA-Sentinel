//////////////////////////////////////////////////////////////////////////////////
// Company: NLnet
// Engineer: Tobias Weber
//.
// Create Date: 07/27/2024 05:06:56 PM
// Design Name: RA Sentinel, open viterby decoder for openofdm
// Module Name: viterbi_decoder
// Project Name:.
// Target Devices: Artix7
// Tool Versions: AMD Vivado 2024.1
// Description:.
//.
// Dependencies:.
//.
// Revision:
// Revision 0.01 - File Created
// Additional Comments: Not yet functional. Punkturing is not yet implemented.
//.
//////////////////////////////////////////////////////////////////////////////////
module viterbi_decoder (
    input  wire         clk,       // System clock
    input  wire         rst,       // Synchronous reset (active high)
    input  wire         in_valid,  // New input symbol available
    input  wire [1:0]   rx,        // Received 2-bit symbol (hard decision)
    output reg          out_valid, // Decoded output is valid
    output reg [1:0]    decoded    // Decoded bits (2 bits per output cycle)
);

  //-------------------------------------------------------------------------
  // Parameters and Constants
  //-------------------------------------------------------------------------
  parameter K                = 7;  // Constraint length of the convolutional code
  localparam NUM_STATES       = (1 << (K-1));  // Number of states = 2^(K-1)
  localparam TRACEBACK_LENGTH = 84;  // How many steps to trace back
  localparam METRIC_MAX       = 8'd255;  // Maximum path metric to prevent overflow

  //-------------------------------------------------------------------------
  // Internal Registers and Memories
  //-------------------------------------------------------------------------
  reg [7:0] path_metric [0:NUM_STATES-1];  // Stores path metrics for each state
  reg [7:0] next_metric [0:NUM_STATES-1];  // Temporary storage for updated metrics

  // Survivor memory: keeps track of the best transition paths for traceback
  reg survivor_mem [0:NUM_STATES-1][0:TRACEBACK_LENGTH-1];

  reg [6:0] tb_counter;  // Counter for traceback, needs 7 bits for 84-length

  reg [1:0] rx_latched;  // Latches input symbol for stable processing

  //-------------------------------------------------------------------------
  // Functions
  //-------------------------------------------------------------------------

  // Hamming distance calculator (counts differing bits between two symbols)
  function [3:0] hamming_distance;
    input [1:0] a, b;
  begin
    hamming_distance = (a[0] ^ b[0]) + (a[1] ^ b[1]);
  end
  endfunction

  // Convolutional encoding logic (generates expected output for a given state)
  function [1:0] conv_encode;
    input bit_in;   // Input bit (0 or 1)
    input [K-2:0] state;  // Current state (shift register)
    reg [K-1:0] shift_reg;
  begin
    shift_reg = {bit_in, state};
    conv_encode[0] = ^(shift_reg & 7'b1011011); // First generator polynomial
    conv_encode[1] = ^(shift_reg & 7'b1111001); // Second generator polynomial
  end
  endfunction

  // Computes the next state based on the current state and input bit
  function [K-2:0] next_state;
    input in_bit;
    input [K-2:0] state;
  begin
    next_state = {in_bit, state[K-2:1]};
  end
  endfunction

  //-------------------------------------------------------------------------
  // Main Processing Logic
  //-------------------------------------------------------------------------
  integer i, s, tb_idx;
  reg [K-2:0] s_bits, ns0, ns1;
  reg [1:0]   expected0, expected1;
  reg [3:0]   bm0, bm1;
  integer     ns0_idx, ns1_idx;
  reg [TRACEBACK_LENGTH-1:0] traceback_path;
  integer best_state;
  reg [7:0] best_metric;
  integer current_state;

  always @(posedge clk) begin
    if (rst) begin
      // Reset path metrics (State 0 gets 0, others max value)
      for (i = 0; i < NUM_STATES; i = i + 1) begin
        path_metric[i] <= (i == 0) ? 8'd0 : METRIC_MAX;
        next_metric[i] <= METRIC_MAX;
      end
      tb_counter <= 0;
      out_valid  <= 1'b0;
      decoded    <= 2'b0;
    end 
    else if (in_valid) begin
      rx_latched <= rx;  // Latch input for stable processing

      // Reset next metrics to high value
      for (i = 0; i < NUM_STATES; i = i + 1)
        next_metric[i] <= METRIC_MAX;

      // Compute new path metrics
      for (s = 0; s < NUM_STATES; s = s + 1) begin
        if (path_metric[s] < METRIC_MAX) begin  // Ignore states with max metric (invalid paths)
          s_bits = s[(K-2):0];

          // Compute next states (0 and 1 input cases)
          ns0 = next_state(1'b0, s_bits);
          expected0 = conv_encode(1'b0, s_bits);
          bm0 = hamming_distance(expected0, rx_latched);
          ns0_idx = ns0;
          if (path_metric[s] + bm0 < next_metric[ns0_idx]) begin
            next_metric[ns0_idx] <= path_metric[s] + bm0;
            survivor_mem[ns0_idx][tb_counter] <= 1'b0;  // Store transition decision
          end

          ns1 = next_state(1'b1, s_bits);
          expected1 = conv_encode(1'b1, s_bits);
          bm1 = hamming_distance(expected1, rx_latched);
          ns1_idx = ns1;
          if (path_metric[s] + bm1 < next_metric[ns1_idx]) begin
            next_metric[ns1_idx] <= path_metric[s] + bm1;
            survivor_mem[ns1_idx][tb_counter] <= 1'b1;  // Store transition decision
          end
        end
      end

      // Copy updated path metrics for the next iteration
      for (i = 0; i < NUM_STATES; i = i + 1)
        path_metric[i] <= next_metric[i];

      // Traceback Counter Update
      if (tb_counter == TRACEBACK_LENGTH - 1)
        tb_counter <= 0;
      else
        tb_counter <= tb_counter + 1;

      // Once traceback memory is full, begin decoding
      if (tb_counter == TRACEBACK_LENGTH - 1) begin
        // Find the best state (lowest metric)
        best_state = 0;
        best_metric = path_metric[0];
        for (i = 1; i < NUM_STATES; i = i + 1) begin
          if (path_metric[i] < best_metric) begin
            best_metric = path_metric[i];
            best_state  = i;
          end
        end

        // Perform traceback to extract decoded bits
        current_state = best_state;
        for (tb_idx = TRACEBACK_LENGTH - 1; tb_idx >= 0; tb_idx = tb_idx - 1) begin
          traceback_path[tb_idx] = survivor_mem[current_state][tb_idx];
          current_state = {traceback_path[tb_idx], current_state[K-2:1]};
        end

        // Output the last two traced bits
        decoded   <= { traceback_path[TRACEBACK_LENGTH-1],
                       traceback_path[TRACEBACK_LENGTH-2] };
        out_valid <= 1'b1;
      end 
      else begin
        out_valid <= 1'b0; // Output remains invalid until traceback is ready
      end
    end
  end

endmodule
