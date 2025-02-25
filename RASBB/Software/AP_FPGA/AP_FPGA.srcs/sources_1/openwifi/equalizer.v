//////////////////////////////////////////////////////////////////////////////////
// 
// Project Name: RA-Sentinel
// 
// Module Name: equalizer
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

`include "common_defs.v"

module equalizer
(
    input i_clock,
    input i_enable,
    input i_reset,

    input [31:0] i_sample_in,
    input i_sample_in_strobe,
    input i_ht_next,
    input i_pkt_ht,
    input i_ht_smoothing,
    input i_disable_all_smoothing,

    output [31:0] o_phase_in_i,
    output [31:0] o_phase_in_q,
    output reg o_phase_in_stb,
    input [15:0] i_phase_out,
    input i_phase_out_stb,

    output [`ROTATE_LUT_LEN_SHIFT-1:0] o_rot_addr,
    input [31:0] i_rot_data,

    output reg [31:0] o_sample_out,
    output reg o_sample_out_strobe,
    
    output reg [3:0] o_state,

    // for side channel
    output [31:0] o_csi,
    output o_csi_valid
);

// mask[0] is DC, mask[1:26] -> 1,..., 26
// mask[38:63] -> -26,..., -1
localparam SUBCARRIER_MASK =
    64'b1111111111111111111111111100000000000111111111111111111111111110;

localparam HT_SUBCARRIER_MASK =
    64'b1111111111111111111111111111000000011111111111111111111111111110;

// -7, -21, 21, 7
localparam PILOT_MASK =
    64'b0000001000000000000010000000000000000000001000000000000010000000;

localparam DATA_SUBCARRIER_MASK =
    SUBCARRIER_MASK ^ PILOT_MASK;

localparam HT_DATA_SUBCARRIER_MASK = 
    HT_SUBCARRIER_MASK ^ PILOT_MASK;

// -1,..,-26, 26,..,1
localparam LTS_REF =
    64'b0000101001100000010100110000000000000000010101100111110101001100;

localparam HT_LTS_REF =
    64'b0000101001100000010100110000000000011000010101100111110101001100;

localparam POLARITY = 
    127'b1111111000111011000101001011111010101000010110111100111001010110011000001101101011101000110010001000000100100110100111101110000;

// 21, 7, -7, -21
localparam HT_POLARITY = 4'b1000;

localparam IN_BUF_LEN_SHIFT = 6;

localparam S_FIRST_LTS = 0;
localparam S_SECOND_LTS = 1;
localparam S_SMOOTH_CH_DC = 2;
localparam S_SMOOTH_CH_LTS = 3;
localparam S_GET_POLARITY = 4;
localparam S_CPE_ESTIMATE = 5;
localparam S_PILOT_PE_CORRECTION = 6; 
localparam S_LVPE_ESTIMATE = 7;
localparam S_ALL_SC_PE_CORRECTION = 8;
localparam S_HT_LTS = 9;

reg enable_delay;
wire reset_internal = (i_enable==0 && enable_delay==1);//i_reset internal after the module is disabled in case the disable lock the o_state/stb to a non-end o_state.

reg ht;
reg [5:0] num_data_carrier;
reg [7:0] num_ofdm_sym;

// bit masks
reg [63:0] lts_ref;
reg [63:0] ht_lts_ref;
reg [63:0] subcarrier_mask;
reg [63:0] data_subcarrier_mask;
reg [63:0] pilot_mask;
reg [5:0] pilot_loc[3:0];
reg signed [5:0] pilot_idx[3:0];
localparam pilot_loc1 = 7;
localparam pilot_loc2 = 21;
localparam pilot_loc3 = 43; 
localparam pilot_loc4 = 57; 
localparam signed pilot_idx1 = 8; 
localparam signed pilot_idx2 = 22; 
localparam signed pilot_idx3 = -20;
localparam signed pilot_idx4 = -6; 
initial begin 
    pilot_loc[0] = pilot_loc1;
    pilot_idx[0] = pilot_idx1;
    pilot_loc[1] = pilot_loc2;
    pilot_idx[1] = pilot_idx2;
    pilot_loc[2] = pilot_loc3;
    pilot_idx[2] = pilot_idx3;
    pilot_loc[3] = pilot_loc4;
    pilot_idx[3] = pilot_idx4;
end

reg [126:0] polarity;
reg [3:0] ht_polarity;
reg [3:0] current_polarity;
reg [3:0] pilot_count1, pilot_count2, pilot_count3;

reg signed [15:0] input_i;
reg signed [15:0] input_q;

reg current_sign;

