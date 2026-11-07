//////////////////////////////////////////////////////////////////////////////////
//
// Design Name: OWIFI_RX
// Module Name: iq_capture
// Project Name: RA-Sentinel IQ snapshot transport (doc/iq_capture/SPEC.md §3/§4)
// Engineer: Tobias Weber
// Target Devices: Artix 7, XC7A100T (RASBB baseboard)
// Description:
//   FPGA1 capture block: mac_filter + iq_snapshot + iq_cap_regs + the dot11
//   trigger glue, in one wrapper so system_top_wbmc.v gets a single
//   instance and the block bench (tools/sim/tb_iq_capture.v) exercises
//   exactly what is integrated. Everything runs on clk_100M.
//
//   TRIGGER GLUE (SPEC §3, dot11 flavour):
//     arm     = rising edge of short_preamble_detected
//     commit  = pass_all     : mac_filter verdict (match or mismatch; SA parsed,
//                              or frame ended / ACK-CTS without Address 2)
//               else         : mac_filter match
//               ... AND, if require_fcs, deferred to fcs_stb & fcs_ok
//     abort   = receiver_rst | SIG invalid | mac mismatch (unless pass_all)
//               | fcs_stb & !fcs_ok (if require_fcs)
//     frame_end = fcs_stb (truncation mark)
//   Descriptor meta is latched at commit (SA, len, rate, ant_sel, flags);
//   fcs_ok is folded in if the FCS arrives before the slot is published.
//
//   TEST PATTERN (CAP_CTRL bit4): every 100ms a synthetic snapshot with
//   proto 255 - the sample stream is replaced by a ramp (channel c:
//   I = n + 256c, Q = ~I, 12-bit), arm+commit are generated internally,
//   dot11 is ignored. Lets the whole downstream chain (link, FPGA2, PC) be
//   verified without RF.
//
//   READ-OUT: iq_snapshot's port, passed through. SENT_COUNT counts slots
//   handed out (o_rd_last pulses).
//
//   PHASE COMPARISON (deliverable 4.b, phase_cmp.v): every arm the slot
//   buffer takes also starts a phase_cmp measurement on the same samples;
//   its result (3 x phase of ch1..3 vs ch0 + magnitude exponents) goes into
//   the descriptor's byte 44..47 word (10-bit phases, valid, weak) of that
//   frame, and - for the most recent frame that reached commit - into the
//   PH_STAT/PH1..3 registers (0x74..0x77) at full 16-bit resolution.
//
// Dependencies: mac_filter.v, iq_snapshot.v, iq_cap_regs.v, phase_cmp.v (+ cordic_vec.v)
//
// Additional Comments: https://github.com/Tobias-DG3YEV/RA-Sentinel
//
//////////////////////////////////////////////////////////////////////////////////
// Copyright (C) 2026 Tobias Weber
// License: GNU GPL v3
//////////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps

