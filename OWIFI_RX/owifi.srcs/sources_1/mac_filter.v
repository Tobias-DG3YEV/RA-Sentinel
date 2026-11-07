//////////////////////////////////////////////////////////////////////////////////
//
// Design Name: OWIFI_RX
// Module Name: mac_filter
// Project Name: RA-Sentinel IQ snapshot transport (doc/iq_capture/SPEC.md §3)
// Engineer: Tobias Weber
// Target Devices: Artix 7, XC7A100T (RASBB baseboard)
// Description:
//   8-slot transmitter-MAC filter on dot11's byte stream. Address 2 (SA) is
//   MAC header bytes 10..15 - the same parse frame_log.v uses. The compare
//   runs byte-serially as the bytes arrive: every slot starts a frame as
//   "still matching" and drops out on the first differing byte, so the
//   verdict is ready in the clock after byte 15 and costs eight 8-bit
//   comparators instead of eight 48-bit ones.
//
//   Verdict strobes (exactly one per frame, never both):
//     o_match_stb    byte 15 seen and (an enabled slot matched)
//     o_mismatch_stb byte 15 seen and no enabled slot matched, OR the frame
//                    ended (i_fcs_stb) with fewer than 16 bytes, OR the
//                    frame control byte says ACK/CTS (no Address 2 field;
//                    bytes 10..13 would be the FCS)
//   i_pass_all does NOT change the verdicts (the counters keep meaning
//   "filter hits"); the capture glue decides what to do with them.
//   o_sa / o_sa_valid hold the parsed SA from byte 15 until the next frame.
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

module mac_filter #(
    parameter NSLOT = 8
)(
    input  wire        i_clk,
    input  wire        i_rst,

    /* dot11 byte stream */
    input  wire        i_hdr_stb,         // pkt_header_valid_strobe: frame start
    input  wire        i_hdr_valid,
    input  wire        i_byte_stb,
    input  wire [7:0]  i_byte,
    input  wire        i_fcs_stb,         // frame end
    input  wire        i_abort,           // receiver_rst

    /* filter table */
    input  wire [NSLOT*48-1:0] i_mac,     // slot k = bits [48k+47:48k], byte 0 (first on air) = [47:40]
    input  wire [NSLOT-1:0]    i_en,

    /* verdict */
    output reg         o_match_stb,
    output reg         o_mismatch_stb,
    output reg  [47:0] o_sa,
    output reg         o_sa_valid,
    output reg  [2:0]  o_hit_slot
);

reg          active;
reg  [4:0]   byte_cnt;                     // saturates at 16
reg  [NSLOT-1:0] ok;
reg  [7:0]   fc0;
reg          decided;

/* byte index 10..15 -> MAC byte 0..5 -> slot bits [47-8j : 40-8j] */
wire in_sa      = active && (byte_cnt >= 5'd10) && (byte_cnt <= 5'd15);
wire [2:0] j    = byte_cnt[2:0] - 3'd2;    // 10->0 .. 15->5
wire no_addr2   = (fc0[3:2] == 2'b01) && ((fc0[7:4] == 4'hD) || (fc0[7:4] == 4'hC));

integer k;
always @(posedge i_clk) begin
    o_match_stb    <= 1'b0;
    o_mismatch_stb <= 1'b0;
    if (i_rst) begin
        active <= 1'b0; byte_cnt <= 5'd0; ok <= {NSLOT{1'b0}};
        fc0 <= 8'h00; decided <= 1'b1;
        o_sa <= 48'd0; o_sa_valid <= 1'b0; o_hit_slot <= 3'd0;
    end
    else begin
        if (i_hdr_stb) begin
            active   <= i_hdr_valid;
            byte_cnt <= 5'd0;
            ok       <= {NSLOT{1'b1}};
            decided  <= ~i_hdr_valid;      // an invalid header never gets a verdict
            o_sa_valid <= 1'b0;
        end
        else if (i_abort) begin
            active  <= 1'b0;
            decided <= 1'b1;
        end
        else if (i_byte_stb && active) begin
            if (byte_cnt == 5'd0) fc0 <= i_byte;
            if (byte_cnt != 5'd16) byte_cnt <= byte_cnt + 5'd1;
            if (in_sa) begin
                o_sa <= {o_sa[39:0], i_byte};
                for (k = 0; k < NSLOT; k = k + 1)
                    if (i_byte != i_mac[48*k + 8*(5-j) +: 8]) ok[k] <= 1'b0;
            end
        end
        else if (i_fcs_stb && active && !decided) begin
            /* frame ended before byte 15: no SA */
            decided        <= 1'b1;
            o_mismatch_stb <= 1'b1;
            active         <= 1'b0;
        end
        else if (i_fcs_stb) begin
            active <= 1'b0;
        end

        /* verdict one clock after byte 15 landed (ok/o_sa are settled) */
        if (active && !decided && byte_cnt == 5'd16) begin
            decided    <= 1'b1;
            o_sa_valid <= 1'b1;
            if (!no_addr2 && |(ok & i_en)) o_match_stb <= 1'b1;
            else                           o_mismatch_stb <= 1'b1;
            o_hit_slot <= 3'd0;
            for (k = NSLOT-1; k >= 0; k = k - 1)
                if (ok[k] & i_en[k]) o_hit_slot <= k[2:0];
        end
    end
end

endmodule
