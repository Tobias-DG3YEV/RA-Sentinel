//////////////////////////////////////////////////////////////////////////////////
// Company: NLnet
// Engineer: Tobias Weber
// 
// Create Date: 07/27/2024 05:06:56 PM
// Design Name: RA Sentinel, openofdm Simulation
// Module Name: top_tb
// Project Name: 
// Target Devices: Artix7
// Tool Versions: AMD Vivado 2024.1
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps

`include "openwifi/openofdm_rx_pre_def.v"

module top_tb;

`include "openwifi/common_params.v"

`ifdef BETTER_SENSITIVITY
`define THRESHOLD_SCALE 1
`else
`define THRESHOLD_SCALE 0
`endif

// "my" definitions
wire [7:0]  o_byteOut;
wire        o_byteOutStrobe;
// End of "my" definitions

reg extosc_clk;
reg clock;
reg lvdsclock;
initial lvdsclock = 0;
reg reset; //high active
reg hw_reset;
reg enable;

reg [10:0] rssi_half_db;
reg sample_in_strobe; // signals data valid at falling edge

reg [15:0] fsample_in_i;
reg [15:0] fsample_in_q;
reg [15:0] clk_count;
reg [31:0] sample_count;

wire pkt_header_valid;
wire pkt_header_valid_strobe;
wire [15:0] pkt_len;

reg set_stb;
reg [7:0] set_addr;
reg [31:0] set_data;

wire demod_is_ongoing;

wire sig_valid = (pkt_header_valid_strobe & pkt_header_valid);


wire [4:0] state;
wire signal_watchdog_enable;
wire [31:0] equalizer;
wire equalizer_valid;
  
integer run_out_of_iq_sample;
integer iq_count, iq_count_tmp, end_dl_count;

// file descriptors 
integer sample_file_name_fd;

// integer bb_sample_fd;
// integer power_trigger_fd;
integer short_preamble_detected_fd;

integer long_preamble_detected_fd;
integer sync_long_out_fd;

integer demod_out_fd;
integer demod_soft_bits_fd;
integer demod_soft_bits_pos_fd;
integer deinterleave_erase_out_fd;
integer conv_out_fd;
integer descramble_out_fd;

integer signal_fd;
integer ht_sig_fd; 

integer byte_out_fd;
integer fcs_out_fd;
integer status_code_fd;

integer phy_len_fd;

// sync_short 
integer mag_sq_fd;
integer mag_sq_avg_fd;
integer prod_fd;
integer prod_avg_fd;
integer phase_in_fd;
integer phase_out_fd;
integer delay_prod_avg_mag_fd;

// sync_long
integer sum_fd;
integer metric_fd;
integer raw_fd;
integer phase_correction_fd;
integer next_phase_correction_fd;
integer fft_in_fd;

// equalizer
integer new_lts_fd;
integer phase_offset_pilot_input_fd;
integer phase_offset_lts_input_fd;
integer phase_offset_pilot_fd;
integer phase_offset_pilot_sum_fd;
integer phase_offset_phase_out_fd;
integer cpe_fd;
integer lvpe_fd;
integer sxy_fd; 
integer prev_peg_fd; 
integer peg_sym_scale_fd;
integer peg_pilot_scale_fd;
integer rot_in_fd;
integer rot_out_fd;
integer equalizer_prod_fd;
integer equalizer_prod_scaled_fd;
integer equalizer_mag_sq_fd;
integer equalizer_out_fd;

integer file_i, file_q, file_rssi_half_db, iq_sample_file;

assign signal_watchdog_enable = (state <= S_DECODE_SIGNAL);

`ifdef SIMULATION
initial begin
    $display("Running in simulation mode.");
end
`else
initial begin
    $display("Running on real hardware.");
end
`endif


initial begin
    // $dumpfile("dot11.vcd");
    // $dumpvars;
    sample_file_name_fd = $fopen("./sample_file_name.txt", "w");
    $fwrite(sample_file_name_fd, "%s", `SAMPLE_FILE); 
    $fflush(sample_file_name_fd);
    $fclose(sample_file_name_fd);
    
    run_out_of_iq_sample = 0;
    end_dl_count = 0;
    sample_count = 0;

    clock = 0;
    extosc_clk = 0;
    reset = 1;
    hw_reset = 1;
    enable = 0;

    enable = 1;

    set_stb = 1;

    reset = #86 0;
    hw_reset = #200 0;

    # 20
    // do not skip sample
    set_addr = CR_SKIP_SAMPLE;
    set_data = 0;

    # 20 set_stb = 0;
end

integer file_open_trigger = 0;
always @(posedge clock) begin
    file_open_trigger = file_open_trigger + 1;
    if (file_open_trigger == 1) begin
        iq_sample_file = $fopen(`SAMPLE_FILE, "r");
    end
