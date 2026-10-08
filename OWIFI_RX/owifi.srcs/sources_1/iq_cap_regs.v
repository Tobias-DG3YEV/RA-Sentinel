//////////////////////////////////////////////////////////////////////////////////
//
// Design Name: OWIFI_RX
// Module Name: iq_cap_regs
// Project Name: RA-Sentinel IQ snapshot transport (doc/iq_capture/SPEC.md §4)
// Engineer: Tobias Weber
// Target Devices: Artix 7, XC7A100T (RASBB baseboard)
// Description:
//   SPEC §4 capture registers on FPGA1's existing config bus (conf_registers
//   style: 7-bit address, 32-bit data, write strobe, tri-state read mux;
//   reached from the STM32 with spi_frame_if opcodes 0xA8 WRITE_REG / 0xA9
//   READ_REG). The bus is 32 bits wide, so every SPEC address holds a full
//   32-bit word: multi-byte SPEC fields (NSAMP, the u32 counters) live
//   whole in the word at their BASE address and the +1..+3 addresses are
//   unused (SPEC §4 note added 2026-09-18). MAC bytes stay one per address.
//
//   0x10 CAP_CTRL     b0 enable b1 pass_all b2 require_fcs b3 clear (pulse)
//                     b4 test_pattern b5 test_fast (1 ms period instead of 100 ms)
//                     b6 free_run: snapshots of the LIVE samples on the test timer (every
//                        100 ms, b5: 1 ms), no frame trigger or verdict, proto 254 - idle
//                        noise spectra (2026-10-03); b4 wins if both are set
//   0x11 CAP_NSAMP    1..NSAMP_MAX, default 1024
//   0x13 CAP_PRETRIG  instants kept before the trigger, default 128 (v0.6; was 64:
//                    the STF detect fires 60..100 instants into the STF, so 64
//                    could cut the first microseconds of the frame's turn-on)
//   0x14 PH_START     phase window: instants after the trigger, default 96
//   0x15 PH_LEN       phase window length in instants, default 128 (1..1024)
//   0x16 PH_CAL       marker calibration, 16-bit binary turns subtracted from the
//                    ch1-vs-ch0 phase before the polar rim marker; default 0, per boot
//   0x18 GAIN_TRIM    4 x signed 8-bit, ch c at [8c +: 8], added to the amplitude-DF log
//                    power (1 LSB = 0.376 dB of power), default 0 = no trim
//   0x17 ADC_SKEW     [2:0] instants ch0/ch1 are delayed, [6:4] ch2/ch3; default 0x02
//                    (ADC2 arrives 2 instants after ADC1 - measured 2026-09-24)
//   0x19 TAP_OVR      IDELAY tap override for eye scans: [4:0] ADC1 tap, [5] ADC1 enable,
//                    [12:8] ADC2 tap, [13] ADC2 enable; default 0 (supervisor owns the taps)
//   0x12 LANE_TAP1    ADC1 per-lane IDELAY tap offsets (2026-10-06): lane n (0 ch0 I, 1 ch0 Q,
//                    2 ch1 I, 3 ch1 Q) at [8n +: 6], signed, added to the supervisor's (or
//                    TAP_OVR's) tap, saturated to 0..31; FCLK keeps the plain tap.
//                    Default LANE_TAP1_DEF. 0x0F LANE_TAP2: the same for ADC2 (ch2/ch3)
//   0x07 IQB_CTRL     I/Q corrector (iq_balance, one per channel): write [1:0] channel for
//                    the read-back, [7:4] bypass ch0..3 (Q leaves uncorrected, the
//                    corrector keeps adapting), [8] = 1 restarts every corrector from
//                    zero (self-clearing); read {w_p[15:0], e_g[15:0]} (Q1.15) of the
//                    selected channel (2026-10-06)
//   0x1A FH_CTRL      fast link heal: [0] ADC1 enable, [1] ADC2 enable (default 1/1);
//                    write [4] / [5] = force one re-init of ADC1 / ADC2 (self-clearing);
//                    read [10:8] ADC1 state, [14:12] ADC2 state (0 disarmed, 1 armed,
//                    2..5 attempt, 6 gave up), [19:16] ADC1 locked word rotation,
//                    [23:20] ADC1 armed reference, [27:24] ADC2 rotation, [31:28] ADC2 reference
//   0x1B FH_STAT1     ADC1 fast heal, 8-bit wrapping: [7:0] attempts, [15:8] successes,
//                    [23:16] give-ups, [31:24] episodes caused by an invisible slip (T2) (RO)
//   0x1D DF_MODE      bearing method: [0] 1 = pattern table (df_pattern.v) refines the formula's
//                    bearing, 0 = formula only; [15:8] search half-window in 0.703-deg bins
//                    around the formula's bearing (>= 255 = whole circle); default 0x4001
//   0x1E DF_STAT      last measurement: [8:0] formula bin, [24:16] table bin, [30:25] table
//                    score[21:16], [31] table result valid; bins 512/turn CCW from east (RO)
//   0x1C FH_STAT2     the same for ADC2 (RO); both since configuration / Key0 (global_rst),
//                    a heal (fe_rst) does not clear them
//   0x20+8k+j (j=0..5) MACk byte j (byte 0 first on air), 0x26+8k MACk_EN b0
//   0x60 TRIG_COUNT  0x64 MATCH_COUNT  0x68 DROP_COUNT  0x6C SENT_COUNT
//   0x70 LINK_STAT   b0 fpga2_ready b1 tx_busy      (all RO)
//   (0x6E NF_CTRL / 0x6F NF_DATA: per-channel receiver noise floor, noise_floor.v)
//   0x71 RD_XOR      running XOR of every instant handed to the read-out
//                    port (96 bits folded to 32) - the link receiver / PC
//                    can recompute it; also what keeps the datapath alive
//                    in a build without the link transmitter
//   0x74 PH_STAT     [15:0] PH_COUNT (committed frames with a phase result),
//                    b16 weak, b17 valid (RO); 0x75/0x76/0x77 PHk: [15:0] phase
//                    of ch k vs ch0 (binary turns), [21:16] magnitude exponent
//   0x78 MARK_DBG    [15:0] rim-marker commits, [24:16] marker angle bin (calibrated), b25 mark_ok (RO)
//   0x7A LINK_DBG    [7:0] ADC1 link drops, [15:8] ADC2 link drops, [20:16] ADC1 IDELAY tap,
//                    [23:21] ADC1 dead-stream count, [28:24] ADC2 tap, [31:29] ADC2 dead; since power-up (RO)
//   0x7B XADC_A      [11:0] die temperature code, [27:16] VCCINT code (T = c*503.975/4096-273.15, V = c*3/4096)
//   0x7C XADC_B      [11:0] VCCAUX code, [27:16] max temperature code since power-up,
//                    [15] JTAGLOCKED [14] JTAGBUSY [13] read pending, [31:28] completed reads (wraps)
//   0x7D FCLK_MISS   [15:0] ADC1, [31:16] ADC2 frame-clock decode misses in the last 2^24 words (0.84 s)
//   0x7E LINK_ACC    retrains ADC1 [7:0] / ADC2 [15:8], re-anchors ADC1 [23:16] / ADC2 [31:24], across heals
//   0x7F LINK_FIRST  [7:0] rotation changes, [15:8] ADC1 failed first, [23:16] ADC2 first, [31:24] both at once
//   0x79 MARK_RAW    [8:0] raw phase bin of the marker frame, [24:16] its amplitude bearing bin (the ray), b25 mark_ok (RO)
//
// Dependencies: none
//
// Additional Comments: https://github.com/Tobias-DG3YEV/RA-Sentinel
//
//////////////////////////////////////////////////////////////////////////////////
// Copyright (C) 2026 Tobias Weber
// License: GNU GPL v3
//////////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps

