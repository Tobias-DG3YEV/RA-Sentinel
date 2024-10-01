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

reg master_clk;
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

    clock = 0;
    master_clk = 0;
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
    if (file_open_trigger==1) begin
        iq_sample_file = $fopen(`SAMPLE_FILE, "r");

        // bb_sample_fd = $fopen("./sample_in.txt", "w");
        // power_trigger_fd = $fopen("./power_trigger.txt", "w");
        short_preamble_detected_fd = $fopen("./short_preamble_detected.txt", "w");
        long_preamble_detected_fd = $fopen("./sync_long_frame_detected.txt", "w");
        
        // sync_short 
        mag_sq_fd = $fopen("./mag_sq.txt", "w");
        mag_sq_avg_fd = $fopen("./mag_sq_avg.txt", "w");
        prod_fd = $fopen("./prod.txt", "w");
        prod_avg_fd = $fopen("./prod_avg.txt", "w");
        phase_in_fd = $fopen("./phase_in.txt", "w");
        phase_out_fd = $fopen("./phase_out.txt", "w");
        delay_prod_avg_mag_fd = $fopen("./delay_prod_avg_mag.txt", "w");

        // sync_long
        sum_fd = $fopen("./sum.txt", "w");
        metric_fd = $fopen("./metric.txt", "w");
        raw_fd = $fopen("./raw.txt", "w");
        phase_correction_fd = $fopen("./phase_correction.txt", "w");
        next_phase_correction_fd = $fopen("./next_phase_correction.txt", "w");
        fft_in_fd = $fopen("./fft_in.txt", "w");                   
        sync_long_out_fd = $fopen("./sync_long_out.txt", "w");
        
        // equalizer
        new_lts_fd = $fopen("./new_lts.txt", "w");
        phase_offset_pilot_input_fd = $fopen("./phase_offset_pilot_input.txt", "w");
        phase_offset_lts_input_fd = $fopen("./phase_offset_lts_input.txt", "w");
        phase_offset_pilot_fd = $fopen("./phase_offset_pilot.txt", "w");
        phase_offset_pilot_sum_fd = $fopen("./phase_offset_pilot_sum.txt", "w");
        phase_offset_phase_out_fd = $fopen("./phase_offset_phase_out.txt", "w");
        cpe_fd = $fopen("./cpe.txt", "w");
        lvpe_fd = $fopen("./lvpe.txt", "w");
        sxy_fd = $fopen("./sxy.txt", "w");
        prev_peg_fd = $fopen("./prev_peg.txt", "w");
        peg_sym_scale_fd = $fopen("./peg_sym_scale.txt", "w");
        peg_pilot_scale_fd = $fopen("./peg_pilot_scale.txt", "w");
        rot_in_fd = $fopen("./rot_in.txt", "w");
        rot_out_fd = $fopen("./rot_out.txt", "w");
        equalizer_prod_fd = $fopen("./equalizer_prod.txt", "w");
        equalizer_prod_scaled_fd = $fopen("./equalizer_prod_scaled.txt", "w");
        equalizer_mag_sq_fd = $fopen("./equalizer_mag_sq.txt", "w");
        equalizer_out_fd = $fopen("./equalizer_out.txt", "w");        

        // ofdm decoder
        demod_out_fd = $fopen("./demod_out.txt", "w");
        demod_soft_bits_fd = $fopen("./demod_soft_bits.txt", "w");
        demod_soft_bits_pos_fd = $fopen("./demod_soft_bits_pos.txt", "w");
        deinterleave_erase_out_fd = $fopen("./deinterleave_erase_out.txt", "w");
        conv_out_fd = $fopen("./conv_out.txt", "w");
        descramble_out_fd = $fopen("./descramble_out.txt", "w");

        signal_fd = $fopen("./signal_out.txt", "w");
        ht_sig_fd = $fopen("./ht_sig_out.txt", "w");
        byte_out_fd = $fopen("./byte_out.txt", "w");
        fcs_out_fd = $fopen("./fcs_out.txt", "w");
        status_code_fd = $fopen("./status_code.txt","w");

        phy_len_fd = $fopen("./phy_len.txt", "w");

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
    #10 master_clk = ~master_clk; // 50MHz
end

// Generate LVDS master clock
always begin
    lvdsclock  = ~lvdsclock;
    #4.1666666666 ;
end


always @(posedge clock) begin
    if (reset) begin
        fsample_in_i <= 0;
        fsample_in_q <= 0;
        clk_count <= 0;
        sample_in_strobe <= 0;
        iq_count <= 0;

    end else if (enable) begin
        // this here will be executed @ 20MHz / each 50ns
        `ifdef CLK_SPEED_100M
    	if (clk_count == 4) begin  // for 100M; 100/20 = 5
        `elsif CLK_SPEED_60M
        if (clk_count == 2) begin  // for 100M; 60/20 = 3
        `elsif CLK_SPEED_120M
        if (clk_count == 5) begin  // for 100M; 120/20 = 5
    	`elsif CLK_SPEED_200M
        if (clk_count == 9) begin // for 200M; 200/20 = 10
        `elsif CLK_SPEED_240M
        if (clk_count == 11) begin // for 200M; 240/20 = 12
        `elsif CLK_SPEED_400M
        if (clk_count == 19) begin // for 200M; 400/20 = 20
        `endif
            //sample_in_strobe <= 1;
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
        
        if (top_inst.legacy_sig_stb) begin
        end

        //if (sample_in_strobe && power_trigger) begin
        if (sample_in_strobe) begin
            // $fwrite(bb_sample_fd, "%d %d %d\n", iq_count, $signed(sample_in[31:16]), $signed(sample_in[15:0]));
            // $fwrite(power_trigger_fd, "%d %d\n", iq_count, top_inst.power_trigger);
            // $fflush(bb_sample_fd);
            // $fflush(power_trigger_fd);

            if ((iq_count % 100) == 0) begin
//                $display("%d", iq_count);
            end

            if (run_out_of_iq_sample) begin
                end_dl_count = end_dl_count+1;
            end
            
            if(end_dl_count == 300 ) begin
                $fclose(iq_sample_file);

                // $fclose(bb_sample_fd);
                // $fclose(power_trigger_fd);
                $fclose(short_preamble_detected_fd);
                $fclose(long_preamble_detected_fd);
                
                // close short preamble detection output files
                $fclose(mag_sq_fd);
                $fclose(mag_sq_avg_fd);
                $fclose(prod_fd);
                $fclose(prod_avg_fd);
                $fclose(phase_in_fd);
                $fclose(phase_out_fd);
                $fclose(delay_prod_avg_mag_fd);
                // close long preamble detection output files
                $fclose(sum_fd);
                $fclose(metric_fd);
                $fclose(raw_fd);
                $fclose(phase_correction_fd);
                $fclose(next_phase_correction_fd);
                $fclose(fft_in_fd);
                $fclose(sync_long_out_fd);
                // close equalizer output files
                $fclose(new_lts_fd);
                $fclose(phase_offset_pilot_input_fd);
                $fclose(phase_offset_lts_input_fd);
                $fclose(phase_offset_pilot_fd);
                $fclose(phase_offset_pilot_sum_fd);
                $fclose(phase_offset_phase_out_fd);
                $fclose(cpe_fd);
                $fclose(lvpe_fd);
                $fclose(sxy_fd);
                $fclose(prev_peg_fd);
                $fclose(peg_sym_scale_fd);
                $fclose(peg_pilot_scale_fd);
                $fclose(rot_in_fd);
                $fclose(rot_out_fd);
                $fclose(equalizer_prod_fd);
                $fclose(equalizer_prod_scaled_fd);
                $fclose(equalizer_mag_sq_fd);
                $fclose(equalizer_out_fd);
                // close ofdm decode files
                $fclose(demod_out_fd);
                $fclose(demod_soft_bits_fd);
                $fclose(demod_soft_bits_pos_fd);
                $fclose(deinterleave_erase_out_fd);
                $fclose(conv_out_fd);
                $fclose(descramble_out_fd);

                $fclose(signal_fd);
                $fclose(ht_sig_fd);
                $fclose(byte_out_fd);
                $fclose(fcs_out_fd);
                $fclose(status_code_fd);

                $fclose(phy_len_fd);
                $finish;
            end
        end
        if(top_inst.short_preamble_detected && top_inst.state == S_SYNC_SHORT) begin
            $fwrite(short_preamble_detected_fd, "%d %d\n", iq_count, top_inst.dot11_inst.sync_short_inst.phase_offset);
            $fflush(short_preamble_detected_fd);
        end
        if(top_inst.long_preamble_detected) begin
            $fwrite(long_preamble_detected_fd, "%d %d\n", iq_count, top_inst.dot11_inst.sync_long_inst.addr1);
            $fflush(long_preamble_detected_fd);
        end
        if(top_inst.fcs_out_strobe) begin
            $fwrite(fcs_out_fd, "%d %d\n", iq_count, top_inst.dot11_inst.fcs_ok);
            $fflush(fcs_out_fd);
        end
        if(top_inst.fcs_out_strobe && top_inst.phy_len_valid) begin
            $fwrite(phy_len_fd, "%d %d %d\n", iq_count, top_inst.dot11_inst.n_ofdm_sym, top_inst.dot11_inst.n_bit_in_last_sym);
            $fflush(phy_len_fd);
        end
        if(top_inst.state == S_HT_SIG_ERROR || top_inst.state == S_SIGNAL_ERROR) begin
            $fwrite(status_code_fd, "%d %d %d\n", iq_count, top_inst.dot11_inst.status_code, top_inst.state);
            $fflush(status_code_fd);    
        end
        if (top_inst.state == S_CHECK_SIGNAL) begin
            $fwrite(signal_fd, "%d %d\n", iq_count, top_inst.dot11_inst.signal_bits);
            $fflush(signal_fd);
        end
        if (top_inst.dot11_inst.ht_sig_stb) begin
            $fwrite(ht_sig_fd, "%d %d %d\n", iq_count, top_inst.dot11_inst.ht_sig1, top_inst.dot11_inst.ht_sig2);
            $fflush(ht_sig_fd);
        end

        if ((top_inst.state == S_MPDU_DELIM || top_inst.state == S_DECODE_DATA || top_inst.state == S_MPDU_PAD) && top_inst.dot11_inst.ofdm_decoder_inst.demod_out_strobe) begin
            $fwrite(demod_out_fd, "%d %b %b %b %b %b %b\n",iq_count, top_inst.dot11_inst.ofdm_decoder_inst.demod_out[0],top_inst.dot11_inst.ofdm_decoder_inst.demod_out[1],top_inst.dot11_inst.ofdm_decoder_inst.demod_out[2],top_inst.dot11_inst.ofdm_decoder_inst.demod_out[3],top_inst.dot11_inst.ofdm_decoder_inst.demod_out[4],top_inst.dot11_inst.ofdm_decoder_inst.demod_out[5]);
            $fwrite(demod_soft_bits_fd, "%d %b %b %b %b %b %b\n",iq_count, top_inst.dot11_inst.ofdm_decoder_inst.demod_soft_bits[0],top_inst.dot11_inst.ofdm_decoder_inst.demod_soft_bits[1],top_inst.dot11_inst.ofdm_decoder_inst.demod_soft_bits[2],top_inst.dot11_inst.ofdm_decoder_inst.demod_soft_bits[3],top_inst.dot11_inst.ofdm_decoder_inst.demod_soft_bits[4],top_inst.dot11_inst.ofdm_decoder_inst.demod_soft_bits[5]);
            $fwrite(demod_soft_bits_pos_fd, "%d %b %b %b %b\n",iq_count, top_inst.dot11_inst.ofdm_decoder_inst.demod_soft_bits_pos[0],top_inst.dot11_inst.ofdm_decoder_inst.demod_soft_bits_pos[1],top_inst.dot11_inst.ofdm_decoder_inst.demod_soft_bits_pos[2],top_inst.dot11_inst.ofdm_decoder_inst.demod_soft_bits_pos[3]);
            $fflush(demod_out_fd);
            $fflush(demod_soft_bits_fd);
            $fflush(demod_soft_bits_pos_fd);
        end

        if ((top_inst.state == S_MPDU_DELIM || top_inst.state == S_DECODE_DATA || top_inst.state == S_MPDU_PAD) && top_inst.dot11_inst.deinterleave_erase_out_strobe) begin
            $fwrite(deinterleave_erase_out_fd, "%d %b %b %b %b %b %b %b %b\n", iq_count, top_inst.dot11_inst.deinterleave_erase_out[0], top_inst.dot11_inst.deinterleave_erase_out[1], top_inst.dot11_inst.deinterleave_erase_out[2], top_inst.dot11_inst.deinterleave_erase_out[3], top_inst.dot11_inst.deinterleave_erase_out[4], top_inst.dot11_inst.deinterleave_erase_out[5], top_inst.dot11_inst.deinterleave_erase_out[6],  top_inst.dot11_inst.deinterleave_erase_out[7]);
            $fflush(deinterleave_erase_out_fd);
        end

        if ((top_inst.state == S_MPDU_DELIM || top_inst.state == S_DECODE_DATA || top_inst.state == S_MPDU_PAD) && top_inst.dot11_inst.conv_decoder_out_stb && top_inst.dot11_inst.ofdm_decoder_inst.reset==0) begin
            $fwrite(conv_out_fd, "%d %b\n", iq_count, top_inst.dot11_inst.conv_decoder_out);
            $fflush(conv_out_fd);
        end

        if ((top_inst.state == S_MPDU_DELIM || top_inst.state == S_DECODE_DATA || top_inst.state == S_MPDU_PAD) && top_inst.dot11_inst.descramble_out_strobe) begin
            $fwrite(descramble_out_fd, "%d %b\n", iq_count, top_inst.dot11_inst.descramble_out);
            $fflush(descramble_out_fd);
        end

        if ((top_inst.state == S_MPDU_DELIM || top_inst.state == S_DECODE_DATA || top_inst.state == S_MPDU_PAD) && top_inst.byte_out_strobe) begin
            $fwrite(byte_out_fd, "%d %02x\n", iq_count, top_inst.byte_out);
            $fflush(byte_out_fd);
        end

        // sync_short 
        if (top_inst.dot11_inst.sync_short_inst.mag_sq_stb && top_inst.dot11_inst.sync_short_inst.enable && ~top_inst.dot11_inst.sync_short_inst.reset && top_inst.state == S_SYNC_SHORT) begin
        //if (top_inst.dot11_inst.sync_short_inst.mag_sq_stb && top_inst.dot11_inst.sync_short_inst.enable && ~top_inst.dot11_inst.sync_short_inst.reset) begin
            $fwrite(mag_sq_fd, "%d %d\n", iq_count, top_inst.dot11_inst.sync_short_inst.mag_sq);
            $fflush(mag_sq_fd);
        end
        if (top_inst.dot11_inst.sync_short_inst.mag_sq_avg_stb && top_inst.dot11_inst.sync_short_inst.enable && ~top_inst.dot11_inst.sync_short_inst.reset && top_inst.state == S_SYNC_SHORT) begin
        //if (top_inst.dot11_inst.sync_short_inst.mag_sq_avg_stb && top_inst.dot11_inst.sync_short_inst.enable && ~top_inst.dot11_inst.sync_short_inst.reset) begin
            $fwrite(mag_sq_avg_fd, "%d %d\n", iq_count, top_inst.dot11_inst.sync_short_inst.mag_sq_avg);
            $fflush(mag_sq_avg_fd);
        end
        if (top_inst.dot11_inst.sync_short_inst.prod_stb && top_inst.dot11_inst.sync_short_inst.enable && ~top_inst.dot11_inst.sync_short_inst.reset && top_inst.state == S_SYNC_SHORT) begin
        //if (top_inst.dot11_inst.sync_short_inst.prod_stb && top_inst.dot11_inst.sync_short_inst.enable && ~top_inst.dot11_inst.sync_short_inst.reset) begin
            $fwrite(prod_fd, "%d %d %d\n", iq_count, $signed(top_inst.dot11_inst.sync_short_inst.prod[63:32]), $signed(top_inst.dot11_inst.sync_short_inst.prod[31:0]));
            $fflush(prod_fd);
        end
        if (top_inst.dot11_inst.sync_short_inst.prod_avg_stb && top_inst.dot11_inst.sync_short_inst.enable && ~top_inst.dot11_inst.sync_short_inst.reset && top_inst.state == S_SYNC_SHORT) begin
        //if (top_inst.dot11_inst.sync_short_inst.prod_avg_stb && top_inst.dot11_inst.sync_short_inst.enable && ~top_inst.dot11_inst.sync_short_inst.reset) begin
            $fwrite(prod_avg_fd, "%d %d %d\n", iq_count, $signed(top_inst.dot11_inst.sync_short_inst.prod_avg[63:32]), $signed(top_inst.dot11_inst.sync_short_inst.prod_avg[31:0]));
            $fflush(prod_avg_fd);
        end
        if (top_inst.dot11_inst.sync_short_inst.phase_in_stb && top_inst.dot11_inst.sync_short_inst.enable && ~top_inst.dot11_inst.sync_short_inst.reset && top_inst.state == S_SYNC_SHORT) begin
        //if (top_inst.dot11_inst.sync_short_inst.phase_in_stb && top_inst.dot11_inst.sync_short_inst.enable && ~top_inst.dot11_inst.sync_short_inst.reset) begin
            $fwrite(phase_in_fd, "%d %d %d\n", iq_count, $signed(top_inst.dot11_inst.sync_short_inst.phase_in_i), $signed(top_inst.dot11_inst.sync_short_inst.phase_in_q));
            $fflush(phase_in_fd);
        end
        if (top_inst.dot11_inst.sync_short_inst.phase_out_stb && top_inst.dot11_inst.sync_short_inst.enable && ~top_inst.dot11_inst.sync_short_inst.reset && top_inst.state == S_SYNC_SHORT) begin
        //if (top_inst.dot11_inst.sync_short_inst.phase_out_stb && top_inst.dot11_inst.sync_short_inst.enable && ~top_inst.dot11_inst.sync_short_inst.reset) begin
            $fwrite(phase_out_fd, "%d %d\n", iq_count, $signed(top_inst.dot11_inst.sync_short_inst.phase_out));
            $fflush(phase_out_fd);
        end
        if (top_inst.dot11_inst.sync_short_inst.delay_prod_avg_mag_stb && top_inst.dot11_inst.sync_short_inst.enable && ~top_inst.dot11_inst.sync_short_inst.reset && top_inst.state == S_SYNC_SHORT) begin
        //if (top_inst.dot11_inst.sync_short_inst.delay_prod_avg_mag_stb && top_inst.dot11_inst.sync_short_inst.enable && ~top_inst.dot11_inst.sync_short_inst.reset) begin
            $fwrite(delay_prod_avg_mag_fd, "%d %d\n", iq_count, top_inst.dot11_inst.sync_short_inst.delay_prod_avg_mag);
            $fflush(delay_prod_avg_mag_fd);
        end

        // sync_long 
        if (top_inst.dot11_inst.sync_long_inst.sum_stb && top_inst.dot11_inst.sync_long_inst.enable && ~top_inst.dot11_inst.sync_long_inst.reset) begin
            $fwrite(sum_fd, "%d %d %d\n", iq_count, top_inst.dot11_inst.sync_long_inst.sum_i, top_inst.dot11_inst.sync_long_inst.sum_q);
            $fflush(sum_fd);
        end
        if (top_inst.dot11_inst.sync_long_inst.metric_stb && top_inst.dot11_inst.sync_long_inst.enable && ~top_inst.dot11_inst.sync_long_inst.reset) begin
            $fwrite(metric_fd, "%d %d\n", iq_count, top_inst.dot11_inst.sync_long_inst.metric);
            $fflush(metric_fd);
        end
        if (top_inst.dot11_inst.sync_long_inst.raw_stb && top_inst.dot11_inst.sync_long_inst.enable && ~top_inst.dot11_inst.sync_long_inst.reset && top_inst.dot11_inst.sync_long_inst.state == top_inst.dot11_inst.sync_long_inst.S_FFT) begin
            $fwrite(raw_fd, "%d %d %d\n", iq_count, top_inst.dot11_inst.sync_long_inst.raw_i, top_inst.dot11_inst.sync_long_inst.raw_q);
            $fflush(raw_fd);
            $fwrite(phase_correction_fd, "%d %d\n", iq_count, top_inst.dot11_inst.sync_long_inst.phase_correction);
            $fflush(phase_correction_fd);
            $fwrite(next_phase_correction_fd, "%d %d\n", iq_count, top_inst.dot11_inst.sync_long_inst.next_phase_correction);
            $fflush(next_phase_correction_fd);
        end
        if (top_inst.dot11_inst.sync_long_inst.fft_in_stb && top_inst.dot11_inst.sync_long_inst.enable && ~top_inst.dot11_inst.sync_long_inst.reset && top_inst.demod_is_ongoing) begin//add demod_is_ongoing to prevent the garbage fft in after decoding is done overlap with the early sync_short of next packet
            $fwrite(fft_in_fd, "%d %d %d\n", iq_count, top_inst.dot11_inst.sync_long_inst.fft_in_re, top_inst.dot11_inst.sync_long_inst.fft_in_im);
            $fflush(fft_in_fd);
        end
        if (top_inst.dot11_inst.sync_long_inst.sample_out_strobe) begin
            $fwrite(sync_long_out_fd, "%d %d %d\n",iq_count, $signed(top_inst.dot11_inst.sync_long_inst.sample_out[31:16]), $signed(top_inst.dot11_inst.sync_long_inst.sample_out[15:0]));
            $fflush(sync_long_out_fd);
        end
        // equalizer 
        if ((top_inst.dot11_inst.equalizer_inst.num_ofdm_sym == 1 || (top_inst.dot11_inst.equalizer_inst.pkt_ht==1 && top_inst.dot11_inst.equalizer_inst.num_ofdm_sym==5)) && top_inst.dot11_inst.equalizer_inst.state == top_inst.dot11_inst.equalizer_inst.S_CPE_ESTIMATE && top_inst.dot11_inst.equalizer_inst.sample_in_strobe_dly == 1 && top_inst.dot11_inst.equalizer_inst.enable && ~top_inst.dot11_inst.equalizer_inst.reset) begin
            $fwrite(new_lts_fd, "%d %d %d\n", iq_count, top_inst.dot11_inst.equalizer_inst.lts_i_out, top_inst.dot11_inst.equalizer_inst.lts_q_out);
            $fflush(new_lts_fd);
        end
        if (top_inst.dot11_inst.equalizer_inst.pilot_in_stb && top_inst.dot11_inst.equalizer_inst.enable && top_inst.dot11_inst.equalizer_inst.state==top_inst.dot11_inst.equalizer_inst.S_CPE_ESTIMATE && ~top_inst.dot11_inst.equalizer_inst.reset && top_inst.demod_is_ongoing) begin
            $fwrite(phase_offset_pilot_input_fd, "%d %d %d\n", iq_count, top_inst.dot11_inst.equalizer_inst.input_i, top_inst.dot11_inst.equalizer_inst.input_q);
            $fflush(phase_offset_pilot_input_fd);
            $fwrite(phase_offset_lts_input_fd, "%d %d %d\n", iq_count, top_inst.dot11_inst.equalizer_inst.lts_i_out, top_inst.dot11_inst.equalizer_inst.lts_q_out);
            $fflush(phase_offset_lts_input_fd);
        end
        if (top_inst.dot11_inst.equalizer_inst.pilot_out_stb && top_inst.dot11_inst.equalizer_inst.enable && top_inst.dot11_inst.equalizer_inst.state==top_inst.dot11_inst.equalizer_inst.S_CPE_ESTIMATE && ~top_inst.dot11_inst.equalizer_inst.reset && top_inst.demod_is_ongoing) begin
            $fwrite(phase_offset_pilot_fd, "%d %d %d\n", iq_count, top_inst.dot11_inst.equalizer_inst.pilot_i, top_inst.dot11_inst.equalizer_inst.pilot_q);
            $fflush(phase_offset_pilot_fd);
        end
        if (top_inst.dot11_inst.equalizer_inst.phase_in_stb && top_inst.dot11_inst.equalizer_inst.enable && top_inst.dot11_inst.equalizer_inst.state==top_inst.dot11_inst.equalizer_inst.S_PILOT_PE_CORRECTION && ~top_inst.dot11_inst.equalizer_inst.reset && top_inst.demod_is_ongoing) begin
            $fwrite(phase_offset_pilot_sum_fd, "%d %d %d\n", iq_count, top_inst.dot11_inst.equalizer_inst.pilot_sum_i, top_inst.dot11_inst.equalizer_inst.pilot_sum_q);
            $fflush(phase_offset_pilot_sum_fd);
        end
        if (top_inst.dot11_inst.equalizer_inst.phase_out_stb && top_inst.dot11_inst.equalizer_inst.enable && top_inst.dot11_inst.equalizer_inst.state==top_inst.dot11_inst.equalizer_inst.S_PILOT_PE_CORRECTION && ~top_inst.dot11_inst.equalizer_inst.reset && top_inst.demod_is_ongoing) begin
            $fwrite(phase_offset_phase_out_fd, "%d %d\n", iq_count, $signed(top_inst.dot11_inst.equalizer_inst.phase_out));
            $fflush(phase_offset_phase_out_fd);
        end
        if (top_inst.dot11_inst.equalizer_inst.lvpe_out_stb && top_inst.dot11_inst.equalizer_inst.enable && ~top_inst.dot11_inst.equalizer_inst.reset && top_inst.demod_is_ongoing) begin
            $fwrite(cpe_fd, "%d %d\n", iq_count, $signed(top_inst.dot11_inst.equalizer_inst.cpe));
            $fflush(cpe_fd);
        end
        if (top_inst.dot11_inst.equalizer_inst.lvpe_out_stb && top_inst.dot11_inst.equalizer_inst.enable && ~top_inst.dot11_inst.equalizer_inst.reset && top_inst.demod_is_ongoing) begin
            $fwrite(lvpe_fd, "%d %d\n", iq_count, $signed(top_inst.dot11_inst.equalizer_inst.lvpe));
            $fflush(lvpe_fd);
        end
        if (top_inst.dot11_inst.equalizer_inst.lvpe_out_stb && top_inst.dot11_inst.equalizer_inst.enable && ~top_inst.dot11_inst.equalizer_inst.reset && top_inst.demod_is_ongoing) begin
            $fwrite(sxy_fd, "%d %d\n", iq_count, $signed(top_inst.dot11_inst.equalizer_inst.Sxy));
            $fflush(sxy_fd);
        end
        if (top_inst.dot11_inst.equalizer_inst.num_output == top_inst.dot11_inst.equalizer_inst.num_data_carrier && top_inst.dot11_inst.equalizer_inst.enable && top_inst.dot11_inst.equalizer_inst.state==top_inst.dot11_inst.equalizer_inst.S_ALL_SC_PE_CORRECTION && ~top_inst.dot11_inst.equalizer_inst.reset && top_inst.demod_is_ongoing) begin
            $fwrite(prev_peg_fd, "%d %d\n", iq_count, $signed(top_inst.dot11_inst.equalizer_inst.prev_peg_reg));
            $fflush(prev_peg_fd);
        end
        if (top_inst.dot11_inst.equalizer_inst.lvpe_out_stb && top_inst.dot11_inst.equalizer_inst.enable && ~top_inst.dot11_inst.equalizer_inst.reset && top_inst.demod_is_ongoing) begin
            $fwrite(peg_sym_scale_fd, "%d %d\n", iq_count, $signed(top_inst.dot11_inst.equalizer_inst.peg_sym_scale));
            $fflush(peg_sym_scale_fd);
        end
        if (top_inst.dot11_inst.equalizer_inst.pilot_count1 < 4 && top_inst.dot11_inst.equalizer_inst.enable && top_inst.dot11_inst.equalizer_inst.enable && top_inst.dot11_inst.equalizer_inst.state==top_inst.dot11_inst.equalizer_inst.S_PILOT_PE_CORRECTION && ~top_inst.dot11_inst.equalizer_inst.reset && top_inst.demod_is_ongoing) begin
            $fwrite(peg_pilot_scale_fd, "%d %d\n", iq_count, $signed(top_inst.dot11_inst.equalizer_inst.peg_pilot_scale));
            $fflush(peg_pilot_scale_fd);
        end
        if (top_inst.dot11_inst.equalizer_inst.rot_in_stb && top_inst.dot11_inst.equalizer_inst.enable && top_inst.dot11_inst.equalizer_inst.state==top_inst.dot11_inst.equalizer_inst.S_ALL_SC_PE_CORRECTION && ~top_inst.dot11_inst.equalizer_inst.reset && top_inst.demod_is_ongoing) begin
            $fwrite(rot_in_fd, "%d %d %d %d\n", iq_count, $signed(top_inst.dot11_inst.equalizer_inst.buf_i_out), $signed(top_inst.dot11_inst.equalizer_inst.buf_q_out), $signed(top_inst.dot11_inst.equalizer_inst.sym_phase));
            $fflush(rot_in_fd);
        end
        if (top_inst.dot11_inst.equalizer_inst.rot_out_stb && top_inst.dot11_inst.equalizer_inst.state==top_inst.dot11_inst.equalizer_inst.S_ALL_SC_PE_CORRECTION && top_inst.dot11_inst.equalizer_inst.enable && ~top_inst.dot11_inst.equalizer_inst.reset && top_inst.demod_is_ongoing) begin
        // when enable is 0, it locked equalizer all internal variables till the next reset/enable, some large delayed signal, such as rot out, logged with some garbage
        // limite the log to top_inst.dot11_inst.equalizer_inst.S_ALL_SC_PE_CORRECTION state
            $fwrite(rot_out_fd, "%d %d %d\n", iq_count, top_inst.dot11_inst.equalizer_inst.rot_i, top_inst.dot11_inst.equalizer_inst.rot_q);
            $fflush(rot_out_fd);
        end
        if (top_inst.dot11_inst.equalizer_inst.prod_out_strobe && top_inst.dot11_inst.equalizer_inst.enable && ~top_inst.dot11_inst.equalizer_inst.reset && top_inst.demod_is_ongoing) begin
            $fwrite(equalizer_prod_fd, "%d %d %d\n", iq_count, $signed(top_inst.dot11_inst.equalizer_inst.prod_i), $signed(top_inst.dot11_inst.equalizer_inst.prod_q));
            $fflush(equalizer_prod_fd);
            $fwrite(equalizer_prod_scaled_fd, "%d %d %d\n", iq_count, $signed(top_inst.dot11_inst.equalizer_inst.prod_i_scaled), $signed(top_inst.dot11_inst.equalizer_inst.prod_q_scaled));
            $fflush(equalizer_prod_scaled_fd);
            $fwrite(equalizer_mag_sq_fd, "%d %d\n", iq_count, top_inst.dot11_inst.equalizer_inst.mag_sq);
            $fflush(equalizer_mag_sq_fd);
        end
        if (top_inst.dot11_inst.equalizer_inst.sample_out_strobe && top_inst.dot11_inst.equalizer_inst.enable && ~top_inst.dot11_inst.equalizer_inst.reset && top_inst.demod_is_ongoing) begin
            $fwrite(equalizer_out_fd, "%d %d %d\n", iq_count, $signed(top_inst.dot11_inst.equalizer_inst.sample_out[31:16]), $signed(top_inst.dot11_inst.equalizer_inst.sample_out[15:0]));
            $fflush(equalizer_out_fd);
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

always @(negedge lvdsclock) begin
    if (reset) begin
        sample_bitClk <= 0; // bit clock
    end else begin
        sample_bitClk <= ~sample_bitClk;
    end
end

always @(posedge lvdsclock) begin
    if (reset) begin
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
    .SYS_clk(master_clk),
    //.clk_100M(clock),
`ifdef USE_PARALLEL_SAMPLES
    .i_sample_i(fsample_in_i),
    .i_sample_q(fsample_in_q),
    .sample_in_strobe(sample_in_strobe),
`endif // !USE_PARALLEL_SAMPLES
    //.rssi_half_db(rssi_half_db),
    .demod_is_ongoing(demod_is_ongoing),
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
