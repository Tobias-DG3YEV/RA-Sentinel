//////////////////////////////////////////////////////////////////////////////////
//
// Design Name: OWIFI_RX
// Module Name: df_frame
// Project Name: RA-Sentinel 802.11 receiver + direction finder
// Target Devices: Artix 7, XC7A100T (RASBB U10 + RASRF2400WBMC)
// Description:
//   Per-FRAME amplitude-comparison direction finder. RASPMO's df_amp.v runs
//   per FFT bin off the spectrum RAMs; this is the same math run once per
//   received 802.11 frame off the four averaged STF powers from ant_select:
//
//     latch P[0..3] at short-preamble detect
//       -> log2 (Q5.3, 1 LSB = 0.376dB of power - the same count scale as
//          RASPMO's logfn, so df_amp's explut applies unchanged)
//       -> normalise to the strongest beam, clamp to the 24dB LUT window
//       -> back to linear power through explut()
//       -> X = P_east - P_west, Y = P_north - P_south
//       -> bearing = atan2(Y, X) via cordic_vec, confidence = |(X,Y)|
//
//   See df_amp.v's header for why this normalise-then-linearise order is
//   load-bearing and why amplitude (not phase) is the method on this array.
//
//   COMMIT AND PERSISTENCE. The bearing is measured at STF time but committed
//   into the angle table only when the frame completes (i_fcs_stb); a
//   watchdog abort commits nothing. FCS-bad frames depend on SHOW_BAD (and
//   on i_show_bad, the run-time switch of the same thing - DISP_CTRL 0x0C):
//   0 never, 1 always (red FRQ_BAD rays), 2 only when their source MAC is
//   valid - the frame is parked at i_fcs_stb and committed (FRQ_BAD) when
//   frame_log's station event (i_adm_stb, ~50 clocks later) reports it
//   admitted with a bad FCS, which frame_log does only for an SA already in
//   its list, i.e. once seen with a good FCS. No event within ADM_WAIT
//   clocks (unknown SA, no SA, list busy repainting) drops the ray. Unlike df_amp's per-video-frame double buffer - right for a
//   display fed ~81 sweeps per frame - frames here are sparse, so the table
//   is a single buffer whose entries DECAY: every DECAY_US microseconds one
//   sweep walks all 512 bins and shrinks each ray by 1/8 (floor 1, to zero).
//   A fresh frame paints a full ray that fades out over a couple of seconds,
//   and repeated traffic from one bearing holds its ray solid.
//
//   The table entry is {frq, len} exactly as polar_view.v expects on its
//   registered read port; frq carries the FCS verdict as a freqmap colour
//   code rather than a frequency (FRQ_OK / FRQ_BAD parameters).
//
//   o_brg_idx/o_brg_ok hold the most recent measurement from STF time until
//   the next one - frame_log captures them at pkt_header_valid_strobe, which
//   always lands between those two points, and prints the BRG column.
//
//   Only one measurement is ever in flight: short-preamble detections are
//   separated by at least a SIGNAL decode (~tens of us) while the pipeline
//   is ~25 clocks, so plain hold registers replace df_amp's delay lines.
//
//   SOLO (2026-10-04, DISP_CTRL b2). With i_solo only frames whose source
//   MAC is in the capture MAC filter list (i_mac_hit at i_fcs_stb) commit a
//   ray; all others are measured (o_brg_idx, the station list's BRG column)
//   but not drawn - one transmitter's ray on an otherwise empty disc.
//
//   PATTERN TABLE (2026-09-25, DF_MODE 0x1D). With i_pat_en the formula's
//   bearing only centres a search: df_pattern.v matches the four normalised
//   levels against a measured table of the array's response within
//   +-i_pat_halfwin bins of it and its best bin replaces the ray's bearing
//   (~1.3 us later, long before frame_log or the commit read it). The
//   length/confidence gating stays the formula's. o_df_stat (DF_STAT) =
//   {valid, score[21:16], table bin, 7'b0, formula bin} of the last measurement.
//
// Dependencies: cordic_vec.v, dp_ram.v (both from the RASPMO repo), df_pattern.v
//
// Additional Comments: https://github.com/Tobias-DG3YEV/RA-Sentinel
//
//////////////////////////////////////////////////////////////////////////////////
// Copyright (C) 2026 Tobias Weber
// License: GNU GPL v3
//////////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps

