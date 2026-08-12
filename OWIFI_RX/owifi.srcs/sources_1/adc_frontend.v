//////////////////////////////////////////////////////////////////////////////////
//
// Design Name: OWIFI_RX
// Module Name: adc_frontend
// Project Name: RA-Sentinel 802.11 receiver
// Engineer: Tobias Weber
// Target Devices: Artix 7, XC7A100T
// Description:
//   The COMPLETE hardware-proven RASM2400 ADC capture chain (extracted from
//   RASM2400/top_LVDSTEST.v @c103c5e, 2026-07-31) as one self-contained
//   module: everything between the RASBB PCIe-connector LVDS pins and a
//   clean, DC-free, I/Q-balanced 20MSPS complex baseband stream.
//
//     lvds_rx (lvds_rx_new.v)  EVEN/ODD ISERDES SDR-6 deserializer, ODD via
//                              IDELAYE2, FCLK captured as data, fast re-anchor
//     rotation search          FCLK-pattern word-boundary decode, 16-decode
//                              hysteresis
//     word assembly            {lane_cur, lane_hist}[base +: 12] - the NEWER
//                              word in the HIGH half. Do not "fix" this back
//                              to {hist, cur}: that ordering was a measured
//                              1-error-per-16-words assembly bug (2.5M err/s
//                              at 20MSPS, flat across all IDELAY taps)
//     adc_sequencer            modulo-6 sample strobes in the bit-clock domain
//     link_supervisor          IDELAY tap ownership + automatic retraining
//     DC removal               leaky integrator per rail, fc ~= 97Hz @ 20MSPS
//     iq_balance               blind adaptive image rejection (Moseley/Slump);
//                              raw analog image measured -15dB, corrected to
//                              ~-32dB. Trains on any carrier >= ~-40dBFS.
//
//   Board/wiring facts this module bakes in (all hardware-verified):
//     - EVERY used LVDS pair needs an EXTERNAL 100R termination at the
//       connector. The pins are DIFF_SSTL18_II in an HR bank at VCCO 1.8V:
//       DIFF_TERM is inert there (LVDS_25/2.5V only, UG471) and IN_TERM's
//       Thevenin split to 0.9V fights the ADC's ~1.2V common mode.
//     - lvds_dclk is a TRUE 120MHz clock. Constrain it at 8.333ns; the old
//       16.667ns constraint hid real failures that came and went with
//       placement luck ("finding D1").
//     - After ANY reconfiguration/reset of the ADC (e.g. an STM32 firmware
//       reflash re-running ADC init) the link can slip word alignment in a
//       way the FCLK watchdog cannot see: reconfigure the FPGA (or toggle
//       i_rst) afterwards.
//
// Dependencies: lvds_rx_new.v, adc_sequencer.v, link_supervisor.v,
//               iq_balance.v; an IDELAYCTRL reference clock (190..210MHz)
//               must be supplied by the parent.
//
// Additional Comments: https://github.com/Tobias-DG3YEV/RA-Sentinel
//
//////////////////////////////////////////////////////////////////////////////////
// Copyright (C) 2026 Tobias Weber
// License: GNU GPL v3
//////////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps

module adc_frontend #(
    parameter ADCBITS    = 12,
    /* 1: Q rail from ADC chB (RASRF single-channel board), 0: from chC
       (RASRF2400BMC pinout). Same convention as RASM2400's Q_FROM_CHB. */
    parameter Q_FROM_CHB = 1
)(
    /* ADC LVDS pins (RASBB PCIe connector). chC exists only on the BMC
       board; on the 1ch RASRF leave the chC ports unconnected - the lane
       deserializes garbage and is never selected. */
    input  wire ADC_dclk_P, ADC_dclk_N,   // 120 MHz bit clock
    input  wire ADC_fclk_P, ADC_fclk_N,   // 20 MHz frame clock
    input  wire ADC_chA_P,  ADC_chA_N,    // I lane
    input  wire ADC_chB_P,  ADC_chB_N,    // Q lane (1ch RASRF)
    input  wire ADC_chC_P,  ADC_chC_N,    // Q lane (BMC)

    input  wire i_rst,            // async-ok, held through power-on
    input  wire i_delay_refclk,   // 190..210MHz for the bank-35 IDELAYCTRL

    /* Everything below is synchronous to o_clk (the BUFG'd 120MHz ADC bit
       clock). o_sample_strobe pulses one cycle per sample pair (20MHz). */
    output wire o_clk,
    output wire o_sample_strobe,
    output wire signed [ADCBITS-1:0] o_i,   // DC-free, I/Q-balanced
    output wire signed [ADCBITS-1:0] o_q,
    /* High once the deserializer is anchored AND 4095 further samples have
       flushed the pipeline - the same mute rule that kept re-anchor garbage
       off the RASM2400 spectrum. Gate the decoder's sample strobe with it. */
    output wire o_samples_valid,
    /* diagnostics */
    output wire o_link_ok,
    output wire [7:0] o_retrain_count,
    output wire [7:0] o_rot_change_count,
    /* converged iq_balance coefficients (Q1.15) = the MEASURED analog
       quadrature imbalance. Quasi-static; they live in the o_clk domain,
       so a consumer in another domain must 2FF-sync them (torn LSBs are
       harmless for a diagnostic readout). */
    output wire signed [15:0] o_iqbal_wp,
    output wire signed [15:0] o_iqbal_eg
);

wire global_rst = i_rst;

/****************************************************************************/
/* Deserializer (lvds_rx_new.v: module name lvds_rx). Tap owned by the      */
/* link supervisor at the bottom.                                           */
/****************************************************************************/
wire [4:0] cal_tap;
wire       cal_load;
wire       lvds_dclk;
wire       lvds_fclk;
wire       lvds_ready;
wire       lvds_dclk_buffered;

wire [3*ADCBITS-1:0] adc_data;      // lane 0 = chA (I), 1 = chB, 2 = chC
wire [ADCBITS-1:0]   adc_fclk_word; // FCLK captured like a data lane

lvds_rx #(.NLANES(3)) lvds_irx0 (
    .i_lvds_dclk_P(ADC_dclk_P),
    .i_lvds_dclk_N(ADC_dclk_N),
    .i_lvds_fclk_P(ADC_fclk_P),
    .i_lvds_fclk_N(ADC_fclk_N),
    .i_lvds_d_P({ADC_chC_P, ADC_chB_P, ADC_chA_P}),
    .i_lvds_d_N({ADC_chC_N, ADC_chB_N, ADC_chA_N}),
    .i_rst(global_rst),
    .i_ctrlClk(lvds_dclk_buffered),
    .i_data_delay_tap(cal_tap),
    .i_data_delay_load(cal_load),
    .o_lvds_dclk(lvds_dclk),
    .o_lvds_fclk(lvds_fclk),
    .o_data(adc_data),
    .o_fclk_word(adc_fclk_word),
    .o_ready(lvds_ready)
);

/* Explicit BUFG so the processing-domain clock tree is deterministic. */
BUFG BUFG_lvds_dclk_1 (
    .I(lvds_dclk),
    .O(lvds_dclk_buffered)
);
assign o_clk = lvds_dclk_buffered;

/* IDELAYCTRL calibrates all IDELAYE2s of the ADC pin bank (one site per
   bank). The parent supplies the reference clock. */
IDELAYCTRL IDELAYCTRL0 (
   .RDY(),
   .REFCLK(i_delay_refclk),
   .RST(global_rst)
);

/****************************************************************************/
/* Sample sequencing (modulo-6 strobes). i_fft_lineSync only aligns the     */
/* FFT-side strobes RASM2400 used; unused here.                             */
/****************************************************************************/
wire adc_frameStrobe;

