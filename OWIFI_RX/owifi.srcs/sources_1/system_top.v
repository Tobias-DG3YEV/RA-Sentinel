// ***************************************************************************
// Xianjun jiao. putaoshu@msn.com; xianjun.jiao@imec.be;
// based on Analog Devices HDL reference design. openwifi add necessary modules/modifications.
// ***************************************************************************
// Copyright 2014 - 2017 (c) Analog Devices, Inc. All rights reserved.
//
// In this HDL repository, there are many different and unique modules, consisting
// of various HDL (Verilog or VHDL) components. The individual modules are
// developed independently, and may be accompanied by separate and unique license
// terms.
//
// The user should read each of these license terms, and understand the
// freedoms and responsibilities that he or she has by using this source/core.
//
// This core is distributed in the hope that it will be useful, but WITHOUT ANY
// WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
// A PARTICULAR PURPOSE.
//
// Redistribution and use of source or resulting binaries, with or without modification
// of this file, are permitted under one of the following two license terms:
//
//   1. The GNU General Public License version 2 as published by the
//      Free Software Foundation, which can be found in the top level directory
//      of this repository (LICENSE_GPL2), and also online at:
//      <https://www.gnu.org/licenses/old-licenses/gpl-2.0.html>
//
// OR
//
//   2. An ADI specific BSD license, which can be found in the top level directory
//      of this repository (LICENSE_ADIBSD), and also on-line at:
//      https://github.com/analogdevicesinc/hdl/blob/master/LICENSE_ADIBSD
//      This will allow to generate bit files and not release the source code,
//      as long as it attaches to an ADI device.
//
// ***************************************************************************
// ***************************************************************************
`timescale 1ns / 1ps

`include "openwifi/common_defs.v"

module system_top(
    /* Master Clock Input */
    input wire SYS_clk,
    /* HDMI */
    //output wire TMDS_clk_n,
    //output wire TMDS_clk_p,
    //output wire [2:0]TMDS_data_n,
    //output wire [2:0]TMDS_data_p,
    output wire [3:0] o_state,
    output wire demod_is_ongoing,
    output wire sig_valid,
    output wire o_short_sync,

`ifdef USE_PARALLEL_SAMPLES
    input [15:0] i_sample_i,
    input [15:0] i_sample_q,
    input i_sample_in_strobe,
`endif // USE_PARALLEL_SAMPLES

`ifdef SIMULATION
    output wire pkt_header_valid_strobe,
    output wire legacy_sig_stb,
`endif // SIMULATION
    /* ADC LVDS */
    input wire         ADC_idataH_P, /* ADC I (real) serial Data */
    input wire         ADC_idataH_N, /* ADC I (real) serial Data */
    input wire         ADC_idataL_P, /* ADC I (real) serial Data */
    input wire         ADC_idataL_N, /* ADC I (real) serial Data */
    input wire         ADC_qdataH_P, /* ADC I (imag) serial Data */
    input wire         ADC_qdataH_N, /* ADC I (imag) serial Data */
    input wire         ADC_qdataL_P, /* ADC I (imag) serial Data */
    input wire         ADC_qdataL_N, /* ADC I (imag) serial Data */
    input wire         ADC_frame_P, /* ADC frame clock */
    input wire         ADC_frame_N,
    input wire         ADC_bitclk_P, /* ADC bit clock*/
    input wire         ADC_bitclk_N, /* ADC bit clock*/

    // SPI slave port
    input wire          SPI_nss, // slave select, low active
    input wire          SPI_clk, // SPI bit clock
    input wire          SPI_mosi, // master out slave in
    output wire         SPI_miso, // master in slave out
    //output wire dbgClk
    //output wire [11:0]  dbgOutI,
    output wire [7:0]  o_byteOut,
    output wire        o_byteOutStrobe,
    //output wire         dbgFftStrobe,
    //output wire         dbgOutQ0,
    //output wire         dbgOutQ1,
    //output wire         dbgBitClkOut,
    //output wire         dbgDDRI,
    /* keys */
    input wire          Key0, /* Wukong board key 0 - NRESET */
    input wire          Key1  /* Wukong board key 1 */

);