module iq_capture #(
    parameter NSLOT      = 4,
    parameter NSAMP_MAX  = 1024,
    parameter SLOT_W     = 2,
    parameter PTR_W      = 10,
    parameter ADDR_WIDTH = 7,
    parameter TEST_IVAL  = 10_000_000,      // 100ms at 100MHz
    parameter [31:0] LANE_TAP1_DEF = 32'd0, // iq_cap_regs 0x12 power-on value
    parameter [31:0] LANE_TAP2_DEF = 32'd0  // iq_cap_regs 0x0F power-on value
)(
    input  wire        i_clk,
    input  wire        i_rst,

    /* sample tap */
    input  wire        i_fe_valid,
    input  wire        i_smp_strobe,
    input  wire [95:0] i_smp,

    /* dot11 */
    input  wire        i_stf_det,
    input  wire        i_hdr_stb,
    input  wire        i_hdr_valid,
    input  wire [15:0] i_pkt_len,
    input  wire [7:0]  i_pkt_rate,
    input  wire        i_byte_stb,
    input  wire [7:0]  i_byte,
    input  wire        i_fcs_stb,
    input  wire        i_fcs_ok,
    input  wire        i_abort,          // receiver_rst
    input  wire        i_rx_idle,        // dot11 state == S_WAIT_POWER_TRIGGER
    input  wire [1:0]  i_ant_sel,

    /* dot11 frame statistics for the descriptor v2 (bytes 50..71): the CFO
       sync_short locked at the STF (its 16-sample autocorrelation phase,
       3216 units = one turn over 16 samples) and frame_stats.v's live
       accumulators */
    input  wire [15:0] i_cfo,
    input  wire [31:0] i_peg,
    input  wire [31:0] i_cpe_sum,
    input  wire [31:0] i_cpe_sq,
    input  wire [31:0] i_evm_sum,
    input  wire [15:0] i_evm_cnt,
    input  wire [15:0] i_nsym,

    /* config bus (conf_registers style) */
    input  wire [ADDR_WIDTH-1:0] i_SPI_addr,
    input  wire        i_SPI_wrStrobe,
    input  wire [31:0] i_SPIdata,
    inout  wire [31:0] o_SPIdata,

    /* link status in (JOB-04) */
    input  wire        i_fpga2_ready,
    input  wire        i_tx_busy,
    input  wire [31:0] i_heal_count,     // front-half self-heals (fe_valid watchdog), 0x72
    input  wire [31:0] i_stall_count,    // receiver-stall heals (no STF for 10 s), 0x73

    /* read-out port (JOB-04 snaplink_tx) */
    output wire [575:0] o_rd_desc,
    output wire         o_rd_valid,
    input  wire         i_rd_ready,
    output wire [95:0]  o_rd_inst,
    output wire         o_rd_inst_valid,
    output wire         o_rd_last,

    /* phase of the current frame, for the polar rim marker (df_frame) */
    input  wire [31:0] i_mark_dbg,
    input  wire [191:0] i_diag,       // 0x7A..0x7F link-health diagnostics (top)
    input  wire [5:0]  i_fh_state,    // 0x1A..0x1C fast link heal (top)
    input  wire [15:0] i_fh_rot,
    input  wire [31:0] i_fh_stat1,
    input  wire [31:0] i_fh_stat2,
    input  wire [31:0] i_df_stat,     // 0x1E DF_STAT (df_frame)
    input  wire [31:0] i_iqb_coef,    // 0x07 IQB_CTRL read-back {w_p, e_g}
    output wire [15:0] o_df_mode,     // 0x1D DF_MODE
    input  wire [31:0] i_mark_raw,
    output wire [15:0] o_ph_cal,
    output wire [7:0]  o_adc_skew,
    output wire [31:0] o_gain_trim,
    output wire [15:0] o_tap_ovr,
    output wire [31:0] o_lane_tap1,   // 0x12 LANE_TAP1
    output wire [31:0] o_lane_tap2,   // 0x0F LANE_TAP2
    output wire [1:0]  o_iqb_sel,     // 0x07 IQB_CTRL
    output wire [3:0]  o_iqb_bypass,
    output wire        o_iqb_clear_tog,
    output wire [47:0] o_mac0,        // MAC filter slot 0 (byte 0 in [47:40]) - the display's pinned station
    output wire        o_mac0_en,
    output wire [1:0]  o_fh_enable,
    output wire [1:0]  o_fh_force_tog,
    output wire [15:0] o_ph1_meta,
    output wire        o_ph_meta_valid,
    output reg         o_mac_hit,        // this frame's SA is in the MAC filter list: set by the
                                         // filter's match (byte 15), cleared at the next header
                                         // (display solo mode, DISP_CTRL b2)

    /* status */
    output wire        o_enabled,
    output wire        o_armed,
    output wire [SLOT_W:0] o_used
);

/*------------------------------------------------------------------*/
/* registers                                                        */
/*------------------------------------------------------------------*/
wire        cfg_enable, cfg_pass_all, cfg_require_fcs, cfg_clear, cfg_test, cfg_test_fast, cfg_free;
wire [15:0] cfg_nsamp, cfg_pretrig, cfg_ph_start, cfg_ph_len, cfg_ph_cal;
wire [8*48-1:0] cfg_mac;
wire [7:0]  cfg_mac_en;
assign o_mac0    = cfg_mac[47:0];
assign o_mac0_en = cfg_mac_en[0];
reg  [31:0] trig_count, match_count, sent_count;
reg  [31:0] rd_xor;                      // RD_XOR 0x71: XOR of all instants read out
reg  [15:0] ph_count;                    // PH_STAT 0x74: committed frames with a phase result
reg  [31:0] ph_reg1, ph_reg2, ph_reg3;   // 0x75..0x77 {exp[5:0], phase[15:0]} of the last committed frame
reg         ph_reg_weak, ph_reg_valid;
wire [31:0] drop_count;

