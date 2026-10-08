//////////////////////////////////////////////////////////////////////////////////
//
// Design Name: OWIFI_RX
// Module Name: fast_heal
// Project Name: RA-Sentinel 802.11 receiver + direction finder (RASBB + RASRF2400WBMC)
// Engineer: Tobias Weber
// Target Devices: Artix 7, XC7A100T
// Description:
//   Per-ADC fast link heal (2026-09-24). lvds_rx_new's ISERDES run on a
//   fabric-made CLKDIV that is not phase-aligned to CLK, and every so often
//   (1-2 per minute on ADC2) the bit grouping slips. Until now only the global
//   heal recovered it: 2 s of fe_valid low, then fe_rst on BOTH front halves,
//   about 2 s dead plus re-convergence. This block detects the slip within
//   microseconds and re-runs only the failing receiver's ISERDES reset/CE
//   sequence (lvds_rx_new i_reinit_tog, anchor untouched), freezing that ADC's
//   link_supervisor and blanking that ADC's channels while it happens. The
//   global heal stays as the backstop: this block gives up after CAP failed
//   attempts per episode or RATE_MAX attempts per ~105 ms window.
//
//   ARMING. Only after ARM_CE consecutive words in which the supervisor
//   reports o_mon (monitoring a good link, no grace) and the FCLK word hits
//   at the locked rotation; that rotation is the reference (a healthy
//   link never changes rotation - the anchor free-runs). Leaving o_mon (the
//   supervisor saw scattered misses and will re-sweep taps) disarms: tap
//   drift is the supervisor's job.
//
//   TRIGGERS (while armed, evaluated per word):
//     T1  N_MISS consecutive FCLK decode misses. The visible slip direction
//         turns the FCLK word into a constant (0x42F seen on hardware), so it
//         misses on every word; eye drift gives scattered misses instead.
//     T2  M_ROT consecutive hits at a decode position other than the
//         reference, or the locked rotation moving away from it. The other
//         slip direction yields a clean-looking FCLK word (0x07E) one bit off,
//         invisible to the supervisor and to T1.
//     F   i_force (manual test trigger), accepted armed or disarmed.
//
//     R   i_reanchor: the receiver re-anchored its FCLK (lvds_rx's own slip
//         watchdog). Its power-on-length init follows (~5.5k words of 0xAAA)
//         and the word rotation moves legitimately, so this episode waits up
//         to TIMEOUT_REANCH and accepts the NEW locked rotation as the
//         reference - but only one of the old one's parity: a re-anchor
//         re-frames by whole DCLK cycles (an even bit shift), the EVEN/ODD
//         grouping slip by one bit, so an odd move is a slip and is re-inited
//         (the fast re-init toggle is ignored by the receiver while its own
//         init runs).
//
//   ATTEMPT. Toggle o_req_tog, raise o_freeze and o_blank, wait SETTLE_CE
//   words, then require K_OK consecutive words that decode at the reference
//   position while the receiver reports ready, and the locked rotation back
//   at the reference (it re-locks after 17 hits if T2 had moved it). Success
//   releases the freeze; the blank is held BLANK_TAIL more words for the
//   sample pipeline between the FCLK decode and the sample FIFO. TIMEOUT_CE
//   words without success = failed attempt: retry up to CAP, then give up
//   (freeze and blank released, the supervisor takes over and the global heal
//   follows if the link stays down). After a give-up the block re-arms only
//   after REARM_CE words of continuous o_mon, or after i_rst.
//
//   AFTER A SUCCESS the block goes straight back to armed with the SAME
//   reference, even while the supervisor's post-freeze grace keeps o_mon low
//   (it cannot sweep then): a re-slip right after a heal is caught, and an
//   invisible slip can never be learnt as the new reference. This holds only
//   for episodes that started armed, and for at most POST_CE words without
//   o_mon (the supervisor left MON after all: tap drift is its job); a forced
//   attempt from disarmed returns to disarmed.
//
//   All logic runs in the ADC1 BUFG domain on i_ce (adc_frameStrobe), where
//   both ADCs' FCLK decodes and both supervisors live. i_ready comes from the
//   receiver's own DCLK domain and is synchronised here.
//
// Dependencies: lvds_rx_new (RASPMO) i_reinit_tog/o_ready, link_supervisor
//   i_freeze/o_mon
//
// Additional Comments: https://github.com/Tobias-DG3YEV/RA-Sentinel
//
//////////////////////////////////////////////////////////////////////////////////
// Copyright (C) 2026 Tobias Weber
// License: GNU GPL v3
//////////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps

module fast_heal #(
    parameter N_MISS      = 64,        // T1: consecutive FCLK misses
    parameter M_ROT       = 32,        // T2: consecutive hits off the reference position
    parameter K_OK        = 64,        // success: consecutive good words
    parameter SETTLE_CE   = 4,         // words after the request before judging
    parameter TIMEOUT_CE  = 4096,      // words per attempt (~205 us at 20 MSPS)
    parameter TIMEOUT_REANCH = 8192,   // words per attempt after a receiver re-anchor (POR init ~5.5k)
    parameter CAP         = 3,         // attempts per episode
    parameter RATE_MAX    = 8,         // attempts per rate window before giving up
    parameter RATE_LOG2   = 21,        // rate window = 2^21 words (~105 ms)
    parameter BLANK_TAIL  = 8,         // words the blank outlives a successful attempt
    parameter ARM_CE      = 2048,      // words of continuous o_mon before arming (~100 us)
    parameter POST_CE     = 50000,     // longest armed stretch without o_mon after a success (> grace)
    parameter REARM_CE    = 20000000   // words of continuous o_mon after a give-up (~1 s)
)(
    input  wire       i_clk,           // ADC1 BUFG DCLK
    input  wire       i_rst,           // fe_rst: state machine
    input  wire       i_rst_cnt,       // counters only (power-up reset: they survive heals)
    input  wire       i_ce,            // adc_frameStrobe
    input  wire       i_enable,        // quasi-static, synchronised by the caller
    input  wire       i_force,         // one-clock pulse in this domain
    input  wire       i_hit,           // FCLK pattern found this word
    input  wire [3:0] i_dec,           // decoded position this word
    input  wire [3:0] i_rot,           // locked rotation (top's rotN_cur)
    input  wire       i_mon,           // link_supervisor o_mon
    input  wire       i_ready,         // lvds_rx_new o_ready (receiver's own clock)
    input  wire       i_reanchor,      // one-clock pulse in this domain: the receiver re-anchored

    output reg        o_req_tog = 1'b0,// -> lvds_rx_new i_reinit_tog
    output reg        o_freeze,        // -> link_supervisor i_freeze
    output reg        o_blank,         // zero this ADC's samples
    output reg  [7:0] o_attempts,      // counters, wrap, reset only by i_rst_cnt
    output reg  [7:0] o_success,
    output reg  [7:0] o_giveups,
    output reg  [7:0] o_t2,
    output wire [2:0] o_state,         // 0 disarmed, 1 armed, 2..5 attempt, 6 gave up
    output wire [3:0] o_rot_ref        // the armed reference rotation (diagnostic)
);

localparam S_DIS = 3'd0, S_ARM = 3'd1, S_REQ = 3'd2, S_SETTLE = 3'd3,
           S_CHECK = 3'd4, S_TAIL = 3'd5, S_GAVEUP = 3'd6;

(* ASYNC_REG = "true" *) reg [1:0] ready_s = 2'b00;
always @(posedge i_clk) ready_s <= {ready_s[0], i_ready};
wire ready = ready_s[1];

reg [2:0]  st;
reg [3:0]  rot_ref;
reg [24:0] mon_ctr;       // continuous o_mon, words (up to REARM_CE)
reg [7:0]  miss_run, rot_run;
reg [13:0] timer;         // words in SETTLE/CHECK
reg [7:0]  ok_run;
reg [3:0]  ep_cnt;        // attempts this episode
reg [3:0]  rate_cnt;      // attempts this rate window
reg [RATE_LOG2-1:0] rate_ctr;
reg [3:0]  tail;
reg        cause_t2;
reg        reanch;        // this episode includes a receiver re-anchor: new rotation is legitimate
reg        from_arm;      // this episode started armed (supervisor in MON when it began)
reg        post;          // armed on the kept reference while the supervisor's grace runs
reg        cnt_att = 1'b0, cnt_ok = 1'b0, cnt_gu = 1'b0, cnt_t2 = 1'b0;   // one-clock count pulses