`include "openwifi/common_params.v"

`ifdef BETTER_SENSITIVITY
`define THRESHOLD_SCALE 1
`define MIN_PLATEAU 32'd100 
`else
`define THRESHOLD_SCALE 0
`define MIN_PLATEAU 32'd100
`endif

    parameter ADCBITS = 12;
    parameter REG_SIZE = 32;
    parameter REG_ADDR_SIZE = 8; //register address size in bits
    parameter integer GPIO_STATUS_WIDTH = 8;
    parameter integer DELAY_CTL_WIDTH = 7;
    parameter integer RSSI_HALF_DB_WIDTH = 11;
    parameter integer IQ_RSSI_HALF_DB_WIDTH = 9;
    parameter integer C_S00_AXIS_TDATA_WIDTH	= 64;
    parameter integer IQ_DATA_WIDTH	= ADCBITS;
    parameter integer WIFI_TX_BRAM_DATA_WIDTH = 64;
    parameter integer C_S00_AXI_DATA_WIDTH	= 32;
    parameter integer C_S00_AXI_ADDR_WIDTH	= 8;
    parameter integer TSF_TIMER_WIDTH = 64; // according to 802.11 standard
    parameter integer WIFI_TX_BRAM_ADDR_WIDTH = 10;
        
    wire clk_locked;
    wire reset_hw;
    wire reset_system;
    
    assign reset_hw = ~Key0;
    assign reset_system = reset_hw; // | ~clk_locked;
    
    wire master_clk; // the master process clock, usually 120MHz
    wire sample_clk; // sample clock generated by the ADC usually 20 MHz

    /* LVDS ADC signals*/
    (* keep = "true" *) wire    sampleStrobe; /* a frame from the ADC deserializer is ready */

    // internal signals

    wire [4:0] state;
    assign o_state = state[3:0];

    wire    [31:0]  gp_out_s;
    wire    [31:0]  gp_in_s;
    wire    [63:0]  gpio_i;
    wire    [63:0]  gpio_o;
    wire    [63:0]  gpio_t;
    wire    [7:0]   gpio_status_dummy;

    wire signal_watchdog_enable;
    
    wire pkt_header_valid_strobe;
    reg ht_unsupport;
    wire [7 : 0] pkt_rate;
    wire [15 : 0] pkt_len;
    reg ht_aggr;
    reg ht_aggr_last;
    reg ht_sgi;
    //reg byte_out_strobe;
    wire [7 : 0] byte_out;
    wire byte_out_strobe;
    wire [15 : 0] byte_count;
    reg fcs_out_strobe;
    reg fcs_ok;
    reg [31 : 0] csi;
    reg csi_valid;
    wire [31 : 0] phase_offset_taken;
    //wire [31 : 0] equalizer;
    //wire equalizer_valid;
    reg ofdm_symbol_eq_out_pulse;
    reg [14 : 0] n_ofdm_sym;
    reg [9 : 0] n_bit_in_last_sym;

    reg [10 : 0] rssi_half_db;
    reg enable;

    /* xpu */    
    wire [(GPIO_STATUS_WIDTH-1):0] gpio_status_delay;
    wire gpio_status_delay_valid;
    wire signed [(IQ_RSSI_HALF_DB_WIDTH-1):0] iq_rssi_half_db;
    wire iq_rssi_half_db_valid;
    wire rssi_half_db_valid;
  
    assign o_byteOut = byte_out;
    assign o_byteOutStrobe = byte_out_strobe;

    assign signal_watchdog_enable = (state <= S_DECODE_SIGNAL);
    wire [31:0] equalizer;
    wire equalizer_valid;

/****************/
/* System Clock */
/****************/
  
wire clk_200M;
wire clk_100M;
//wire clk_120M;
//wire clk_50M;
(* keep = "true" *) wire    testClk_300M;
  
clk_system clk_system_inst (
    //.i_clk_50M(SYS_clk),
    .i_clk_60M(sample_clk),
    .o_clk_100M(clk_100M),
    //.o_clk_120M(clk_120M),
    .o_clk_200M(clk_200M),
    .o_clk_300M(testClk_300M),
    //.o_clk_50M(clk_50M),
    .reset(reset_hw),
    .locked(clk_locked)
);

assign master_clk = clk_100M;

/*
wire s00_axi_aclk;

clk_wiz_0 clk_wiz_0_inst (
    .clk_in1(clk_50M),
    .clk_out1(s00_axi_aclk),
    .reset(reset_hw)
);
*/


/*****************************************
    #        #     #  ######    #####
    #        #     #  #     #  #     #
    #        #     #  #     #  #
    #        #     #  #     #   #####
    #         #   #   #     #        #
    #          # #    #     #  #     #
    #######     #     ######    #####
******************************************/

wire [ADCBITS-1:0] adc_i;
wire [ADCBITS-1:0] adc_q;


`ifdef USE_PARALLEL_SAMPLES

`else // !USE_PARALLEL_SAMPLES