end

/**************************************************

     #####   #        #######   #####   #    #
    #     #  #        #     #  #     #  #   #
    #        #        #     #  #        #  #
    #        #        #     #  #        ###
    #        #        #     #  #        #  #
    #     #  #        #     #  #     #  #   #
     #####   #######  #######   #####   #    #

***************************************************/

always begin
`ifdef CLK_SPEED_100M
    #5 clock = !clock;
`elsif CLK_SPEED_60M
    #8.3333333333 clock = !clock;
`elsif CLK_SPEED_120M
    #4.1666666666 clock = !clock;
`elsif CLK_SPEED_200M
    #2.5 clock = !clock;
`elsif CLK_SPEED_240M
    #2.0833333333 clock = !clock;
`elsif CLK_SPEED_400M
    #1.25 clock = !clock;
`endif
end

// Generate external crystal clock
always begin
    #10 extosc_clk = ~extosc_clk; // 50MHz external oscillator
end

// Generate LVDS master clock
always begin
    lvdsclock  = ~lvdsclock;
    #4.1666666665;
end


always @(posedge clock) begin
    if (reset) begin
        fsample_in_i <= 0;
        fsample_in_q <= 0;
        clk_count <= 0;
        sample_in_strobe <= 0;
        iq_count <= 0;
    end
    else if (enable) begin
        if (clk_count == 5) begin  // for 120M; 120/20 = 5
            sample_in_strobe <= 1;
            //$fscanf(iq_sample_file, "%d %d %d", file_i, file_q, file_rssi_half_db);
            iq_count_tmp = $fscanf(iq_sample_file, "%d %d", file_i, file_q);
            if (iq_count_tmp != 2) begin
                run_out_of_iq_sample = 1;
                fsample_in_q <= 0;
                fsample_in_i <= 0;
            end
            else begin
                fsample_in_q <= file_q;
                fsample_in_i <= file_i;
            end
            //rssi_half_db <= file_rssi_half_db;
            rssi_half_db <= 0;
            iq_count <= iq_count + 1;
            clk_count <= 0;
        end else begin
            sample_in_strobe <= 0;
            clk_count <= clk_count + 1; 
        end
        
        // for finer sample_in_strobe phase control
        if (clk_count == 0) begin
            sample_in_strobe <= 1;
        end else begin
            sample_in_strobe <= 0;
        end
        
        if (sample_in_strobe) begin

            if ((iq_count % 100) == 0) begin
//                $display("%d", iq_count);
            end

            if (run_out_of_iq_sample) begin
                end_dl_count = end_dl_count+1;
            end
            
            if(end_dl_count == 300 ) begin
                $fclose(iq_sample_file);
                $finish;
            end
        end

    end
end

/****************************************************************************************************************************

#        #     #  ######    #####         #####   ###  #     #  #     #  #           #     #######  ###  #######  #     #
#        #     #  #     #  #     #       #     #   #   ##   ##  #     #  #          # #       #      #   #     #  ##    #
#        #     #  #     #  #             #         #   # # # #  #     #  #         #   #      #      #   #     #  # #   #
#        #     #  #     #   #####         #####    #   #  #  #  #     #  #        #     #     #      #   #     #  #  #  #
#         #   #   #     #        #             #   #   #     #  #     #  #        #######     #      #   #     #  #   # #
#          # #    #     #  #     #       #     #   #   #     #  #     #  #        #     #     #      #   #     #  #    ##
#######     #     ######    #####         #####   ###  #     #   #####   #######  #     #     #     ###  #######  #     #

******************************************************************************************************************************/
reg sample_frameClk; // frame signal
reg sample_bitClk; // bit clock
reg sample_bit_il; // I bit low
reg sample_bit_ih; // I bit low
reg sample_bit_ql; // I bit low
reg sample_bit_qh; // I bit low
reg [5:0] sample_bitMask; // output bit mask

always @(negedge !clock) begin
    if (reset) begin
        sample_bitClk <= 0; // bit clock
    end else begin
        sample_bitClk <= ~sample_bitClk;
    end
end

always @(posedge !clock) begin
    if (hw_reset) begin
        sample_bitClk <= 0;
        sample_frameClk <= 0; // frame signal
        sample_bit_il <= 0; // I bit low
        sample_bit_ih <= 0; // I bit low
        sample_bit_ql <= 0; // I bit low
        sample_bit_qh <= 0; // I bit low
        sample_bitMask <= 1;
    end
    else begin
        if(clk_count == 0) begin
            sample_frameClk <= 1;
        end
        if(clk_count == 5) begin
            sample_bitMask <= 1;
        end
        else
            sample_bitMask <= sample_bitMask << 1;

        sample_bit_il <= (fsample_in_i & sample_bitMask) == sample_bitMask;
        sample_bit_ih <= (fsample_in_i >> 6 & sample_bitMask) == sample_bitMask;
        sample_bit_ql <= (fsample_in_q & sample_bitMask) == sample_bitMask;
        sample_bit_qh <= (fsample_in_q >> 6 & sample_bitMask) == sample_bitMask;
        
        if(clk_count == 3)
            sample_frameClk <= 0;
    end
end

/***********************************************************************************************************************************************

    #######  #######  ######        ###  #     #   #####   #######     #     #     #  #######  ###     #     #######  ###  #######  #     #
       #     #     #  #     #        #   ##    #  #     #     #       # #    ##    #     #      #     # #       #      #   #     #  ##    #
       #     #     #  #     #        #   # #   #  #           #      #   #   # #   #     #      #    #   #      #      #   #     #  # #   #
       #     #     #  ######         #   #  #  #   #####      #     #     #  #  #  #     #      #   #     #     #      #   #     #  #  #  #
       #     #     #  #              #   #   # #        #     #     #######  #   # #     #      #   #######     #      #   #     #  #   # #
       #     #     #  #              #   #    ##  #     #     #     #     #  #    ##     #      #   #     #     #      #   #     #  #    ##
       #     #######  #             ###  #     #   #####      #     #     #  #     #     #     ###  #     #     #     ###  #######  #     #

************************************************************************************************************************************************/

system_top top_inst (
    .SYS_clk(extosc_clk),
    //.clk_100M(clock),
`ifdef USE_PARALLEL_SAMPLES
    .i_sample_i(fsample_in_i),
    .i_sample_q(fsample_in_q),
    .sample_in_strobe(sample_in_strobe),