/* a word that counts toward success: receiver ready, FCLK hit, at the
   reference position - or, after a re-anchor, at the newly locked rotation */
wire good = ready && i_hit && (reanch ? (i_dec == i_rot && i_rot[0] == rot_ref[0]) : (i_dec == rot_ref));

always @(posedge i_clk) begin
    if (i_rst) begin
        st <= S_DIS; rot_ref <= 4'd0; mon_ctr <= 25'd0; miss_run <= 8'd0; rot_run <= 8'd0;
        timer <= 14'd0; ok_run <= 8'd0; ep_cnt <= 4'd0; rate_cnt <= 4'd0; rate_ctr <= {RATE_LOG2{1'b0}};
        tail <= 4'd0; cause_t2 <= 1'b0; reanch <= 1'b0; from_arm <= 1'b0; post <= 1'b0;
        cnt_att <= 1'b0; cnt_ok <= 1'b0; cnt_gu <= 1'b0; cnt_t2 <= 1'b0;
        o_freeze <= 1'b0; o_blank <= 1'b0;
        /* o_req_tog keeps its level: a toggle here would be a request */
    end
    else begin
        cnt_att <= 1'b0; cnt_ok <= 1'b0; cnt_gu <= 1'b0; cnt_t2 <= 1'b0;
        /* rate window */
        if (i_ce) begin
            rate_ctr <= rate_ctr + 1'b1;
            if (&rate_ctr) rate_cnt <= 4'd0;
        end

        case (st)
        S_DIS: begin
            o_freeze <= 1'b0; o_blank <= 1'b0;
            miss_run <= 8'd0; rot_run <= 8'd0;
            reanch <= 1'b0; post <= 1'b0;
            if (i_force) begin
                rot_ref <= i_rot; ep_cnt <= 4'd0; cause_t2 <= 1'b0; from_arm <= 1'b0; st <= S_REQ;
            end
            else if (i_ce) begin
                if (i_enable && i_mon && i_hit && i_dec == i_rot && !i_reanchor) begin
                    if (mon_ctr >= ARM_CE - 1) begin
                        rot_ref <= i_rot; ep_cnt <= 4'd0; mon_ctr <= 25'd0; st <= S_ARM;
                    end
                    else mon_ctr <= mon_ctr + 25'd1;
                end
                else mon_ctr <= 25'd0;
            end
        end

        S_ARM: begin
            if (i_mon) post <= 1'b0;                    // the supervisor's grace is over
            else if (post && i_ce) mon_ctr <= mon_ctr + 25'd1;
            if (i_reanchor) reanch <= 1'b1;             // kept whichever branch runs below
            if (i_force) begin                          // before the disarm check: a write
                cause_t2 <= 1'b0;                       // that disables AND forces still forces
                from_arm <= i_mon | post;               // taken on a disarm clock: back to disarmed after
                st <= S_REQ;
            end
            else if (!i_enable || (!i_mon && !post) || (post && !i_mon && mon_ctr >= POST_CE - 1)) begin
                st <= S_DIS; mon_ctr <= 25'd0; post <= 1'b0;
            end
            else if (i_reanchor || reanch) begin
                reanch <= 1'b1; cause_t2 <= 1'b0; from_arm <= 1'b1; st <= S_REQ;
            end
            else if (i_ce) begin
                miss_run <= i_hit ? 8'd0 : ((miss_run == 8'hFF) ? miss_run : miss_run + 8'd1);
                rot_run  <= (i_hit && i_dec != rot_ref) ? ((rot_run == 8'hFF) ? rot_run : rot_run + 8'd1) : 8'd0;
                if (i_rot != rot_ref || (i_hit && i_dec != rot_ref && rot_run >= M_ROT - 1)) begin
                    cause_t2 <= 1'b1; from_arm <= 1'b1; st <= S_REQ;
                end
                else if (!i_hit && miss_run >= N_MISS - 1) begin
                    cause_t2 <= 1'b0; from_arm <= 1'b1; st <= S_REQ;
                end
            end
        end

        S_REQ: begin
            if (i_reanchor) reanch <= 1'b1;
            if (rate_cnt >= RATE_MAX) begin
                /* flapping: stop fighting, let the supervisor / global heal act */
                cnt_gu <= 1'b1; o_freeze <= 1'b0; o_blank <= 1'b0;
                mon_ctr <= 25'd0; post <= 1'b0; st <= S_GAVEUP;
            end
            else begin
                o_req_tog <= ~o_req_tog;
                o_freeze  <= 1'b1;
                o_blank   <= 1'b1;
                cnt_att <= 1'b1;
                if (cause_t2 && ep_cnt == 4'd0) cnt_t2 <= 1'b1;
                ep_cnt   <= ep_cnt + 4'd1;
                rate_cnt <= rate_cnt + 4'd1;
                timer    <= 14'd0; ok_run <= 8'd0;
                st <= S_SETTLE;
            end
        end

        S_SETTLE: begin
            if (i_ce) begin
                if (timer >= SETTLE_CE - 1) begin timer <= 14'd0; st <= S_CHECK; end
                else timer <= timer + 14'd1;
            end
            if (i_reanchor) reanch <= 1'b1;
        end

        S_CHECK: begin
            if (i_ce) begin
                timer  <= timer + 14'd1;
                ok_run <= good ? ((ok_run == 8'hFF) ? ok_run : ok_run + 8'd1) : 8'd0;
                if (good && ok_run >= K_OK - 1 && (reanch || i_rot == rot_ref)) begin
                    cnt_ok    <= 1'b1;
                    o_freeze  <= 1'b0;
                    ep_cnt    <= 4'd0;
                    tail      <= 4'd0;
                    if (reanch) rot_ref <= i_rot;   // the re-anchored rotation is the new truth
                    reanch    <= 1'b0;
                    st        <= S_TAIL;
                end
                else if (timer >= (reanch ? TIMEOUT_REANCH : TIMEOUT_CE) - 1) begin
                    if (ep_cnt >= CAP) begin
                        cnt_gu <= 1'b1; o_freeze <= 1'b0; o_blank <= 1'b0;
                        mon_ctr <= 25'd0; reanch <= 1'b0; post <= 1'b0; st <= S_GAVEUP;
                    end
                    else st <= S_REQ;       // retry
                end
            end
            /* after the block above so it wins: a re-anchor restarts this
               attempt's clock and success run under the re-anchor rules (a
               success in this very clock goes on to a re-anchor episode) */
            if (i_reanchor) begin
                reanch <= 1'b1; timer <= 14'd0; ok_run <= 8'd0;
            end
        end

        S_TAIL: begin
            if (i_reanchor) reanch <= 1'b1;                 // S_ARM starts a re-anchor episode
            if (i_ce) begin
                if (tail >= BLANK_TAIL - 1) begin
                    o_blank <= 1'b0; mon_ctr <= 25'd0; miss_run <= 8'd0; rot_run <= 8'd0;
                    if (from_arm && i_enable) begin
                        post <= 1'b1; st <= S_ARM;          // keep rot_ref, watch through the grace
                    end
                    else st <= S_DIS;                       // forced from disarmed: arm the normal way
                end
                else tail <= tail + 4'd1;
            end
        end

        S_GAVEUP: begin
            o_freeze <= 1'b0; o_blank <= 1'b0;
            reanch <= 1'b0; post <= 1'b0;
            if (i_force) begin
                rot_ref <= i_rot; ep_cnt <= 4'd0; cause_t2 <= 1'b0; from_arm <= 1'b0; st <= S_REQ;
            end
            else if (i_ce) begin
                if (i_mon) begin
                    if (mon_ctr >= REARM_CE - 1) begin mon_ctr <= 25'd0; st <= S_DIS; end
                    else mon_ctr <= mon_ctr + 25'd1;
                end
                else mon_ctr <= 25'd0;
            end
        end

        default: st <= S_DIS;
        endcase
    end
end

assign o_state = st;
assign o_rot_ref = rot_ref;

/* counters: the FSM above says when, this block counts, so a global heal
   (i_rst) does not wipe the history */
always @(posedge i_clk) begin
    if (i_rst_cnt) begin
        o_attempts <= 8'd0; o_success <= 8'd0; o_giveups <= 8'd0; o_t2 <= 8'd0;
    end
    else begin
        if (cnt_att) o_attempts <= o_attempts + 8'd1;
        if (cnt_ok)  o_success  <= o_success  + 8'd1;
        if (cnt_gu)  o_giveups  <= o_giveups  + 8'd1;
        if (cnt_t2)  o_t2       <= o_t2       + 8'd1;
    end
end

endmodule
