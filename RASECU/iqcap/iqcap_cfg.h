/*
 * SPDX-FileCopyrightText: 2026 Tobias Weber <tobiw@supralfuid.com>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
/*
 * iqcap_cfg.h - IQ snapshot transport configuration (doc/iq_capture/SPEC.md
 * sections 4, 7, 9): typed access to FPGA1's capture registers (CS1) and
 * FPGA2's network registers (CS2), a persisted settings block, and the
 * status/counter readers used by the console and the web GUI.
 *
 * TREE-INDEPENDENT: the module needs only four register accessors, an
 * optional non-volatile load/save pair and an optional bus guard, all handed
 * in through iqcap_port_t. STM32H743_Test wires rasbb_fpga_* + the flash
 * store in iqcap_nv_h7.c; RASBB_ECU can wire its own.
 */
#ifndef IQCAP_CFG_H
#define IQCAP_CFG_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#define IQCAP_NMAC        8u
#define IQCAP_NSAMP_MAX   1024u
#define IQCAP_CFG_MAGIC   0x47464351u   /* "QCFG" */
#define IQCAP_CFG_VERSION 5u      /* v5 (2026-10-02): + phase averaging; v4: + display switches; v3: + HDMI pop-up box; v2 (2026-09-24): + gain_trim_ddb; older blocks are migrated */
#define IQCAP_OVL_MAX     120u    /* pop-up text, bytes incl. 0x0D line breaks */
#define IQCAP_PHY_ID_RTL8211E 0x001CC915u

typedef struct {
    uint8_t mac[6];        /* byte 0 = first on air */
    uint8_t en;
    uint8_t rsvd;
} iqcap_mac_t;

typedef struct {
    uint32_t magic;
    uint16_t version;
    uint16_t size;
    /* FPGA1 capture, SPEC section 4 */
    uint8_t  cap_enable, pass_all, require_fcs, test_pattern;
    uint16_t nsamp, pretrig;
    iqcap_mac_t mac[IQCAP_NMAC];
    /* FPGA2 network, SPEC section 7 */
    uint8_t  src_mac[6], dst_mac[6];
    uint8_t  src_ip[4], dst_ip[4];
    uint16_t src_port, dst_port;
    uint8_t  tx_enable, use_bcast, net_test, rsvd0;
    /* v2: amplitude-DF gain trim per receive path J1..J4 (ch0..3), tenths of
       a dB ADDED to that channel's power before the bearing (FPGA1 0x18,
       1 LSB there = 0.376 dB). Measured with a split test signal (SPEC 0x18,
       VALIDATION s7.4); hardware property, persisted. */
    int16_t  gain_trim_ddb[4];
    /* v3: HDMI pop-up box on FPGA1 (OWIFI_RX ovl_box.v, registers 0x08..0x0B):
       a white window in the lower right corner with the project logo and
       this text below it. scale 0 = the FPGA's default magnification (2),
       1..4 explicit; colours RGB 4:4:4. Text NUL-terminated, 0x0D = line
       break (console / web write "\r"). */
    uint8_t  ovl_show, ovl_center, ovl_scale, ovl_rsvd;
    uint16_t ovl_text_rgb, ovl_box_rgb;
    char     ovl_text[IQCAP_OVL_MAX + 4];
    /* v4: HDMI display switches (FPGA1 DISP_CTRL 0x0C), set from the
       on-screen menu (menu.c) or the console: FCS-bad frames drawn (red rays,
       label moves; default 1), the label position (bearing) averaging 1/2^k,
       k = 0..7 (default 4 = 1/16) and, v5, the phase dot averaging on the
       same scale (default 4). Pause is run-time only, never stored.
       disp_solo (2026-10-04, DISP_CTRL b2; the byte was reserved and 0 before,
       so the block version stays 5): rays, labels and phase dots only for
       transmitters in the capture MAC filter list (default 0). */
    uint8_t  disp_show_bad, disp_avg_shift, disp_ph_shift, disp_solo;
    uint32_t crc;          /* CRC-32 over everything above */
} iqcap_cfg_t;

typedef struct {
    bool (*f1_read)(uint8_t addr, uint32_t *val);   /* FPGA1, CS1: 32-bit word at addr */
    bool (*f1_write)(uint8_t addr, uint32_t val);
    bool (*f2_read)(uint8_t addr, uint32_t *val);   /* FPGA2, CS2: LE word at addr..addr+3 */
    bool (*f2_write)(uint8_t addr, uint32_t val);
    bool (*nv_load)(void *buf, size_t n);           /* NULL = volatile */
    bool (*nv_save)(const void *buf, size_t n);
} iqcap_port_t;

typedef struct { uint32_t ctrl, nsamp, pretrig, trig, match, drop, sent, link, rd_xor; } iqcap_stat1_t;
typedef struct { uint32_t phy_id, stat, ctrl, pkt, snap, crc_err, frame_err, pending; } iqcap_stat2_t;
/* 4.b phase comparison, FPGA1 0x74..0x77 (SPEC v0.5 s4): last committed frame */
typedef struct { uint16_t count; bool valid, weak; uint16_t ph[3]; uint8_t exp[3]; } iqcap_phase_t;

