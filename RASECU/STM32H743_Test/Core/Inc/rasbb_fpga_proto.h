/*
 * rasbb_fpga_proto.h - FPGA1 <-> STM32H743 SPI protocol for OWIFI_RX frame
 * delivery.  Shared definition: keep in step with
 * owifi.srcs/sources_1/spi_frame_if.v and frame_buffer.v.
 *
 * BUS (from RASBB.kicad_pcb, verified 2026-07-31)
 *   STM32 SPI4  PE12 SCK  --R13--> SCK_FLASH_uC --> FPGA1 D18
 *               PE14 MOSI --R14--> SI_FLASH_uC  --> FPGA1 E17
 *               PE13 MISO <-------- SO_FLASH_uC <-- FPGA1 D17
 *               PE11 CS   --------> CS_FLASH_uC --> FPGA1 E18
 *   Mode 0 (CPOL=0, CPHA=0), MSB first, SCLK <= 12.5 MHz (the FPGA
 *   oversamples SCLK at 100 MHz and needs 8 clocks per bit).
 *   Drive CS from software GPIO, not hardware NSS: one CS-low window must
 *   span a whole multi-hundred-byte burst.
 *
 * SHARING THE BUS WITH THE CONFIG FLASH
 *   The FPGA's user pins tap this bus permanently; the TS3A5018 (IC6) decides
 *   whether the config flash IC5 hangs on it too.  Both controls have 10k
 *   pull-downs, so the resting state connects the flash to the FPGA's
 *   configuration pins and CS_FLASH_uC then selects ONLY the FPGA.
 *     - normal operation: leave SWITCH_FLASH_1 (PB15) low.
 *     - reprogramming the config flash: drive it high; the FPGA still sees
 *       every byte, but none of the opcodes below collide with the SPI-NOR
 *       command set, so it stays tri-stated and ignores the traffic.
 */
#ifndef RASBB_FPGA_PROTO_H
#define RASBB_FPGA_PROTO_H

#include <stdint.h>

/* ---- opcodes (byte 0; MISO is high-Z during this byte) ----------------- */
#define RASBB_OP_NOP         0xA4u  /* [A4][xx]                    -> status  */
#define RASBB_OP_READ_FRAME  0xA5u  /* [A5][xx] + 16+len dummies            */
#define RASBB_OP_POP         0xA6u  /* [A6][xx]  retires head frame on CS up */
#define RASBB_OP_STATUS_EXT  0xA7u  /* [A7][xx] + 8 dummies                 */
#define RASBB_OP_WRITE_REG   0xA8u  /* [A8][addr][b31_24..b7_0]             */
#define RASBB_OP_READ_REG    0xA9u  /* [A9][addr] + 4 dummies               */
#define RASBB_OP_CONTROL     0xAAu  /* [AA][ctrl]                           */

/* ---- STATUS byte: always returned as byte 1 of every transaction ------- */
#define RASBB_ST_FRAME_READY   0x01u
#define RASBB_ST_OVERFLOW      0x02u  /* sticky: something was dropped      */
#define RASBB_ST_LINK_OK       0x04u  /* ADC LVDS link healthy              */
#define RASBB_ST_FE_VALID      0x08u  /* front end delivering samples       */
#define RASBB_ST_DEMOD         0x10u  /* a decode is in progress            */
#define RASBB_ST_COUNT_SHIFT   5u     /* queued frames, saturating at 7     */
#define RASBB_ST_COUNT(s)      (((s) >> RASBB_ST_COUNT_SHIFT) & 0x07u)

/* ---- CONTROL byte ------------------------------------------------------ */
#define RASBB_CTRL_FLUSH       0x01u  /* discard the whole queue            */
#define RASBB_CTRL_CLR_STICKY  0x02u  /* clear the overflow flag            */
#define RASBB_CTRL_KEEP_BAD    0x04u  /* level: also queue bad-FCS frames   */

/* ---- config register addresses (openwifi common_params.v) -------------- */
#define RASBB_REG_POWER_THRES   3u
#define RASBB_REG_POWER_WINDOW  4u
#define RASBB_REG_SKIP_SAMPLE   5u
#define RASBB_REG_MIN_PLATEAU   6u

/*
 * 16-byte frame descriptor, little endian, returned by READ_FRAME before the
 * payload.  'len' is what actually follows on the wire; 'orig_len' is the
 * length dot11 read out of the SIGNAL field (they differ only if the frame
 * was truncated, and truncated frames are dropped rather than queued).
 */
typedef struct __attribute__((packed)) {
    uint8_t  flags;        /* bit0 fcs_ok, bit1 truncated, bit3 overflow     */
    uint8_t  rate;         /* dot11 o_pkt_rate                               */
    uint16_t len;          /* payload bytes that follow                      */
    uint16_t orig_len;     /* length announced in the PHY header             */
    uint16_t dropped;      /* frames lost to a full buffer, at capture time  */
    uint32_t timestamp_us; /* 1us tick, wraps every ~71 minutes              */
    uint32_t seq;          /* monotonic committed-frame counter              */
} rasbb_frame_desc_t;

#define RASBB_DESC_FCS_OK    0x01u
#define RASBB_DESC_TRUNCATED 0x02u

/* ---- extended status block (8 bytes after the STATUS byte) ------------- */
typedef struct __attribute__((packed)) {
    uint8_t version;        /* 0x01                                          */
    uint8_t frame_count;    /* exact queue depth (0..16)                     */
    uint8_t flags;          /* bit0 link_ok, bit1 overflow, bit2 keep_bad    */
    uint8_t retrain_count;  /* front-end LVDS retrains (link health)         */
    uint8_t rot_change;     /* word-rotation changes (link health)           */
    uint8_t fcs_err_count;  /* frames seen with a bad checksum               */
    uint8_t rsvd[2];
} rasbb_status_ext_t;

/*
 * Suggested host loop:
 *   every ~2ms:  tx {A4,00} rx {xx,status}          <- 2 bytes, ~1.3us
 *   if status & RASBB_ST_FRAME_READY:
 *       tx {A5,00} + 16 dummies -> descriptor
 *       continue clocking desc.len dummies          -> payload (DMA)
 *       tx {A6,00}                                  -> pop
 *
 * H7 TRAP: if the RX buffer is in cacheable memory, invalidate it after the
 * DMA completes (or place it in a non-cacheable MPU region), otherwise the
 * CPU reads stale data and it looks exactly like a broken link.
 */

#endif /* RASBB_FPGA_PROTO_H */