wire signed [15:0] new_lts_i;
wire signed [15:0] new_lts_q;
wire new_lts_stb;

reg calc_mean_strobe;

reg [5:0] lts_waddr;
reg [6:0] lts_raddr; // one bit wider to detect overflow
reg [15:0] lts_i_in;
reg [15:0] lts_q_in;
reg lts_in_stb;
wire signed [15:0] lts_i_out;
wire signed [15:0] lts_q_out;
wire signed [15:0] lts_q_out_neg = ~lts_q_out + 1;

reg [5:0] in_waddr;
reg [6:0] in_raddr;
wire [15:0] buf_i_out;
wire [15:0] buf_q_out;

reg pilot_in_stb;
wire signed [31:0] pilot_i;
wire signed [31:0] pilot_q;
reg signed [31:0] pilot_i_reg, pilot_q_reg;
reg signed [15:0] pilot_iq_phase[0:3];

reg signed [31:0] pilot_sum_i;
reg signed [31:0] pilot_sum_q;

assign o_phase_in_i = pilot_i_reg;
assign o_phase_in_q = pilot_q_reg;

//reg signed [15:0] pilot_phase_err;
reg signed [16:0] pilot_phase_err; // 15 --> 16 = 15 + 1, extended from cpe
reg signed [15:0] cpe; // common phase error due to RFO
//reg signed [15:0] Sxy;
reg signed [23:0] Sxy; // 15-->23. to avoid overflow: pilot_phase_err 16 + 5 + 2. 5 for 21* (rounding to 32); 2 for 4 pilots
localparam Sx2 = 980;

// linear varying phase error (LVPE) parameters
reg signed [7:0] sym_idx, sym_idx2; 
reg lvpe_in_stb;
wire lvpe_out_stb;
wire signed [31:0] lvpe_dividend, lvpe, peg_sym_scale;
wire signed [23:0] lvpe_divisor;
assign lvpe_dividend = (sym_idx <= 33 ? sym_idx*Sxy : (sym_idx-64)*Sxy);
assign lvpe_divisor = Sx2;
reg signed [31:0] prev_peg, prev_peg_reg, peg_pilot_scale; 
assign peg_sym_scale = (sym_idx2 <= 33 ? sym_idx2*prev_peg : (sym_idx2-64)*prev_peg);

//reg signed [15:0] phase_err;
reg signed  [17:0] phase_err; // 15-->16: phase_err <= cpe + lvpe[17:0]; 16 + 1 = 17 for sym_phase
//wire signed [15:0] sym_phase;
wire signed [17:0] sym_phase;// phase_err 16 + 1
assign sym_phase = (phase_err > 1608) ? (phase_err - 3217) : ((phase_err < -1608) ? (phase_err + 3217) : phase_err);//only taking [15:0] to rotate could have overflow!

reg rot_in_stb;
wire signed [15:0] rot_i;
wire signed [15:0] rot_q;

wire [31:0] mag_sq;
wire [31:0] prod_i;
wire [31:0] prod_q;
wire [31:0] prod_i_scaled = prod_i<<(`CONS_SCALE_SHIFT+1);
wire [31:0] prod_q_scaled = prod_q<<(`CONS_SCALE_SHIFT+1); // +1 to fix the bug threshold for demodulate.v
//wire prod_stb;

reg signed [15:0] lts_reg1_i, lts_reg2_i, lts_reg3_i, lts_reg4_i, lts_reg5_i;
reg signed [15:0] lts_reg1_q, lts_reg2_q, lts_reg3_q, lts_reg4_q, lts_reg5_q;
wire signed [18:0] lts_sum_1_3_i = lts_reg1_i + lts_reg2_i + lts_reg3_i;
wire signed [18:0] lts_sum_1_3_q = lts_reg1_q + lts_reg2_q + lts_reg3_q;
wire signed [18:0] lts_sum_1_4_i = lts_reg1_i + lts_reg2_i + lts_reg3_i + lts_reg4_i;
wire signed [18:0] lts_sum_1_4_q = lts_reg1_q + lts_reg2_q + lts_reg3_q + lts_reg4_q;
wire signed [18:0] lts_sum_1_5_i = lts_reg1_i + lts_reg2_i + lts_reg3_i + lts_reg4_i + lts_reg5_i;
wire signed [18:0] lts_sum_1_5_q = lts_reg1_q + lts_reg2_q + lts_reg3_q + lts_reg4_q + lts_reg5_q;
wire signed [18:0] lts_sum_2_5_i =              lts_reg2_i + lts_reg3_i + lts_reg4_i + lts_reg5_i;
wire signed [18:0] lts_sum_2_5_q =              lts_reg2_q + lts_reg3_q + lts_reg4_q + lts_reg5_q;
wire signed [18:0] lts_sum_3_5_i =                           lts_reg3_i + lts_reg4_i + lts_reg5_i;
wire signed [18:0] lts_sum_3_5_q =                           lts_reg3_q + lts_reg4_q + lts_reg5_q;
wire signed [18:0] lts_sum_wo3_i = lts_reg1_i + lts_reg2_i              + lts_reg4_i + lts_reg5_i;
wire signed [18:0] lts_sum_wo3_q = lts_reg1_q + lts_reg2_q              + lts_reg4_q + lts_reg5_q;
reg signed [18:0] lts_sum_i;
reg signed [18:0] lts_sum_q;