void         iqcap_cfg_init(const iqcap_port_t *port);   /* loads NV or defaults */
iqcap_cfg_t *iqcap_cfg(void);
void         iqcap_cfg_defaults(iqcap_cfg_t *c);
bool         iqcap_cfg_save(void);                       /* NV, if provided */
bool         iqcap_cfg_apply_fpga1(void);                /* capture registers + display switches + the pop-up box */
bool         iqcap_cap_apply_fpga1(void);                /* the capture registers alone (0x10.. / MAC filter) */
bool         iqcap_ovl_apply_fpga1(void);                /* the pop-up box alone (0x08..0x0B) */
/* pop-up text: the escapes \r \n (line break) and \\ are decoded, the rest is
   stored as typed (printable ASCII; the FPGA ignores other bytes), cut at
   IQCAP_OVL_MAX. Returns the number of bytes stored. */
size_t       iqcap_ovl_set_text(const char *s);
int          iqcap_ovl_fmt_text(char *dst, size_t n, const char *text);   /* re-escaped for display */

/* display switches (FPGA1 DISP_CTRL 0x0C): the stored show_bad / avg_shift plus
   the run-time pause; the clear pulse resets the station list, labels and rays */
bool         iqcap_disp_apply_fpga1(void);
bool         iqcap_disp_clear_fpga1(void);
bool         iqcap_disp_set_pause(bool on);         /* applies at once */
bool         iqcap_disp_pause(void);
/* run-time hide of the pop-up box (menu escape / OK), not stored: the box
   shows when ovl_show is set and it is not hidden, or while paused */
bool         iqcap_ovl_set_hidden(bool on);         /* applies at once */
bool         iqcap_ovl_hidden(void);

/* pop-up frames drawn by the menu: raw text (0x0D = line break) and up to
   IQCAP_OVL_NRECT filled rectangles, visible together at commit. Coordinates
   are pixels relative to the first text line's top left corner, signed; a
   size of IQCAP_OVL_FULL reaches the frame. iqcap_ovl_apply_fpga1() restores
   the stored text afterwards. */
#define IQCAP_OVL_NRECT 8u
#define IQCAP_OVL_FULL  0xFFFu
#define IQCAP_OVL_PAD   16              /* the box's padding, the FPGA's PAD parameter */
bool         iqcap_ovl_frame_begin(void);
bool         iqcap_ovl_frame_text(const char *s, size_t n);
bool         iqcap_ovl_frame_rect(int x, int y, unsigned w, unsigned h, uint16_t text_rgb, uint16_t fill_rgb);
bool         iqcap_ovl_frame_commit(bool show, bool center, unsigned scale);
bool         iqcap_cfg_apply_fpga2(void);
bool         iqcap_stat_fpga1(iqcap_stat1_t *s);
bool         iqcap_phase_fpga1(iqcap_phase_t *p);             /* ph[k] = ch k+1 vs ch0, 65536 = 360 deg */
bool         iqcap_phase_window_fpga1(uint16_t start, uint16_t len); /* PH_START / PH_LEN (not persisted) */
/* rim-marker calibration (SPEC 0x16 PH_CAL, 0x78/0x79): per boot, not persisted */
typedef struct { bool ok; uint16_t count, ang, raw, brg; } iqcap_mark_t;  /* bins 0..511, CCW from east */
bool         iqcap_mark_fpga1(iqcap_mark_t *m);
bool         iqcap_phase_cal_get_fpga1(uint16_t *turns);
bool         iqcap_phase_cal_set_fpga1(uint16_t turns);
uint32_t     iqcap_gain_trim_word(const int16_t ddb[4]);      /* 4 x int8 in 0.376 dB counts, ch c at [8c +: 8] */
int          iqcap_phase_deg10(uint16_t turns);               /* -1800..1800 = degrees x 10 */
bool         iqcap_stat_fpga2(iqcap_stat2_t *s);
bool         iqcap_fpga2_present(void);                  /* PHY_ID == RTL8211E */
bool         iqcap_clear_counters(void);                 /* both FPGAs */

bool iqcap_parse_mac(const char *s, uint8_t mac[6]);     /* aa:bb:cc:dd:ee:ff or aabbccddeeff */
bool iqcap_parse_ip(const char *s, uint8_t ip[4]);
int  iqcap_fmt_mac(char *dst, size_t n, const uint8_t mac[6]);
int  iqcap_fmt_ip(char *dst, size_t n, const uint8_t ip[4]);

/* STM32H743 flash store (iqcap_nv_h7.c): bank 2, last sector */
bool iqcap_nv_h7_load(void *buf, size_t n);
bool iqcap_nv_h7_save(const void *buf, size_t n);

#endif