iq_cap_regs #(.ADDR_WIDTH(ADDR_WIDTH), .NSAMP_MAX(NSAMP_MAX),
              .LANE_TAP1_DEF(LANE_TAP1_DEF), .LANE_TAP2_DEF(LANE_TAP2_DEF)) u_regs (
    .i_clock(i_clk), .i_reset(i_rst),
    .i_SPI_addr(i_SPI_addr), .i_SPI_wrStrobe(i_SPI_wrStrobe),
    .i_SPIdata(i_SPIdata), .o_SPIdata(o_SPIdata),
    .o_enable(cfg_enable), .o_pass_all(cfg_pass_all), .o_require_fcs(cfg_require_fcs),
    .o_clear(cfg_clear), .o_test_pattern(cfg_test), .o_test_fast(cfg_test_fast), .o_free_run(cfg_free),
    .o_nsamp(cfg_nsamp), .o_pretrig(cfg_pretrig),
    .o_ph_start(cfg_ph_start), .o_ph_len(cfg_ph_len), .o_ph_cal(cfg_ph_cal), .o_adc_skew(o_adc_skew), .o_gain_trim(o_gain_trim), .o_tap_ovr(o_tap_ovr),
    .o_lane_tap1(o_lane_tap1), .o_lane_tap2(o_lane_tap2), .o_iqb_sel(o_iqb_sel), .o_iqb_bypass(o_iqb_bypass),
    .o_iqb_clear_tog(o_iqb_clear_tog), .i_iqb_coef(i_iqb_coef),
    .o_fh_enable(o_fh_enable), .o_fh_force_tog(o_fh_force_tog),
    .o_mac(cfg_mac), .o_mac_en(cfg_mac_en),
    .i_trig_count(trig_count), .i_match_count(match_count),
    .i_drop_count(drop_count), .i_sent_count(sent_count),
    .i_fpga2_ready(i_fpga2_ready), .i_tx_busy(i_tx_busy), .i_rd_xor(rd_xor),
    .i_heal_count(i_heal_count), .i_stall_count(i_stall_count),
    .i_ph_stat({14'd0, ph_reg_valid, ph_reg_weak, ph_count}),
    .i_ph1(ph_reg1), .i_ph2(ph_reg2), .i_ph3(ph_reg3),
    .i_mark_dbg(i_mark_dbg), .i_mark_raw(i_mark_raw), .i_diag(i_diag),
    .i_fh_state(i_fh_state), .i_fh_rot(i_fh_rot), .i_fh_stat1(i_fh_stat1), .i_fh_stat2(i_fh_stat2),
    .i_df_stat(i_df_stat), .o_df_mode(o_df_mode)
);
assign o_ph_cal = cfg_ph_cal;
assign o_enabled = cfg_enable;

/*------------------------------------------------------------------*/
/* MAC filter                                                       */
/*------------------------------------------------------------------*/
wire        mf_match, mf_mismatch, mf_sa_valid;
wire [47:0] mf_sa;
wire [2:0]  mf_slot;

mac_filter #(.NSLOT(8)) u_mf (
    .i_clk(i_clk), .i_rst(i_rst),
    .i_hdr_stb(i_hdr_stb), .i_hdr_valid(i_hdr_valid),
    .i_byte_stb(i_byte_stb), .i_byte(i_byte),
    .i_fcs_stb(i_fcs_stb), .i_abort(i_abort),
    .i_mac(cfg_mac), .i_en(cfg_mac_en),
    .o_match_stb(mf_match), .o_mismatch_stb(mf_mismatch),
    .o_sa(mf_sa), .o_sa_valid(mf_sa_valid), .o_hit_slot(mf_slot)
);

always @(posedge i_clk) begin
    if (i_rst || i_hdr_stb) o_mac_hit <= 1'b0;
    else if (mf_match)      o_mac_hit <= 1'b1;
end

/*------------------------------------------------------------------*/
/* test pattern source                                              */
/*------------------------------------------------------------------*/
reg [23:0] tp_timer;
reg [2:0]  tp_div;
reg [11:0] tp_n;
reg        tp_strobe, tp_arm, tp_commit;
reg [95:0] tp_smp;
always @(posedge i_clk) begin
    tp_strobe <= 1'b0; tp_arm <= 1'b0; tp_commit <= tp_arm;
    if (i_rst || !(cfg_test || cfg_free)) begin
        tp_timer <= 24'd0; tp_div <= 3'd0; tp_n <= 12'd0; tp_smp <= 96'd0;
    end
    else begin
        if (tp_div == 3'd4) begin
            tp_div    <= 3'd0;
            tp_strobe <= 1'b1;
            tp_n      <= tp_n + 12'd1;
            tp_smp    <= { tp_n + 12'd768, ~(tp_n + 12'd768),
                           tp_n + 12'd512, ~(tp_n + 12'd512),
                           tp_n + 12'd256, ~(tp_n + 12'd256),
                           tp_n,           ~tp_n };
        end
        else tp_div <= tp_div + 3'd1;
        if (tp_timer >= (cfg_test_fast ? (TEST_IVAL / 100) - 1 : TEST_IVAL - 1)) begin
            tp_timer <= 24'd0;
            tp_arm   <= 1'b1;
        end
        else tp_timer <= tp_timer + 24'd1;
    end