reg [2:0] lts_mv_avg_len;
reg lts_div_in_stb;

reg prod_in_strobe;
wire prod_out_strobe;

wire [31:0] dividend_i = (o_state == S_SMOOTH_CH_DC || o_state == S_SMOOTH_CH_LTS) ? (lts_sum_i[18] == 0 ? {13'h0,lts_sum_i} : {13'h1FFF,lts_sum_i}) : (o_state == S_ALL_SC_PE_CORRECTION ? prod_i_scaled : 0);
wire [31:0] dividend_q = (o_state == S_SMOOTH_CH_DC || o_state == S_SMOOTH_CH_LTS) ? (lts_sum_q[18] == 0 ? {13'h0,lts_sum_q} : {13'h1FFF,lts_sum_q}) : (o_state == S_ALL_SC_PE_CORRECTION ? prod_q_scaled : 0);
wire [23:0] divisor_i = (o_state == S_SMOOTH_CH_DC || o_state == S_SMOOTH_CH_LTS) ? {21'b0,lts_mv_avg_len} : (o_state == S_ALL_SC_PE_CORRECTION ? mag_sq[23:0] : 1);
wire [23:0] divisor_q = (o_state == S_SMOOTH_CH_DC || o_state == S_SMOOTH_CH_LTS) ? {21'b0,lts_mv_avg_len} : (o_state == S_ALL_SC_PE_CORRECTION ? mag_sq[23:0] : 1);
wire div_in_stb = (o_state == S_SMOOTH_CH_DC || o_state == S_SMOOTH_CH_LTS) ? lts_div_in_stb : (o_state == S_ALL_SC_PE_CORRECTION ? prod_out_strobe : 0);

reg [15:0] num_output;
wire [31:0] quotient_i;
wire [31:0] quotient_q;
wire [31:0] norm_i = quotient_i;
wire [31:0] norm_q = quotient_q;
wire [31:0] lts_div_i = quotient_i;
wire [31:0] lts_div_q = quotient_q;

wire div_out_stb;
wire norm_out_stb = div_out_stb;
wire lts_div_out_stb = div_out_stb;

// for side channel
reg sample_in_strobe_dly;
assign o_csi = {lts_i_out, lts_q_out};
assign o_csi_valid = ( (num_ofdm_sym == 1 || (i_pkt_ht == 1 && num_ofdm_sym == 5)) && o_state == S_CPE_ESTIMATE && sample_in_strobe_dly == 1 && i_enable && (~i_reset) );

always @(posedge i_clock) begin
    if (i_reset) begin
        enable_delay <= 0;
    end else begin
        enable_delay <= i_enable;
    end
end

ram_2port #(.DWIDTH(32), .AWIDTH(6)) lts_inst (
    .i_clka(i_clock),
    .i_ena(1),
    .i_wea(lts_in_stb),
    .i_addra(lts_waddr),
    .i_dia({lts_i_in, lts_q_in}),
    .o_doa(),
    .i_clkb(i_clock),
    .i_enb(1),
    .i_web(1'b0),
    .i_addrb(lts_raddr[5:0]),
    .i_dib(32'hFFFF),
    .o_dob({lts_i_out, lts_q_out})
);

calc_mean lts_i_inst (
    .i_clock(i_clock),
    .i_enable(i_enable),
    .i_reset(i_reset|reset_internal),
    
    .i_a(lts_i_out),
    .i_b(input_i),
    .i_sign(current_sign),
    .i_input_strobe(calc_mean_strobe),

    .o_c(new_lts_i),
    .o_output_strobe(new_lts_stb)
);

calc_mean lts_q_inst (
    .i_clock(i_clock),
    .i_enable(i_enable),
    .i_reset(i_reset|reset_internal),
    
    .i_a(lts_q_out),
    .i_b(input_q),
    .i_sign(current_sign),
    .i_input_strobe(calc_mean_strobe),

    .o_c(new_lts_q),
    .o_output_strobe()
);

ram_2port  #(.DWIDTH(32), .AWIDTH(6)) in_buf_inst (
    .i_clka(i_clock),
    .i_ena(1),
    .i_wea(i_sample_in_strobe),
    .i_addra(in_waddr),
    .i_dia(i_sample_in),
    .o_doa(),
    .i_clkb(i_clock),
    .i_enb(1),
    .i_web(1'b0),
    .i_addrb(in_raddr[5:0]),
    .i_dib(32'hFFFF),
    .o_dob({buf_i_out, buf_q_out})
);

wire pilot_out_stb;

complex_mult pilot_inst (
    .i_clock(i_clock),
    .i_enable(i_enable),
    .i_reset(i_reset|reset_internal),
    .i_a_i(input_i),
    .i_a_q(input_q),
    .i_b_i(lts_i_out),
    .i_b_q(lts_q_out),
    .i_input_strobe(pilot_in_stb),
    .o_p_i(pilot_i),
    .o_p_q(pilot_q),
    .o_output_strobe(pilot_out_stb)
);

wire rot_out_stb;

rotate rotate_inst (
    .i_clock(i_clock),
    .i_enable(i_enable),
    .i_reset(i_reset|reset_internal),

    .i_in_i(buf_i_out),
    .i_in_q(buf_q_out),
    // .phase(sym_phase),
    .i_phase(sym_phase[15:0]),//only taking [15:0] to rotate could have overflow!
    .i_input_strobe(rot_in_stb),

    .o_rot_addr(o_rot_addr),
    .i_rot_data(i_rot_data),
    
    .o_out_i(rot_i),
    .o_out_q(rot_q),
    .o_output_strobe(rot_out_stb)
);

complex_mult input_lts_prod_inst (
    .i_clock(i_clock),
    .i_enable(i_enable),
    .i_reset(i_reset|reset_internal),
    .i_a_i(rot_i),
    .i_a_q(rot_q),
    .i_b_i(lts_i_out),
    .i_b_q(lts_q_out_neg),
    .i_input_strobe(rot_out_stb),
    .o_p_i(prod_i),
    .o_p_q(prod_q),
    .o_output_strobe(prod_out_strobe)
);

complex_mult lts_lts_prod_inst (
    .i_clock(i_clock),
    .i_enable(i_enable),
    .i_reset(i_reset|reset_internal),
    .i_a_i(lts_i_out),
    .i_a_q(lts_q_out),
    .i_b_i(lts_i_out),
    .i_b_q(lts_q_out_neg),
    .i_input_strobe(rot_out_stb),
    .o_p_i(mag_sq),
    .o_p_q(),
    .o_output_strobe()
);

divider norm_i_inst (
    .i_clock(i_clock),
    .i_enable(i_enable),
    .i_reset(i_reset|reset_internal),

    .i_dividend(dividend_i),
    .i_divisor(divisor_i),
    .i_input_strobe(div_in_stb),

    .o_quotient(quotient_i),
    .o_output_strobe(div_out_stb)
);

divider norm_q_inst (
    .i_clock(i_clock),
    .i_enable(i_enable),
    .i_reset(i_reset|reset_internal),

    .i_dividend(dividend_q),
    .i_divisor(divisor_q),
    .i_input_strobe(div_in_stb),

    .o_quotient(quotient_q),
    .o_output_strobe()
);

// LVPE calculation to estimate SFO
divider lvpe_inst (
    .i_clock(i_clock),
    .i_enable(i_enable),
    .i_reset(i_reset|reset_internal),

    .i_dividend(lvpe_dividend),
    .i_divisor(lvpe_divisor),
    .i_input_strobe(lvpe_in_stb),

    .o_quotient(lvpe),
    .o_output_strobe(lvpe_out_stb)
);

always @(posedge i_clock) begin
    if (i_reset|reset_internal) begin
        o_sample_out_strobe <= 0;
        lts_raddr <= 0;
        lts_waddr <= 0;
        o_sample_out <= 0;

        lts_in_stb <= 0;
        lts_i_in <= 0;
        lts_q_in <= 0;

        ht <= 0;
        num_data_carrier <= 48;
        num_ofdm_sym <= 0;

        subcarrier_mask <= SUBCARRIER_MASK;
        data_subcarrier_mask <= DATA_SUBCARRIER_MASK;
        pilot_mask <= PILOT_MASK;
        lts_ref <= LTS_REF;
        ht_lts_ref <= HT_LTS_REF;
        polarity <= POLARITY;

        ht_polarity <= HT_POLARITY;

        current_polarity <= 0;
        pilot_count1 <= 0;
        pilot_count2 <= 0;
        pilot_count3 <= 0; 

        in_waddr <= 0;
        in_raddr <= 0;
        sym_idx <= 0;
        sym_idx2 <= 0; 

        lts_reg1_i <= 0; lts_reg2_i <= 0; lts_reg3_i <= 0; lts_reg4_i <= 0; lts_reg5_i <= 0;
        lts_reg1_q <= 0; lts_reg2_q <= 0; lts_reg3_q <= 0; lts_reg4_q <= 0; lts_reg5_q <= 0;
        lts_sum_i <= 0;
        lts_sum_q <= 0;
        lts_mv_avg_len <= 0;
        lts_div_in_stb <= 0;

        o_phase_in_stb <= 0;
        pilot_sum_i <= 0;
        pilot_sum_q <= 0;
        pilot_phase_err <= 0;
        cpe <= 0;
        Sxy <= 0;
        lvpe_in_stb <= 0;
        phase_err <= 0;
        pilot_in_stb <= 0;
        pilot_i_reg <= 0;
        pilot_q_reg <= 0;
        pilot_iq_phase[0] <= 0; pilot_iq_phase[1] <= 0; pilot_iq_phase[2] <= 0; pilot_iq_phase[3] <= 0;
        prev_peg <= 0; 
        prev_peg_reg <= 0; 
        peg_pilot_scale <= 0; 

        prod_in_strobe <= 0;

        rot_in_stb <= 0;

        current_sign <= 0;
        input_i <= 0;
        input_q <= 0;
        calc_mean_strobe <= 0;

        num_output <= 0;

        o_state <= S_FIRST_LTS;
    end else if (i_enable) begin
        sample_in_strobe_dly <= i_sample_in_strobe;
        case(o_state)
            S_FIRST_LTS: begin
                // store first LTS as is
                lts_in_stb <= i_sample_in_strobe;
                {lts_i_in, lts_q_in} <= i_sample_in;

                if (lts_in_stb) begin
                    if (lts_waddr == 63) begin
                        lts_waddr <= 0;
                        lts_raddr <= 0;
                        o_state <= S_SECOND_LTS;
                    end else begin
                        lts_waddr <= lts_waddr + 1;
                    end
                end
            end

            S_SECOND_LTS: begin
                // calculate and store the mean of the two LTS
                if (i_sample_in_strobe) begin
                    calc_mean_strobe <= i_sample_in_strobe;
                    {input_i, input_q} <= i_sample_in;
                    current_sign <= lts_ref[0];
                    lts_ref <= {lts_ref[0], lts_ref[63:1]};
                    lts_raddr <= lts_raddr + 1;
                end else begin
                    calc_mean_strobe <= 0;
                end

                lts_in_stb <= new_lts_stb;
                {lts_i_in, lts_q_in} <= {new_lts_i, new_lts_q};

                if (lts_in_stb) begin
                    if (lts_waddr == 63) begin
                        lts_waddr <= 0;
                        lts_raddr <= 62;
                        lts_in_stb <= 0;
                        lts_div_in_stb <= 0;
                        o_state <= (i_disable_all_smoothing?S_GET_POLARITY:S_SMOOTH_CH_DC);
                    end else begin
                        lts_waddr <= lts_waddr + 1;
                    end
                end
            end 

            // 802.11-2012.pdf: 20.3.9.4.3 Table 20-11
            // channel estimate smoothing (averaging length = 5)
            S_SMOOTH_CH_DC: begin
                if(lts_div_in_stb == 1) begin
                    lts_div_in_stb <= 0;
                end else if(lts_raddr == 4) begin
                    lts_sum_i <= lts_sum_wo3_i;
                    lts_sum_q <= lts_sum_wo3_q;
                    lts_mv_avg_len <= 4;
                    lts_div_in_stb <= 1;
                    lts_raddr <= 5;
                end else if(lts_raddr != 5) begin
                    // LTS Shift register
                    lts_reg1_i <= lts_i_out; lts_reg2_i <= lts_reg1_i; lts_reg3_i <= lts_reg2_i; lts_reg4_i <= lts_reg3_i; lts_reg5_i <= lts_reg4_i;
                    lts_reg1_q <= lts_q_out; lts_reg2_q <= lts_reg1_q; lts_reg3_q <= lts_reg2_q; lts_reg4_q <= lts_reg3_q; lts_reg5_q <= lts_reg4_q;
                    lts_raddr[5:0] <= lts_raddr[5:0] + 1;
                end else begin
                    if(lts_in_stb == 1) begin
                        lts_waddr <= 37;
                        lts_raddr <= 38;
                        lts_in_stb <= 0;
                        o_state <= S_SMOOTH_CH_LTS;
                    end else if(lts_div_out_stb == 1) begin
                        lts_i_in <= lts_div_i[15:0];
                        lts_q_in <= lts_div_q[15:0];
                        lts_in_stb <= 1;
                    end
                end

            end

            // 802.11-2012.pdf: 20.3.9.4.3 Table 20-11
            // channel estimate smoothing (averaging length = 5)
            S_SMOOTH_CH_LTS: begin
                if(lts_raddr == 42) begin
                    lts_sum_i <= lts_sum_1_3_i;
                    lts_sum_q <= lts_sum_1_3_q;
                    lts_mv_avg_len <= 3;
                    lts_div_in_stb <= 1;
                end else if(lts_raddr == 43) begin
                    lts_sum_i <= lts_sum_1_4_i;
                    lts_sum_q <= lts_sum_1_4_q;
                    lts_mv_avg_len <= 4;
                    lts_div_in_stb <= 1;
                end else if(lts_raddr > 43 || lts_raddr < 29) begin
                    lts_sum_i <= lts_sum_1_5_i;
                    lts_sum_q <= lts_sum_1_5_q;
                    lts_mv_avg_len <= 5;
                    lts_div_in_stb <= 1;
                end else if(lts_raddr == 29) begin
                    lts_sum_i <= lts_sum_2_5_i;
                    lts_sum_q <= lts_sum_2_5_q;
                    lts_mv_avg_len <= 4;
                    lts_div_in_stb <= 1;
                end else if(lts_raddr == 30) begin
                    lts_sum_i <= lts_sum_3_5_i;
                    lts_sum_q <= lts_sum_3_5_q;
                    lts_mv_avg_len <= 3;
                    lts_div_in_stb <= 1;
                end else if(lts_raddr == 31) begin
                    lts_div_in_stb <= 0;
                end

                if(lts_raddr >= 38 || lts_raddr <= 30) begin
                    // LTS Shift register
                    lts_reg1_i <= lts_i_out; lts_reg2_i <= lts_reg1_i; lts_reg3_i <= lts_reg2_i; lts_reg4_i <= lts_reg3_i; lts_reg5_i <= lts_reg4_i;
                    lts_reg1_q <= lts_q_out; lts_reg2_q <= lts_reg1_q; lts_reg3_q <= lts_reg2_q; lts_reg4_q <= lts_reg3_q; lts_reg5_q <= lts_reg4_q;
                    lts_raddr[5:0] <= lts_raddr[5:0] + 1;
                end

                if(lts_div_out_stb == 1) begin
                    lts_i_in <= lts_div_i[15:0];
                    lts_q_in <= lts_div_q[15:0];
                    lts_waddr[5:0] <= lts_waddr[5:0] + 1;
                end
                lts_in_stb <= lts_div_out_stb;

                if(lts_waddr == 26) begin
                    o_state <= S_GET_POLARITY;
                end
            end

            S_GET_POLARITY: begin
                // obtain the polarity of pilot sub-carriers for next OFDM symbol
                if (ht) begin
                    current_polarity <= {
                        ht_polarity[1]^polarity[0], // -7
                        ht_polarity[0]^polarity[0], // -21
                        ht_polarity[3]^polarity[0], // 21
                        ht_polarity[2]^polarity[0]  // 7
                        };
                    ht_polarity <= {ht_polarity[0], ht_polarity[3:1]};
                end else begin
                    current_polarity <= {
                        polarity[0],    // -7
                        polarity[0],    // -21
                        ~polarity[0],   // 21
                        polarity[0]     // 7
                        };
                end
                polarity <= {polarity[0], polarity[126:1]};

                pilot_sum_i <= 0;
                pilot_sum_q <= 0;
                pilot_count1 <= 0;
                pilot_count2 <= 0;
                cpe <= 0;
                in_waddr <= 0;
                in_raddr <= 0;
                input_i <= 0;
                input_q <= 0;
                lts_raddr <= 0;
                num_ofdm_sym <= num_ofdm_sym + 1;
                o_state <= S_CPE_ESTIMATE;
            end

            S_CPE_ESTIMATE: begin
                if (~ht & i_ht_next) begin
                    ht <= 1;
                    num_data_carrier <= 52;
                    lts_waddr <= 0;
                    lts_ref <= HT_LTS_REF;
                    subcarrier_mask <= HT_SUBCARRIER_MASK;
                    data_subcarrier_mask <= HT_DATA_SUBCARRIER_MASK;
                    pilot_mask <= PILOT_MASK;
                    // reverse this extra shift
                    polarity <= {polarity[125:0], polarity[126]};
                    o_state <= S_HT_LTS;
                end

                // calculate residue freq offset using pilot sub carriers
                if (i_sample_in_strobe) begin
                    in_waddr <= in_waddr + 1;
                    lts_raddr <= lts_raddr + 1;

                    pilot_mask <= {pilot_mask[0], pilot_mask[63:1]};
                    if (pilot_mask[0]) begin
                        pilot_count1 <= pilot_count1 + 1;
                        // obtain the conjugate of current pilot sub carrier
                        if (current_polarity[pilot_count1] == 0) begin
                            input_i <= i_sample_in[31:16];
                            input_q <= ~i_sample_in[15:0] + 1;
                        end else begin
                            input_i <= ~i_sample_in[31:16] + 1;
                            input_q <= i_sample_in[15:0];
                        end
                        pilot_in_stb <= 1;
                    end else begin
                        pilot_in_stb <= 0;
                    end
                end else begin
                    pilot_in_stb <= 0;
                end

                if (pilot_out_stb) begin
                    pilot_sum_i <= pilot_sum_i + pilot_i;
                    pilot_sum_q <= pilot_sum_q + pilot_q;
                    pilot_count2 <= pilot_count2 + 1; 
                end else if (pilot_count2 == 4) begin
                    pilot_i_reg <= pilot_sum_i;
                    pilot_q_reg <= pilot_sum_q; 
                    o_phase_in_stb <= 1;
                    pilot_count2 <= 0; 
                end else begin
                    o_phase_in_stb <= 0; 
                end

                if (i_phase_out_stb) begin
                    cpe <= i_phase_out; 
                    pilot_count1 <= 0; 
                    pilot_count2 <= 0;
                    pilot_count3 <= 0; 
                    Sxy <= 0;
                    in_raddr <= pilot_loc[0][5:0];  // sample in location, compensate for RAM read delay
                    lts_raddr <= pilot_loc[0][5:0]; // LTS location, compensate for RAM read delay
                    peg_pilot_scale <= pilot_idx[0]*prev_peg;
                    o_state <= S_PILOT_PE_CORRECTION;
                end
            end

            S_PILOT_PE_CORRECTION: begin
                // rotate pilots with accumulated PEG up to previous symbol
                if (pilot_count1 < 4) begin
                    if (pilot_count1 < 3) begin
                        in_raddr <= pilot_loc[pilot_count1+1][5:0];
                        peg_pilot_scale <= (pilot_idx[pilot_count1+1])*prev_peg;
                        rot_in_stb <= 1;
                    end
                    phase_err <= {cpe[15], cpe[15], cpe[15:0]} + peg_pilot_scale[17:0];
                    pilot_count1 <= pilot_count1 + 1; 
                end else begin
                    rot_in_stb <= 0;
                end

                if (rot_out_stb && pilot_count2 < 4) begin
                    if (pilot_count2 < 3) begin
                        lts_raddr <= pilot_loc[pilot_count2+1][5:0]; 
                    end
                    // obtain the conjugate of current pilot sub carrier
                    if (current_polarity[pilot_count2] == 0) begin
                        input_i <= rot_i;
                        input_q <= -rot_q;
                    end else begin
                        input_i <= -rot_i;
                        input_q <= rot_q;
                    end
                    pilot_in_stb <= 1;  // start complex mult. with LTS pilot
                    pilot_count2 <= pilot_count2 + 1; 
                end else begin
                    pilot_in_stb <= 0; 
                end

                if (pilot_out_stb) begin
                    pilot_i_reg <= pilot_i;
                    pilot_q_reg <= pilot_q;
                    o_phase_in_stb <= 1;
                end else begin
                    o_phase_in_stb <= 0; 
                end

                if (i_phase_out_stb && pilot_count3 < 4) begin
                    pilot_count3 <= pilot_count3 + 1; 
                    pilot_iq_phase[pilot_count3] <= i_phase_out;
                end

                if (pilot_count3 == 4) begin
                    o_phase_in_stb <= 0; 
                    pilot_count1 <= 0; 
                    pilot_count2 <= 0; 
                    pilot_count3 <= 0; 
                    o_state <= S_LVPE_ESTIMATE; 
                end
            end

            S_LVPE_ESTIMATE: begin
                if (pilot_count1 < 4) begin
                    // sampling rate offset (SFO) is calculated as pilot phase error
                    if(pilot_iq_phase[pilot_count1] < -1608) begin
                        pilot_phase_err <= pilot_iq_phase[pilot_count1] + 3217;
                    end else if(pilot_iq_phase[pilot_count1] > 1608) begin
                        pilot_phase_err <= pilot_iq_phase[pilot_count1] - 3217;
                    end else begin
                        pilot_phase_err <= pilot_iq_phase[pilot_count1];
                    end

                    pilot_count1 <= pilot_count1 + 1;
                end

                if(pilot_count1 == 1) begin
                    Sxy <= Sxy + 7*pilot_phase_err;
                end else if(pilot_count1 == 2) begin
                    Sxy <= Sxy + 21*pilot_phase_err;
                end else if(pilot_count1 == 3) begin
                    Sxy <= Sxy + -21*pilot_phase_err;
                end else if(pilot_count1 == 4) begin
                    Sxy <= Sxy + -7*pilot_phase_err;

                    in_raddr <= 0; 
                    sym_idx <= 0;
                    sym_idx2 <= 1; 
                    lvpe_in_stb <= 0;
                    // compensate for RAM read delay
                    lts_raddr <= 1;
                    rot_in_stb <= 0;
                    num_output <= 0;
                    o_state <= S_ALL_SC_PE_CORRECTION;
                end
                // Sx² = ∑(x-x̄)*(x-x̄) = ∑x² = (7² + 21² + (-21)² + (-7)²) = 980
                // phase error gradient (PEG) = Sxy/Sx²
            end

            S_ALL_SC_PE_CORRECTION: begin
                if (sym_idx < 64) begin
                    sym_idx <= sym_idx + 1;
                    lvpe_in_stb <= 1;
                end else begin
                    lvpe_in_stb <= 0;
                end

                // first rotate, then normalize by avg LTS
                if (lvpe_out_stb) begin
                    sym_idx2 <= sym_idx2 + 1; 
                    phase_err <= {cpe[15], cpe[15], cpe[15:0]} + lvpe[17:0] + peg_sym_scale[17:0];
                    rot_in_stb <= 1;
                    in_raddr <= in_raddr + 1;
                    if (sym_idx2 == 32) begin
                        // lvpe output is 32*PEG due to sym_idx
                        prev_peg_reg <= prev_peg_reg + (lvpe >>> 5); 
                    end
                end else begin
                    rot_in_stb <= 0;
                end

                if (rot_out_stb) begin
                    lts_raddr <= lts_raddr + 1;
                end

                if (norm_out_stb) begin
                    data_subcarrier_mask <= {data_subcarrier_mask[0],
                        data_subcarrier_mask[63:1]};
                    if (data_subcarrier_mask[0]) begin
                        o_sample_out_strobe <= 1;
                        o_sample_out <= {norm_i[31], norm_i[14:0],
                            norm_q[31], norm_q[14:0]};
                        num_output <= num_output + 1;
                    end else begin
                        o_sample_out_strobe <= 0;
                    end
                end else begin
                    o_sample_out_strobe <= 0;
                end

                if (num_output == num_data_carrier) begin
                    prev_peg <= prev_peg_reg; 
                    o_state <= S_GET_POLARITY;
                end
            end

            S_HT_LTS: begin
                if (i_sample_in_strobe) begin
                    lts_in_stb <= 1;
                    ht_lts_ref <= {ht_lts_ref[0], ht_lts_ref[63:1]};
                    if (ht_lts_ref[0] == 0) begin
                        {lts_i_in, lts_q_in} <= i_sample_in;
                    end else begin
                        lts_i_in <= ~i_sample_in[31:16]+1;
                        lts_q_in <= ~i_sample_in[15:0]+1;
                    end
                end else begin
                    lts_in_stb <= 0;
                end

                if (lts_in_stb) begin
                    if (lts_waddr == 63) begin
                        lts_waddr <= 0;
                        lts_raddr <= 62;
                        lts_in_stb <= 0;
                        lts_div_in_stb <= 0;
                        // Depending on smoothing bit in HT-SIG, smooth the channel
                        if(i_ht_smoothing==1 && i_disable_all_smoothing==0) begin
                            o_state <= S_SMOOTH_CH_DC;
                        end else begin
                            o_state <= S_GET_POLARITY;
                        end
                    end else begin
                        lts_waddr <= lts_waddr + 1;
                    end
                end

            end

            default: begin
                o_state <= S_FIRST_LTS;
            end
        endcase
    end else begin
        o_sample_out_strobe <= 0;
    end
end

endmodule

