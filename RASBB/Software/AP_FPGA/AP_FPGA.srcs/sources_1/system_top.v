//////////////////////////////////////////////////////////////////////////////////
// 
// Project Name: RA-Sentinel
// 
// Module Name: system_top
//
// Engineer: Tobias Weber
// Target Devices: Artix 7, XC7A100T
// Tool Versions: Vivado 2024.1
// Description:
// 
// Fork of the openofdm project
// https://github.com/jhshi/openofdm
// 
// Dependencies: 
//
// Funded by NGI0 Entrust nlnet foundation
// https://nlnet.nl/project/RA-Sentinel/
// Licence: GNU GENERAL PUBLIC LICENSE
// 
// Revision 1.00 - File Created
// Project: https://github.com/Tobias-DG3YEV/RA-Sentinel
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
    //output wire o_demod_is_ongoing,
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
    output o_demod_is_ongoing,
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
    output reg [7:0]    o_byteOut,
    output reg          o_byteOutStrobe, //pixel clock
    output reg          o_DCMI_hsync,
    output reg          o_DCMI_vsync,
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

`define OUTSTREAM_META_SIZE      256 // the first 256 bytes of our forwarded info frame are metadata (phase misalignement currently)
`define OUTSTREAM_HDR_SIZE       64 // the amount of header data we store and forward in bytes
`define OUTSTREAM_HDR_BITS       6 // range of the HDR info address range. 2^6 = 64
`define OUTSTREAM_META_BITS      8 // range of the meta info address range. 2^8 = 256
`define OUTSTREAM_ADDR_BITS      9 // 2^9 = 256 we can store up to 512 bytes

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

    wire o_demod_is_ongoing;

    /* LVDS ADC signals*/
    (* keep = "true" *) wire    sampleStrobe; /* a frame from the ADC deserializer is ready */

    // internal signals

    wire [4:0] state;
    assign o_state = state[3:0];

    wire signal_watchdog_enable;
    
    wire pkt_header_valid_strobe;
    reg ht_unsupport;
    //wire [7 : 0] pkt_rate;
    wire [15 : 0] pkt_len;
    reg ht_aggr;
    reg ht_aggr_last;
    reg ht_sgi;
    wire [7 : 0] byte_out;
    wire byte_out_strobe;
    wire fcs_ok;
    //reg [31 : 0] csi;
    (* keep = "true" *) wire csi_valid;
    //wire [31 : 0] phase_offset_taken;
    //reg ofdm_symbol_eq_out_pulse;
    //reg [14 : 0] n_ofdm_sym;
    //reg [9 : 0] n_bit_in_last_sym;

    reg [10 : 0] rssi_half_db;
    reg enable;

    /* xpu */    
    wire [(GPIO_STATUS_WIDTH-1):0] gpio_status_delay;
    wire gpio_status_delay_valid;
    wire signed [(IQ_RSSI_HALF_DB_WIDTH-1):0] iq_rssi_half_db;
    wire iq_rssi_half_db_valid;
    //wire rssi_half_db_valid;
  
    //assign o_byteOut = byte_out;
    //assign o_byteOutStrobe = byte_out_strobe;

    assign signal_watchdog_enable = (state <= S_DECODE_SIGNAL);
    wire [31:0] equalizer;
    wire equalizer_valid;

/****************/
/* System Clock */
/****************/
  
wire clk_200M;
wire clk_100M;
wire clk_DCMI;
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
    .o_clk_20M(clk_DCMI),
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

//wire short_preamble_detected;
//wire long_preamble_detected;
wire pkt_header_valid;
wire phy_len_valid;
//wire sig_valid;

assign sig_valid = (pkt_header_valid_strobe & pkt_header_valid);

wire receiver_rst;
wire dot11_reset;
assign dot11_reset = reset_system | receiver_rst;

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
    .i_sysclk(clk_100M),          // System clock
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
    .i_clk(master_clk),
    .i_rstn(~reset_hw),
//    .enable(~o_demod_is_ongoing),
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

(* keep = "true" *) wire [15:0] reg_powerThresh;
(* keep = "true" *) wire [15:0] reg_window_size;
(* keep = "true" *) wire [SPI_REG_REGISTER_WIDTH-1:0] reg_num_sample_to_skip;
(* keep = "true" *) wire [31:0] reg_minPlateau;
wire num_sample_changed;

conf_registers conf_registers_inst (
    .i_clock(master_clk),
    .i_reset(reset_system),
    .i_SPI_addr(regAddr),
    .o_SPIdata(regRdData),
    .i_SPIdata(regWrData),
    .i_SPI_wrStrobe(reg_wrStrobe),
    .o_regPowerThreshold( reg_powerThresh ),
    .o_num_sample_to_skip_stb(num_sample_changed),
    .o_reg_num_sample_to_skip(reg_num_sample_to_skip),
    .o_reg_window_size( reg_window_size ),
    .o_reg_minPlateau(reg_minPlateau)
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

wire [15:0] eq_phase_out;
wire eq_phase_out_stb;
wire fcs_out_strobe;

dot11 dot11_inst (
    .i_clock(master_clk),
    .i_enable(enable),
    .i_reset(dot11_reset),

    // Configuration connection
    .i_num_sample_changed(num_sample_changed),
    .i_reg_power_thres(reg_powerThresh[15:0]),
    .i_reg_num_sample_to_skip(reg_num_sample_to_skip[31:0]),
    .i_reg_window_size(reg_window_size[15:0]),

    //.i_power_thres(11'd0),
    .i_min_plateau(reg_minPlateau),
    .i_threshold_scale(`THRESHOLD_SCALE),

    .i_rssi_half_db(rssi_half_db),
    .i_sample_in(sample_in),
    .i_sample_in_strobe(sampleStrobe),
    .i_soft_decoding(1'b1),
    .i_force_ht_smoothing(1'b0),
    .i_disable_all_smoothing(1'b0),
    .i_fft_win_shift(4'b1),

    .o_demod_is_ongoing(o_demod_is_ongoing),
    .o_short_preamble_detected(o_short_sync),
    .o_pkt_header_valid(pkt_header_valid),
    .o_pkt_header_valid_strobe(pkt_header_valid_strobe),
    .o_pkt_len(pkt_len),
    
    .o_state(state),
	.o_equalizer_out(equalizer),
    .o_equalizer_out_strobe(equalizer_valid),
    
    .o_csi_valid(csi_valid),

    .o_byte_out_strobe(byte_out_strobe),
    .o_byte_out(byte_out),

    .o_eq_phase_out_stb(eq_phase_out_stb),
    .o_eq_phase_out(eq_phase_out),

    .o_fcs_out_strobe(fcs_out_strobe),
    .o_fcs_ok(fcs_ok)
);

/****************************************

    ######    #####   #     #  ###
    #     #  #     #  ##   ##   #
    #     #  #        # # # #   #
    #     #  #        #  #  #   #
    #     #  #        #     #   #
    #     #  #     #  #     #   #
    ######    #####   #     #  ###

*****************************************/

`define DCMI_START_DEBOUNCE     15

reg [`OUTSTREAM_HDR_BITS -1:0] addr_in_hdr; //half the RAM buffer is reserved for header + payload data
reg [`OUTSTREAM_META_BITS-1:0] addr_in_meta;
reg [`OUTSTREAM_HDR_BITS   :0] addr_out_hdr;
reg [`OUTSTREAM_META_BITS  :0] addr_out_meta;
reg ram_in_hdr_stb;
reg ram_in_meta_stb;
wire [7:0] meta_out;
wire [7:0] hdr_out;
reg [31:0] bufferWord; // allow storing up to 32 bit values
reg [2:0] bytesToStore; // 0 to 3 byte offet in the buffer word

// the DCMI frame buffer
ram_2port #(.DWIDTH(8), .AWIDTH(`OUTSTREAM_META_BITS)) output_ram_meta (
    .i_clka(master_clk),
    .i_ena(1),
    .i_wea(ram_in_meta_stb),
    .i_addra(addr_in_meta),
    .i_dia(bufferWord[7:0]),
    .o_doa(),
    //--------------------
    .i_clkb(master_clk),
    .i_enb(1),
    .i_web(0),
    .i_addrb(addr_out_meta),
    .i_dib(32'hFFFF),
    .o_dob(meta_out)
);

ram_2port #(.DWIDTH(8), .AWIDTH(`OUTSTREAM_HDR_BITS)) output_ram_hdr (
    .i_clka(master_clk),
    .i_ena(1),
    .i_wea(ram_in_hdr_stb),
    .i_addra(addr_in_hdr),
    .i_dia(bufferWord[7:0]),
    .o_doa(),
    //--------------------
    .i_clkb(master_clk),
    .i_enb(1),
    .i_web(0),
    .i_addrb(addr_out_hdr[`OUTSTREAM_HDR_BITS-1:0]),
    .i_dib(32'hFFFF),
    .o_dob(hdr_out)
);

// the data INPUT receiver circuit
reg meta_full;
reg hdr_full;

always @(negedge master_clk or posedge dot11_reset) begin
    if(dot11_reset == 1) begin
        addr_in_meta <= 0;
        addr_in_hdr <= 0;
        meta_full <= 0;
        hdr_full <= 0;
        bytesToStore <= 0;
        bufferWord <= 0;
    end
    else begin 
        // payload header data, comes in bytewise
        if(byte_out_strobe == 1 && hdr_full == 0) begin
            bufferWord[7:0] <= byte_out;
            bytesToStore <= 1;
            ram_in_hdr_stb <= 1;
            if(addr_in_hdr == {`OUTSTREAM_HDR_BITS{1'b1}})
              hdr_full <= 1;
        end
        // meta data, comes in word wise
        if(eq_phase_out_stb == 1 && meta_full == 0) begin
            bufferWord[15:0] <= eq_phase_out;
            bytesToStore <= 2;
            ram_in_meta_stb <= 1;
            if(addr_in_meta == {`OUTSTREAM_META_BITS{1'b1}})
              meta_full <= 1;
        end
        else if(bytesToStore > 1) begin
            //ram_in_strobe <= 1;
            bytesToStore <= bytesToStore - 1;
            bufferWord <= { 8'h00, bufferWord[15:8] };
        end

        // check if we are alread in a store phase, and if, disable the write signal
        if(ram_in_hdr_stb == 1) begin
            ram_in_hdr_stb <= 0;
            addr_in_hdr <= addr_in_hdr + 1;
        end
        if(ram_in_meta_stb == 1) begin
            ram_in_meta_stb <= 0;
            addr_in_meta <= addr_in_meta + 1;
        end
    end
end

// the OUTPUT frame generator
reg dcmi_frame; // low means we are idle, high means frame must be streamed out

// frame signal generator
always @(negedge master_clk) begin
    if(reset_system == 1) begin
        dcmi_frame <= 0;
    end
    else begin
        if(fcs_out_strobe == 1 && dcmi_frame == 0) begin //new data and idle?
            dcmi_frame <= 1;
        end

        if(addr_out_hdr == (`OUTSTREAM_HDR_SIZE+1)) begin //reached end of frame buffer?
            dcmi_frame <= 0;
        end
    end
end

// 
always @(posedge clk_DCMI or posedge reset_system) begin
    if(reset_system == 1) begin
        addr_out_meta <= 0;
        addr_out_hdr <= 0;
        o_byteOutStrobe <= 0;
        o_byteOut <= 8'hAA;
        o_DCMI_vsync <= 1; // high inactive
        o_DCMI_hsync <= 1;
    end
    else if(dcmi_frame == 0) begin
        addr_out_meta <= 0;
        addr_out_hdr <= 0;
        //o_byteOutStrobe <= 0;
        o_byteOutStrobe <= ~o_byteOutStrobe; // pixel clock is alway running
    end
    else begin
        o_byteOutStrobe <= ~o_byteOutStrobe; // pixel clock is alway running
        if(dcmi_frame == 1) begin // idle state
            //are we in clock high phase?
            if (o_byteOutStrobe == 0) begin
                // did we reach the end of both parts?
                if(addr_out_meta != (`OUTSTREAM_META_SIZE)) begin
                    o_DCMI_hsync <= 0;
                    o_DCMI_vsync <= 0; // set frame active signal
                    //o_byteOutStrobe <= 1;  // generate pixel clock
                    addr_out_meta <= addr_out_meta + 1;
                    o_byteOut <= meta_out;
                end
                else if(addr_out_hdr != (`OUTSTREAM_HDR_SIZE)) begin
                    //o_byteOutStrobe <= 1;  // generate pixel clock
                    addr_out_hdr <= addr_out_hdr + 1;
                    o_byteOut <= hdr_out;
                end
                else begin
                    addr_out_hdr <= addr_out_hdr + 1;
                    o_DCMI_vsync <= 1; // high inactive
                    o_DCMI_hsync <= 1;
                    o_byteOut <= 0;
                end
            end
        end
    end
    // serialize into bytes
end

always @(posedge reset_system) begin
    rssi_half_db <= 0;
    enable <= 1;
end

endmodule

// ***************************************************************************