end

/*------------------------------------------------------------------*/
/* trigger glue                                                     */
/*------------------------------------------------------------------*/
reg  stf_d;
always @(posedge i_clk) stf_d <= i_stf_det;
wire stf_rise = i_stf_det & ~stf_d;
wire sig_valid   = i_hdr_stb &  i_hdr_valid;
wire sig_invalid = i_hdr_stb & ~i_hdr_valid;

/* phase_cmp result (declared here, instance below) */
wire        pc_done, pc_busy, pc_weak;
wire [15:0] pc_ph1, pc_ph2, pc_ph3;
wire [5:0]  pc_exp1, pc_exp2, pc_exp3;

/* per-frame decision state */
reg        want_fcs;          // committed on MAC/pass_all, waiting for fcs (require_fcs)
reg        armed_frame;
reg        meta_match, meta_pass, meta_hdr, meta_fcs_ok;
reg [15:0] meta_len;
reg [7:0]  meta_rate;
reg [1:0]  meta_ant;
reg [47:0] meta_sa;
reg        meta_ph_valid, meta_ph_weak;   // phase_cmp result of this frame
reg [15:0] meta_ph1, meta_ph2, meta_ph3;
reg [5:0]  meta_exp1, meta_exp2, meta_exp3;
reg        frame_committed, ph_latched;
reg        meta_frame_end;   // fcs strobe seen since the arm: frame statistics complete

/* timer-armed modes: the test pattern (synthetic samples) and free-run (live
   samples, idle noise spectra, 2026-10-03) - both without a frame verdict */
wire t_mode   = cfg_test | cfg_free;
wire d_arm    = t_mode   ? tp_arm    : (stf_rise & cfg_enable);
wire d_strobe = cfg_test ? tp_strobe : i_smp_strobe;
wire [95:0] d_smp = cfg_test ? tp_smp : i_smp;

/* commit / abort decisions (dot11 path) */
/* frame accepted by the filter. pass_all waits for the MAC verdict (match OR
   mismatch = byte 15 parsed, or frame ended / ACK-CTS without Address 2) so the
   descriptor carries the SA; committing at SIG published 6 Mbps frames at 51.2 us
   before their SA had been decoded (JOB-07: 65 % of on-air snapshots had SA 0). */
wire accept_now = cfg_pass_all ? (mf_match | mf_mismatch) : mf_match;
wire mismatch   = ~cfg_pass_all & mf_mismatch;
wire d_commit_dot11 = cfg_require_fcs ? (i_fcs_stb & i_fcs_ok & (want_fcs | accept_now))
                                      : accept_now;
wire d_abort_dot11  = i_abort | sig_invalid | mismatch |
                      (cfg_require_fcs & i_fcs_stb & ~i_fcs_ok);

wire d_commit    = t_mode ? tp_commit : d_commit_dot11;
wire d_abort     = t_mode ? 1'b0      : d_abort_dot11;
wire d_frame_end = t_mode ? 1'b0      : i_fcs_stb;
wire d_idle      = t_mode ? 1'b0      : i_rx_idle;