adc_sequencer adc_sequencer0 (
    .i_lvds_frameClk(lvds_fclk),
    .i_lvds_bitClk(lvds_dclk_buffered),
    .i_fft_lineSync(1'b0),
    .i_rst(global_rst),
    .o_adc_frameStrobe(adc_frameStrobe),
    .o_fft_frameStrobe(),
    .o_frameCounter(),
    .o_mem_sampleStrobe()
);
assign o_sample_strobe = adc_frameStrobe;

/****************************************************************************/
/* Word-boundary rotation search on the decoded FCLK word (verbatim from    */
/* RASM2400 top_LVDSTEST.v - see that file for the full derivation).        */
/****************************************************************************/
localparam ROT_POS = ADCBITS + 1; // window base positions (13)
localparam [ADCBITS-1:0] FCLK_PAT = {{(ADCBITS/2){1'b0}}, {(ADCBITS/2){1'b1}}}; // 12'h03F
localparam [3:0] FCLK_PHASE_ADJ = 4'd0;

reg [ADCBITS-1:0] fclk_cur;
reg [ADCBITS-1:0] fclk_hist;
always @(posedge lvds_dclk_buffered) begin
    if (global_rst) begin
        fclk_cur <= 0; fclk_hist <= 0;
    end
    else if (adc_frameStrobe) begin
        fclk_cur <= adc_fclk_word; fclk_hist <= fclk_cur;
    end
end

wire [2*ADCBITS-1:0] fclk_win = {fclk_hist, fclk_cur};

reg [3:0] fclk_dec;
reg       fclk_hit;
integer fd;
always @* begin
    fclk_dec = 4'd0; fclk_hit = 1'b0;
    for (fd = 0; fd < ROT_POS; fd = fd + 1) begin
        if (fclk_win[fd +: ADCBITS] == FCLK_PAT) begin
            fclk_dec = fd[3:0] + FCLK_PHASE_ADJ; fclk_hit = 1'b1;
        end
        else if (fclk_win[fd +: ADCBITS] == ~FCLK_PAT) begin
            fclk_dec = ((fd >= ADCBITS/2) ? fd[3:0] - ADCBITS/2
                                          : fd[3:0] + ADCBITS/2) + FCLK_PHASE_ADJ;
            fclk_hit = 1'b1;
        end
    end
end

/* Commit with hysteresis: 16 consecutive identical decodes. */
reg [3:0] rot_cur;
reg [3:0] rot_cand;
reg [3:0] rot_cnt;
reg [7:0] rot_change_count;
always @(posedge lvds_dclk_buffered) begin
    if (global_rst) begin
        rot_cur <= 4'd0; rot_cand <= 4'd0; rot_cnt <= 4'd0;
        rot_change_count <= 8'd0;
    end
    else if (adc_frameStrobe && fclk_hit) begin
        if (fclk_dec == rot_cur)
            rot_cnt <= 4'd0;
        else if (fclk_dec == rot_cand) begin
            if (rot_cnt == 4'd15) begin
                rot_cur <= fclk_dec;
                rot_cnt <= 4'd0;
                rot_change_count <= rot_change_count + 8'd1;
            end
            else rot_cnt <= rot_cnt + 4'd1;
        end
        else begin
            rot_cand <= fclk_dec;
            rot_cnt  <= 4'd0;
        end
    end
end
assign o_rot_change_count = rot_change_count;

/* Word assembly: NEWER word in the HIGH half - see header. */
reg  [ADCBITS-1:0] lane_cur  [0:2];
reg  [ADCBITS-1:0] lane_hist [0:2];
wire [ADCBITS-1:0] lane_sample [0:2];

genvar rl;
generate for (rl = 0; rl < 3; rl = rl + 1) begin : gen_rot
    always @(posedge lvds_dclk_buffered) begin
        if (global_rst) begin
            lane_cur[rl]  <= {ADCBITS{1'b0}};
            lane_hist[rl] <= {ADCBITS{1'b0}};
        end
        else if (adc_frameStrobe) begin
            lane_cur[rl]  <= adc_data[rl*ADCBITS +: ADCBITS];
            lane_hist[rl] <= lane_cur[rl];
        end
    end
    wire [2*ADCBITS-1:0] rot_pair = {lane_cur[rl], lane_hist[rl]};
    assign lane_sample[rl] = rot_pair[rot_cur +: ADCBITS];
end
endgenerate

wire [ADCBITS-1:0] adc_ipar = lane_sample[0];
wire [ADCBITS-1:0] adc_qpar = Q_FROM_CHB ? lane_sample[1] : lane_sample[2];

/****************************************************************************/
/* Link supervisor: IDELAY tap ownership + automatic retraining.            */
/****************************************************************************/
link_supervisor sup_adc (
    .i_clk(lvds_dclk_buffered),
    .i_rst(global_rst),
    .i_ce(adc_frameStrobe),
    .i_hit(fclk_hit),
    .o_tap(cal_tap),
    .o_load(cal_load),
    .o_healthy(o_link_ok),
    .o_retrain_count(o_retrain_count)
);

/****************************************************************************/
/* Output-valid gating: deserializer outages freeze the ISERDES outputs at  */
/* a constant, which downstream sees as a huge DC step. Same 4095-sample    */
/* flush rule as RASM2400's spectrum mute.                                  */
/****************************************************************************/
reg [11:0] mute_ctr;
always @(posedge lvds_dclk_buffered) begin
    if (global_rst)                                 mute_ctr <= 12'hFFF;
    else if (!lvds_ready)                           mute_ctr <= 12'hFFF;
    else if (adc_frameStrobe && mute_ctr != 12'd0)  mute_ctr <= mute_ctr - 12'd1;
end
assign o_samples_valid = (mute_ctr == 12'd0);

/****************************************************************************/
/* DC removal: leaky integrator per rail, fc ~= 97Hz @ 20MSPS, settles ~5ms */
/****************************************************************************/
localparam DC_K = 15;

wire signed [ADCBITS-1:0] raw_i = adc_ipar;
wire signed [ADCBITS-1:0] raw_q = adc_qpar;

reg signed [ADCBITS+DC_K-1:0] dc_acc_i, dc_acc_q;
wire signed [ADCBITS-1:0] dc_i = dc_acc_i >>> DC_K;
wire signed [ADCBITS-1:0] dc_q = dc_acc_q >>> DC_K;

always @(posedge lvds_dclk_buffered) begin
    if (global_rst) begin
        dc_acc_i <= 0;
        dc_acc_q <= 0;
    end
    else if (adc_frameStrobe) begin
        dc_acc_i <= dc_acc_i + (raw_i - dc_i);
        dc_acc_q <= dc_acc_q + (raw_q - dc_q);
    end
end

wire signed [ADCBITS:0] hp_i_full = raw_i - dc_i;
wire signed [ADCBITS:0] hp_q_full = raw_q - dc_q;
reg signed [ADCBITS-1:0] hp_i_r, hp_q_r;
always @(posedge lvds_dclk_buffered) begin
    if (global_rst) begin
        hp_i_r <= 0;
        hp_q_r <= 0;
    end
    else if (adc_frameStrobe) begin
        hp_i_r <=
            (hp_i_full > $signed(13'sd2047))  ? $signed(12'sd2047)  :
            (hp_i_full < $signed(-13'sd2048)) ? $signed(-12'sd2048) : hp_i_full[ADCBITS-1:0];
        hp_q_r <=
            (hp_q_full > $signed(13'sd2047))  ? $signed(12'sd2047)  :
            (hp_q_full < $signed(-13'sd2048)) ? $signed(-12'sd2048) : hp_q_full[ADCBITS-1:0];
    end
end

/****************************************************************************/
/* Blind adaptive I/Q imbalance correction. Both rails leave with the same  */
/* one-word latency, pair stays sample-aligned.                             */
/****************************************************************************/
iq_balance iq_bal (
    .i_clk(lvds_dclk_buffered),
    .i_rst(global_rst),
    .i_ce(adc_frameStrobe),
    .i_i(hp_i_r),
    .i_q(hp_q_r),
    .o_i(o_i),
    .o_q(o_q),
    .o_wp(o_iqbal_wp),
    .o_eg(o_iqbal_eg)
);

endmodule
