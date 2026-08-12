//////////////////////////////////////////////////////////////////////////////////
//
// Design Name: OWIFI_RX
// Module Name: frame_buffer
// Project Name: RA-Sentinel 802.11 receiver
// Engineer: Tobias Weber
// Target Devices: Artix 7, XC7A100T (RASBB baseboard)
// Description:
//   Packet FIFO between dot11's byte stream and the STM32 read-out port.
//
//   dot11 does not know whether a frame is good until the FCS arrives at the
//   very end, so this buffer writes speculatively and only COMMITS on
//   o_fcs_out_strobe: the write pointer runs ahead of commit_ptr during
//   reception and is either published (commit_ptr <= wr_ptr) or rewound
//   (wr_ptr <= commit_ptr).  A frame that aborts mid-decode - which really
//   happens, signal_watchdog resets the receiver on runt/oversized SIGNAL
//   fields - must rewind too, otherwise the buffer leaks a little on every
//   false trigger and eventually wedges.
//
//   Payload bytes live in a byte-wide block RAM; the per-frame metadata lives
//   in a separate small descriptor FIFO.  Keeping them apart avoids the
//   reserve-then-backfill dance for a length that is only known at the end.
//
//   Everything is in ONE clock domain (the 100MHz receiver clock).  The SPI
//   side oversamples its pads instead of clocking on SCLK, so no CDC is
//   needed here - see spi_frame_if.v.
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

module frame_buffer #(
    parameter ADDR_BITS  = 15,          // payload RAM = 2^ADDR_BITS bytes (32KB)
    parameter DESC_BITS  = 4            // descriptor FIFO depth = 2^DESC_BITS
)(
    input  wire        i_clk,
    input  wire        i_rst,

    /* microsecond time base (802.11 TSF convention; wraps every 71 min) */
    input  wire        i_us_tick,

    /* dot11 receive stream */
    input  wire        i_hdr_valid_stb,
    input  wire        i_hdr_valid,
    input  wire [15:0] i_pkt_len,
    input  wire [7:0]  i_pkt_rate,
    input  wire        i_byte_stb,
    input  wire [7:0]  i_byte,
    input  wire        i_fcs_stb,
    input  wire        i_fcs_ok,
    input  wire        i_abort,         // receiver_rst: decode gave up mid-frame

    /* control */
    input  wire        i_keep_bad,      // also queue frames whose FCS failed
    input  wire        i_flush,
    input  wire        i_clr_sticky,

    /* read-out port (SPI side, same clock) */
    output wire [DESC_BITS:0]  o_frame_count,
    output wire        o_overflow,      // sticky: something was dropped
    input  wire [3:0]  i_desc_idx,      // which descriptor byte to present
    output reg  [7:0]  o_desc_byte,
    input  wire [15:0] i_pay_offset,    // byte offset inside the head frame
    output wire [7:0]  o_pay_byte,
    input  wire        i_pop            // retire the head frame (1 clk pulse)
);

localparam SIZE = (1 << ADDR_BITS);
localparam DEPTH = (1 << DESC_BITS);

/*------------------------------------------------------------------*/
/* payload RAM                                                      */
/*------------------------------------------------------------------*/
(* ram_style = "block" *) reg [7:0] mem [0:SIZE-1];

reg [ADDR_BITS-1:0] wr_ptr;      // next write position (speculative)
reg [ADDR_BITS-1:0] commit_ptr;  // start of the in-flight frame = end of queue
reg [ADDR_BITS-1:0] rd_ptr;      // start of the head (oldest queued) frame
reg [ADDR_BITS:0]   used;        // committed bytes waiting to be read
reg [ADDR_BITS:0]   pending;     // bytes written for the in-flight frame

wire [ADDR_BITS-1:0] rd_addr = rd_ptr + i_pay_offset[ADDR_BITS-1:0];