always @(posedge i_clk) begin
    if (i_rst) begin
        want_fcs <= 1'b0; armed_frame <= 1'b0;
        meta_match <= 1'b0; meta_pass <= 1'b0; meta_hdr <= 1'b0; meta_fcs_ok <= 1'b0;
        meta_len <= 16'd0; meta_rate <= 8'd0; meta_ant <= 2'd0; meta_sa <= 48'd0;
        trig_count <= 32'd0; match_count <= 32'd0; sent_count <= 32'd0; rd_xor <= 32'd0;
        meta_ph_valid <= 1'b0; meta_ph_weak <= 1'b0; meta_ph1 <= 16'd0; meta_ph2 <= 16'd0; meta_ph3 <= 16'd0;
        meta_exp1 <= 6'd0; meta_exp2 <= 6'd0; meta_exp3 <= 6'd0; frame_committed <= 1'b0; ph_latched <= 1'b0;
        meta_frame_end <= 1'b0;
        ph_count <= 16'd0; ph_reg1 <= 32'd0; ph_reg2 <= 32'd0; ph_reg3 <= 32'd0; ph_reg_weak <= 1'b0; ph_reg_valid <= 1'b0;
    end
    else begin
        if (cfg_clear) begin trig_count <= 32'd0; match_count <= 32'd0; sent_count <= 32'd0; rd_xor <= 32'd0; ph_count <= 16'd0; end
        if (d_arm)     trig_count  <= trig_count + 32'd1;
        if (mf_match)  match_count <= match_count + 32'd1;
        if (o_rd_last) sent_count  <= sent_count + 32'd1;
        if (o_rd_inst_valid) rd_xor <= {rd_xor[30:0], rd_xor[31]} ^ o_rd_inst[31:0] ^ o_rd_inst[63:32] ^ o_rd_inst[95:64];

        /* meta reset only for an arm the slot buffer takes (o_armed low): a
           second STF edge during a running capture must not wipe the header
           and SA already latched (JOB-07: 2.7 % of snapshots had rate 0 / SA 0) */
        if (d_arm & ~o_armed) begin
            armed_frame <= 1'b1; want_fcs <= 1'b0;
            meta_match <= 1'b0; meta_pass <= cfg_pass_all; meta_hdr <= 1'b0;
            meta_fcs_ok <= 1'b0; meta_len <= 16'd0; meta_rate <= 8'd0;
            meta_ant <= i_ant_sel; meta_sa <= 48'd0;
            meta_ph_valid <= 1'b0; frame_committed <= 1'b0; ph_latched <= 1'b0;
            meta_frame_end <= 1'b0;
        end
        /* phase result of this frame: into the descriptor meta, and into the
           registers once the frame has also reached commit (either order) */
        if (pc_done) begin
            meta_ph_valid <= 1'b1; meta_ph_weak <= pc_weak;
            meta_ph1 <= pc_ph1; meta_ph2 <= pc_ph2; meta_ph3 <= pc_ph3;
            meta_exp1 <= pc_exp1; meta_exp2 <= pc_exp2; meta_exp3 <= pc_exp3;
        end
        if (d_commit) frame_committed <= 1'b1;
        if (!ph_latched && ((pc_done && (frame_committed || d_commit)) || (d_commit && meta_ph_valid))) begin
            ph_latched   <= 1'b1;
            ph_count     <= ph_count + 16'd1;
            ph_reg_valid <= 1'b1;
            ph_reg_weak  <= pc_done ? pc_weak : meta_ph_weak;
            ph_reg1      <= pc_done ? {10'd0, pc_exp1, pc_ph1} : {10'd0, meta_exp1, meta_ph1};
            ph_reg2      <= pc_done ? {10'd0, pc_exp2, pc_ph2} : {10'd0, meta_exp2, meta_ph2};
            ph_reg3      <= pc_done ? {10'd0, pc_exp3, pc_ph3} : {10'd0, meta_exp3, meta_ph3};
        end
        if (sig_valid) begin
            meta_hdr <= 1'b1; meta_len <= i_pkt_len; meta_rate <= i_pkt_rate;
        end
        /* SA only on this frame's verdict: mf_sa_valid is a level that outlives
           the frame, so a frame without Address 2 must not inherit the last SA */
        if ((mf_match | mf_mismatch) & mf_sa_valid) meta_sa <= mf_sa;
        if (mf_match)    meta_match <= 1'b1;
        if (accept_now)  want_fcs <= cfg_require_fcs;
        if (i_fcs_stb)   begin meta_fcs_ok <= i_fcs_ok; want_fcs <= 1'b0; meta_frame_end <= 1'b1; end
        if (d_abort | i_rx_idle) armed_frame <= 1'b0;
    end
