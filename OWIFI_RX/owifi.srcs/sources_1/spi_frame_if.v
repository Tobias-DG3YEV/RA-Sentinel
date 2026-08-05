//////////////////////////////////////////////////////////////////////////////////
//
// Design Name: OWIFI_RX
// Module Name: spi_frame_if
// Project Name: RA-Sentinel 802.11 receiver
// Engineer: Tobias Weber
// Target Devices: Artix 7, XC7A100T (RASBB baseboard)
// Description:
//   SPI slave for the STM32H743: frame read-out plus the dot11 config
//   registers.  Replaces SPI_Peripheral.v on this design (that module is left
//   untouched because RASM2400 uses it).
//
//   TWO DELIBERATE DIFFERENCES FROM SPI_Peripheral:
//
//   1) SCLK is OVERSAMPLED in the 100MHz receiver clock instead of being used
//      as a clock.  SCLK arrives on D18, which is not clock-capable - the old
//      module needed a CLOCK_DEDICATED_ROUTE waiver and a BUFG on a fabric
//      route, which is tolerable for the odd 32-bit config write and a poor
//      foundation for streaming kilobytes.  Oversampling removes the clock
//      domain entirely: this block, the frame buffer and dot11 all run on
//      clk_100M.  LIMIT: 8 fabric clocks per SPI bit means SCLK <= 12.5MHz.
//
//   2) The transaction starts with a one-byte OPCODE, and CIPO stays
//      tri-stated until that opcode is recognised.  This is not paranoia
//      about bus arbitration - CS_FLASH_uC selects only this FPGA in normal
//      operation.  It covers the one window where that is NOT true: when
//      firmware drives SWITCH_FLASH_1 high to reprogram the FPGA config
//      flash, IC5 is switched onto the very same bus and CS line, and an
//      ungated slave would drive D17 against the flash's SO and could decode
//      a Page-Program opcode as a register write.  The opcodes below are all
//      outside the SPI-NOR command space (nearest neighbours 0xA3 and 0xAB
//      are avoided), so flash traffic can never address this block and this
//      block's traffic can never address the flash.  Cost: zero extra bytes.
//
//   Wire format (MOSI -> MISO), CPOL=0 CPHA=0, MSB first:
//
//     byte 0 : opcode                       MISO: high-Z (never driven)
//     byte 1 : dummy / address / control    MISO: STATUS byte
//     byte 2+: payload per opcode
//
//   A poll is therefore a 2-byte transaction (~1.3us at 12.5MHz).
//
//     0xA4 NOP        [A4][xx]                     -> [zz][status]
//     0xA5 READ_FRAME [A5][xx] + N dummies         -> [zz][status][desc 16][payload]
//                     does NOT retire the frame, so a garbled read is retryable
//     0xA6 POP        [A6][xx]                     -> retires the head frame on CS rise
//     0xA7 STATUS_EXT [A7][xx] + 8 dummies         -> [zz][status][8 diag bytes]
//     0xA8 WRITE_REG  [A8][addr][d31:24..d7:0]     -> applied on CS rise
//     0xA9 READ_REG   [A9][addr] + 4 dummies       -> [zz][status][d31:24..d7:0]
//     0xAA CONTROL    [AA][ctrl]                   -> applied on CS rise
//
//   STATUS byte: {frame_count[2:0] saturating, demod, fe_valid, link_ok,
//                 overflow_sticky, frame_ready}
//   CONTROL bits: 0 = flush buffer, 1 = clear sticky overflow,
//                 2 = keep frames with bad FCS (level, latched)
//
// Dependencies: frame_buffer.v, conf_registers (registers.v)
//
// Additional Comments: https://github.com/Tobias-DG3YEV/RA-Sentinel
//
//////////////////////////////////////////////////////////////////////////////////
// Copyright (C) 2026 Tobias Weber
// License: GNU GPL v3
//////////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps

