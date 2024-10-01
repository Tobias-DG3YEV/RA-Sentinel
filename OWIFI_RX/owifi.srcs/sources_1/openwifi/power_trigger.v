module power_trigger #(
    parameter INITIAL_SAMPLES_TO_SKIP = 5
)(
    input clock,
    input enable,
    input reset,

    //input reg_setStrobe,
    //input [7:0] reg_setAddr,
    //input [31:0] reg_setData,

    input [31:0] sample_in,
    input sample_in_strobe,

    //TWMOD
    input i_num_sample_changed,
    input [31:0] i_reg_num_sample_to_skip,
    input [15:0] i_reg_power_thres,
    input [15:0] i_reg_window_size,

    output reg trigger
);
`include "common_params.v"

localparam S_SKIP =             0;
localparam S_IDLE =             1;
localparam S_PACKET =           2;
reg [1:0] powtrig_state;

//wire [15:0] i_reg_power_thres;
//wire [15:0] i_reg_window_size;
//wire [31:0] reg_num_sample_to_skip;
//wire num_sample_changed;


reg [31:0] sample_count;

wire [15:0] input_i = sample_in[31:16];
reg [15:0] abs_i;

always @(posedge clock) begin
    if (reset) begin
        sample_count <= 0;
        trigger <= 0;
        abs_i <= 0;
        powtrig_state <= S_SKIP;
    end else if (enable & sample_in_strobe) begin
        abs_i <= input_i[15]? ~input_i+1: input_i;
        case(powtrig_state)
            S_SKIP: begin
                if(sample_count > i_reg_num_sample_to_skip) begin
                    powtrig_state <= S_IDLE;
                end else begin
                    sample_count <= sample_count + 1;
                end
            end

            S_IDLE: begin
                if (i_num_sample_changed) begin
                    sample_count <= 0;
                    powtrig_state <= S_SKIP;
                end else if (abs_i > i_reg_power_thres) begin
                    // trigger on any significant signal 
                    trigger <= 1;
                    sample_count <= 0;
                    powtrig_state <= S_PACKET;
                end
            end

            S_PACKET: begin
                if (i_num_sample_changed) begin
                    sample_count <= 0;
                    powtrig_state <= S_SKIP;
                end else if (abs_i < i_reg_power_thres) begin
                    // go back to idle for N consecutive low signals
                    if (sample_count > i_reg_window_size) begin
                        trigger <= 0;
                        powtrig_state <= S_IDLE;
                    end else begin
                        sample_count <= sample_count + 1;
                    end
                end else begin
                    sample_count <= 0;
                end
            end
        endcase
    end
end
endmodule
