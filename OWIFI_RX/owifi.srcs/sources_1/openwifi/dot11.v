`include "common_defs.v"
`include "openofdm_rx_pre_def.v"

`ifdef OPENOFDM_RX_ENABLE_DBG
`define DEBUG_PREFIX (*mark_debug="true",DONT_TOUCH="TRUE"*)
`else
`define DEBUG_PREFIX
`endif

`define USE_POWER_TRIGGER

module dot11 (
    input i_clock,
    input i_enable,
    input i_reset,
    input i_reset_without_watchdog,

    // setting registers
    //input set_stb,
    //input [7:0] set_addr,
    //input [31:0] set_data,
    
    // add ports for register based inputs
    input signed [10:0] i_power_thres,
    input [31:0] i_min_plateau,
    input i_threshold_scale,
    input i_num_sample_changed,
    input [31:0] i_reg_num_sample_to_skip,
    input [15:0] i_reg_power_thres, //signal power threshold that asserts trigger
    input [15:0] i_reg_window_size,

    // INPUT: RSSI
    input signed [10:0] i_rssi_half_db,
    // INPUT: I/Q sample
    input [31:0] i_sample_in,
    input i_sample_in_strobe,
    input i_soft_decoding,
    input wire i_force_ht_smoothing,
    input wire i_disable_all_smoothing,
    input [3:0] i_fft_win_shift, 

    // OUTPUT: bytes and FCS status
    output reg demod_is_ongoing,
    output reg pkt_begin,
    output reg pkt_ht,
    output reg pkt_header_valid,
    output reg pkt_header_valid_strobe,
    output reg ht_unsupport,
    output reg [7:0] pkt_rate,
    output reg [15:0] pkt_len,
    output reg [15:0] pkt_len_total,
    output byte_out_strobe,
    output [7:0] byte_out,
    output reg [15:0] byte_count_total,
    output reg [15:0] byte_count,
    output reg fcs_out_strobe,
    output reg fcs_ok,

    /////////////////////////////////////////////////////////
    // DEBUG PORTS
    /////////////////////////////////////////////////////////
    
    // decode status
    // (* mark_debug = "true", DONT_TOUCH = "TRUE" *) 
    `DEBUG_PREFIX output reg [4:0] state,
    `DEBUG_PREFIX output reg [4:0] status_code,
    `DEBUG_PREFIX output state_changed,
    `DEBUG_PREFIX output reg [31:0] state_history,

    // power trigger
    `DEBUG_PREFIX output power_trigger,

    // sync short
    `DEBUG_PREFIX output short_preamble_detected,
    `DEBUG_PREFIX output [15:0] phase_offset,

    // sync long
    `DEBUG_PREFIX output [31:0] sync_long_metric,
    `DEBUG_PREFIX output sync_long_metric_stb,
    `DEBUG_PREFIX output long_preamble_detected,
    `DEBUG_PREFIX output [31:0] sync_long_out,
    `DEBUG_PREFIX output sync_long_out_strobe,
    `DEBUG_PREFIX output wire signed [31:0] phase_offset_taken,
    `DEBUG_PREFIX output [2:0] sync_long_state,

    // equalizer
    `DEBUG_PREFIX output [31:0] equalizer_out,
    `DEBUG_PREFIX output equalizer_out_strobe,
    `DEBUG_PREFIX output [3:0] equalizer_state,
    `DEBUG_PREFIX output wire ofdm_symbol_eq_out_pulse,

    // legacy signal info
    output reg legacy_sig_stb,
    output [3:0] legacy_rate,
    output legacy_sig_rsvd,
    output [11:0] legacy_len,
    output legacy_sig_parity,
    output legacy_sig_parity_ok,
    output [5:0] legacy_sig_tail,

    // ht signal info
    output reg ht_sig_stb,
    output [6:0] ht_mcs,
    output ht_cbw,
    output [15:0] ht_len,
    output ht_smoothing,
    output ht_not_sounding,
    output ht_aggr,
    output reg ht_aggr_last,
    output [1:0] ht_stbc,
    output ht_fec_coding,
    output ht_sgi,
    output [1:0] ht_num_ext,
    output reg ht_sig_crc_ok,

    `DEBUG_PREFIX output [14:0] n_ofdm_sym,//max 20166 = (22+65535*8)/26 (max ht len 65535 in sig, min ndbps 26 for mcs0)
    `DEBUG_PREFIX output [9:0]  n_bit_in_last_sym,//max ht ndbps 260 (ht mcs7)
    `DEBUG_PREFIX output        phy_len_valid,

    // decoding pipeline
    output [5:0] demod_out,
    output [5:0] demod_soft_bits,
    output [3:0] demod_soft_bits_pos,
    output demod_out_strobe,

    output [7:0] deinterleave_erase_out,
    output deinterleave_erase_out_strobe,

    output conv_decoder_out,
    output conv_decoder_out_stb,

    output descramble_out,
    output descramble_out_strobe,

    // for side channel
    output wire [31:0] csi,
    output wire csi_valid
);

`include "common_params.v"

wire [19:0] n_bit_in_last_sym_tmp;
assign n_bit_in_last_sym = n_bit_in_last_sym_tmp[9:0];

// -------------- DEBUG for rx_stop_state4e012345-------------------------------
`DEBUG_PREFIX reg  [14:0] timeout_counter;
always @(posedge i_clock) begin
  if ( (i_reset==1) || (~(state==S_DETECT_HT)) ) begin
    timeout_counter <= 0;
  end else begin
    timeout_counter <= ( (timeout_counter == 15'h7fff)? timeout_counter : (timeout_counter+1) );
  end
end
// -------------- DEBUG for rx_stop_state4e012345-------------------------------

////////////////////////////////////////////////////////////////////////////////
// extra info output to ease side info and viterbi state monitor
////////////////////////////////////////////////////////////////////////////////
`DEBUG_PREFIX reg  [3:0] equalizer_state_reg;

assign ofdm_symbol_eq_out_pulse = (equalizer_state==4 && equalizer_state_reg==8);

always @(posedge i_clock) begin
    if (i_reset_without_watchdog == 1) begin
        state_history <= 0;
        equalizer_state_reg <= 0;
    end else begin
        equalizer_state_reg <= equalizer_state;
        if (state_changed) begin
            state_history[3:0] <= state;
            state_history[31:4] <= state_history[27:0];
        end 
    end
end
////////////////////////////////////////////////////////////////////////////////


////////////////////////////////////////////////////////////////////////////////
// Shared rotation LUT for sync_long and equalizer
////////////////////////////////////////////////////////////////////////////////
wire [`ROTATE_LUT_LEN_SHIFT-1:0] sync_long_rot_addr;
wire [31:0] sync_long_rot_data;

wire [`ROTATE_LUT_LEN_SHIFT-1:0] eq_rot_addr;
wire [31:0] eq_rot_data;

rot_lut rot_lut_inst (
    .clka(i_clock),
    .addra(sync_long_rot_addr),
    .douta(sync_long_rot_data),

    .clkb(i_clock),
    .addrb(eq_rot_addr),
    .doutb(eq_rot_data),
    .enb(1'b1)
);
////////////////////////////////////////////////////////////////////////////////


////////////////////////////////////////////////////////////////////////////////
// Shared phase module for sync_short and equalizer
////////////////////////////////////////////////////////////////////////////////
wire [31:0] sync_short_phase_in_i;
wire [31:0] sync_short_phase_in_q;
wire sync_short_phase_in_stb;
wire [15:0] sync_short_phase_out;
wire sync_short_phase_out_stb;

wire [31:0] eq_phase_in_i;
wire [31:0] eq_phase_in_q;
wire eq_phase_in_stb;
wire [15:0] eq_phase_out;
wire eq_phase_out_stb;

wire[31:0] phase_in_i = state == S_SYNC_SHORT?
    sync_short_phase_in_i: eq_phase_in_i;
wire[31:0] phase_in_q = state == S_SYNC_SHORT?
    sync_short_phase_in_q: eq_phase_in_q;
wire phase_in_stb = state == S_SYNC_SHORT?
    sync_short_phase_in_stb: eq_phase_in_stb;

wire [15:0] phase_out;
wire phase_out_stb;

assign sync_short_phase_out = phase_out;
assign sync_short_phase_out_stb = phase_out_stb;
assign eq_phase_out = phase_out;
assign eq_phase_out_stb = phase_out_stb;

phase phase_inst (
    .clock(i_clock),
    .reset(i_reset),
    .enable(i_enable),

    .in_i(phase_in_i),
    .in_q(phase_in_q),
    .input_strobe(phase_in_stb),

    .phase(phase_out),
    .output_strobe(phase_out_stb)
);
////////////////////////////////////////////////////////////////////////////////

reg sync_short_reset;
reg sync_long_reset;
// wire sync_short_enable = state == S_SYNC_SHORT;
wire sync_short_enable = 1;
reg sync_long_enable;
wire [15:0] num_ofdm_symbol;

reg equalizer_reset;
reg equalizer_enable;

reg ht_next;

wire eq_out_stb_delayed;
wire [15:0] eq_out_i = equalizer_out[31:16];
wire [15:0] eq_out_q = equalizer_out[15:0];
wire [15:0] eq_out_i_delayed;
wire [15:0] eq_out_q_delayed;
reg [15:0] abs_eq_i;
reg [15:0] abs_eq_q;
reg [3:0] rot_eq_count;
reg [3:0] normal_eq_count;

// OFDM control
reg ofdm_reset;
reg ofdm_enable;
reg ofdm_in_stb;
reg [15:0] ofdm_in_i;
reg [15:0] ofdm_in_q;

reg do_descramble;
reg [19:0] num_bits_to_decode; //4bits + ht_len: num_bits_to_decode <= (22+(ht_len<<3));
reg short_gi;

reg [4:0] old_state;

`ifndef USE_POWER_TRIGGER
assign power_trigger = (rssi_half_db>=i_power_thres? 1: 0);
`endif // USE_POWER_TRIGGER
assign state_changed = state != old_state;

// SIGNAL information
reg [23:0] signal_bits;

assign legacy_rate = signal_bits[3:0];
assign legacy_sig_rsvd = signal_bits[4];
assign legacy_len = signal_bits[16:5];
assign legacy_sig_parity = signal_bits[17];
assign legacy_sig_tail = signal_bits[23:18];
assign legacy_sig_parity_ok = ~^signal_bits[17:0];

// HT-SIG information
reg [23:0] ht_sig1;
reg [23:0] ht_sig2;

assign ht_mcs = ht_sig1[6:0];
assign ht_cbw = ht_sig1[7];
assign ht_len = ht_sig1[23:8];

assign ht_smoothing = ht_sig2[0];
assign ht_not_sounding = ht_sig2[1];
assign ht_aggr = ht_sig2[3];
assign ht_stbc = ht_sig2[5:4];
assign ht_fec_coding = ht_sig2[6];
assign ht_sgi = ht_sig2[7];
assign ht_num_ext = ht_sig2[9:8];

wire ht_rsvd = ht_sig2[2];
wire [7:0] crc = ht_sig2[17:10];
wire [5:0] ht_sig_tail = ht_sig2[23:18];

reg [15:0] pkt_len_rem;
reg [7:0] mpdu_del_crc;
reg [1:0] mpdu_pad;

reg crc_in_stb;
reg crc_in;
reg [7:0] crc_count;
reg crc_reset;
wire [7:0] crc_out;

reg [31:0] sample_count;

wire fcs_enable = state == S_DECODE_DATA && byte_out_strobe;
wire fcs_reset = state_changed && state == S_DECODE_DATA;
wire [7:0] byte_reversed;
wire [31:0] pkt_fcs;

assign byte_reversed[0] = byte_out[7];
assign byte_reversed[1] = byte_out[6];
assign byte_reversed[2] = byte_out[5];
assign byte_reversed[3] = byte_out[4];
assign byte_reversed[4] = byte_out[3];
assign byte_reversed[5] = byte_out[2];
assign byte_reversed[6] = byte_out[1];
assign byte_reversed[7] = byte_out[0];

reg [15:0] sync_long_out_count;

`ifdef USE_POWER_TRIGGER
power_trigger power_trigger_inst (
    .clock(i_clock),
    .enable(i_enable),
    .reset(i_reset),

    .sample_in(i_sample_in),
    .sample_in_strobe(i_sample_in_strobe),

    //.i_power_thres(i_power_thres),
    //.window_size(window_size),
    //.num_sample_to_skip(num_sample_to_skip),
    //.num_sample_changed(num_sample_changed),
    .i_num_sample_changed(i_num_sample_changed),
    .i_reg_num_sample_to_skip(i_reg_num_sample_to_skip),
    .i_reg_power_thres(i_reg_power_thres),
    .i_reg_window_size(i_reg_window_size),

    //.pw_state_spy(pw_state_spy),
    .trigger(power_trigger)
);
`endif // USE_POWER_TRIGGER

sync_short sync_short_inst (
    .clock(i_clock),
    .reset(i_reset | sync_short_reset),
    .enable(i_enable & sync_short_enable),

    .min_plateau(i_min_plateau),
    .threshold_scale(i_threshold_scale),
    
    .sample_in(i_sample_in),
    .sample_in_strobe(i_sample_in_strobe),

    .phase_in_i(sync_short_phase_in_i),
    .phase_in_q(sync_short_phase_in_q),
    .phase_in_stb(sync_short_phase_in_stb),

    .phase_out(sync_short_phase_out),
    .phase_out_stb(sync_short_phase_out_stb),

    .demod_is_ongoing(demod_is_ongoing),
    .short_preamble_detected(short_preamble_detected),
    .phase_offset(phase_offset)
);

sync_long sync_long_inst (
    .clock(i_clock),
    .reset(i_reset | sync_long_reset),
    .enable(i_enable & sync_long_enable),

    .sample_in(i_sample_in),
    .sample_in_strobe(i_sample_in_strobe),
    .phase_offset(phase_offset),
    .short_gi(short_gi),
    .fft_win_shift(i_fft_win_shift),

    .rot_addr(sync_long_rot_addr),
    .rot_data(sync_long_rot_data),

    .metric(sync_long_metric),
    .metric_stb(sync_long_metric_stb),
    .long_preamble_detected(long_preamble_detected),
    .phase_offset_taken(phase_offset_taken),
    .state(sync_long_state),

    .sample_out(sync_long_out),
    .sample_out_strobe(sync_long_out_strobe),
    .num_ofdm_symbol(num_ofdm_symbol)
);

equalizer equalizer_inst (
    .clock(i_clock),
    .reset(i_reset | equalizer_reset),
    .enable(i_enable & equalizer_enable),

    .sample_in(sync_long_out),
    .sample_in_strobe(sync_long_out_strobe && !(state==S_HT_SIGNAL && num_ofdm_symbol==6)),
    .ht_next(ht_next),
    .pkt_ht(pkt_ht),
    .ht_smoothing(ht_smoothing|i_force_ht_smoothing),
    .disable_all_smoothing(i_disable_all_smoothing),

    .phase_in_i(eq_phase_in_i),
    .phase_in_q(eq_phase_in_q),
    .phase_in_stb(eq_phase_in_stb),

    .phase_out(eq_phase_out),
    .phase_out_stb(eq_phase_out_stb),

    .rot_addr(eq_rot_addr),
    .rot_data(eq_rot_data),

    .sample_out(equalizer_out),
    .sample_out_strobe(equalizer_out_strobe),

    .state(equalizer_state),

    .csi(csi),
    .csi_valid(csi_valid)
);


delayT #(.DATA_WIDTH(33), .DELAY(9)) eq_delay_inst (
    .clock(i_clock),
    .reset(i_reset),

    .data_in({equalizer_out_strobe, equalizer_out}),
    .data_out({eq_out_stb_delayed, eq_out_i_delayed, eq_out_q_delayed})
);


ofdm_decoder ofdm_decoder_inst (
    .clock(i_clock),
    .reset(i_reset|ofdm_reset),
    .enable(i_enable & ofdm_enable),

    .sample_in({ofdm_in_i, ofdm_in_q}),
    .sample_in_strobe(ofdm_in_stb),
    .soft_decoding(i_soft_decoding),

    .do_descramble(do_descramble),
    .num_bits_to_decode(num_bits_to_decode),
    .rate(pkt_rate),

    .byte_out(byte_out),
    .byte_out_strobe(byte_out_strobe),

    .demod_out(demod_out),
    .demod_soft_bits(demod_soft_bits),
    .demod_soft_bits_pos(demod_soft_bits_pos),
    .demod_out_strobe(demod_out_strobe),

    .deinterleave_erase_out(deinterleave_erase_out),
    .deinterleave_erase_out_strobe(deinterleave_erase_out_strobe),

    .conv_decoder_out(conv_decoder_out),
    .conv_decoder_out_stb(conv_decoder_out_stb),

    .descramble_out(descramble_out),
    .descramble_out_strobe(descramble_out_strobe)
);

ht_sig_crc crc_inst (
    .clock(i_clock),
    .enable(i_enable),
    .reset(i_reset | crc_reset),

    .bit(crc_in),
    .input_strobe(crc_in_stb),
    .crc(crc_out)
);

crc32 fcs_inst (
    .clk(i_clock),
    .crc_en(i_enable & fcs_enable),
    .rst(i_reset | fcs_reset),
    .data_in(byte_reversed),
    .crc_out(pkt_fcs)
);

phy_len_calculation phy_len_calculation_inst(
    .clock(i_clock),
    .reset(i_reset_without_watchdog | long_preamble_detected),
    .enable(),

    .state(state),
    .old_state(old_state),
    .num_bits_to_decode(num_bits_to_decode),
    .pkt_rate(pkt_rate),//bit [7] 1 means ht; 0 means non-ht
    
    .n_ofdm_sym(n_ofdm_sym),//max 20166 = (22+65535*8)/26
    .n_bit_in_last_sym(n_bit_in_last_sym_tmp),//max ht ndbps 260
    .phy_len_valid(phy_len_valid)
);

always @(posedge i_clock) begin
    if (i_reset) begin
        status_code <= E_OK;
        state <= S_WAIT_POWER_TRIGGER;
        old_state <= 0;

        sync_short_reset <= 0;

        sync_long_reset <= 0;
        sync_long_enable <= 0;

        byte_count <= 0;
        byte_count_total <= 0;

        demod_is_ongoing <= 0;
        pkt_begin <= 0;
        pkt_ht <= 0;
        pkt_header_valid <= 0;
        pkt_header_valid_strobe <= 0;
        ht_unsupport <= 0;

        rot_eq_count <= 0;
        normal_eq_count <= 0;
        abs_eq_i <= 0;
        abs_eq_q <= 0;

        do_descramble <= 0;
        num_bits_to_decode <= 0;
        short_gi <= 0;
        pkt_rate <= 0;

        equalizer_reset <= 0;
        equalizer_enable <= 0;
        ht_next <= 0;

        pkt_len_rem <= 0;
        mpdu_del_crc <= 0;
        mpdu_pad <= 0;
        pkt_len <= 0;
        pkt_len_total <= 0;

        ofdm_reset <= 0;
        ofdm_enable <= 0;
        ofdm_in_stb <= 0;
        ofdm_in_i <= 0;
        ofdm_in_q <= 0;

        sample_count <= 0;

        sync_long_out_count <= 0;

        signal_bits <= 0;
        legacy_sig_stb <= 0;

        ht_sig1 <= 0;
        ht_sig2 <= 0;
        crc_in_stb <= 0;
        crc_in <= 0;
        crc_count <= 0;
        crc_reset <= 0;
        ht_sig_crc_ok <= 0;
        ht_sig_stb <= 0;
        ht_aggr_last <= 0;

        fcs_out_strobe <= 0;
        fcs_ok <= 0;
    end else if (i_enable) begin
        old_state <= state;

        case(state)
            S_WAIT_POWER_TRIGGER: begin
                sync_short_reset <= 0;

                pkt_begin <= 0;
                pkt_ht <= 0;
                crc_reset <= 0;
                short_gi <= 0;
                demod_is_ongoing <= 0;
                sync_long_enable <= 0;
                equalizer_enable <= 0;
                ofdm_enable <= 0;
                ofdm_reset <= 0;
                pkt_len_total <= 16'hffff;
                ht_sig1 <= 0;
                ht_sig2 <= 0;
                pkt_len_rem <= 0;

                if (power_trigger) begin
                    `ifdef DEBUG_PRINT
                        $display("Power triggered.");
                    `endif
                    // sync_short_reset <= 1;
                    state <= S_SYNC_SHORT;
                end
            end

            S_SYNC_SHORT: begin

                if (~power_trigger) begin
                    // power level drops before finding STS
                    state <= S_WAIT_POWER_TRIGGER;
                    sync_short_reset <= 1;
                end

                if (short_preamble_detected) begin
                    `ifdef DEBUG_PRINT
                        $display("Short preamble detected");
                    `endif
                    sync_long_reset <= 1;
                    sync_long_enable <= 1;
                    sample_count <= 0;
                    state <= S_SYNC_LONG;
                end
                
            end

            S_SYNC_LONG: begin
                if (sync_long_reset) begin
                    sync_long_reset <= 0;
                end

                if (i_sample_in_strobe) begin
                    sample_count <= sample_count + 1;
                end
                if (sample_count > 320) begin
                    state <= S_WAIT_POWER_TRIGGER;
                    sync_short_reset <= 1;
                end

                if (~power_trigger) begin
                    state <= S_WAIT_POWER_TRIGGER;
                    sync_short_reset <= 1;
                end

                if (long_preamble_detected) begin
                    demod_is_ongoing <= 1;
                    pkt_rate <= {1'b0, 3'b0, 4'b1011};
                    do_descramble <= 0;
                    num_bits_to_decode <= 24;

                    ofdm_reset <= 1;
                    ofdm_enable <= 1;

                    equalizer_enable <= 1;
                    equalizer_reset <= 1;

                    byte_count <= 0;
                    byte_count_total <= 0;
                    state <= S_DECODE_SIGNAL;
                    sync_short_reset <= 1;
                end
            end

            S_DECODE_SIGNAL: begin
                sync_short_reset <= 0;
                ofdm_reset <= 0;

                if (equalizer_reset) begin
                    equalizer_reset <= 0;
                end

                ofdm_in_stb <= equalizer_out_strobe;
                ofdm_in_i <= eq_out_i;
                ofdm_in_q <= eq_out_q;

                if (byte_out_strobe) begin
                    signal_bits <= {byte_out, signal_bits[23:8]};
                    byte_count <= byte_count + 1;
                    byte_count_total <= byte_count_total + 1;
                end

                if (byte_count == 3) begin
                    byte_count <= 0;
                    `ifdef DEBUG_PRINT
                        $display("[SIGNAL] rate = %04b, ", legacy_rate,
                            "length = %012b (%d), ", legacy_len, legacy_len,
                            "parity = %b, ", legacy_sig_parity,
                            "tail = %6b", legacy_sig_tail);
                    `endif

                    num_bits_to_decode <= (22+(legacy_len<<3));
                    pkt_rate <= {1'b0, 3'b0, legacy_rate};
                    pkt_len <= legacy_len;
                    pkt_len_total <= legacy_len+3;
                    
                    ofdm_reset <= 1;
                    state <= S_CHECK_SIGNAL;
                end
            end

            S_CHECK_SIGNAL: begin
                if (~legacy_sig_parity_ok) begin
                    pkt_header_valid_strobe <= 1;
                    status_code <= E_PARITY_FAIL;
                    state <= S_SIGNAL_ERROR;
                end else if (legacy_sig_rsvd) begin
                    pkt_header_valid_strobe <= 1;
                    status_code <= E_WRONG_RSVD;
                    state <= S_SIGNAL_ERROR;
                end else if (|legacy_sig_tail) begin
                    pkt_header_valid_strobe <= 1;
                    status_code <= E_WRONG_TAIL;
                    state <= S_SIGNAL_ERROR;
                end else if (legacy_rate[3]==0) begin
                    pkt_header_valid_strobe <= 1;
                    status_code <= E_UNSUPPORTED_RATE;
                    state <= S_SIGNAL_ERROR;
                end else begin
                    legacy_sig_stb <= 1;
                    status_code <= E_OK;
                    if (legacy_rate == 4'b1011) begin
                        abs_eq_i <= 0;
                        abs_eq_q <= 0;
                        rot_eq_count <= 0;
                        normal_eq_count <= 0;
                        state <= S_DETECT_HT;
                    end else begin
                        //num_bits_to_decode <= (legacy_len+3)<<4;
                        do_descramble <= 1;
                        pkt_header_valid <= 1;
                        pkt_header_valid_strobe <= 1;
                        pkt_begin <= 1;
                        state <= S_DECODE_DATA;
                    end
                end
            end

            S_SIGNAL_ERROR: begin
                pkt_header_valid_strobe <= 0;
                byte_count <= 0;
                byte_count_total <= 0;
                state <= S_WAIT_POWER_TRIGGER;
            end

            S_DETECT_HT: begin
                legacy_sig_stb <= 0;
                ofdm_reset <= 0;
                
                ofdm_in_stb <= eq_out_stb_delayed;
                // rotate clockwise by 90 degree
                ofdm_in_i <= eq_out_q_delayed;
                ofdm_in_q <= ~eq_out_i_delayed+1;

                if (equalizer_out_strobe) begin
                    abs_eq_i <= eq_out_i[15]? ~eq_out_i+1: eq_out_i;
                    abs_eq_q <= eq_out_q[15]? ~eq_out_q+1: eq_out_q;
                    if (abs_eq_q >= abs_eq_i) begin // Add "=" to prevent state stuck. Push to S_HT_SIGNAL and hope there is error
                        rot_eq_count <= rot_eq_count + 1;
                    end else if (abs_eq_q < abs_eq_i) begin
                        normal_eq_count <= normal_eq_count + 1;
                    end
                end

                if (rot_eq_count >= 4) begin
                    // HT-SIG detected
                    num_bits_to_decode <= 48;
                    do_descramble <= 0;
                    state <= S_HT_SIGNAL;
                end else if (normal_eq_count > 4) begin
                    //num_bits_to_decode <= (legacy_len+3)<<4;
                    do_descramble <= 1;
                    pkt_header_valid <= 1;
                    pkt_header_valid_strobe <= 1;
                    pkt_begin <= 1;
                    state <= S_DECODE_DATA;
                end
            end

            S_HT_SIGNAL: begin
                ofdm_reset <= 0;

                ofdm_in_stb <= eq_out_stb_delayed;
                // rotate clockwise by 90 degree
                ofdm_in_i <= eq_out_q_delayed;
                ofdm_in_q <= ~eq_out_i_delayed+1;

                if (byte_out_strobe) begin
                    if (byte_count < 3) begin
                        ht_sig1 <= {byte_out, ht_sig1[23:8]};
                    end else begin
                        ht_sig2 <= {byte_out, ht_sig2[23:8]};
                    end
                    byte_count <= byte_count + 1;
                    byte_count_total <= byte_count_total + 1;
                end

                if (byte_count == 6) begin
                    byte_count <= 0;
                    `ifdef DEBUG_PRINT
                        $display("[HT SIGNAL] mcs = %07b (%d), ", ht_mcs, ht_mcs,
                            "CBW: %d, ", ht_cbw? 40: 20,
                            "length = %012b (%d), ", ht_len, ht_len,
                            "rsvd = %d, ", ht_rsvd,
                            "aggr = %d, ", ht_aggr,
                            "aggr_last = %d, ", ht_aggr_last,
                            "stbd = %02b, ", ht_stbc,
                            "fec = %d, ", ht_fec_coding,
                            "sgi = %d, ", ht_sgi,
                            "num_ext = %d, ", ht_num_ext,
                            "crc = %08b, ", crc,
                            "tail = %06b", ht_sig_tail);
                    `endif

                    num_bits_to_decode <= (22+(ht_len<<3));
                    pkt_rate <= {1'b1, ht_mcs};
                    pkt_len_rem <= ht_len;
                    pkt_len <= ht_len;
                    pkt_len_total <= ht_len+3+6; //(6 bytes for 3 byte HT-SIG1 and 3 byte HT-SIG2)

                    crc_count <= 0;
                    crc_reset <= 1;
                    crc_in_stb <= 0;
                    ht_sig_crc_ok <= 0;
                    state <= S_CHECK_HT_SIG_CRC;
                end
            end

            S_CHECK_HT_SIG_CRC: begin
                ofdm_reset <= 1;
                crc_reset <= 0;
                crc_count <= crc_count + 1;

                if (crc_count < 24) begin
                    crc_in_stb <= 1;
                    crc_in <= ht_sig1[crc_count];
                end else if (crc_count < 34) begin
                    crc_in_stb <= 1;
                    crc_in <= ht_sig2[crc_count-24];
                end else if (crc_count == 34) begin
                    crc_in_stb <= 0;
                end else if (crc_count == 35) begin
                    ht_sig_stb <= 1;
                    pkt_ht <= 1;
                    if (crc_out ^ crc) begin
                        pkt_header_valid_strobe <= 1;
                        status_code <= E_WRONG_CRC;
                        state <= S_HT_SIG_ERROR;
                    end else begin
                        `ifdef DEBUG_PRINT
                            $display("[HT SIGNAL] CRC OK");
                        `endif
                        ht_sig_crc_ok <= 1;
                        state <= S_CHECK_HT_SIG;
                    end
                end
            end

            S_CHECK_HT_SIG: begin
                ofdm_reset <= 1;
                ht_sig_stb <= 0;
                ht_aggr_last <= 0;

                if (ht_mcs > 7) begin
                    ht_unsupport <= 1;
                    status_code <= E_UNSUPPORTED_MCS;
                    state <= S_HT_SIG_ERROR;
                end else if (ht_cbw) begin
                    ht_unsupport <= 1;
                    status_code <= E_UNSUPPORTED_CBW;
                    state <= S_HT_SIG_ERROR;
                end else if (ht_rsvd == 0) begin
                    ht_unsupport <= 1;
                    status_code <= E_HT_WRONG_RSVD;
                    state <= S_HT_SIG_ERROR;
                end else if (ht_stbc != 0) begin
                    ht_unsupport <= 1;
                    status_code <= E_UNSUPPORTED_STBC;
                    state <= S_HT_SIG_ERROR;
                end else if (ht_fec_coding) begin
                    ht_unsupport <= 1;
                    status_code <= E_UNSUPPORTED_FEC;
                    state <= S_HT_SIG_ERROR;
                // end else if (ht_sgi) begin // seems like it supports ht short_gi, we should proceed
                //     ht_unsupport <= 1;
                //     status_code <= E_UNSUPPORTED_SGI;
                //     state <= S_HT_SIG_ERROR;
                end else if (ht_num_ext != 0) begin
                    ht_unsupport <= 1;
                    status_code <= E_UNSUPPORTED_SPATIAL;
                    state <= S_HT_SIG_ERROR;
                end else if (ht_sig_tail != 0) begin
                    ht_unsupport <= 1;
                    status_code <= E_HT_WRONG_TAIL;
                    state <= S_HT_SIG_ERROR;
                end else begin
                    sync_long_out_count <= 0;
                    // When decoding 80211n packets, a lower i_clock running platform (i.e. zedboard @ 100MHz) will spend more than 4usec to decode an entire OFDM symbol.
                    // This creates misalignment between the control state and the actual decoding process since a feedback mechanism is not applied.
                    // By the time the 1st OFDM DATA symbol is being decoded, the control is in HT-LTS state and the equalizer module mistakenly calculates the channel gain.
                    // A quick fix for this is to bypass the HT-STS symbol to re-establish the alignment. Afterall, HT-STS is not used in this module.
                    if (num_ofdm_symbol == 5) begin
                        state <= S_HT_STS;
                    end else begin
                        ht_next <= 1;
                        state <= S_HT_LTS;
                    end
                end
            end

            S_HT_SIG_ERROR: begin
                ht_unsupport <= 0;
                pkt_header_valid <= 0;
                pkt_header_valid_strobe <= 0;
                byte_count <= 0;
                byte_count_total <= 0;
                ht_sig_stb <= 0;
                state <= S_WAIT_POWER_TRIGGER;
            end

            S_HT_STS: begin
                if (sync_long_out_strobe) begin
                    sync_long_out_count <= sync_long_out_count + 1;
                end
                if (sync_long_out_count == 64) begin
                    sync_long_out_count <= 0;
                    ht_next <= 1;
                    state <= S_HT_LTS;
                end
            end

            S_HT_LTS: begin
                short_gi <= ht_sgi;
                if (sync_long_out_strobe) begin
                    sync_long_out_count <= sync_long_out_count + 1;
                end
                if (sync_long_out_count == 64) begin
                    ht_next <= 0;
                    //num_bits_to_decode <= (ht_len+3)<<4;
                    do_descramble <= 1;
                    ofdm_reset <= 1;
                    if(ht_aggr) begin
                        crc_reset <= 1;
                        crc_count <= 0;
                        state <= S_MPDU_DELIM;
                    end else begin
                        pkt_header_valid <= 1;
                        pkt_header_valid_strobe <= 1;
                        pkt_begin <= 1;
                        pkt_len_rem <= 0;
                        state <= S_DECODE_DATA;
                    end
                end
            end

            S_MPDU_DELIM: begin

                crc_reset <= 0;
                ofdm_reset <= 0;

                ofdm_in_stb <= eq_out_stb_delayed;
                ofdm_in_i <= eq_out_i_delayed;
                ofdm_in_q <= eq_out_q_delayed;

                if(byte_out_strobe) begin

                    if(byte_count == 3) begin

                        byte_count <= 0;
                        byte_count_total <= 3+6;
                        if(crc_out == mpdu_del_crc && byte_out == 8'h4e) begin

                            // Jump over an empty MPDU delimiter
                            if(pkt_len == 0) begin
                                pkt_len_rem <= pkt_len_rem - 4;
                                crc_reset <= 1;
                                crc_count <= 0;
                                state <= S_MPDU_DELIM;

                            // Start actual packet decoding
                            end else begin
                                pkt_header_valid <= 1;
                                pkt_header_valid_strobe <= 1;
                                pkt_len_total <= pkt_len+3+6;
                                pkt_begin <= 1;
                                state <= S_DECODE_DATA;

                                // All MPDUs except last one does include padding
                                if((pkt_len_rem-pkt_len-mpdu_pad) > 4) begin
                                    ht_aggr_last <= 0;
                                    pkt_len_rem <= pkt_len_rem - (4 + pkt_len + mpdu_pad);
                                end else begin
                                    ht_aggr_last <= 1;
                                    pkt_len_rem <= 0;
                                end
                            end

                        // MPDU delimiter is erroneous and remaining packet length is less than 8. Stop searching
                        end else if(|pkt_len_rem[15:3] == 0) begin

                            ht_aggr_last <= 1;
                            fcs_out_strobe <= 1;
                            fcs_ok <= 0;
                            status_code <= E_HT_AMPDU_ERROR;
                            state <= S_DECODE_DONE;

                        // Else, restart searching
                        end else begin
                            pkt_len_rem <= pkt_len_rem - 4;
                            crc_reset <= 1;
                            crc_count <= 0;
                            status_code <= E_HT_AMPDU_WARN;
                            state <= S_MPDU_DELIM;
                        end

                    end else begin
                        byte_count <= byte_count + 1;
                        byte_count_total <= byte_count_total + 1;
                        if(byte_count == 0) begin
                            pkt_len[3:0] <= byte_out[7:4];
                        end else if(byte_count == 1) begin
                            pkt_len[11:4] <= byte_out;
                        end else if(byte_count == 2) begin
                            pkt_len[15:12] <= 0;
                            mpdu_del_crc <= byte_out;
                            if(pkt_len[1:0] == 0)
                                mpdu_pad <= 0;
                            else if(pkt_len[1:0] == 1)
                                mpdu_pad <= 3;
                            else if(pkt_len[1:0] == 2)
                                mpdu_pad <= 2;
                            else
                                mpdu_pad <= 1;
                        end

                        // i_enable CRC calculation on the first two bytes
                        if(crc_count[4] == 0) begin
                            crc_in <= byte_out[crc_count[2:0]];
                            crc_in_stb <= 1;
                            crc_count <= crc_count + 1;
                        end else begin
                            crc_in_stb <= 0;
                        end
                    end

                // i_enable CRC calculation on the first two bytes
                end else if((^byte_count[1:0] == 1) && (|crc_count[2:0] == 1)) begin
                    crc_in <= byte_out[crc_count[2:0]];
                    crc_in_stb <= 1;
                    crc_count <= crc_count + 1;

                end else begin
                    crc_in_stb <= 0;
                end
            end

            S_DECODE_DATA: begin
                pkt_begin <= 0;
                legacy_sig_stb <= 0;

                pkt_header_valid <= 0;
                pkt_header_valid_strobe <= 0;

                ofdm_reset <= 0;

                ofdm_in_stb <= eq_out_stb_delayed;
                ofdm_in_i <= eq_out_i_delayed;
                ofdm_in_q <= eq_out_q_delayed;

                if (byte_out_strobe) begin
                    `ifdef DEBUG_PRINT
                        $display("[BYTE] [%4d / %-4d] %02x", byte_count+1, pkt_len,
                            byte_out);
                    `endif
                    byte_count <= byte_count + 1;
                    byte_count_total <= byte_count_total + 1;
                end

                if (byte_count >= pkt_len) begin
                    fcs_out_strobe <= 1;
                    byte_count <= 0;
                    byte_count_total <= 0;
                    if (pkt_fcs == EXPECTED_FCS) begin
                        fcs_ok <= 1;
                        status_code <= E_OK;
                    end else begin
                        fcs_ok <= 0;
                        status_code <= E_WRONG_FCS;
                    end

                    // restart the decoding process on remaining MPDUs
                    if(|pkt_len_rem[15:2] == 1) begin
                        state <= S_MPDU_PAD;
                    end else begin
                        state <= S_DECODE_DONE;
                    end
                end
            end

            S_MPDU_PAD: begin
                fcs_out_strobe <= 0;
                fcs_ok <= 0;

                ofdm_in_stb <= eq_out_stb_delayed;
                ofdm_in_i <= eq_out_i_delayed;
                ofdm_in_q <= eq_out_q_delayed;

                if (byte_out_strobe)
                    mpdu_pad <= mpdu_pad - 1;

                if (mpdu_pad == 0) begin
                    crc_reset <= 1;
                    crc_count <= 0;
                    state <= S_MPDU_DELIM;
                end
            end

            S_DECODE_DONE: begin
                `ifdef DEBUG_PRINT
                    $display("===== PACKET DECODE DONE =====");
                    if (status_code == E_OK) begin
                        $display("FCS CORRECT");
                    end else begin
                        $display("FCS WRONG");
                    end
                `endif
                ht_aggr_last <= 0;
                fcs_out_strobe <= 0;
                fcs_ok <= 0;
                state <= S_WAIT_POWER_TRIGGER;
            end

            default: begin
                byte_count <= 0;
                byte_count_total <= 0;
                state <= S_WAIT_POWER_TRIGGER;
            end
        endcase
    end
end

endmodule