module iq_cap_regs #(
    parameter ADDR_WIDTH = 7,
    parameter NSAMP_MAX  = 1024,
    parameter [31:0] LANE_TAP1_DEF = 32'd0,   // 0x12 power-on value
    parameter [31:0] LANE_TAP2_DEF = 32'd0    // 0x0F power-on value
)(
    input  wire        i_clock,
    input  wire        i_reset,
    input  wire [ADDR_WIDTH-1:0] i_SPI_addr,
    input  wire        i_SPI_wrStrobe,
    input  wire [31:0] i_SPIdata,
    inout  wire [31:0] o_SPIdata,

    /* configuration out */
    output reg         o_enable,
    output reg         o_pass_all,
    output reg         o_require_fcs,
    output reg         o_clear,          // one-clock pulse
    output reg         o_test_pattern,
    output reg         o_test_fast,
    output reg         o_free_run,
    output reg  [15:0] o_nsamp,
    output reg  [15:0] o_pretrig,
    output reg  [15:0] o_ph_start,
    output reg  [15:0] o_ph_len,
    output reg  [15:0] o_ph_cal,
    output reg  [7:0]  o_adc_skew,
    output reg  [31:0] o_gain_trim,
    output reg  [15:0] o_tap_ovr,
    output reg  [31:0] o_lane_tap1,      // 0x12
    output reg  [31:0] o_lane_tap2,      // 0x0F
    output reg  [1:0]  o_iqb_sel,        // 0x07 [1:0]
    output reg  [3:0]  o_iqb_bypass,     // 0x07 [7:4]
    output reg         o_iqb_clear_tog,  // toggles on every write of 0x07 bit8
    output reg  [1:0]  o_fh_enable,
    output reg  [1:0]  o_fh_force_tog,   // bit k toggles on every write of FH_CTRL[4+k]
    output reg  [15:0] o_df_mode,
    output reg  [8*48-1:0] o_mac,
    output reg  [7:0]  o_mac_en,

    /* read-only in */
    input  wire [31:0] i_trig_count,
    input  wire [31:0] i_match_count,
    input  wire [31:0] i_drop_count,
    input  wire [31:0] i_sent_count,
    input  wire        i_fpga2_ready,
    input  wire        i_tx_busy,
    input  wire [31:0] i_rd_xor,
    input  wire [31:0] i_heal_count,
    input  wire [31:0] i_stall_count,
    input  wire [31:0] i_ph_stat,
    input  wire [31:0] i_ph1,
    input  wire [31:0] i_ph2,
    input  wire [31:0] i_ph3,
    input  wire [31:0] i_mark_dbg,     // 0x78: {6'd0, mark_ok, mark_ang[8:0], mark_cnt[15:0]} from df_frame
    input  wire [31:0] i_mark_raw,     // 0x79: {6'd0, mark_ok, mark_brg[8:0], 7'd0, mark_raw[8:0]}
    input  wire [5:0]  i_fh_state,     // 0x1A: {ADC2 state, ADC1 state}
    input  wire [15:0] i_fh_rot,       // 0x1A: {ADC2 ref, ADC2 rot, ADC1 ref, ADC1 rot}
    input  wire [31:0] i_fh_stat1,     // 0x1B
    input  wire [31:0] i_fh_stat2,     // 0x1C
    input  wire [31:0] i_df_stat,      // 0x1E
    input  wire [31:0] i_iqb_coef,     // 0x07: {w_p, e_g} of channel o_iqb_sel
    input  wire [191:0] i_diag         // 0x7A..0x7F: word k at [32k +: 32] -> address 0x7A+k (link-health diagnostics)
);

