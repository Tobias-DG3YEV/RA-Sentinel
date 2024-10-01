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

`timescale 1ns/100ps

module top(
    /* Master Clock Input */
    input wire SYS_clk,
    /* HDMI */
    output wire TMDS_clk_n,
    output wire TMDS_clk_p,
    output wire [2:0]TMDS_data_n,
    output wire [2:0]TMDS_data_p,
    /* ADC LVDS */
    //input wire         ADC_idataH_P, /* ADC I serial Data */
    //input wire         ADC_idataH_N, /* ADC I serial Data */
    input wire         ADC_idataL_P, /* ADC I serial Data */
    input wire         ADC_idataL_N, /* ADC I serial Data */
    //input wire         ADC_qdataH_P, /* ADC I serial Data */
    //input wire         ADC_qdataH_N, /* ADC I serial Data */
    input wire         ADC_qdataL_P, /* ADC I serial Data */
    input wire         ADC_qdataL_N, /* ADC I serial Data */
    input wire         ADC_frame_P, /* ADC frame clock */
    input wire         ADC_frame_N,
    input wire         ADC_bitclk_P, /* ADC bit clock*/
    input wire         ADC_bitclk_N, /* ADC bit clock*/
    //output wire dbgClk
    output wire [11:0]  dbgOutI,
    output wire [11:0]  dbgOutQ,
    output wire         dbgFrameRdy,
    output wire         dbgFftStrobe,
    output wire         dbgOutQ0,
    output wire         dbgOutQ1,
    output wire         dbgBitClkOut,
    output wire         dbgDDRI,
    /* keys */
    input wire          Key0, /* Wukong board key 0 - NRESET */
    input wire          Key1  /* Wukong board key 1 */

);

    parameter ADCBITS = 12;
    parameter I_DELAY = 0;
    parameter Q_DELAY = 0;
    parameter BITCLK_DELAY = 0;
    parameter FS_DELAY = 0; /* Frame Sync delay */
    
    wire global_rst;
    assign global_rst = ~Key0;
    
    /* LVDS ADC signals*/
    (* keep = "true" *) wire    [ADCBITS-1:0] adc_ipar; /* ADC I paralell data */
    (* keep = "true" *) wire    [ADCBITS-1:0] adc_qpar; /* ADC Q paralell data */
    wire        lvds_bitClk; /* 120MHz */
    wire        lvds_frameClk; /* 20MHz buffered */
    wire        lvds_iDDR_L; /* serial line */
    wire        lvds_qDDR_L; /* serial line */
    (* keep = "true" *) wire adc_frameStrobe; /* a frame from the ADC deserializer is ready */
    (* keep = "true" *) wire testClk_480M;
    (* keep = "true" *) wire testClk_240M;

    // internal signals

    wire    [31:0]  gp_out_s;
    wire    [31:0]  gp_in_s;
    wire    [63:0]  gpio_i;
    wire    [63:0]  gpio_o;
    wire    [63:0]  gpio_t;
    wire    [7:0]   gpio_status_dummy;

    // internal regs
    
    reg [10 : 0] rssi_half_db;
    reg [31 : 0] sample_in;
    reg sample_in_strobe;
    wire demod_is_ongoing;
    wire short_preamble_detected;
    wire long_preamble_detected;
    reg pkt_header_valid;
    reg pkt_header_valid_strobe;
    reg ht_unsupport;
    reg [7 : 0] pkt_rate;
    reg [15 : 0] pkt_len;
    reg ht_aggr;
    reg ht_aggr_last;
    reg ht_sgi;
    reg byte_out_strobe;
    reg [7 : 0] byte_out;
    reg [15 : 0] byte_count;
    reg fcs_out_strobe;
    reg fcs_ok;
    reg [31 : 0] csi;
    reg csi_valid;
    reg [31 : 0] phase_offset_taken;
    reg [31 : 0] equalizer;
    reg equalizer_valid;
    reg ofdm_symbol_eq_out_pulse;
    reg [14 : 0] n_ofdm_sym;
    reg [9 : 0] n_bit_in_last_sym;
    reg phy_len_valid;

  // assignments

lvds_rx #(
      12
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
  .i_rst(global_rst),
  .i_delayClk(clk_195M),
  .o_dataOut_I(adc_ipar),
  .o_dataOut_R(adc_qpar),
  .o_lvds_dclk(lvds_dclk),
  .o_lvds_fclk(lvds_fclk)
);

openofdm_rx #(
  .IQ_DATA_WIDTH(16),
  .RSSI_HALF_DB_WIDTH(11),
  .C_S00_AXI_DATA_WIDTH(32),
  .C_S00_AXI_ADDR_WIDTH(7)
) ofdmrx_inst (
  .rssi_half_db(rssi_half_db),
  .sample_in(sample_in),
  .sample_in_strobe(sample_in_strobe),
  .demod_is_ongoing(demod_is_ongoing),
  .short_preamble_detected(short_preamble_detected),
  .long_preamble_detected(long_preamble_detected),
  .pkt_header_valid(pkt_header_valid),
  .pkt_header_valid_strobe(pkt_header_valid_strobe),
  .ht_unsupport(ht_unsupport),
  .pkt_rate(pkt_rate),
  .pkt_len(pkt_len),
  .ht_aggr(ht_aggr),
  .ht_aggr_last(ht_aggr_last),
  .ht_sgi(ht_sgi),
  .byte_out_strobe(byte_out_strobe),
  .byte_out(byte_out),
  .byte_count(byte_count),
  .fcs_out_strobe(fcs_out_strobe),
  .fcs_ok(fcs_ok),
  .csi(csi),
  .csi_valid(csi_valid),
  .phase_offset_taken(phase_offset_taken)
//  .equalizer(equalizer),
//  .equalizer_valid(equalizer_valid),
//  .ofdm_symbol_eq_out_pulse(ofdm_symbol_eq_out_pulse),
//  .n_ofdm_sym(n_ofdm_sym),
//  .n_bit_in_last_sym(n_bit_in_last_sym),
//  .phy_len_valid(phy_len_valid)
/*  .s00_axi_aclk(s00_axi_aclk),
  .s00_axi_aresetn(s00_axi_aresetn),
  .s00_axi_awaddr(s00_axi_awaddr),
  .s00_axi_awprot(s00_axi_awprot),
  .s00_axi_awvalid(s00_axi_awvalid),
  .s00_axi_awready(s00_axi_awready),
  .s00_axi_wdata(s00_axi_wdata),
  .s00_axi_wstrb(s00_axi_wstrb),
  .s00_axi_wvalid(s00_axi_wvalid),
  .s00_axi_wready(s00_axi_wready),
  .s00_axi_bresp(s00_axi_bresp),
  .s00_axi_bvalid(s00_axi_bvalid),
  .s00_axi_bready(s00_axi_bready),
  .s00_axi_araddr(s00_axi_araddr),
  .s00_axi_arprot(s00_axi_arprot),
  .s00_axi_arvalid(s00_axi_arvalid),
  .s00_axi_arready(s00_axi_arready),
  .s00_axi_rdata(s00_axi_rdata),
  .s00_axi_rresp(s00_axi_rresp),
  .s00_axi_rvalid(s00_axi_rvalid),
  .s00_axi_rready(s00_axi_rready)
*/
);

endmodule

// ***************************************************************************
// ***************************************************************************
