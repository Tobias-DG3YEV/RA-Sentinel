// Xianjun jiao. putaoshu@msn.com; xianjun.jiao@imec.be;
`timescale 1 ns / 1 ps

`include "openofdm_rx_pre_def.v"
`include "openofdm_rx_git_rev.v"

`ifdef OPENOFDM_RX_ENABLE_DBG
`define DEBUG_PREFIX (*mark_debug="true",DONT_TOUCH="TRUE"*)
`else
`define DEBUG_PREFIX
`endif

	module openofdm_rx #
	(
		parameter integer IQ_DATA_WIDTH	= 12,
		parameter integer RSSI_HALF_DB_WIDTH = 11,

		parameter integer C_S00_AXI_DATA_WIDTH	= 32,
		parameter integer C_S00_AXI_ADDR_WIDTH	= 7
	)
	(
		// intf to dot11
		//input  wire openofdm_core_rst,
		input  wire signed [(RSSI_HALF_DB_WIDTH-1):0] rssi_half_db,
		input  wire [(2*IQ_DATA_WIDTH-1):0] sample_in,
        input  wire sample_in_strobe,

		output wire demod_is_ongoing, // this needs to be corrected further to indicate actual RF on going regardless the latency
//		output wire pkt_ht,
		output wire short_preamble_detected,
		output wire long_preamble_detected,
		output wire pkt_header_valid,
		output wire pkt_header_valid_strobe,
		output wire ht_unsupport,
		output wire [7:0] pkt_rate,
		output wire [15:0] pkt_len,
		output ht_aggr,
		output ht_aggr_last,
		output wire ht_sgi,
//		output wire [15:0] pkt_len_total, // for interface to byte_to_word.v in rx_intf.v
		output wire byte_out_strobe,
		output wire [7:0] byte_out,
//		output wire [15:0] byte_count_total, // for interface to byte_to_word.v in rx_intf.v
		output wire [15:0] byte_count,
		output wire fcs_out_strobe,
		output wire fcs_ok,
		// for side channel
    output wire [31:0] csi,
    output wire csi_valid,
		output wire signed [31:0] phase_offset_taken,
		output wire [31:0] equalizer,
		output wire equalizer_valid,
		output wire ofdm_symbol_eq_out_pulse,

		// phy len info
		output [14:0] n_ofdm_sym,//max 20166 = (22+65535*8)/26 (max ht len 65535 in sig, min ndbps 26 for mcs0)
		output [9:0]  n_bit_in_last_sym,//max ht ndbps 260 (ht mcs7)
		output        phy_len_valid,

        // reg0~19 for config write; from reg20 for reading status
        input [(C_S00_AXI_DATA_WIDTH-1):0] slv_reg0, 
        input [(C_S00_AXI_DATA_WIDTH-1):0] slv_reg1, // 
        input [(C_S00_AXI_DATA_WIDTH-1):0] slv_reg2, 
        input [(C_S00_AXI_DATA_WIDTH-1):0] slv_reg3, // 
        input [(C_S00_AXI_DATA_WIDTH-1):0] slv_reg4, // 
        input [(C_S00_AXI_DATA_WIDTH-1):0] slv_reg5, //
        input [(C_S00_AXI_DATA_WIDTH-1):0] slv_reg6, //
        input [(C_S00_AXI_DATA_WIDTH-1):0] slv_reg7, //       
        output [(C_S00_AXI_DATA_WIDTH-1):0] slv_reg20, // read openofdm rx core internal state
        output [(C_S00_AXI_DATA_WIDTH-1):0] slv_reg31, 

		// axi lite based register configuration interface
		input  wire s00_axi_aclk,
		input  wire s00_axi_aresetn,
		input  wire [C_S00_AXI_ADDR_WIDTH-1 : 0] s00_axi_awaddr,
		input  wire [2 : 0] s00_axi_awprot,
		input  wire s00_axi_awvalid,
		output wire s00_axi_awready,
		input  wire [C_S00_AXI_DATA_WIDTH-1 : 0] s00_axi_wdata,
		input  wire [(C_S00_AXI_DATA_WIDTH/8)-1 : 0] s00_axi_wstrb,
		input  wire s00_axi_wvalid,
		output wire s00_axi_wready,
		output wire [1 : 0] s00_axi_bresp,
		output wire s00_axi_bvalid,
		input  wire s00_axi_bready,
		input  wire [C_S00_AXI_ADDR_WIDTH-1 : 0] s00_axi_araddr,
		input  wire [2 : 0] s00_axi_arprot,
		input  wire s00_axi_arvalid,
		output wire s00_axi_arready,
		output wire [C_S00_AXI_DATA_WIDTH-1 : 0] s00_axi_rdata,
		output wire [1 : 0] s00_axi_rresp,
		output wire s00_axi_rvalid,
		input  wire s00_axi_rready
	);