reg [7:0] mem_dout;
always @(posedge i_clk) mem_dout <= mem[rd_addr];
assign o_pay_byte = mem_dout;

/*------------------------------------------------------------------*/
/* descriptor FIFO                                                  */
/*------------------------------------------------------------------*/
reg [15:0] d_len   [0:DEPTH-1];   // bytes actually stored (what the host reads)
reg [15:0] d_orig  [0:DEPTH-1];   // length dot11 announced in SIGNAL
reg [7:0]  d_flags [0:DEPTH-1];
reg [7:0]  d_rate  [0:DEPTH-1];
reg [31:0] d_ts    [0:DEPTH-1];
reg [31:0] d_seq   [0:DEPTH-1];
reg [15:0] d_drop  [0:DEPTH-1];

reg [DESC_BITS-1:0] d_wr, d_rd;
reg [DESC_BITS:0]   d_cnt;

assign o_frame_count = d_cnt;

/*------------------------------------------------------------------*/
/* housekeeping counters                                            */
/*------------------------------------------------------------------*/
reg [31:0] us_ctr;
reg [31:0] seq_ctr;
reg [15:0] drop_ctr;
reg        sticky_ovf;

assign o_overflow = sticky_ovf;

/*------------------------------------------------------------------*/
/* in-flight frame state                                            */
/*------------------------------------------------------------------*/
reg        active;
reg        trunc;
reg [15:0] orig_len;
reg [7:0]  rate_l;
reg [31:0] ts_l;

wire space_left = ((used + pending) < SIZE);
wire desc_room  = (d_cnt != DEPTH);

/* a commit needs both a descriptor slot and every byte actually stored */
wire commit_ok  = desc_room && !trunc && (i_fcs_ok || i_keep_bad);

/* head frame length, for the pop arithmetic */
wire [15:0] head_len = d_len[d_rd];

/* The write side (commit/rollback) and the read side (pop) are independent
   and CAN land on the same clock, so the two shared counters are updated once
   at the end of the block from both deltas - an earlier version decremented
   the count on a coincident pop without advancing the read pointers, which
   loses a frame and desynchronises the queue. */
wire do_pop    = i_pop && (d_cnt != 0);
wire do_commit = i_fcs_stb && active && commit_ok;