module spi_frame_if #(
    parameter REG_ADDR_W = 7,
    parameter DESC_BITS  = 4
)(
    input  wire i_clk,                 // 100MHz, same domain as the frame buffer
    input  wire i_rst,

    /* SPI pads (asynchronous - oversampled here) */
    input  wire i_sclk,
    input  wire i_copi,
    input  wire i_ncs,
    output wire o_cipo,
    output wire o_cipo_oe,             // drive the pad only while this is high

    /* status sources */
    input  wire i_link_ok,
    input  wire i_fe_valid,
    input  wire i_demod_ongoing,
    input  wire [7:0] i_retrain_count,
    input  wire [7:0] i_rot_change_count,
    input  wire [7:0] i_fcs_err_cnt,

    /* frame buffer port */
    input  wire [DESC_BITS:0] i_frame_count,
    input  wire i_buf_overflow,
    output wire [3:0]  o_desc_idx,
    input  wire [7:0]  i_desc_byte,
    output wire [15:0] o_pay_offset,
    input  wire [7:0]  i_pay_byte,
    output reg  o_pop,
    output reg  o_flush,
    output reg  o_clr_sticky,
    output reg  o_keep_bad,

    /* config register bus (conf_registers) */
    output reg  [REG_ADDR_W-1:0] o_reg_addr,
    output reg  o_reg_wr,
    output reg  [31:0] o_reg_wdata,
    input  wire [31:0] i_reg_rdata
);

localparam OP_NOP        = 8'hA4;
localparam OP_READ_FRAME = 8'hA5;
localparam OP_POP        = 8'hA6;
localparam OP_STATUS_EXT = 8'hA7;
localparam OP_WRITE_REG  = 8'hA8;
localparam OP_READ_REG   = 8'hA9;
localparam OP_CONTROL    = 8'hAA;

/*------------------------------------------------------------------*/
/* pad synchronisers + edge detect                                  */
/*------------------------------------------------------------------*/
(* ASYNC_REG = "true" *) reg [2:0] sclk_s = 3'b000;
(* ASYNC_REG = "true" *) reg [2:0] copi_s = 3'b000;
(* ASYNC_REG = "true" *) reg [2:0] ncs_s  = 3'b111;

always @(posedge i_clk) begin
    sclk_s <= {sclk_s[1:0], i_sclk};
    copi_s <= {copi_s[1:0], i_copi};
    ncs_s  <= {ncs_s[1:0],  i_ncs};
end

