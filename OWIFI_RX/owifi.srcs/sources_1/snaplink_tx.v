//////////////////////////////////////////////////////////////////////////////////
//
// Design Name: OWIFI_RX
// Module Name: snaplink_tx
// Project Name: RA-Sentinel IQ snapshot transport (doc/iq_capture/SPEC.md §5)
// Engineer: Tobias Weber
// Target Devices: Artix 7, XC7A100T (RASBB baseboard, FPGA1 = U10)
// Description:
//   SNAPLINK v1 transmitter: takes snapshots from iq_capture's read-out port
//   (100 MHz) and ships them to FPGA2 over the 32-line DEBUG bus as 24-bit
//   words on a forwarded 20 MHz clock (LCLK), source-synchronous:
//
//     word 0        0xA5C3E1 (SOF)
//     word 1..24    descriptor, 72 bytes (v2 "IQD2"), byte 0 in bits [7:0] of word 1
//     4 per instant {I[11:0],Q[11:0]} of channel 0,1,2,3
//     last          CRC-24 (snaplink_crc24) over all previous words
//
//   VALID is high for exactly the packet's words; between packets VALID = 0
//   and the data alternates 0xAAAAAA / 0x555555 (link-alive pattern).
//   Data and VALID change on the RISING edge of LCLK (the ODDR forwards the
//   clock edge-aligned); FPGA2 samples on the falling edge.
//
//   STORE-AND-FORWARD: the whole packet (up to 4122 words) is written into
//   an async FIFO by the 100 MHz generator before the 20 MHz side starts
//   shifting it out, so VALID can never stall mid-packet. A packet is only
//   generated when the FIFO has room for a maximal one and FPGA2's READY
//   line (synchronised) is high; otherwise the capture slot simply waits.
//
// Dependencies: snaplink_crc24.v (DFPGA/rtl, shared), xpm_fifo_async
//
// Additional Comments: https://github.com/Tobias-DG3YEV/RA-Sentinel
//
//////////////////////////////////////////////////////////////////////////////////
// Copyright (C) 2026 Tobias Weber
// License: GNU GPL v3
//////////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps

module snaplink_tx #(
    parameter FIFO_DEPTH = 8192          // >= 4122 + margin, words
)(
    input  wire         i_clk,           // 100 MHz
    input  wire         i_rst,
    input  wire         i_lclk,          // 20 MHz link clock (BUFG'd PLL output)

    /* iq_capture read-out port */
    input  wire [575:0] i_rd_desc,
    input  wire         i_rd_valid,
    output reg          o_rd_ready,
    input  wire [95:0]  i_rd_inst,
    input  wire         i_rd_inst_valid,
    input  wire         i_rd_last,

    /* pads */
    input  wire         i_ready_pad,     // READY from FPGA2 (async)
    output wire         o_lclk_pad,      // forwarded clock (ODDR)
    output reg  [23:0]  o_d,             // registered on i_lclk
    output reg          o_valid,
    output reg          o_aux,

    /* status (i_clk) */
    output wire         o_fpga2_ready,
    output wire         o_busy,
    output reg  [31:0]  o_pkt_count
);

localparam [23:0] SOF = 24'hA5C3E1;
localparam [15:0] MAX_WORDS = 16'd4122 + 16'd8;   // SOF + 24 desc + 4*1024 + CRC

/*------------------------------------------------------------------*/
/* READY synchroniser                                               */
/*------------------------------------------------------------------*/
(* ASYNC_REG = "true" *) reg [1:0] ready_s = 2'b00;
always @(posedge i_clk) ready_s <= {ready_s[0], i_ready_pad};
assign o_fpga2_ready = ready_s[1];

/*------------------------------------------------------------------*/
/* packet FIFO (100 MHz -> 20 MHz), word + last flag                */
/*------------------------------------------------------------------*/
reg         f_wr;
reg  [24:0] f_din;
wire [24:0] f_dout;
wire        f_empty, f_rd;
wire [13:0] f_wr_count;