end

/*------------------------------------------------------------------*/
/* phase comparison (4.b)                                           */
/*------------------------------------------------------------------*/
phase_cmp u_ph (
    .i_clk(i_clk), .i_rst(i_rst),
    .i_smp_strobe(d_strobe), .i_smp(d_smp),
    .i_arm(d_arm & ~o_armed), .i_abort(d_abort),
    .i_start(cfg_ph_start), .i_len(cfg_ph_len),
    .o_busy(pc_busy), .o_done(pc_done),
    .o_ph1(pc_ph1), .o_ph2(pc_ph2), .o_ph3(pc_ph3),
    .o_exp1(pc_exp1), .o_exp2(pc_exp2), .o_exp3(pc_exp3), .o_weak(pc_weak)
);
wire [31:0] meta_phase = {meta_ph_weak, meta_ph_valid, meta_ph3[15:6], meta_ph2[15:6], meta_ph1[15:6]};
assign o_ph1_meta = meta_ph1;
/* marker gate: pair 1 only (the all-pairs weak flag would suppress the
   marker whenever ch2/ch3 vs ch0 are weak, which on WBMC is most frames) */
assign o_ph_meta_valid = meta_ph_valid & (meta_exp1 >= 6'd18);

/*------------------------------------------------------------------*/
/* slot buffer                                                      */
/*------------------------------------------------------------------*/
iq_snapshot #(.NSLOT(NSLOT), .NSAMP_MAX(NSAMP_MAX), .SLOT_W(SLOT_W), .PTR_W(PTR_W)) u_snap (
    .i_clk(i_clk), .i_rst(i_rst),
    .i_fe_valid(cfg_test | i_fe_valid), .i_smp_strobe(d_strobe), .i_smp(d_smp),
    .i_enable(cfg_enable | t_mode), .i_nsamp(cfg_nsamp), .i_pretrig(cfg_pretrig),
    .i_clear(cfg_clear),
    .i_arm(d_arm), .i_commit(d_commit), .i_abort(d_abort),
    .i_frame_end(d_frame_end), .i_idle(d_idle),
    .i_meta_proto(cfg_test ? 8'd255 : cfg_free ? 8'd254 : 8'd0),
    .i_meta_pkt_len(meta_len), .i_meta_mac_sa(meta_sa), .i_meta_rate(meta_rate),
    .i_meta_ant_sel(meta_ant),
    .i_meta_fcs_ok(meta_fcs_ok | (i_fcs_stb & i_fcs_ok)),
    .i_meta_mac_match(meta_match | mf_match), .i_meta_pass_all(meta_pass),
    .i_meta_header_valid(meta_hdr | sig_valid),
    .i_meta_match_count(match_count), .i_meta_trig_count(trig_count),
    .i_meta_phase(meta_phase),
    .i_meta_cfo(t_mode ? 16'd0 : i_cfo), .i_meta_peg(t_mode ? 32'd0 : i_peg),
    .i_meta_cpe_sum(t_mode ? 32'd0 : i_cpe_sum), .i_meta_cpe_sq(t_mode ? 32'd0 : i_cpe_sq),
    .i_meta_evm_sum(t_mode ? 32'd0 : i_evm_sum), .i_meta_evm_cnt(t_mode ? 16'd0 : i_evm_cnt),
    .i_meta_nsym(t_mode ? 16'd0 : i_nsym),
    .i_meta_frame_end(t_mode ? 1'b0 : (meta_frame_end | i_fcs_stb)),
    .o_drop_count(drop_count), .o_seq(),
    .o_armed(o_armed), .o_used(o_used),
    .o_rd_desc(o_rd_desc), .o_rd_valid(o_rd_valid), .i_rd_ready(i_rd_ready),
    .o_rd_inst(o_rd_inst), .o_rd_inst_valid(o_rd_inst_valid), .o_rd_last(o_rd_last)
);

endmodule