lvds_rx #(
      ADCBITS
) lvds_irx0 (
  .i_lvds_dclk_P(ADC_bitclk_P), // 120/60 MHz
  .i_lvds_dclk_N(ADC_bitclk_N), // 120/60 MHz
  .i_lvds_fclk_P(ADC_frame_P), // 40/20 MHz
  .i_lvds_fclk_N(ADC_frame_N), // 40/20 MHz
  .i_lvds_dr0_P(ADC_qdataL_P),  // data lane 0 real part, lower bits
  .i_lvds_dr0_N(ADC_qdataL_N),  // data lane 0 real part, lower bits
  .i_lvds_di0_P(ADC_idataL_P),  // data lane 0 imaginary part, higher 6 bits
  .i_lvds_di0_N(ADC_idataL_N),  // data lane 0 imaginary part, higher 6 bits
  .i_lvds_dr1_P(ADC_qdataH_P),  // data lane 1 real part, lower 6 bits
  .i_lvds_dr1_N(ADC_qdataH_N),  // data lane 1 real part, lower 6 bits
  .i_lvds_di1_P(ADC_idataH_P),  // data lane 1 imaginary part, higher 6 bits
  .i_lvds_di1_N(ADC_idataH_N),  // data lane 1 imaginary part, higher 6 bits
  .i_masterClk(master_clk),
  .i_delayClk(clk_200M),
  .o_dataOut_I(adc_i),
  .o_dataOut_R(adc_q),
  .o_lvds_dclk(sample_clk),
  .o_lvds_fclk(),
  .o_parFrameRdy(),
  .o_sampleStrobe(sampleStrobe),
  .i_rst(reset_hw)
);

`endif // USE_PARALLEL_SAMPLES

wire [31:0] statusReg;
reg  [31:0] packetReg;
wire [31:0] phaseReg;
wire [31:0] byteCountReg;
wire [31:0] rssiReg;
wire [31:0] versionReg;

//wire demod_is_ongoing; externalized
wire short_preamble_detected;
wire long_preamble_detected;
wire pkt_header_valid;
wire phy_len_valid;

assign sig_valid = (pkt_header_valid_strobe & pkt_header_valid);

wire receiver_rst;
wire[31:0] sample_in;

//`ifdef SIMULATION
`ifdef USE_PARALLEL_SAMPLES
    assign sample_in = { i_sample_i, i_sample_q };
    assign sampleStrobe = i_sample_in_strobe;
`else
    //wire i_sample_in_strobe; // data valid on falling edge
    //assign i_sample_in_strobe = ~sampleStrobe;
    assign sample_in = { {4{adc_i[ADCBITS-1]}}, adc_i,  {4{adc_q[ADCBITS-1]}}, adc_q };