module df_frame #(
    parameter PWRW    = 25,
    parameter ANGBITS = 9,          // 512 angle bins (0.703deg each)
    parameter FRQBITS = 8,
    parameter CH_E    = 0,          // channel index of the antenna facing east
    parameter CH_N    = 1,          //                                    north
    parameter CH_W    = 2,          //                                    west
    parameter CH_S    = 3,          //                                    south
    parameter [10:0] DIR_MIN   = 11'd24, // min |(X,Y)| for a trustworthy bearing
    parameter [7:0]  LEN_FLOOR = 8'd96,  // log2q3 counts; below this no ray
    parameter        LEN_SHIFT = 1,      // ray length = (l2max-floor) << this
    parameter [7:0]  FRQ_OK    = 8'd96,  // freqmap colour code, FCS good
    parameter [7:0]  FRQ_BAD   = 8'd224, // freqmap colour code, FCS bad
    parameter        SHOW_BAD  = 0,      // FCS-bad frames: 0 never, 1 always, 2 listed SA only (FRQ_BAD)
    parameter [9:0]  ADM_WAIT  = 10'd1000, // SHOW_BAD 2: clocks to wait for the station event
    parameter [15:0] DECAY_US  = 16'd50000, // us between decay sweeps
    parameter        STAGES    = 16,
    parameter        CGUARD    = 10,
    parameter        TABLE_FILE = ""  // df_pattern ROM ($readmemh), "" = empty table
)(
    input  wire                i_clk,      // receiver domain (100MHz)
    input  wire                i_rst,
    input  wire                i_us_tick,
    input  wire [4*PWRW-1:0]   i_pwr,      // ant_select averages, [c*PWRW +: PWRW]
    input  wire [31:0]         i_gain_trim,// GAIN_TRIM 0x18: 4 x signed 8-bit, ch c at [8c +: 8],
                                           // added to log2q3 power (1 LSB = 0.376 dB), 0 = off
    input  wire                i_stf_det,  // dot11 o_short_preamble_detected
    input  wire                i_fcs_stb,  // frame completed
    input  wire                i_fcs_ok,
    input  wire                i_abort,    // watchdog receiver_rst
    input  wire                i_show_bad, // 1 = FCS-bad frames as SHOW_BAD says, 0 = never (DISP_CTRL b1)
    input  wire                i_adm_stb,  // frame_log station event: frame admitted to the list
    input  wire                i_adm_fcs,  // ...and its FCS verdict (SHOW_BAD 2)
    input  wire                i_solo,     // 1 = rays only for frames with i_mac_hit (DISP_CTRL b2)
    input  wire                i_mac_hit,  // the frame's SA is in the MAC filter list (valid at i_fcs_stb)

    output wire [ANGBITS-1:0]  o_brg_idx,  // last bearing, held
    output wire                o_brg_ok,   // ...and its confidence gate

    /* pattern-table refinement (DF_MODE 0x1D) */
    input  wire                i_pat_en,
    input  wire [7:0]          i_pat_halfwin,
    output wire [31:0]         o_df_stat,  // DF_STAT 0x1E

    /* phase comparison of the same frame (phase_cmp via iq_capture), latched
       at commit for the rim marker (phase_marker.v) */
    input  wire [15:0]         i_ph_ang,   // ch1 vs ch0, binary turns
    input  wire                i_ph_valid,
    input  wire [15:0]         i_ph_cal,   // PH_CAL: subtracted before the marker (per-boot LO offset)
    output reg  [ANGBITS-1:0]  o_mark_ang, // calibrated marker angle bin
    output reg                 o_mark_ok,
    output reg  [15:0]         o_mark_cnt, // commits that carried a phase (debug readback)
    output reg  [ANGBITS-1:0]  o_mark_raw, // uncalibrated phase bin of the marker frame
    output reg  [ANGBITS-1:0]  o_mark_brg, // amplitude bearing bin of the same frame (the ray)

    /* angle table read port, pixel domain (polar_view) */
    input  wire                i_rdClk,
    input  wire [ANGBITS-1:0]  i_rdAddr,
    output wire [7:0]          o_rdLen,
    output wire [FRQBITS-1:0]  o_rdFrq
);