wire sclk_rise = (sclk_s[2:1] == 2'b01);
wire sclk_fall = (sclk_s[2:1] == 2'b10);
wire cs_active = ~ncs_s[1];
wire cs_fall   = (ncs_s[2:1] == 2'b10);
wire cs_rise   = (ncs_s[2:1] == 2'b01);

/*------------------------------------------------------------------*/
/* shift engine                                                     */
/*------------------------------------------------------------------*/
reg [2:0]  bit_cnt;
reg [15:0] byte_idx;
reg [7:0]  rx_shift;
reg [7:0]  opcode;
reg        opcode_ok;
reg [7:0]  tx_shift;
reg        tx_oe;

wire [7:0] rx_byte = {rx_shift[6:0], copi_s[1]};
wire byte_done = sclk_rise && cs_active && (bit_cnt == 3'd7);

assign o_cipo    = tx_shift[7];
assign o_cipo_oe = tx_oe && cs_active;

/* status byte */
wire [2:0] fc_sat = (i_frame_count > 7) ? 3'd7 : i_frame_count[2:0];
wire [7:0] status_byte = { fc_sat,
                           i_demod_ongoing,
                           i_fe_valid,
                           i_link_ok,
                           i_buf_overflow,
                           (i_frame_count != 0) };

/* extended status block */
reg [7:0] ext_byte;
always @(*) begin
    case (byte_idx[3:0])
        4'd2:    ext_byte = 8'h01;                    // format version
        4'd3:    ext_byte = { 3'd0, i_frame_count };
        4'd4:    ext_byte = { 5'd0, o_keep_bad, i_buf_overflow, i_link_ok };
        4'd5:    ext_byte = i_retrain_count;
        4'd6:    ext_byte = i_rot_change_count;
        4'd7:    ext_byte = i_fcs_err_cnt;
        default: ext_byte = 8'h00;
    endcase
end

/* Buffer addressing. byte_idx already names the byte that is ABOUT to be
   shifted out: it increments on the rising edge that finishes the previous
   byte, and tx_shift is loaded on the following falling edge - 4 fabric
   clocks later at 12.5MHz, which covers the buffer's 1-clock read latency.
   So the address is simply the current index, with no extra look-ahead
   (adding one was a real bug: every payload byte came out shifted by one).
   Subtract at full width and truncate afterwards - truncating byte_idx to 4
   bits first breaks the descriptor from byte 16 onwards. */
wire [15:0] desc_pos = (byte_idx >= 16'd2) ? (byte_idx - 16'd2) : 16'd0;

assign o_desc_idx   = desc_pos[3:0];
assign o_pay_offset = (byte_idx >= 16'd18) ? (byte_idx - 16'd18) : 16'd0;

/* next byte to transmit, selected by the index it will be shifted out at */
reg [7:0] next_tx;
always @(*) begin
    if (byte_idx == 16'd1)
        next_tx = status_byte;
    else begin
        case (opcode)
            OP_READ_FRAME: next_tx = (byte_idx < 16'd18) ? i_desc_byte : i_pay_byte;
            OP_STATUS_EXT: next_tx = ext_byte;
            OP_READ_REG:   begin
                case (byte_idx[2:0])
                    3'd2:    next_tx = i_reg_rdata[31:24];
                    3'd3:    next_tx = i_reg_rdata[23:16];
                    3'd4:    next_tx = i_reg_rdata[15:8];
                    3'd5:    next_tx = i_reg_rdata[7:0];
                    default: next_tx = 8'h00;
                endcase
            end
            default: next_tx = 8'h00;
        endcase
    end
end

wire opcode_valid = (rx_byte == OP_NOP)       || (rx_byte == OP_READ_FRAME) ||
                    (rx_byte == OP_POP)       || (rx_byte == OP_STATUS_EXT) ||
                    (rx_byte == OP_WRITE_REG) || (rx_byte == OP_READ_REG)   ||
                    (rx_byte == OP_CONTROL);

reg [7:0] ctrl_byte;

always @(posedge i_clk) begin
    if (i_rst) begin
        bit_cnt    <= 3'd0;
        byte_idx   <= 16'd0;
        rx_shift   <= 8'h00;
        opcode     <= 8'h00;
        opcode_ok  <= 1'b0;
        tx_shift   <= 8'h00;
        tx_oe      <= 1'b0;
        o_pop      <= 1'b0;
        o_flush    <= 1'b0;
        o_clr_sticky <= 1'b0;
        o_keep_bad <= 1'b0;
        o_reg_wr   <= 1'b0;
        o_reg_addr <= {REG_ADDR_W{1'b0}};
        o_reg_wdata <= 32'd0;
        ctrl_byte  <= 8'h00;
    end
    else begin
        o_pop        <= 1'b0;
        o_flush      <= 1'b0;
        o_clr_sticky <= 1'b0;
        o_reg_wr     <= 1'b0;

        if (cs_fall) begin
            bit_cnt   <= 3'd0;
            byte_idx  <= 16'd0;
            opcode_ok <= 1'b0;
            tx_oe     <= 1'b0;
        end
        else if (cs_active) begin
            /* ---- receive ---------------------------------------- */
            if (sclk_rise) begin
                rx_shift <= rx_byte;
                bit_cnt  <= bit_cnt + 3'd1;
                if (bit_cnt == 3'd7) begin
                    byte_idx <= byte_idx + 16'd1;
                    if (byte_idx == 16'd0) begin
                        opcode    <= rx_byte;
                        opcode_ok <= opcode_valid;
                    end
                    else if (byte_idx == 16'd1) begin
                        if (opcode == OP_WRITE_REG || opcode == OP_READ_REG)
                            o_reg_addr <= rx_byte[REG_ADDR_W-1:0];
                        if (opcode == OP_CONTROL)
                            ctrl_byte <= rx_byte;
                    end
                    else if (opcode == OP_WRITE_REG && byte_idx <= 16'd5)
                        o_reg_wdata <= {o_reg_wdata[23:0], rx_byte};
                end
            end

            /* ---- transmit ---------------------------------------- */
            if (sclk_fall) begin
                if (bit_cnt == 3'd0) begin
                    tx_shift <= next_tx;
                    tx_oe    <= opcode_ok;
                end
                else
                    tx_shift <= {tx_shift[6:0], 1'b0};
            end
        end

        /* ---- end of transaction: apply side effects -------------- */
        if (cs_rise) begin
            tx_oe <= 1'b0;
            if (opcode_ok) begin
                case (opcode)
                    OP_POP:       if (byte_idx >= 16'd1) o_pop <= 1'b1;
                    OP_WRITE_REG: if (byte_idx >= 16'd6) o_reg_wr <= 1'b1;
                    OP_CONTROL:   if (byte_idx >= 16'd2) begin
                                      o_flush      <= ctrl_byte[0];
                                      o_clr_sticky <= ctrl_byte[1];
                                      o_keep_bad   <= ctrl_byte[2];
                                  end
                    default: ;
                endcase
            end
        end
    end
end

endmodule