`endif // USE_LVDS_SIMULATION

assign statusReg[0] = demod_is_ongoing;
assign statusReg[1] = short_preamble_detected;
assign statusReg[2] = long_preamble_detected;
assign statusReg[3] = pkt_header_valid;
assign statusReg[4] = phy_len_valid;
assign rssiReg      = { 21'd0, rssi_half_db };
assign byteCountReg = { 16'h0000, byte_count };

//assign packetReg = { byte_count, 8'b00000000, byte_out };
assign phaseReg = phase_offset_taken;
assign versionReg[31:0] = 32'd1;

/****************************

     #####   ######   ###
    #     #  #     #   #
    #        #     #   #
     #####   ######    #
          #  #         #
    #     #  #         #
     #####   #        ###

*****************************/

wire reg_wrStrobe;
wire [SPI_REG_REGISTER_WIDTH-1:0] regAddr;
wire [SPI_REG_REGISTER_WIDTH-1:0] regWrData;
wire [SPI_REG_REGISTER_WIDTH-1:0] regRdData;

SPI_Peripheral  #(
    .ADDR_WIDTH(SPI_REG_ADDRESS_WIDTH)
) spip_inst (
    .i_sysclk(SPI_clk),          // System clock
    .i_reset(reset_hw),    // Active low reset
    .i_sclk(SPI_clk),         // SPI clock
    .i_copi(SPI_mosi),        // Master out slave in
    .o_cipo(SPI_miso),        // Master in slave out
    .i_ncs(SPI_nss),           // Slave select (active low)
    .o_dataRdy(reg_wrStrobe), // register write strobe
    .o_addr(regAddr),     // Adress of the Register to be written
    .o_regData(regWrData),  // Data written to  a register
    .i_regData(regRdData) 
);

/************************************************************************

#     #     #     #######   #####   #     #  ######   #######   #####
#  #  #    # #       #     #     #  #     #  #     #  #     #  #     #
#  #  #   #   #      #     #        #     #  #     #  #     #  #
#  #  #  #     #     #     #        #######  #     #  #     #  #  ####
#  #  #  #######     #     #        #     #  #     #  #     #  #     #
#  #  #  #     #     #     #     #  #     #  #     #  #     #  #     #
 ## ##   #     #     #      #####   #     #  ######   #######   #####

*************************************************************************/

signal_watchdog signal_watchdog_inst (
    .i_clk(clk_100M),
    .i_rstn(~reset_hw),
//    .enable(~demod_is_ongoing),
    .i_enable(signal_watchdog_enable),
    
    .i_data(sample_in[31:16]),
    .q_data(sample_in[15:0]),
    .i_iq_valid(sampleStrobe),

    .i_signal_len(pkt_len),
    .i_sig_valid(sig_valid),
    
    .i_power_trigger(1'b1),

    // // configuration for disabling
//    .min_signal_len_th(0),
//    .max_signal_len_th(16'hFFFF),
//    .dc_running_sum_th(65),
    
    // // configuration for normal
    .i_min_signal_len_th(14),
    .i_max_signal_len_th(1700),
    .i_dc_running_sum_th(64),
    
    // equalizer monitor: the normalized constellation shoud not be too small (like only has 1 or 2 bits effective)
    .i_equalizer_monitor_enable(1),
    .i_small_eq_out_counter_th(8),
    .i_state(state),
	.i_equalizer(equalizer),
	.i_equalizer_valid(equalizer_valid),
		
    .o_receiver_rst(receiver_rst)
);

/***********************************************************************

    ######   #######   #####   ###   #####   #######  #######  ######
    #     #  #        #     #   #   #     #     #     #        #     #
    #     #  #        #         #   #           #     #        #     #
    ######   #####    #  ####   #    #####      #     #####    ######
    #   #    #        #     #   #         #     #     #        #   #
    #    #   #        #     #   #   #     #     #     #        #    #
    #     #  #######   #####   ###   #####      #     #######  #     #

***********************************************************************/

wire [SPI_REG_REGISTER_WIDTH-1:0] reg_powerThresh;
wire [SPI_REG_REGISTER_WIDTH-1:0] reg_window_size;
wire [SPI_REG_REGISTER_WIDTH-1:0] reg_num_sample_to_skip;
wire num_sample_changed;

conf_registers conf_registers_inst (
    .i_clock(clk_100M),
    .i_reset(reset_system),
    .i_SPI_addr(regAddr),
    .o_SPIdata(regWrData),
    .i_SPIdata(regRdData),
    .o_regPowerThreshold(reg_powerThresh),
    .o_num_sample_to_skip_stb(num_sample_changed),
    .o_reg_num_sample_to_skip(reg_num_sample_to_skip),
    .o_reg_window_size(reg_window_size)
);

/****************************************

######   #######  #######    #      #
#     #  #     #     #      ##     ##
#     #  #     #     #     # #    # #
#     #  #     #     #       #      #
#     #  #     #     #       #      #
#     #  #     #     #       #      #
######   #######     #     #####  #####

*****************************************/

dot11 dot11_inst (
    .i_clock(clk_100M),
    .i_enable(enable),
    .i_reset(reset_system | receiver_rst),

    // Configuration connection
    .i_num_sample_changed(num_sample_changed),
    .i_reg_power_thres(reg_powerThresh[15:0]),
    .i_reg_num_sample_to_skip(reg_num_sample_to_skip[31:0]),
    .i_reg_window_size(reg_window_size[15:0]),

    .i_power_thres(11'd0),
    .i_min_plateau(`MIN_PLATEAU),
    .i_threshold_scale(`THRESHOLD_SCALE),

    .i_rssi_half_db(rssi_half_db),
    .i_sample_in(sample_in),
    .i_sample_in_strobe(sampleStrobe),
    .i_soft_decoding(1'b1),
    .i_force_ht_smoothing(1'b0),
    .i_disable_all_smoothing(1'b0),
    .i_fft_win_shift(4'b1),

    .demod_is_ongoing(demod_is_ongoing),
    .short_preamble_detected(o_short_sync),
    .pkt_header_valid(pkt_header_valid),
    .pkt_header_valid_strobe(pkt_header_valid_strobe),
    .pkt_len(pkt_len),
    
    .state(state),
	.equalizer_out(equalizer),
    .equalizer_out_strobe(equalizer_valid),

    .byte_out_strobe(byte_out_strobe),
    .byte_out(byte_out)
);


    always @(posedge reset_system) begin
        rssi_half_db <= 0;
        enable <= 1;
    end

endmodule

// ***************************************************************************

