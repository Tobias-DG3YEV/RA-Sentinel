//////////////////////////////////////////////////////////////////////////////////
//
// Design Name: OWIFI_RX
// Module Name: iq_snapshot
// Project Name: RA-Sentinel IQ snapshot transport (doc/iq_capture/SPEC.md §2/§3)
// Engineer: Tobias Weber
// Target Devices: Artix 7, XC7A100T (RASBB baseboard)
// Description:
//   Slot buffer for 4-channel IQ "instants" (96 bits = 4 x {I,Q} 12-bit) with
//   a protocol-neutral trigger interface and a streaming read-out port.
//
//   STORAGE: one block RAM of NSLOT x NSAMP_MAX instants (default 4 x 1024 x
//   96 bit = 12 RAMB36). Each slot is used as a RING while it is the write
//   slot: samples are written continuously, so at i_arm the last PRETRIG
//   instants are already there and the snapshot starts PRETRIG instants
//   BEFORE the trigger. dot11 detects the STF some 60..100 samples after it
//   begins; without the pre-trigger every snapshot would start mid-STF.
//
//   LIFE OF A SLOT (frame_buffer.v's speculative pattern, per slot):
//     PRE    ring-writing the free write slot, waiting for i_arm
//     ARMED  i_arm seen: start = wr_ptr - pretrig, count up to nsamp, then
//            stop writing (FULL). i_frame_end before FULL = "truncated":
//            stop there and remember the shorter length.
//     commit (i_commit, sticky) + FULL/truncated -> PUBLISH: descriptor and
//            start/length go to the slot table, write slot advances.
//     i_abort at any time before publish -> back to PRE on the SAME slot,
//            the ring keeps running (nothing is lost, nothing is leaked).
//     i_idle (receiver back in WAIT) while unpublished and uncommitted ->
//            abort too (safety net: a decode that ended without fcs or
//            receiver_rst would otherwise pin the slot forever).
//   i_arm with no free slot: o_drop_count++ and the trigger is ignored.
//
//   DESCRIPTOR (72 bytes, SPEC §2 v2 "IQD2", byte 0 in bits [7:0]) is
//   assembled at publish time from the i_meta_* inputs, which the glue holds
//   valid from commit until publish. 'ts' is the 64-bit instant counter
//   (counts i_smp_strobe, cleared while !i_fe_valid) at the FIRST STORED
//   instant. flags bit4 fifo_was_full = a drop occurred since the previous
//   publish, bit6 frame_stats = the frame had ended (fcs strobe) when the
//   snapshot was published, so bytes 52..71 (the receiver's frame statistics)
//   cover the whole frame. Bytes 48..49 hold the pre-trigger length of THIS
//   snapshot (the trigger instant is at index pretrig).
//
//   READ-OUT: o_rd_valid presents the oldest published slot on o_rd_desc.
//   The consumer raises i_rd_ready (a LEVEL) to stream instants: one per
//   clock, first instant one clock after ready rises, o_rd_last with the
//   final one, then the slot is freed and o_rd_valid shows the next slot (or
//   drops). Instants are issued only in clocks where i_rd_ready is high but
//   arrive 3 clocks later (registered RAM read), so after dropping ready the
//   consumer must still absorb whatever it enabled in the last 3 clocks.
//
// Dependencies: none (inferred simple-dual-port BRAM)
//
// Additional Comments: https://github.com/Tobias-DG3YEV/RA-Sentinel
//
//////////////////////////////////////////////////////////////////////////////////
// Copyright (C) 2026 Tobias Weber
// License: GNU GPL v3
//////////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps

module iq_snapshot #(
    parameter NSLOT     = 4,
    parameter NSAMP_MAX = 1024,
    parameter SLOT_W    = 2,            // log2(NSLOT)
    parameter PTR_W     = 10            // log2(NSAMP_MAX)
)(
    input  wire        i_clk,
    input  wire        i_rst,

    /* sample stream (clk domain) */
    input  wire        i_fe_valid,
    input  wire        i_smp_strobe,
    input  wire [95:0] i_smp,

    /* configuration (static while enabled) */
    input  wire        i_enable,
    input  wire [15:0] i_nsamp,          // 1..NSAMP_MAX
    input  wire [15:0] i_pretrig,        // 0..nsamp-1
    input  wire        i_clear,          // clear counters (pulse)

    /* trigger interface */
    input  wire        i_arm,
    input  wire        i_commit,
    input  wire        i_abort,
    input  wire        i_frame_end,      // fcs strobe: samples after this are not the frame
    input  wire        i_idle,           // receiver idle (safety abort)

    /* descriptor meta, valid from commit until publish */
    input  wire [7:0]  i_meta_proto,
    input  wire [15:0] i_meta_pkt_len,
    input  wire [47:0] i_meta_mac_sa,
    input  wire [7:0]  i_meta_rate,
    input  wire [1:0]  i_meta_ant_sel,
    input  wire        i_meta_fcs_ok,
    input  wire        i_meta_mac_match,
    input  wire        i_meta_pass_all,
    input  wire        i_meta_header_valid,
    input  wire [31:0] i_meta_match_count,
    input  wire [31:0] i_meta_trig_count,
    input  wire [31:0] i_meta_phase,      // bytes 44..47: phase_cmp result (SPEC s2, 4.b)
    /* v2 (bytes 50..71): the receiver's frame statistics, live accumulators */
    input  wire [15:0] i_meta_cfo,        // 50..51 sync_short phase_offset
    input  wire [31:0] i_meta_peg,        // 52..55 equalizer phase error gradient
    input  wire [31:0] i_meta_cpe_sum,    // 56..59
    input  wire [31:0] i_meta_cpe_sq,     // 60..63
    input  wire [31:0] i_meta_evm_sum,    // 64..67
    input  wire [15:0] i_meta_evm_cnt,    // 68..69
    input  wire [15:0] i_meta_nsym,       // 70..71
    input  wire        i_meta_frame_end,  // flags bit6: frame ended before publish

    /* counters / status */
    output reg  [31:0] o_drop_count,
    output reg  [31:0] o_seq,            // snapshots published
    output wire        o_armed,
    output wire [SLOT_W:0] o_used,

    /* read-out port */
    output wire [575:0] o_rd_desc,
    output wire         o_rd_valid,
    input  wire         i_rd_ready,
    output reg  [95:0]  o_rd_inst,
    output reg          o_rd_inst_valid,
    output reg          o_rd_last
);

localparam [1:0] S_PRE = 2'd0, S_ARMED = 2'd1, S_WAIT = 2'd2;

/*------------------------------------------------------------------*/
/* instant counter (ts)                                             */
/*------------------------------------------------------------------*/
reg [63:0] ts;
always @(posedge i_clk)
    if (i_rst || !i_fe_valid) ts <= 64'd0;
    else if (i_smp_strobe)    ts <= ts + 64'd1;

/*------------------------------------------------------------------*/
/* slot RAM                                                         */
/*------------------------------------------------------------------*/
(* ram_style = "block" *) reg [95:0] ram [0:NSLOT*NSAMP_MAX-1];
reg                  wr_en;
reg  [SLOT_W+PTR_W-1:0] wr_addr;
reg  [95:0]          wr_data;
reg  [SLOT_W+PTR_W-1:0] rd_addr;
reg  [95:0]          rd_q;
always @(posedge i_clk) begin
    if (wr_en) ram[wr_addr] <= wr_data;
    rd_q <= ram[rd_addr];
end

/*------------------------------------------------------------------*/
/* slot table                                                       */
/*------------------------------------------------------------------*/
reg [575:0]   desc  [0:NSLOT-1];
reg [PTR_W-1:0] start [0:NSLOT-1];
reg [15:0]    slen  [0:NSLOT-1];
reg [SLOT_W-1:0] wslot, rslot;
reg [SLOT_W:0]   used;
assign o_used = used;
wire full_slots = (used == NSLOT[SLOT_W:0]);

/*------------------------------------------------------------------*/
/* write side                                                       */
/*------------------------------------------------------------------*/
reg [1:0]     st;
reg [PTR_W-1:0] wr_ptr;
reg [PTR_W-1:0] cap_start;
reg [15:0]    cap_cnt;
reg           committed, trunc, filled;
reg [63:0]    ts_first;
reg           drop_since;                  // for flags.fifo_was_full
reg [15:0]    nsamp_q, pretrig_q;
reg [5:0]     armed_age;                  // i_idle is honoured only after 32 clocks armed
reg [3:0]     idle_run;                   // consecutive i_idle clocks (commit may lag the frame end by the verdict pipeline)