always @(posedge i_clk) begin
    if (i_rst || i_flush) begin
        wr_ptr     <= {ADDR_BITS{1'b0}};
        commit_ptr <= {ADDR_BITS{1'b0}};
        rd_ptr     <= {ADDR_BITS{1'b0}};
        used       <= {(ADDR_BITS+1){1'b0}};
        pending    <= {(ADDR_BITS+1){1'b0}};
        d_wr       <= {DESC_BITS{1'b0}};
        d_rd       <= {DESC_BITS{1'b0}};
        d_cnt      <= {(DESC_BITS+1){1'b0}};
        active     <= 1'b0;
        trunc      <= 1'b0;
        drop_ctr   <= 16'd0;
        seq_ctr    <= 32'd0;
        if (i_rst) begin
            us_ctr     <= 32'd0;
            sticky_ovf <= 1'b0;
        end
        else if (i_clr_sticky)
            sticky_ovf <= 1'b0;
    end
    else begin
        if (i_us_tick) us_ctr <= us_ctr + 32'd1;
        if (i_clr_sticky) sticky_ovf <= 1'b0;

        /* ---- start of a frame: PHY header decoded OK -------------- */
        if (i_hdr_valid_stb) begin
            /* rewind anything half-written (a previous frame that never
               reached its FCS - the watchdog restarts the receiver without
               telling us) */
            wr_ptr  <= commit_ptr;
            pending <= {(ADDR_BITS+1){1'b0}};
            trunc   <= 1'b0;
            if (i_hdr_valid) begin
                active   <= 1'b1;
                orig_len <= i_pkt_len;
                rate_l   <= i_pkt_rate;
                ts_l     <= us_ctr;
            end
            else
                active <= 1'b0;
        end

        /* ---- payload ---------------------------------------------- */
        else if (i_byte_stb && active) begin
            if (space_left) begin
                mem[wr_ptr] <= i_byte;
                wr_ptr      <= wr_ptr + 1'b1;
                pending     <= pending + 1'b1;
            end
            else begin
                trunc      <= 1'b1;
                sticky_ovf <= 1'b1;
            end
        end

        /* ---- end of frame: commit or rewind ------------------------ */
        else if (i_fcs_stb && active) begin
            active  <= 1'b0;
            pending <= {(ADDR_BITS+1){1'b0}};
            if (commit_ok) begin
                d_len[d_wr]   <= pending[15:0];
                d_orig[d_wr]  <= orig_len;
                d_rate[d_wr]  <= rate_l;
                d_ts[d_wr]    <= ts_l;
                d_seq[d_wr]   <= seq_ctr;
                d_drop[d_wr]  <= drop_ctr;
                d_flags[d_wr] <= { 4'b0000, sticky_ovf, 1'b0, trunc, i_fcs_ok };
                d_wr          <= d_wr + 1'b1;
                commit_ptr    <= wr_ptr;
                seq_ctr       <= seq_ctr + 32'd1;
            end
            else begin
                /* bad FCS, no descriptor slot, or truncated: drop it */
                wr_ptr <= commit_ptr;
                if (!desc_room || trunc) begin
                    drop_ctr   <= drop_ctr + 16'd1;
                    sticky_ovf <= 1'b1;
                end
            end
        end

        /* ---- decode aborted mid-frame ------------------------------ */
        else if (i_abort && active) begin
            active  <= 1'b0;
            wr_ptr  <= commit_ptr;
            pending <= {(ADDR_BITS+1){1'b0}};
        end

        /* ---- host retires the head frame (independent of the above) - */
        if (do_pop) begin
            d_rd   <= d_rd + 1'b1;
            rd_ptr <= rd_ptr + head_len[ADDR_BITS-1:0];
        end

        /* ---- the two counters both sides touch --------------------- */
        d_cnt <= d_cnt + (do_commit ? 1'b1 : 1'b0) - (do_pop ? 1'b1 : 1'b0);
        used  <= used
                 + (do_commit ? pending  : {(ADDR_BITS+1){1'b0}})
                 - (do_pop    ? {1'b0, head_len[ADDR_BITS-1:0]} : {(ADDR_BITS+1){1'b0}});
    end
end

/*------------------------------------------------------------------*/
/* descriptor byte mux (16 bytes, little endian)                    */
/*------------------------------------------------------------------*/
always @(posedge i_clk) begin
    case (i_desc_idx)
        4'd0:  o_desc_byte <= d_flags[d_rd];
        4'd1:  o_desc_byte <= d_rate[d_rd];
        4'd2:  o_desc_byte <= d_len[d_rd][7:0];
        4'd3:  o_desc_byte <= d_len[d_rd][15:8];
        4'd4:  o_desc_byte <= d_orig[d_rd][7:0];
        4'd5:  o_desc_byte <= d_orig[d_rd][15:8];
        4'd6:  o_desc_byte <= d_drop[d_rd][7:0];
        4'd7:  o_desc_byte <= d_drop[d_rd][15:8];
        4'd8:  o_desc_byte <= d_ts[d_rd][7:0];
        4'd9:  o_desc_byte <= d_ts[d_rd][15:8];
        4'd10: o_desc_byte <= d_ts[d_rd][23:16];
        4'd11: o_desc_byte <= d_ts[d_rd][31:24];
        4'd12: o_desc_byte <= d_seq[d_rd][7:0];
        4'd13: o_desc_byte <= d_seq[d_rd][15:8];
        4'd14: o_desc_byte <= d_seq[d_rd][23:16];
        default: o_desc_byte <= d_seq[d_rd][31:24];
    endcase
end

endmodule