`include "common_params.v"
	// reg0~19 for config write; from reg20 for reading status
	/*
	wire [(C_S00_AXI_DATA_WIDTH-1):0] slv_reg0; 
	wire [(C_S00_AXI_DATA_WIDTH-1):0] slv_reg1; // 
	wire [(C_S00_AXI_DATA_WIDTH-1):0] slv_reg2; 
	wire [(C_S00_AXI_DATA_WIDTH-1):0] slv_reg3; // 
	wire [(C_S00_AXI_DATA_WIDTH-1):0] slv_reg4; // 
	wire [(C_S00_AXI_DATA_WIDTH-1):0] slv_reg5; //
	*/ 
	/*
	wire [(C_S00_AXI_DATA_WIDTH-1):0] slv_reg6; // 
	wire [(C_S00_AXI_DATA_WIDTH-1):0] slv_reg7; // 
	wire [(C_S00_AXI_DATA_WIDTH-1):0] slv_reg8; 
	wire [(C_S00_AXI_DATA_WIDTH-1):0] slv_reg9; // 
	wire [(C_S00_AXI_DATA_WIDTH-1):0] slv_reg10; 
	wire [(C_S00_AXI_DATA_WIDTH-1):0] slv_reg11; 
	wire [(C_S00_AXI_DATA_WIDTH-1):0] slv_reg12; 
	wire [(C_S00_AXI_DATA_WIDTH-1):0] slv_reg13; 
	wire [(C_S00_AXI_DATA_WIDTH-1):0] slv_reg14; 
	wire [(C_S00_AXI_DATA_WIDTH-1):0] slv_reg15; 
	wire [(C_S00_AXI_DATA_WIDTH-1):0] slv_reg16; 
	wire [(C_S00_AXI_DATA_WIDTH-1):0] slv_reg17; 
	wire [(C_S00_AXI_DATA_WIDTH-1):0] slv_reg18; 
	wire [(C_S00_AXI_DATA_WIDTH-1):0] slv_reg19; */
	//wire [(C_S00_AXI_DATA_WIDTH-1):0] slv_reg20; // read openofdm rx core internal state
	/*
	wire [(C_S00_AXI_DATA_WIDTH-1):0] slv_reg21; 
	wire [(C_S00_AXI_DATA_WIDTH-1):0] slv_reg22; 
	wire [(C_S00_AXI_DATA_WIDTH-1):0] slv_reg23; 
	wire [(C_S00_AXI_DATA_WIDTH-1):0] slv_reg24; 
	wire [(C_S00_AXI_DATA_WIDTH-1):0] slv_reg25; 
	wire [(C_S00_AXI_DATA_WIDTH-1):0] slv_reg26; 
	wire [(C_S00_AXI_DATA_WIDTH-1):0] slv_reg27; 
	wire [(C_S00_AXI_DATA_WIDTH-1):0] slv_reg28; 
	wire [(C_S00_AXI_DATA_WIDTH-1):0] slv_reg29; 
	wire [(C_S00_AXI_DATA_WIDTH-1):0] slv_reg30; 
*/
  //wire [(C_S00_AXI_DATA_WIDTH-1):0] slv_reg31; 

	`DEBUG_PREFIX wire [(RSSI_HALF_DB_WIDTH-1):0] rx_sensitivity_th;

  `DEBUG_PREFIX wire [4:0] state;

  `DEBUG_PREFIX wire signal_watchdog_enable;
	wire power_trigger;
	wire sig_valid = (pkt_header_valid_strobe&pkt_header_valid);
	wire receiver_rst;

	assign slv_reg31 = `OPENOFDM_RX_GIT_REV;

	assign rx_sensitivity_th = slv_reg2[(RSSI_HALF_DB_WIDTH-1):0];

  assign signal_watchdog_enable = (state <= S_DECODE_SIGNAL);
	signal_watchdog signal_watchdog_inst (
		.clk(s00_axi_aclk),
		.rstn(s00_axi_aresetn),
		// .enable(~demod_is_ongoing),
    .enable(signal_watchdog_enable),

		.i_data(sample_in[31:16]),
		.q_data(sample_in[15:0]),
		.iq_valid(sample_in_strobe),

		.power_trigger(power_trigger|(~slv_reg1[12])),//by default the watchdog will run regardless the power_trigger

		.signal_len(pkt_len),
    .sig_valid(sig_valid),

		.min_signal_len_th(slv_reg4[15:12]),
    .max_signal_len_th(slv_reg4[31:16]),
		.dc_running_sum_th(slv_reg2[23:16]),

    // equalizer monitor: the normalized constellation shoud not be too small (like only has 1 or 2 bits effective)
    .equalizer_monitor_enable((~slv_reg1[16])),
    .small_eq_out_counter_th(slv_reg5[9:4]),
    .state(state),
		.equalizer(equalizer),
		.equalizer_valid(equalizer_valid),

		.receiver_rst(receiver_rst)
	);

	dot11 # ( 
	) dot11_i (
		.clock(s00_axi_aclk),
		.enable( 1 ),
		//.reset ( (~s00_axi_aresetn)|slv_reg0[0]|openofdm_core_rst ),
		.reset ( (~s00_axi_aresetn)|slv_reg0[0]|receiver_rst ),
		.reset_without_watchdog((~s00_axi_aresetn)|slv_reg0[0]),

		.power_thres(rx_sensitivity_th),
		.min_plateau(slv_reg3),
		.threshold_scale(~slv_reg1[8]),

		.rssi_half_db(rssi_half_db),

		.sample_in(sample_in),
		.sample_in_strobe(sample_in_strobe),
		.soft_decoding(slv_reg4[0]),
		.force_ht_smoothing(slv_reg1[0]),
		.disable_all_smoothing(slv_reg1[4]),

		// OUTPUT: bytes and FCS status
		.demod_is_ongoing(demod_is_ongoing),
//		.pkt_begin(),
//		.pkt_ht(),
		.pkt_header_valid(pkt_header_valid),
		.pkt_header_valid_strobe(pkt_header_valid_strobe),
		.ht_unsupport(ht_unsupport),
		.pkt_rate(pkt_rate),
		.pkt_len(pkt_len),
//		.pkt_len_total(pkt_len_total),
		.byte_out_strobe(byte_out_strobe),
		.byte_out(byte_out),
//		.byte_count_total(byte_count_total),
		.byte_count(byte_count),
		.fcs_out_strobe(fcs_out_strobe),
		.fcs_ok(fcs_ok),

		.n_ofdm_sym(n_ofdm_sym),//max 20166 = (22+65535*8)/26 (max ht len 65535 in sig, min ndbps 26 for mcs0)
    	.n_bit_in_last_sym(n_bit_in_last_sym),//max ht ndbps 260 (ht mcs7)
    	.phy_len_valid(phy_len_valid),

		/////////////////////////////////////////////////////////
		// DEBUG PORTS
		/////////////////////////////////////////////////////////
		// decode status
		.state(state),
		.status_code(),
		.state_changed(state_changed),
		.state_history(slv_reg20),
		// power trigger
		.power_trigger(power_trigger),

		// sync short
		.short_preamble_detected(short_preamble_detected),
		.phase_offset(),

		// sync long
		.sync_long_metric(),
		.sync_long_metric_stb(),
		.long_preamble_detected(long_preamble_detected),
		.sync_long_out(),
		.sync_long_out_strobe(),
		.phase_offset_taken(phase_offset_taken),
		.sync_long_state(),
		.fft_win_shift(slv_reg5[3:0]),

		// equalizer
		.equalizer_out(equalizer),
		.equalizer_out_strobe(equalizer_valid),
		.equalizer_state(),
		.ofdm_symbol_eq_out_pulse(ofdm_symbol_eq_out_pulse),

		// legacy signal info
		.legacy_sig_stb(),
		.legacy_rate(),
		.legacy_sig_rsvd(),
		.legacy_len(),
		.legacy_sig_parity(),
		.legacy_sig_parity_ok(),
		.legacy_sig_tail(),

		// ht signal info
		.ht_sig_stb(),
		.ht_mcs(),
		.ht_cbw(),
		.ht_len(),
		.ht_smoothing(),
		.ht_not_sounding(),
		.ht_aggr(ht_aggr),
		.ht_aggr_last(ht_aggr_last),
		.ht_stbc(),
		.ht_fec_coding(),
		.ht_sgi(ht_sgi),
		.ht_num_ext(),
		.ht_sig_crc_ok(),

		// decoding pipeline
		.demod_out(),
		.demod_soft_bits(),
		.demod_soft_bits_pos(),
		.demod_out_strobe(),

		.deinterleave_erase_out(),
		.deinterleave_erase_out_strobe(),

		.conv_decoder_out(),
		.conv_decoder_out_stb(),

		.descramble_out(),
		.descramble_out_strobe(),

		// for side channel
		.csi(csi),
		.csi_valid(csi_valid)
	);
/*
	openofdm_rx_s_axi # ( 
		.C_S_AXI_DATA_WIDTH(C_S00_AXI_DATA_WIDTH),
		.C_S_AXI_ADDR_WIDTH(C_S00_AXI_ADDR_WIDTH)
	) openofdm_rx_s_axi_i (
		.S_AXI_ACLK(s00_axi_aclk),
		.S_AXI_ARESETN(s00_axi_aresetn),
		.S_AXI_AWADDR(s00_axi_awaddr),
		.S_AXI_AWPROT(s00_axi_awprot),
		.S_AXI_AWVALID(s00_axi_awvalid),
		.S_AXI_AWREADY(s00_axi_awready),
		.S_AXI_WDATA(s00_axi_wdata),
		.S_AXI_WSTRB(s00_axi_wstrb),
		.S_AXI_WVALID(s00_axi_wvalid),
		.S_AXI_WREADY(s00_axi_wready),
		.S_AXI_BRESP(s00_axi_bresp),
		.S_AXI_BVALID(s00_axi_bvalid),
		.S_AXI_BREADY(s00_axi_bready),
		.S_AXI_ARADDR(s00_axi_araddr),
		.S_AXI_ARPROT(s00_axi_arprot),
		.S_AXI_ARVALID(s00_axi_arvalid),
		.S_AXI_ARREADY(s00_axi_arready),
		.S_AXI_RDATA(s00_axi_rdata),
		.S_AXI_RRESP(s00_axi_rresp),
		.S_AXI_RVALID(s00_axi_rvalid),
		.S_AXI_RREADY(s00_axi_rready) */
/*
		.SLV_REG0(slv_reg0),
		.SLV_REG1(slv_reg1),
		.SLV_REG2(slv_reg2),
		.SLV_REG3(slv_reg3),
		.SLV_REG4(slv_reg4), 
		.SLV_REG5(slv_reg5), /*,
        .SLV_REG6(slv_reg6),
        .SLV_REG7(slv_reg7),
		.SLV_REG8(slv_reg8),
        .SLV_REG9(slv_reg9),
        .SLV_REG10(slv_reg10),
        .SLV_REG11(slv_reg11),
        .SLV_REG12(slv_reg12),
        .SLV_REG13(slv_reg13),
        .SLV_REG14(slv_reg14),
        .SLV_REG15(slv_reg15),
		.SLV_REG16(slv_reg16),
        .SLV_REG17(slv_reg17),
        .SLV_REG18(slv_reg18),
        .SLV_REG19(slv_reg19),
        .SLV_REG20(slv_reg20),
        .SLV_REG21(slv_reg21),
        .SLV_REG22(slv_reg22),
        .SLV_REG23(slv_reg23),
		.SLV_REG24(slv_reg24),
        .SLV_REG25(slv_reg25),
        .SLV_REG26(slv_reg26),
        .SLV_REG27(slv_reg27),
        .SLV_REG28(slv_reg28),
        .SLV_REG29(slv_reg29),
        .SLV_REG30(slv_reg30),
        .SLV_REG31(slv_reg31) */
	//);
	
	endmodule