wire [6:0] a = i_SPI_addr[6:0];
wire       is_mac = (a >= 7'h20) && (a < 7'h60);
wire [2:0] mk = (a - 7'h20) >> 3;             // slot
wire [2:0] mj = (a - 7'h20) & 3'd7;           // byte / 6 = enable

integer k;
always @(posedge i_clock) begin
    o_clear <= 1'b0;
    if (i_reset) begin
        o_enable <= 1'b0; o_pass_all <= 1'b0; o_require_fcs <= 1'b0;
        o_test_pattern <= 1'b0; o_test_fast <= 1'b0; o_free_run <= 1'b0; o_nsamp <= NSAMP_MAX[15:0]; o_pretrig <= 16'd128;
        o_ph_start <= 16'd96; o_ph_len <= 16'd128; o_ph_cal <= 16'd0; o_adc_skew <= 8'h02; o_gain_trim <= 32'd0;
        o_tap_ovr <= 16'd0; o_lane_tap1 <= LANE_TAP1_DEF; o_lane_tap2 <= LANE_TAP2_DEF;
        o_iqb_sel <= 2'd0; o_iqb_bypass <= 4'd0; o_iqb_clear_tog <= 1'b0;
        o_fh_enable <= 2'b11; o_fh_force_tog <= 2'b00; o_df_mode <= 16'h4001;
        o_mac <= {8*48{1'b0}}; o_mac_en <= 8'd0;
    end
    else if (i_SPI_wrStrobe) begin
        case (a)
            7'h10: begin
                o_enable       <= i_SPIdata[0];
                o_pass_all     <= i_SPIdata[1];
                o_require_fcs  <= i_SPIdata[2];
                o_clear        <= i_SPIdata[3];
                o_test_pattern <= i_SPIdata[4];
                o_test_fast    <= i_SPIdata[5];
                o_free_run     <= i_SPIdata[6];
            end
            7'h11: o_nsamp   <= (i_SPIdata[15:0] == 16'd0) ? 16'd1 :
                                (i_SPIdata[15:0] > NSAMP_MAX[15:0]) ? NSAMP_MAX[15:0] : i_SPIdata[15:0];
            7'h13: o_pretrig <= i_SPIdata[15:0];
            7'h14: o_ph_start <= i_SPIdata[15:0];
            7'h15: o_ph_len   <= (i_SPIdata[15:0] == 16'd0) ? 16'd1 :
                                 (i_SPIdata[15:0] > NSAMP_MAX[15:0]) ? NSAMP_MAX[15:0] : i_SPIdata[15:0];
            7'h16: o_ph_cal   <= i_SPIdata[15:0];
            7'h17: o_adc_skew <= {1'b0, i_SPIdata[6:4], 1'b0, i_SPIdata[2:0]};
            7'h18: o_gain_trim <= i_SPIdata;
            7'h19: o_tap_ovr   <= {2'b00, i_SPIdata[13:8], 2'b00, i_SPIdata[5:0]};
            7'h12: o_lane_tap1 <= {2'b00, i_SPIdata[29:24], 2'b00, i_SPIdata[21:16],
                                   2'b00, i_SPIdata[13:8],  2'b00, i_SPIdata[5:0]};
            7'h0F: o_lane_tap2 <= {2'b00, i_SPIdata[29:24], 2'b00, i_SPIdata[21:16],
                                   2'b00, i_SPIdata[13:8],  2'b00, i_SPIdata[5:0]};
            7'h07: begin
                o_iqb_sel       <= i_SPIdata[1:0];
                o_iqb_bypass    <= i_SPIdata[7:4];
                o_iqb_clear_tog <= o_iqb_clear_tog ^ i_SPIdata[8];
            end
            7'h1D: o_df_mode <= {i_SPIdata[15:8], 7'd0, i_SPIdata[0]};
            7'h1A: begin
                o_fh_enable    <= i_SPIdata[1:0];
                o_fh_force_tog <= o_fh_force_tog ^ i_SPIdata[5:4];
            end
            default: begin
                if (is_mac) begin
                    if (mj == 3'd6)      o_mac_en[mk] <= i_SPIdata[0];
                    else if (mj <= 3'd5) o_mac[48*mk + 8*(5-mj) +: 8] <= i_SPIdata[7:0];
                end
            end
        endcase
    end
end

reg [31:0] rd;
reg        sel;
always @(*) begin
    sel = 1'b1; rd = 32'd0;
    case (a)
        7'h10: rd = {25'd0, o_free_run, o_test_fast, o_test_pattern, 1'b0, o_require_fcs, o_pass_all, o_enable};
        7'h11: rd = {16'd0, o_nsamp};
        7'h13: rd = {16'd0, o_pretrig};
        7'h14: rd = {16'd0, o_ph_start};
        7'h15: rd = {16'd0, o_ph_len};
        7'h16: rd = {16'd0, o_ph_cal};
        7'h17: rd = {24'd0, o_adc_skew};
        7'h18: rd = o_gain_trim;
        7'h19: rd = {16'd0, o_tap_ovr};
        7'h12: rd = o_lane_tap1;
        7'h0F: rd = o_lane_tap2;
        7'h07: rd = i_iqb_coef;
        7'h1A: rd = {i_fh_rot, 1'b0, i_fh_state[5:3], 1'b0, i_fh_state[2:0], 6'd0, o_fh_enable};
        7'h1B: rd = i_fh_stat1;
        7'h1C: rd = i_fh_stat2;
        7'h1D: rd = {16'd0, o_df_mode};
        7'h1E: rd = i_df_stat;
        7'h60: rd = i_trig_count;
        7'h64: rd = i_match_count;
        7'h68: rd = i_drop_count;
        7'h6C: rd = i_sent_count;
        7'h70: rd = {30'd0, i_tx_busy, i_fpga2_ready};
        7'h71: rd = i_rd_xor;
        7'h72: rd = i_heal_count;
        7'h73: rd = i_stall_count;
        7'h74: rd = i_ph_stat;
        7'h75: rd = i_ph1;
        7'h76: rd = i_ph2;
        7'h77: rd = i_ph3;
        7'h78: rd = i_mark_dbg;
        7'h79: rd = i_mark_raw;
        7'h7A: rd = i_diag[ 31:  0];
        7'h7B: rd = i_diag[ 63: 32];
        7'h7C: rd = i_diag[ 95: 64];
        7'h7D: rd = i_diag[127: 96];
        7'h7E: rd = i_diag[159:128];
        7'h7F: rd = i_diag[191:160];
        default: begin
            if (is_mac && mj == 3'd6)      rd = {31'd0, o_mac_en[mk]};
            else if (is_mac && mj <= 3'd5) rd = {24'd0, o_mac[48*mk + 8*(5-mj) +: 8]};
            else sel = 1'b0;
        end
    endcase
end
assign o_SPIdata = sel ? rd : 32'bz;

endmodule