/* log2 in Q5.3: MSB position plus the next three bits; 1 LSB = 0.376dB of
   power. Same function as frame_log.v's. log2q3(0) = 0 by construction. */
function [7:0] log2q3;
    input [31:0] v;
    integer k;
    reg [4:0] p;
    reg [31:0] sh;
    begin
        p = 5'd0;
        for (k = 0; k < 32; k = k + 1)
            if (v[k]) p = k[4:0];
        sh = v << (5'd31 - p);
        log2q3 = {p, sh[30:28]};
    end
endfunction

/* Normalised-log -> linear power, 255 * 10^(-0.376*d/10) - identical to
   df_amp.v's explut(), same 64-entry / 24dB window. */
function [7:0] explut;
    input [5:0] d;
    begin
        case (d)
            0: explut = 8'd255; 1: explut = 8'd234; 2: explut = 8'd214; 3: explut = 8'd197;
            4: explut = 8'd180; 5: explut = 8'd165; 6: explut = 8'd152; 7: explut = 8'd139;
            8: explut = 8'd128; 9: explut = 8'd117; 10: explut = 8'd107; 11: explut = 8'd98;
            12: explut = 8'd90; 13: explut = 8'd83; 14: explut = 8'd76; 15: explut = 8'd70;
            16: explut = 8'd64; 17: explut = 8'd59; 18: explut = 8'd54; 19: explut = 8'd49;
            20: explut = 8'd45; 21: explut = 8'd41; 22: explut = 8'd38; 23: explut = 8'd35;
            24: explut = 8'd32; 25: explut = 8'd29; 26: explut = 8'd27; 27: explut = 8'd25;
            28: explut = 8'd23; 29: explut = 8'd21; 30: explut = 8'd19; 31: explut = 8'd17;
            32: explut = 8'd16; 33: explut = 8'd15; 34: explut = 8'd13; 35: explut = 8'd12;
            36: explut = 8'd11; 37: explut = 8'd10; 38: explut = 8'd10; 39: explut = 8'd9;
            40: explut = 8'd8;  41: explut = 8'd7;  42: explut = 8'd7;  43: explut = 8'd6;
            44: explut = 8'd6;  45: explut = 8'd5;  46: explut = 8'd5;  47: explut = 8'd4;
            48: explut = 8'd4;  49: explut = 8'd4;  50: explut = 8'd3;  51: explut = 8'd3;
            52: explut = 8'd3;  53: explut = 8'd3;  54: explut = 8'd2;  55: explut = 8'd2;
            56: explut = 8'd2;  57: explut = 8'd2;  58: explut = 8'd2;  59: explut = 8'd2;
            default: explut = 8'd1;
        endcase
    end
endfunction

/****************************************************************************/
/* Measurement pipeline, launched on the STF-detect rising edge             */
/****************************************************************************/
reg stf_d;
always @(posedge i_clk) stf_d <= i_rst ? 1'b0 : i_stf_det;
wire stf_rise = i_stf_det & ~stf_d;

/* s0: latch the four powers */
reg        s0_v;
reg [PWRW-1:0] p_lat [0:3];
always @(posedge i_clk) begin
    s0_v <= i_rst ? 1'b0 : stf_rise;
    if (stf_rise) begin
        p_lat[0] <= i_pwr[0*PWRW +: PWRW];
        p_lat[1] <= i_pwr[1*PWRW +: PWRW];
        p_lat[2] <= i_pwr[2*PWRW +: PWRW];
        p_lat[3] <= i_pwr[3*PWRW +: PWRW];
    end
end

/* s1: log2 of each, plus the per-channel gain trim (GAIN_TRIM 0x18). The
   trim corrects fixed gain differences between the four receive paths
   (cable, front end, ADC channel - measured with a split test signal, see
   doc/iq_capture/VALIDATION.md s7.4), so the bearing compares antenna
   levels, not path gains. Log domain: 1 LSB = 0.376 dB, saturating 0..255;
   a zero power (log 0) stays 0. The antenna selection (ant_select) uses the
   untrimmed linear powers. */
function [7:0] trim_add;
    input [7:0] l;
    input signed [7:0] t;
    reg signed [9:0] v;
    begin
        v = $signed({2'b00, l}) + t;
        trim_add = (l == 8'd0) ? 8'd0 : (v < 0) ? 8'd0 : (v > 10'sd255) ? 8'd255 : v[7:0];
    end
endfunction
reg       s1_v;
reg [7:0] l2 [0:3];
always @(posedge i_clk) begin
    s1_v  <= i_rst ? 1'b0 : s0_v;
    l2[0] <= trim_add(log2q3({{(32-PWRW){1'b0}}, p_lat[0]}), i_gain_trim[ 7: 0]);
    l2[1] <= trim_add(log2q3({{(32-PWRW){1'b0}}, p_lat[1]}), i_gain_trim[15: 8]);
    l2[2] <= trim_add(log2q3({{(32-PWRW){1'b0}}, p_lat[2]}), i_gain_trim[23:16]);
    l2[3] <= trim_add(log2q3({{(32-PWRW){1'b0}}, p_lat[3]}), i_gain_trim[31:24]);
end

/* s2: strongest beam */
wire [7:0] m01 = (l2[0] > l2[1]) ? l2[0] : l2[1];
wire [7:0] m23 = (l2[2] > l2[3]) ? l2[2] : l2[3];
reg        s2_v;
reg [7:0]  s2_max;
reg [7:0]  s2_l2 [0:3];
always @(posedge i_clk) begin
    s2_v     <= i_rst ? 1'b0 : s1_v;
    s2_max   <= (m01 > m23) ? m01 : m23;
    s2_l2[0] <= l2[0];
    s2_l2[1] <= l2[1];
    s2_l2[2] <= l2[2];
    s2_l2[3] <= l2[3];
end

/* s3: normalised difference per channel, clamped to the LUT window; the
   strongest beam's level is held for the ray length (single measurement in
   flight - see header). */
wire [7:0] dd0 = s2_max - s2_l2[0];
wire [7:0] dd1 = s2_max - s2_l2[1];
wire [7:0] dd2 = s2_max - s2_l2[2];
wire [7:0] dd3 = s2_max - s2_l2[3];
reg       s3_v;
reg [7:0] amp_hold;
reg [5:0] s3_c [0:3];
always @(posedge i_clk) begin
    s3_v <= i_rst ? 1'b0 : s2_v;
    if (s2_v) amp_hold <= s2_max;
    s3_c[0] <= (dd0 > 8'd63) ? 6'd63 : dd0[5:0];
    s3_c[1] <= (dd1 > 8'd63) ? 6'd63 : dd1[5:0];
    s3_c[2] <= (dd2 > 8'd63) ? 6'd63 : dd2[5:0];
    s3_c[3] <= (dd3 > 8'd63) ? 6'd63 : dd3[5:0];
end

/* s4: back to linear */
reg       s4_v;
reg [7:0] s4_lin [0:3];
always @(posedge i_clk) begin
    s4_v      <= i_rst ? 1'b0 : s3_v;
    s4_lin[0] <= explut(s3_c[0]);
    s4_lin[1] <= explut(s3_c[1]);
    s4_lin[2] <= explut(s3_c[2]);
    s4_lin[3] <= explut(s3_c[3]);
end

/* s5: the two Fourier differences, into the CORDIC */
reg signed [9:0] s5_x, s5_y;
reg              s5_v;
always @(posedge i_clk) begin
    s5_v <= i_rst ? 1'b0 : s4_v;
    s5_x <= $signed({2'b00, s4_lin[CH_E]}) - $signed({2'b00, s4_lin[CH_W]});
    s5_y <= $signed({2'b00, s4_lin[CH_N]}) - $signed({2'b00, s4_lin[CH_S]});
end

wire [11:0] cd_mag;
wire [15:0] cd_ang;
wire        cd_vld;

cordic_vec #(.XYW(10), .STAGES(STAGES), .GUARD(CGUARD)) cordic_df (
    .i_clk(i_clk),
    .i_ce(1'b1),
    .i_valid(s5_v),
    .i_x(s5_x),
    .i_y(s5_y),
    .o_mag(cd_mag),
    .o_ang(cd_ang),
    .o_valid(cd_vld)
);

/* pattern-table refinement, centred on the formula's bearing */
wire               pat_vld;
wire [ANGBITS-1:0] pat_bin;
wire [21:0]        pat_score;
df_pattern #(.ANGBITS(ANGBITS), .TABLE_FILE(TABLE_FILE)) pattern_inst (
    .i_clk(i_clk),
    .i_rst(i_rst),
    .i_start(cd_vld & i_pat_en),
    .i_center(cd_ang[15 -: ANGBITS]),
    .i_halfwin(i_pat_halfwin),
    .i_d0(s3_c[0]), .i_d1(s3_c[1]), .i_d2(s3_c[2]), .i_d3(s3_c[3]),
    .o_valid(pat_vld),
    .o_bin(pat_bin),
    .o_score(pat_score)
);
reg [ANGBITS-1:0] dbg_form, dbg_pat;
reg [5:0]         dbg_score;
reg               dbg_pvld;
always @(posedge i_clk) begin
    if (i_rst) begin
        dbg_form <= {ANGBITS{1'b0}}; dbg_pat <= {ANGBITS{1'b0}}; dbg_score <= 6'd0; dbg_pvld <= 1'b0;
    end
    else begin
        if (cd_vld) begin dbg_form <= cd_ang[15 -: ANGBITS]; dbg_pvld <= 1'b0; end
        if (pat_vld) begin dbg_pat <= pat_bin; dbg_score <= pat_score[21:16]; dbg_pvld <= 1'b1; end
    end
end
/* DF_STAT: [8:0] formula bin, [24:16] table bin, [30:25] score[21:16], [31] table result valid */
assign o_df_stat = {dbg_pvld, dbg_score, dbg_pat, {(16-ANGBITS){1'b0}}, dbg_form};

/* ray length from the strongest beam's level */
wire        above_floor = (amp_hold > LEN_FLOOR);
wire [8:0]  len_raw     = {1'b0, (amp_hold - LEN_FLOOR)} << LEN_SHIFT;
wire [7:0]  len_sat     = len_raw[8] ? 8'hFF : len_raw[7:0];

/* pending measurement: held for frame_log and for the commit at frame end */
reg [ANGBITS-1:0] pend_idx;
reg [7:0]         pend_len;
reg               pend_ok;

/* calibrated phase for the marker: modular subtraction in binary turns */
wire [15:0] ph_cal = i_ph_ang - i_ph_cal;

/* commit request toward the table FSM (one deep; frames are far apart) */
reg               req_commit;
reg [ANGBITS-1:0] req_idx;
reg [7:0]         req_len;
reg [FRQBITS-1:0] req_frq;
wire              req_taken;   // from the FSM below

/* SHOW_BAD 2: an FCS-bad frame parked until the station list has ruled on
   its SA. Every frame end re-parks (or clears) it, so a late event can never
   commit an older frame. */
reg               bad_wait;    // parked, waiting for i_adm_stb
reg               bad_go;      // admitted: commit once the request slot is free
reg [9:0]         bad_age;
reg [ANGBITS-1:0] bad_idx;
reg [7:0]         bad_len;
reg               bad_phv;
reg [ANGBITS-1:0] bad_ph_cal;
reg [ANGBITS-1:0] bad_ph_raw;

wire solo_ok     = !i_solo || i_mac_hit;
wire good_commit = i_fcs_stb && pend_ok && solo_ok && (i_fcs_ok || (SHOW_BAD == 1 && i_show_bad));
wire bad_commit  = bad_go && !req_commit;

always @(posedge i_clk) begin
    if (i_rst) begin
        pend_idx   <= {ANGBITS{1'b0}};
        pend_len   <= 8'd0;
        pend_ok    <= 1'b0;
        req_commit <= 1'b0;
        bad_wait   <= 1'b0;
        bad_go     <= 1'b0;
        bad_age    <= 10'd0;
        o_mark_ang <= {ANGBITS{1'b0}}; o_mark_ok <= 1'b0; o_mark_cnt <= 16'd0;
        o_mark_raw <= {ANGBITS{1'b0}}; o_mark_brg <= {ANGBITS{1'b0}};
    end
    else begin
        /* the table's bin replaces the formula's once the search is done
           (a new measurement's cd_vld below wins in the same clock) */
        if (pat_vld)
            pend_idx <= pat_bin;
        if (cd_vld) begin
            pend_idx <= cd_ang[15 -: ANGBITS];
            pend_len <= len_sat;
            pend_ok  <= above_floor && (cd_mag > {1'b0, DIR_MIN});
        end
        else if (i_abort)
            pend_ok <= 1'b0;      // false SIGNAL detection: draw nothing

        /* park an FCS-bad frame for SHOW_BAD 2 (2026-09-23 the red rays went
           away entirely; 2026-09-25 back, for listed stations only) */
        if (i_fcs_stb) begin
            bad_wait   <= (SHOW_BAD == 2) && i_show_bad && pend_ok && !i_fcs_ok && solo_ok;
            bad_go     <= 1'b0;
            bad_age    <= 10'd0;
            bad_idx    <= pend_idx;
            bad_len    <= pend_len;
            bad_phv    <= i_ph_valid;
            bad_ph_cal <= ph_cal[15:16-ANGBITS];
            bad_ph_raw <= i_ph_ang[15:16-ANGBITS];
        end
        else if (bad_wait) begin
            bad_age <= bad_age + 10'd1;
            if (i_adm_stb && !i_adm_fcs) begin
                bad_wait <= 1'b0;
                bad_go   <= 1'b1;
            end
            else if (bad_age == ADM_WAIT)
                bad_wait <= 1'b0;
        end
        else if (bad_commit)
            bad_go <= 1'b0;

        if (good_commit) begin
            if (i_ph_valid) begin
                o_mark_ang <= ph_cal[15:16-ANGBITS];
                o_mark_raw <= i_ph_ang[15:16-ANGBITS];
                o_mark_brg <= pend_idx;
                o_mark_ok  <= 1'b1;
                o_mark_cnt <= o_mark_cnt + 16'd1;
            end
            req_commit <= 1'b1;
            req_idx    <= pend_idx;
            req_len    <= pend_len;
            req_frq    <= i_fcs_ok ? FRQ_OK : FRQ_BAD;
        end
        else if (bad_commit) begin
            if (bad_phv) begin
                o_mark_ang <= bad_ph_cal;
                o_mark_raw <= bad_ph_raw;
                o_mark_brg <= bad_idx;
                o_mark_ok  <= 1'b1;
                o_mark_cnt <= o_mark_cnt + 16'd1;
            end
            req_commit <= 1'b1;
            req_idx    <= bad_idx;
            req_len    <= bad_len;
            req_frq    <= FRQ_BAD;
        end
        else if (req_taken)
            req_commit <= 1'b0;
    end
end

assign o_brg_idx = pend_idx;
assign o_brg_ok  = pend_ok;

/****************************************************************************/
/* Angle table with decay. dp_ram registers its port A read, so every RMW   */
/* is three phases: address, wait, write (df_amp's hard-won lesson). The    */
/* decay sweep yields to a pending commit between bins.                     */
/****************************************************************************/
localparam TBLW = 8 + FRQBITS;

localparam T_IDLE = 3'd0,
           T_CRD  = 3'd1, T_CWT = 3'd2, T_CWR = 3'd3,
           T_DRD  = 3'd4, T_DWT = 3'd5, T_DWR = 3'd6;

reg [2:0]         tst;
reg [ANGBITS-1:0] tbl_addr;
reg [TBLW-1:0]    tbl_din;
reg               tbl_we;
wire [TBLW-1:0]   tbl_douta;

reg [ANGBITS-1:0] didx;
reg               decay_run;
reg               decay_due;
reg [15:0]        us_ctr;

function [7:0] decay_next;
    input [7:0] len;
    reg   [7:0] step;
    begin
        step = (len[7:3] == 5'd0) ? 8'd1 : {3'd0, len[7:3]};
        decay_next = (len > step) ? (len - step) : 8'd0;
    end
endfunction

assign req_taken = (tst == T_CRD);   // request consumed on entry

always @(posedge i_clk) begin
    if (i_rst) begin
        tst       <= T_IDLE;
        tbl_addr  <= {ANGBITS{1'b0}};
        tbl_din   <= {TBLW{1'b0}};
        tbl_we    <= 1'b0;
        didx      <= {ANGBITS{1'b0}};
        decay_run <= 1'b0;
        decay_due <= 1'b0;
        us_ctr    <= 16'd0;
    end
    else begin
        tbl_we <= 1'b0;

        if (i_us_tick) begin
            if (us_ctr == DECAY_US - 16'd1) begin
                us_ctr    <= 16'd0;
                decay_due <= 1'b1;
            end
            else
                us_ctr <= us_ctr + 16'd1;
        end

        case (tst)
        T_IDLE: begin
            if (req_commit) begin
                tbl_addr <= req_idx;
                tst      <= T_CRD;
            end
            else if (decay_due) begin
                decay_due <= 1'b0;
                decay_run <= 1'b1;
                didx      <= {ANGBITS{1'b0}};
                tbl_addr  <= {ANGBITS{1'b0}};
                tst       <= T_DRD;
            end
            else if (decay_run) begin
                tbl_addr <= didx;
                tst      <= T_DRD;
            end
        end

        /* commit: max-accumulate on LENGTH, the winner keeps its colour */
        T_CRD: tst <= T_CWT;
        T_CWT: tst <= T_CWR;
        T_CWR: begin
            tbl_din <= (tbl_douta[7:0] > req_len) ? tbl_douta
                                                  : {req_frq, req_len};
            tbl_we  <= 1'b1;
            tst     <= T_IDLE;
        end

        /* decay: len -= max(len/8, 1), floor 0; empty bins skip the write */
        T_DRD: tst <= T_DWT;
        T_DWT: tst <= T_DWR;
        T_DWR: begin
            if (tbl_douta[7:0] != 8'd0) begin
                tbl_din <= {tbl_douta[TBLW-1:8],
                            decay_next(tbl_douta[7:0])};
                tbl_we  <= 1'b1;
            end
            if (didx == {ANGBITS{1'b1}})
                decay_run <= 1'b0;
            didx <= didx + 1'b1;
            tst  <= T_IDLE;
        end

        default: tst <= T_IDLE;
        endcase
    end
end

dp_ram #(.ADDRBITS(ANGBITS), .BITS(TBLW)) angTbl (
    .i_clka(i_clk),
    .i_wea(tbl_we),
    .i_addra(tbl_addr),
    .i_dina(tbl_din),
    .o_douta(tbl_douta),
    .i_clkb(i_rdClk),
    .i_addrb(i_rdAddr),
    .o_doutb({o_rdFrq, o_rdLen})
);

endmodule