assign o_armed = (st != S_PRE);

wire [15:0] pretrig_lim = (i_pretrig >= i_nsamp) ? (i_nsamp - 16'd1) : i_pretrig;

/* descriptor assembled combinationally from the held meta */
wire [7:0] flags = {1'b0, i_meta_frame_end, i_meta_header_valid, drop_since, trunc,
                    i_meta_pass_all, i_meta_mac_match, i_meta_fcs_ok};
wire [575:0] desc_now = {
    i_meta_nsym,                            // 70..71 OFDM symbols with a CPE
    i_meta_evm_cnt,                         // 68..69 data subcarriers in evm_sum
    i_meta_evm_sum,                         // 64..67 sum of |error vector|^2 / 4
    i_meta_cpe_sq,                          // 60..63 sum of CPE^2
    i_meta_cpe_sum,                         // 56..59 sum of CPE
    i_meta_peg,                             // 52..55 phase error gradient
    i_meta_cfo,                             // 50..51 phase_offset (CFO)
    pretrig_q,                              // 48..49 instants before the trigger
    i_meta_phase,                           // 44..47 phase word (was reserved)
    i_meta_trig_count,                      // 40..43
    i_meta_match_count,                     // 36..39
    o_drop_count,                           // 32..35
    6'd0, i_meta_ant_sel,                   // 31
    i_meta_rate,                            // 30
    i_meta_mac_sa[7:0],  i_meta_mac_sa[15:8], i_meta_mac_sa[23:16],   // 29..27
    i_meta_mac_sa[31:24], i_meta_mac_sa[39:32], i_meta_mac_sa[47:40], // 26..24
    i_meta_pkt_len,                         // 22..23 (LE: [7:0] at 22)
    cap_cnt,                                // 20..21 nsamp actually stored
    flags,                                  // 19
    8'd12,                                  // 18 bits
    8'd4,                                   // 17 nch
    i_meta_proto,                           // 16
    ts_first,                               // 8..15
    o_seq,                                  // 4..7
    32'h32445149                            // 0..3 "IQD2"
};

wire publish = (st != S_PRE) && filled && committed;

integer s;
always @(posedge i_clk) begin
    wr_en <= 1'b0;
    if (i_rst) begin
        st <= S_PRE; wr_ptr <= {PTR_W{1'b0}}; cap_start <= {PTR_W{1'b0}};
        cap_cnt <= 16'd0; committed <= 1'b0; trunc <= 1'b0; filled <= 1'b0;
        ts_first <= 64'd0; drop_since <= 1'b0; armed_age <= 6'd0; idle_run <= 4'd0;
        o_drop_count <= 32'd0; o_seq <= 32'd0;
        wslot <= {SLOT_W{1'b0}}; nsamp_q <= 16'd1024; pretrig_q <= 16'd0;
        for (s = 0; s < NSLOT; s = s + 1) begin
            desc[s] <= 576'd0; start[s] <= {PTR_W{1'b0}}; slen[s] <= 16'd0;
        end
    end
    else begin
        if (i_clear) begin o_drop_count <= 32'd0; drop_since <= 1'b0; end

        case (st)
        S_PRE: begin
            /* ring-write the free write slot */
            if (i_smp_strobe && !full_slots) begin
                wr_en   <= 1'b1;
                wr_addr <= {wslot, wr_ptr};
                wr_data <= i_smp;
                wr_ptr  <= wr_ptr + 1'b1;
            end
            if (i_arm && i_enable) begin
                if (full_slots) begin
                    o_drop_count <= o_drop_count + 32'd1;
                    drop_since   <= 1'b1;
                end
                else begin
                    nsamp_q   <= i_nsamp;
                    pretrig_q <= pretrig_lim;
                    cap_start <= wr_ptr - pretrig_lim[PTR_W-1:0];
                    /* a strobe in this very clock is written (above) but
                       lies after the trigger: count it, or the slot fills
                       one instant late and the last write wraps onto the
                       first (seen on hardware: instant 0 = instant 960) */
                    cap_cnt   <= pretrig_lim + {15'd0, i_smp_strobe};
                    ts_first  <= ts - {48'd0, pretrig_lim};
                    committed <= 1'b0; trunc <= 1'b0; filled <= 1'b0;
                    armed_age <= 6'd0; idle_run <= 4'd0;
                    st        <= S_ARMED;
                end
            end
        end
        S_ARMED: begin
            if (armed_age != 6'd63) armed_age <= armed_age + 6'd1;
            /* JOB-07: dot11 goes idle in the clock of the FCS strobe while the
               MAC verdict (and thus a pass-all commit of an ACK/CTS) arrives a
               clock later - honour idle only after 8 consecutive idle clocks */
            idle_run <= i_idle ? (idle_run == 4'd15 ? 4'd15 : idle_run + 4'd1) : 4'd0;
            if (i_abort || (i_idle && idle_run >= 4'd8 && !committed && armed_age > 6'd32)) begin
                st <= S_PRE;               // ring resumes on the same slot
            end
            else begin
                if (i_commit) committed <= 1'b1;
                if (i_smp_strobe && !filled) begin
                    wr_en   <= 1'b1;
                    wr_addr <= {wslot, wr_ptr};
                    wr_data <= i_smp;
                    wr_ptr  <= wr_ptr + 1'b1;
                    cap_cnt <= cap_cnt + 16'd1;
                    if (cap_cnt + 16'd1 >= nsamp_q) filled <= 1'b1;
                end
                if (i_frame_end && !filled) begin
                    filled <= 1'b1;
                    trunc  <= 1'b1;
                end
                if (publish) begin
                    desc[wslot]  <= desc_now;
                    start[wslot] <= cap_start;
                    slen[wslot]  <= cap_cnt;
                    wslot        <= wslot + 1'b1;
                    o_seq        <= o_seq + 32'd1;
                    drop_since   <= 1'b0;
                    wr_ptr       <= {PTR_W{1'b0}};
                    st           <= S_PRE;
                end
            end
        end
        default: st <= S_PRE;
        endcase
    end
end

/*------------------------------------------------------------------*/
/* read side                                                        */
/*                                                                  */
/* issue@t -> rd_addr@t+1 -> rd_q@t+2 -> o_rd_inst@t+3. One instant  */
/* per clock while i_rd_ready; instants issued before ready dropped  */
/* still arrive (up to 3 clocks later).                              */
/*------------------------------------------------------------------*/
reg [15:0]       rd_idx;
reg [PTR_W-1:0]  rd_ptr;
reg              p1, p1_last, p2, p2_last;
wire             free_ev = p2 & p2_last;   // the last instant is on o_rd_inst next clock

assign o_rd_valid = (used != 0);
assign o_rd_desc  = desc[rslot];

wire issue = o_rd_valid && i_rd_ready && (rd_idx < slen[rslot]);

always @(posedge i_clk) begin
    if (i_rst) begin
        rd_idx <= 16'd0; rd_ptr <= {PTR_W{1'b0}};
        p1 <= 1'b0; p1_last <= 1'b0; p2 <= 1'b0; p2_last <= 1'b0;
        o_rd_inst_valid <= 1'b0; o_rd_last <= 1'b0; o_rd_inst <= 96'd0;
        rslot <= {SLOT_W{1'b0}}; used <= {(SLOT_W+1){1'b0}};
        rd_addr <= {(SLOT_W+PTR_W){1'b0}};
    end
    else begin
        /* slot occupancy */
        case ({publish, free_ev})
            2'b10: used <= used + 1'b1;
            2'b01: used <= used - 1'b1;
            default: ;
        endcase

        /* stage 0: address issue */
        p1      <= issue;
        p1_last <= issue && (rd_idx + 16'd1 == slen[rslot]);
        if (issue) begin
            rd_addr <= {rslot, (rd_idx == 16'd0) ? start[rslot] : rd_ptr};
            rd_ptr  <= ((rd_idx == 16'd0) ? start[rslot] : rd_ptr) + 1'b1;
            rd_idx  <= rd_idx + 16'd1;
        end

        /* stage 1: RAM read happens (rd_q <= ram[rd_addr]) */
        p2      <= p1;
        p2_last <= p1_last;

        /* stage 2: data out */
        o_rd_inst_valid <= p2;
        o_rd_last       <= p2 & p2_last;
        if (p2) o_rd_inst <= rd_q;

        if (free_ev) begin
            rslot  <= rslot + 1'b1;
            rd_idx <= 16'd0;
        end
    end
end

endmodule