`endif // !USE_PARALLEL_SAMPLES
    //.rssi_half_db(rssi_half_db),
    .o_demod_is_ongoing(demod_is_ongoing),
    .o_state(state),
    //.equalizer(equalizer),
    //.equalizer_valid(equalizer_valid),
    /* ADC LVDS */
    .ADC_idataH_P(sample_bit_ih), /* ADC I serial Data */
    .ADC_idataH_N(~sample_bit_ih), /* ADC I serial Data */
    .ADC_idataL_P(sample_bit_il), /* ADC I serial Data */
    .ADC_idataL_N(~sample_bit_il), /* ADC I serial Data */
    .ADC_qdataH_P(sample_bit_qh), /* ADC I serial Data */
    .ADC_qdataH_N(~sample_bit_qh), /* ADC I serial Data */
    .ADC_qdataL_P(sample_bit_ql), /* ADC I serial Data */
    .ADC_qdataL_N(~sample_bit_ql), /* ADC I serial Data */
    .ADC_frame_P(sample_frameClk), /* ADC frame clock */
    .ADC_frame_N(~sample_frameClk),
    .ADC_bitclk_P(sample_bitClk), /* ADC bit clock*/
    .ADC_bitclk_N(~sample_bitClk), /* ADC bit clock*/
    // decoder output signals
    .pkt_header_valid_strobe(pkt_header_valid_strobe),
    .o_byteOut(o_byteOut),
    .o_byteOutStrobe(o_byteOutStrobe),
    .Key0( ~hw_reset ) /* Wukong board key 0 - NRESET */
    //.enable(enable)
);

endmodule