xpm_fifo_async #(
    .FIFO_MEMORY_TYPE("block"),
    .FIFO_WRITE_DEPTH(FIFO_DEPTH),
    .WRITE_DATA_WIDTH(25),
    .READ_DATA_WIDTH(25),
    .READ_MODE("fwft"),
    .FIFO_READ_LATENCY(0),
    .CDC_SYNC_STAGES(2),
    .WR_DATA_COUNT_WIDTH(14),
    .RD_DATA_COUNT_WIDTH(14),
    .USE_ADV_FEATURES("0404")           // wr_data_count + rd_data_count
) u_fifo (
    .rst(i_rst), .wr_clk(i_clk), .wr_en(f_wr), .din(f_din),
    .rd_clk(i_lclk), .rd_en(f_rd), .dout(f_dout), .empty(f_empty),
    .wr_data_count(f_wr_count), .rd_data_count(),
    .full(), .almost_full(), .almost_empty(), .data_valid(), .dbiterr(),
    .overflow(), .prog_empty(), .prog_full(), .rd_rst_busy(),
    .sbiterr(), .underflow(), .wr_ack(), .wr_rst_busy(),
    .injectdbiterr(1'b0), .injectsbiterr(1'b0), .sleep(1'b0)
);

/* packets written (gray) -> lclk domain, so the reader only starts a packet
   that is completely in the FIFO */
reg  [3:0] pkt_wr = 4'd0;
wire [3:0] pkt_wr_gray = pkt_wr ^ (pkt_wr >> 1);
(* ASYNC_REG = "true" *) reg [3:0] pkt_gray_s0 = 4'd0, pkt_gray_s1 = 4'd0;
always @(posedge i_lclk) begin pkt_gray_s0 <= pkt_wr_gray; pkt_gray_s1 <= pkt_gray_s0; end
wire [3:0] pkt_wr_l = pkt_gray_s1 ^ (pkt_gray_s1 >> 1) ^ (pkt_gray_s1 >> 2) ^ (pkt_gray_s1 >> 3);

/*------------------------------------------------------------------*/
/* generator (100 MHz)                                              */
/*------------------------------------------------------------------*/
localparam [2:0] G_IDLE = 3'd0, G_DESC = 3'd1, G_INST = 3'd2, G_CRC = 3'd3;
reg  [2:0]   g;
reg  [4:0]   dw;                          // descriptor word index
reg  [575:0] desc_q;
reg  [95:0]  inst_q;
reg  [1:0]   iw;                          // instant word index
reg          inst_pend, last_pend;
reg  [23:0]  crc;
wire [23:0]  crc_next;
reg  [23:0]  crc_in;
reg          ready_gap;                   // spacing of ready pulses

snaplink_crc24 u_crc (.i_crc(crc), .i_word(crc_in), .o_crc(crc_next));

assign o_busy = (g != G_IDLE);
wire room = (f_wr_count < (FIFO_DEPTH - MAX_WORDS));

wire [23:0] desc_word = desc_q[24*dw +: 24];
wire [23:0] inst_word = inst_q[24*iw +: 24];

always @(posedge i_clk) begin
    f_wr       <= 1'b0;
    o_rd_ready <= 1'b0;
    if (i_rst) begin
        g <= G_IDLE; dw <= 5'd0; iw <= 2'd0; crc <= 24'd0; crc_in <= 24'd0;
        inst_pend <= 1'b0; last_pend <= 1'b0; pkt_wr <= 4'd0; o_pkt_count <= 32'd0;
        desc_q <= 576'd0; inst_q <= 96'd0; f_din <= 25'd0; ready_gap <= 1'b0;
    end
    else begin
        case (g)
        G_IDLE: begin
            if (i_rd_valid && ready_s[1] && room) begin
                desc_q <= i_rd_desc;
                f_wr   <= 1'b1; f_din <= {1'b0, SOF};
                crc    <= 24'd0; crc_in <= SOF;
                dw     <= 5'd0;
                g      <= G_DESC;
            end
        end
        G_DESC: begin
            crc    <= crc_next;                  // absorb previous word
            f_wr   <= 1'b1; f_din <= {1'b0, desc_word}; crc_in <= desc_word;
            if (dw == 5'd23) begin
                g <= G_INST; iw <= 2'd0; inst_pend <= 1'b0; last_pend <= 1'b0;
                o_rd_ready <= 1'b1;              // fetch the first instant
                ready_gap  <= 1'b0;
            end
            dw <= dw + 5'd1;
        end
        G_INST: begin
            if (i_rd_inst_valid) begin           // one instant arrives (3 clocks after ready)
                inst_q    <= i_rd_inst;
                inst_pend <= 1'b1;
                last_pend <= i_rd_last;
                iw        <= 2'd0;
            end
            if (inst_pend) begin
                crc    <= crc_next;
                f_wr   <= 1'b1; f_din <= {1'b0, inst_word}; crc_in <= inst_word;
                iw     <= iw + 2'd1;
                if (iw == 2'd3) begin
                    inst_pend <= 1'b0;
                    if (last_pend) g <= G_CRC;
                    else           o_rd_ready <= 1'b1;   // next instant
                end
            end
        end
        G_CRC: begin
            crc    <= crc_next;
            f_wr   <= 1'b1; f_din <= {1'b1, crc_next};
            pkt_wr <= pkt_wr + 4'd1;
            o_pkt_count <= o_pkt_count + 32'd1;
            g <= G_IDLE;
        end
        default: g <= G_IDLE;
        endcase
    end
end

/*------------------------------------------------------------------*/
/* shifter (20 MHz)                                                 */
/*------------------------------------------------------------------*/
reg [3:0] pkt_rd = 4'd0;
reg       sending = 1'b0;
reg       idle_tog = 1'b0;
assign f_rd = sending & ~f_empty;

always @(posedge i_lclk) begin
    idle_tog <= ~idle_tog;
    o_aux    <= 1'b0;
    if (!sending) begin
        o_valid <= 1'b0;
        o_d     <= idle_tog ? 24'h555555 : 24'hAAAAAA;
        if (pkt_rd != pkt_wr_l && !f_empty) sending <= 1'b1;
    end
    else begin
        if (!f_empty) begin
            o_valid <= 1'b1;
            o_d     <= f_dout[23:0];
            if (f_dout[24]) begin
                sending <= 1'b0;
                pkt_rd  <= pkt_rd + 4'd1;
            end
        end
    end
end

/* forwarded clock: rising edge aligned with the data change */
ODDR #(.DDR_CLK_EDGE("SAME_EDGE"), .INIT(1'b0), .SRTYPE("ASYNC")) u_oddr_lclk (
    .Q(o_lclk_pad), .C(i_lclk), .CE(1'b1), .D1(1'b1), .D2(1'b0), .R(1'b0), .S(1'b0)
);

endmodule
