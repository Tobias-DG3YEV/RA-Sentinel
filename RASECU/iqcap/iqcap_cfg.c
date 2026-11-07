/*
 * SPDX-FileCopyrightText: 2026 Tobias Weber <tobiw@supralfuid.com>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

/* iqcap_cfg.c - see iqcap_cfg.h. No HAL, no RTOS: pure register/format logic. */
#include "iqcap_cfg.h"
#include <string.h>
#include <stdio.h>

/* FPGA1 (SPEC section 4; one 32-bit word per address) */
#define F1_CTRL     0x10u
#define F1_NSAMP    0x11u
#define F1_PRETRIG  0x13u
#define F1_MAC(k,j) (0x20u + 8u*(k) + (j))
#define F1_MAC_EN(k) (0x26u + 8u*(k))
#define F1_TRIG     0x60u
#define F1_MATCH    0x64u
#define F1_DROP     0x68u
#define F1_SENT     0x6Cu
#define F1_LINK     0x70u
#define F1_RDXOR    0x71u
#define F1_GAIN_TRIM 0x18u
#define F1_OVL_CTRL  0x08u   /* pop-up box: b0 show, b1 centre, [7:4] scale, b8 BEGIN, b9 COMMIT */
#define F1_OVL_TEXT  0x09u   /* four text bytes, [7:0] first */
#define F1_OVL_COLOR 0x0Au   /* [11:0] text, [23:12] box, RGB 4:4:4 */
#define F1_DISP_CTRL 0x0Cu   /* b0 pause, b1 show FCS-bad, [6:4] label position averaging shift, b8 clear (pulse), [14:12] phase averaging shift */
#define F1_OVL_RPTR  0x0Du   /* rectangle pointer {rect[4:2], word[1:0]} */
#define F1_OVL_RDATA 0x0Eu   /* rectangle words: {y, x}, {h, w}, {en, text rgb, fill rgb} */
/* FPGA2 (SPEC section 7; LE word at addr..addr+3) */
#define F2_SRC_MAC  0x00u
#define F2_SRC_IP   0x08u
#define F2_DST_IP   0x0Cu
#define F2_DST_MAC  0x10u
#define F2_PORTS    0x18u
#define F2_CTRL     0x1Cu
#define F2_STAT     0x20u
#define F2_PKT      0x24u
#define F2_SNAP     0x28u
#define F2_CRCERR   0x2Cu
#define F2_PHYID    0x30u
#define F2_FRMERR   0x34u
#define F2_PEND     0x38u

static iqcap_port_t s_port;
static iqcap_cfg_t  s_cfg;

static uint32_t crc32(const void *p, size_t n)
{
    const uint8_t *b = p;
    uint32_t c = 0xFFFFFFFFu;
    while (n--) {
        c ^= *b++;
        for (int i = 0; i < 8; i++) c = (c >> 1) ^ (0xEDB88320u & (0u - (c & 1u)));
    }
    return ~c;
}
static uint32_t cfg_crc(const iqcap_cfg_t *c) { return crc32(c, offsetof(iqcap_cfg_t, crc)); }

void iqcap_cfg_defaults(iqcap_cfg_t *c)
{
    static const uint8_t src_mac[6] = { 0x02, 0x52, 0x41, 0x53, 0x42, 0x32 };   /* "RASB2" */
    memset(c, 0, sizeof(*c));
    c->magic = IQCAP_CFG_MAGIC; c->version = IQCAP_CFG_VERSION; c->size = sizeof(*c);
    c->cap_enable = 1u; c->pass_all = 1u; c->require_fcs = 0u; c->test_pattern = 0u;
    c->nsamp = IQCAP_NSAMP_MAX; c->pretrig = 128u;   /* v0.6: the STF detect fires 60..100 instants into the STF; 128 keeps the frame's turn-on in the snapshot */
    memcpy(c->src_mac, src_mac, 6);
    memset(c->dst_mac, 0xFF, 6);
    c->src_ip[0] = 10; c->src_ip[1] = 0; c->src_ip[2] = 10; c->src_ip[3] = 250;
    c->dst_ip[0] = 10; c->dst_ip[1] = 0; c->dst_ip[2] = 10; c->dst_ip[3] = 3;
    c->src_port = 46000u; c->dst_port = 46000u;
    c->tx_enable = 1u; c->use_bcast = 1u; c->net_test = 0u;
    c->ovl_show = 1u; c->ovl_center = 0u; c->ovl_scale = 0u;     /* logo-only box, FPGA default scale */
    c->ovl_text_rgb = 0x444u; c->ovl_box_rgb = 0xFFFu; c->ovl_text[0] = '\0';
    c->disp_show_bad = 1u; c->disp_avg_shift = 4u; c->disp_ph_shift = 4u;
    c->crc = cfg_crc(c);
}

static void disp_defaults(iqcap_cfg_t *c)
{
    c->disp_show_bad = 1u; c->disp_avg_shift = 4u; c->disp_ph_shift = 4u; c->disp_solo = 0u;
}

static void ovl_defaults(iqcap_cfg_t *c)
{
    iqcap_cfg_t d;
    iqcap_cfg_defaults(&d);
    c->ovl_show = d.ovl_show; c->ovl_center = d.ovl_center; c->ovl_scale = d.ovl_scale; c->ovl_rsvd = 0u;
    c->ovl_text_rgb = d.ovl_text_rgb; c->ovl_box_rgb = d.ovl_box_rgb;
    memcpy(c->ovl_text, d.ovl_text, sizeof(c->ovl_text));
}

/* older layouts, kept only to migrate a stored block:
   v1 (2026-09-19 .. 09-24) ends after rsvd0, v2 (.. 2026-10-02) after gain_trim_ddb */
typedef struct {
    uint32_t magic; uint16_t version; uint16_t size;
    uint8_t  cap_enable, pass_all, require_fcs, test_pattern;
    uint16_t nsamp, pretrig;
    iqcap_mac_t mac[IQCAP_NMAC];
    uint8_t  src_mac[6], dst_mac[6];
    uint8_t  src_ip[4], dst_ip[4];
    uint16_t src_port, dst_port;
    uint8_t  tx_enable, use_bcast, net_test, rsvd0;
    uint32_t crc;
} iqcap_cfg_v1_t;

typedef struct {
    uint32_t magic; uint16_t version; uint16_t size;
    uint8_t  cap_enable, pass_all, require_fcs, test_pattern;
    uint16_t nsamp, pretrig;
    iqcap_mac_t mac[IQCAP_NMAC];
    uint8_t  src_mac[6], dst_mac[6];
    uint8_t  src_ip[4], dst_ip[4];
    uint16_t src_port, dst_port;
    uint8_t  tx_enable, use_bcast, net_test, rsvd0;
    int16_t  gain_trim_ddb[4];
    uint32_t crc;
} iqcap_cfg_v2_t;

typedef struct {
    uint32_t magic; uint16_t version; uint16_t size;
    uint8_t  cap_enable, pass_all, require_fcs, test_pattern;
    uint16_t nsamp, pretrig;
    iqcap_mac_t mac[IQCAP_NMAC];
    uint8_t  src_mac[6], dst_mac[6];
    uint8_t  src_ip[4], dst_ip[4];
    uint16_t src_port, dst_port;
    uint8_t  tx_enable, use_bcast, net_test, rsvd0;
    int16_t  gain_trim_ddb[4];
    uint8_t  ovl_show, ovl_center, ovl_scale, ovl_rsvd;
    uint16_t ovl_text_rgb, ovl_box_rgb;
    char     ovl_text[IQCAP_OVL_MAX + 4];
    uint32_t crc;
} iqcap_cfg_v3_t;

void iqcap_cfg_init(const iqcap_port_t *port)
{
    /* v4 (2026-10-02, a few hours): the v5 layout with the phase shift byte
       still reserved (0) - same size, so only the version tells them apart */
    union { iqcap_cfg_t v5; iqcap_cfg_v3_t v3; iqcap_cfg_v2_t v2; iqcap_cfg_v1_t v1; } tmp;
    s_port = *port;
    iqcap_cfg_defaults(&s_cfg);
    if (!s_port.nv_load || !s_port.nv_load(&tmp, sizeof(tmp))) return;
    if (tmp.v5.magic != IQCAP_CFG_MAGIC) return;
    if ((tmp.v5.version == IQCAP_CFG_VERSION || tmp.v5.version == 4u) && tmp.v5.size == sizeof(iqcap_cfg_t) &&
        tmp.v5.crc == cfg_crc(&tmp.v5))
    {
        bool v4 = (tmp.v5.version == 4u);
        s_cfg = tmp.v5;
        s_cfg.version = IQCAP_CFG_VERSION;
        s_cfg.ovl_text[sizeof(s_cfg.ovl_text) - 1u] = '\0';
        if (v4 || s_cfg.disp_ph_shift > 7u) s_cfg.disp_ph_shift = 4u;
        if (s_cfg.disp_avg_shift > 7u) s_cfg.disp_avg_shift = 4u;
        if (v4) s_cfg.crc = cfg_crc(&s_cfg);
    }
    else if (tmp.v3.version == 3u && tmp.v3.size == sizeof(iqcap_cfg_v3_t) &&
             tmp.v3.crc == crc32(&tmp.v3, offsetof(iqcap_cfg_v3_t, crc)))
    {
        /* identical layout up to ovl_text: copy it, the display switches take their defaults */
        memcpy(&s_cfg, &tmp.v3, offsetof(iqcap_cfg_v3_t, crc));
        s_cfg.version = IQCAP_CFG_VERSION; s_cfg.size = sizeof(iqcap_cfg_t);
        s_cfg.ovl_text[sizeof(s_cfg.ovl_text) - 1u] = '\0';
        disp_defaults(&s_cfg);
        s_cfg.crc = cfg_crc(&s_cfg);
    }
    else if (tmp.v2.version == 2u && tmp.v2.size == sizeof(iqcap_cfg_v2_t) &&
             tmp.v2.crc == crc32(&tmp.v2, offsetof(iqcap_cfg_v2_t, crc)))
    {
        /* identical layout up to gain_trim_ddb: copy it, the box takes its defaults */
        memcpy(&s_cfg, &tmp.v2, offsetof(iqcap_cfg_v2_t, crc));
        s_cfg.version = IQCAP_CFG_VERSION; s_cfg.size = sizeof(iqcap_cfg_t);
        ovl_defaults(&s_cfg); disp_defaults(&s_cfg);
        s_cfg.crc = cfg_crc(&s_cfg);
    }
    else if (tmp.v1.version == 1u && tmp.v1.size == sizeof(iqcap_cfg_v1_t) &&
             tmp.v1.crc == crc32(&tmp.v1, offsetof(iqcap_cfg_v1_t, crc)))
    {
        /* identical layout up to rsvd0: copy it, trims start at 0 */
        memcpy(&s_cfg, &tmp.v1, offsetof(iqcap_cfg_v1_t, crc));
        s_cfg.version = IQCAP_CFG_VERSION; s_cfg.size = sizeof(iqcap_cfg_t);
        memset(s_cfg.gain_trim_ddb, 0, sizeof(s_cfg.gain_trim_ddb));
        ovl_defaults(&s_cfg); disp_defaults(&s_cfg);
        s_cfg.crc = cfg_crc(&s_cfg);
    }
}

uint32_t iqcap_gain_trim_word(const int16_t ddb[4])
{
    uint32_t w = 0;
    for (int c = 0; c < 4; c++) {
        /* 1 count = 10*log10(2)/8 dB = 0.3763 dB -> counts = ddb / 3.763, rounded */
        int32_t n = ((int32_t)ddb[c] * 1000 + (ddb[c] >= 0 ? 1882 : -1882)) / 3763;
        if (n > 127) n = 127; if (n < -128) n = -128;
        w |= ((uint32_t)(uint8_t)(int8_t)n) << (8 * c);
    }
    return w;
}

iqcap_cfg_t *iqcap_cfg(void) { return &s_cfg; }

bool iqcap_cfg_save(void)
{
    s_cfg.crc = cfg_crc(&s_cfg);
    if (!s_port.nv_save) return true;
    return s_port.nv_save(&s_cfg, sizeof(s_cfg));
}

/* ---- FPGA1 ------------------------------------------------------------- */
bool iqcap_cfg_apply_fpga1(void)
{
    bool ok = iqcap_cap_apply_fpga1();
    ok = ok && iqcap_disp_apply_fpga1();
    ok = ok && iqcap_ovl_apply_fpga1();
    return ok;
}

bool iqcap_cap_apply_fpga1(void)
{
    const iqcap_cfg_t *c = &s_cfg;
    uint32_t ctrl = (c->cap_enable ? 1u : 0u) | (c->pass_all ? 2u : 0u) |
                    (c->require_fcs ? 4u : 0u) | (c->test_pattern ? 16u : 0u);
    bool ok = true;
    for (unsigned k = 0; k < IQCAP_NMAC; k++) {
        for (unsigned j = 0; j < 6; j++)
            ok = ok && s_port.f1_write((uint8_t)F1_MAC(k, j), c->mac[k].mac[j]);
        ok = ok && s_port.f1_write((uint8_t)F1_MAC_EN(k), c->mac[k].en ? 1u : 0u);
    }
    ok = ok && s_port.f1_write(F1_NSAMP, c->nsamp);
    ok = ok && s_port.f1_write(F1_PRETRIG, c->pretrig);
    ok = ok && s_port.f1_write(F1_GAIN_TRIM, iqcap_gain_trim_word(c->gain_trim_ddb));
    ok = ok && s_port.f1_write(F1_CTRL, ctrl);
    return ok;
}

/* ---- display switches (FPGA1 DISP_CTRL 0x0C) --------------------------- */
static bool s_pause;

static uint32_t disp_word(void)
{
    const iqcap_cfg_t *c = &s_cfg;
    return (s_pause ? 1u : 0u) | (c->disp_show_bad ? 2u : 0u) | (c->disp_solo ? 4u : 0u) |
           ((uint32_t)(c->disp_avg_shift & 7u) << 4) |
           ((uint32_t)(c->disp_ph_shift & 7u) << 12);
}
bool iqcap_disp_apply_fpga1(void)  { return s_port.f1_write(F1_DISP_CTRL, disp_word()); }
bool iqcap_disp_clear_fpga1(void)  { return s_port.f1_write(F1_DISP_CTRL, disp_word() | 0x100u); }
bool iqcap_disp_set_pause(bool on) { s_pause = on; return iqcap_disp_apply_fpga1(); }
bool iqcap_disp_pause(void)        { return s_pause; }

static bool s_hidden;
bool iqcap_ovl_set_hidden(bool on) { s_hidden = on; return iqcap_ovl_apply_fpga1(); }
bool iqcap_ovl_hidden(void)        { return s_hidden; }

/* ---- HDMI pop-up box (FPGA1 0x08..0x0B) -------------------------------- */
bool iqcap_ovl_apply_fpga1(void)
{
    const iqcap_cfg_t *c = &s_cfg;
    size_t n = 0;
    while (n < IQCAP_OVL_MAX && c->ovl_text[n]) n++;
    bool ok = s_port.f1_write(F1_OVL_COLOR, (uint32_t)(c->ovl_text_rgb & 0xFFFu) |
                                            ((uint32_t)(c->ovl_box_rgb & 0xFFFu) << 12));
    ok = ok && iqcap_ovl_frame_begin();                            /* BEGIN: a new text into the back bank */
    ok = ok && iqcap_ovl_frame_text(c->ovl_text, n);
    if (s_pause) ok = ok && iqcap_ovl_frame_text(n ? "\r[PAUSED]" : "[PAUSED]", n ? 9u : 8u);
    ok = ok && iqcap_ovl_frame_commit((c->ovl_show != 0u && !s_hidden) || s_pause, c->ovl_center != 0u, c->ovl_scale);
    return ok;
}

/* ---- pop-up frames (menu) ---------------------------------------------- */
static bool     s_ovl_shown;          /* what the FPGA's show bit holds right now */
static unsigned s_frame_rects;

static uint32_t ovl_ctrl_word(bool show, bool center, unsigned scale)
{
    return (show ? 1u : 0u) | (center ? 2u : 0u) | ((uint32_t)(scale & 15u) << 4);
}

bool iqcap_ovl_frame_begin(void)
{
    s_frame_rects = 0;
    /* BEGIN with the show bit as it is: switching it here would flash the old text */
    return s_port.f1_write(F1_OVL_CTRL, ovl_ctrl_word(s_ovl_shown, s_cfg.ovl_center != 0u,
                                                      s_cfg.ovl_scale) | 0x100u);
}

bool iqcap_ovl_frame_text(const char *s, size_t n)
{
    bool ok = true;
    for (size_t i = 0; i < n && ok; i += 4u) {
        uint32_t w = 0;
        for (unsigned j = 0; j < 4u && i + j < n; j++)
            w |= (uint32_t)(uint8_t)s[i + j] << (8u * j);
        ok = s_port.f1_write(F1_OVL_TEXT, w);
    }
    return ok;
}

bool iqcap_ovl_frame_rect(int x, int y, unsigned w, unsigned h, uint16_t text_rgb, uint16_t fill_rgb)
{
    if (s_frame_rects >= IQCAP_OVL_NRECT) return false;
    if (x < -2048) x = -2048; if (x > 2047) x = 2047;
    if (y < -2048) y = -2048; if (y > 2047) y = 2047;
    if (w > IQCAP_OVL_FULL) w = IQCAP_OVL_FULL;
    if (h > IQCAP_OVL_FULL) h = IQCAP_OVL_FULL;
    bool ok = s_port.f1_write(F1_OVL_RDATA, ((uint32_t)y & 0xFFFu) << 12 | ((uint32_t)x & 0xFFFu));
    ok = ok && s_port.f1_write(F1_OVL_RDATA, ((uint32_t)h & 0xFFFu) << 12 | (w & 0xFFFu));
    ok = ok && s_port.f1_write(F1_OVL_RDATA, (1u << 24) | ((uint32_t)(text_rgb & 0xFFFu) << 12) | (fill_rgb & 0xFFFu));
    s_frame_rects++;
    return ok;
}

bool iqcap_ovl_frame_commit(bool show, bool center, unsigned scale)
{
    s_ovl_shown = show;
    return s_port.f1_write(F1_OVL_CTRL, ovl_ctrl_word(show, center, scale) | 0x200u);
}

size_t iqcap_ovl_set_text(const char *s)
{
    char *d = s_cfg.ovl_text;
    size_t o = 0;
    while (*s && o < IQCAP_OVL_MAX) {
        char ch = *s++;
        if (ch == '\\' && *s) {
            char e = *s++;
            if (e == 'r' || e == 'n') ch = '\r';
            else if (e == '\\') ch = '\\';
            else { d[o++] = '\\'; if (o >= IQCAP_OVL_MAX) break; ch = e; }
        }
        d[o++] = ch;
    }
    d[o] = '\0';
    return o;
}

int iqcap_ovl_fmt_text(char *dst, size_t n, const char *text)
{
    size_t o = 0;
    for (; *text && o + 3u < n; text++) {
        if (*text == '\r' || *text == '\n') { dst[o++] = '\\'; dst[o++] = 'r'; }
        else if (*text == '\\')               { dst[o++] = '\\'; dst[o++] = '\\'; }
        else dst[o++] = *text;
    }
    dst[o] = '\0';
    return (int)o;
}

bool iqcap_stat_fpga1(iqcap_stat1_t *s)
{
    return s_port.f1_read(F1_CTRL, &s->ctrl) && s_port.f1_read(F1_NSAMP, &s->nsamp) &&
           s_port.f1_read(F1_PRETRIG, &s->pretrig) && s_port.f1_read(F1_TRIG, &s->trig) &&
           s_port.f1_read(F1_MATCH, &s->match) && s_port.f1_read(F1_DROP, &s->drop) &&
           s_port.f1_read(F1_SENT, &s->sent) && s_port.f1_read(F1_LINK, &s->link) &&
           s_port.f1_read(F1_RDXOR, &s->rd_xor);
}

bool iqcap_phase_fpga1(iqcap_phase_t *p)
{
    uint32_t st, r[3];
    if (!s_port.f1_read(0x74u, &st) || !s_port.f1_read(0x75u, &r[0]) ||
        !s_port.f1_read(0x76u, &r[1]) || !s_port.f1_read(0x77u, &r[2])) return false;
    p->count = (uint16_t)(st & 0xFFFFu);
    p->weak  = (st >> 16) & 1u;
    p->valid = (st >> 17) & 1u;
    for (int k = 0; k < 3; k++) { p->ph[k] = (uint16_t)(r[k] & 0xFFFFu); p->exp[k] = (uint8_t)((r[k] >> 16) & 0x3Fu); }
    return true;
}

bool iqcap_phase_window_fpga1(uint16_t start, uint16_t len)
{
    return s_port.f1_write(0x14u, start) && s_port.f1_write(0x15u, len);
}

bool iqcap_mark_fpga1(iqcap_mark_t *m)
{
    uint32_t d, r;
    if (!s_port.f1_read(0x78u, &d) || !s_port.f1_read(0x79u, &r)) return false;
    m->ok = (d >> 25) & 1u; m->count = (uint16_t)(d & 0xFFFFu); m->ang = (uint16_t)((d >> 16) & 0x1FFu);
    m->raw = (uint16_t)(r & 0x1FFu); m->brg = (uint16_t)((r >> 16) & 0x1FFu);
    return true;
}

bool iqcap_phase_cal_get_fpga1(uint16_t *turns)
{
    uint32_t v; if (!s_port.f1_read(0x16u, &v)) return false; *turns = (uint16_t)(v & 0xFFFFu); return true;
}

bool iqcap_phase_cal_set_fpga1(uint16_t turns) { return s_port.f1_write(0x16u, turns); }

int iqcap_phase_deg10(uint16_t turns)
{
    int32_t d = ((int32_t)turns * 3600 + 32768) / 65536;   /* 0..3600 */
    return (d > 1800) ? d - 3600 : d;
}

/* ---- FPGA2 ------------------------------------------------------------- */
static uint32_t le4(const uint8_t *b) { return (uint32_t)b[0] | ((uint32_t)b[1] << 8) | ((uint32_t)b[2] << 16) | ((uint32_t)b[3] << 24); }

bool iqcap_cfg_apply_fpga2(void)
{
    const iqcap_cfg_t *c = &s_cfg;
    uint32_t ctrl = (c->tx_enable ? 1u : 0u) | (c->use_bcast ? 2u : 0u) | (c->net_test ? 8u : 0u);
    bool ok = true;
    ok = ok && s_port.f2_write(F2_SRC_MAC,      le4(c->src_mac));
    ok = ok && s_port.f2_write(F2_SRC_MAC + 4u, (uint32_t)c->src_mac[4] | ((uint32_t)c->src_mac[5] << 8));
    ok = ok && s_port.f2_write(F2_SRC_IP,       le4(c->src_ip));
    ok = ok && s_port.f2_write(F2_DST_IP,       le4(c->dst_ip));
    ok = ok && s_port.f2_write(F2_DST_MAC,      le4(c->dst_mac));
    ok = ok && s_port.f2_write(F2_DST_MAC + 4u, (uint32_t)c->dst_mac[4] | ((uint32_t)c->dst_mac[5] << 8));
    ok = ok && s_port.f2_write(F2_PORTS,        (uint32_t)c->dst_port | ((uint32_t)c->src_port << 16));
    ok = ok && s_port.f2_write(F2_CTRL,         ctrl);
    return ok;
}

bool iqcap_stat_fpga2(iqcap_stat2_t *s)
{
    return s_port.f2_read(F2_PHYID, &s->phy_id) && s_port.f2_read(F2_STAT, &s->stat) &&
           s_port.f2_read(F2_CTRL, &s->ctrl) && s_port.f2_read(F2_PKT, &s->pkt) &&
           s_port.f2_read(F2_SNAP, &s->snap) && s_port.f2_read(F2_CRCERR, &s->crc_err) &&
           s_port.f2_read(F2_FRMERR, &s->frame_err) && s_port.f2_read(F2_PEND, &s->pending);
}

bool iqcap_fpga2_present(void)
{
    uint32_t id;
    return s_port.f2_read(F2_PHYID, &id) && id == IQCAP_PHY_ID_RTL8211E;
}

bool iqcap_clear_counters(void)
{
    const iqcap_cfg_t *c = &s_cfg;
    uint32_t c1 = (c->cap_enable ? 1u : 0u) | (c->pass_all ? 2u : 0u) | (c->require_fcs ? 4u : 0u) |
                  (c->test_pattern ? 16u : 0u) | 8u;
    uint32_t c2 = (c->tx_enable ? 1u : 0u) | (c->use_bcast ? 2u : 0u) | (c->net_test ? 8u : 0u) | 4u;
    bool ok = s_port.f1_write(F1_CTRL, c1);
    ok = s_port.f2_write(F2_CTRL, c2) && ok;
    return ok;
}

/* ---- text helpers ------------------------------------------------------- */
static int hexv(char ch)
{
    if (ch >= '0' && ch <= '9') return ch - '0';
    if (ch >= 'a' && ch <= 'f') return ch - 'a' + 10;
    if (ch >= 'A' && ch <= 'F') return ch - 'A' + 10;
    return -1;
}

bool iqcap_parse_mac(const char *s, uint8_t mac[6])
{
    uint8_t out[6];
    while (*s == ' ' || *s == '\t') s++;
    for (int i = 0; i < 6; i++) {
        int h = hexv(s[0]), l = hexv(s[1]);
        if (h < 0 || l < 0) return false;
        out[i] = (uint8_t)((h << 4) | l);
        s += 2;
        if (i < 5 && (*s == ':' || *s == '-')) s++;
    }
    if (*s != '\0' && *s != ' ' && *s != '\t' && *s != '\r' && *s != '\n') return false;
    memcpy(mac, out, 6);
    return true;
}

bool iqcap_parse_ip(const char *s, uint8_t ip[4])
{
    uint8_t out[4];
    while (*s == ' ' || *s == '\t') s++;
    for (int i = 0; i < 4; i++) {
        unsigned v = 0; int n = 0;
        while (*s >= '0' && *s <= '9') { v = v * 10u + (unsigned)(*s - '0'); s++; n++; if (v > 255u) return false; }
        if (n == 0) return false;
        out[i] = (uint8_t)v;
        if (i < 3) { if (*s != '.') return false; s++; }
    }
    if (*s != '\0' && *s != ' ' && *s != '\t' && *s != '\r' && *s != '\n') return false;
    memcpy(ip, out, 4);
    return true;
}

int iqcap_fmt_mac(char *dst, size_t n, const uint8_t m[6])
{
    return snprintf(dst, n, "%02X:%02X:%02X:%02X:%02X:%02X", m[0], m[1], m[2], m[3], m[4], m[5]);
}
int iqcap_fmt_ip(char *dst, size_t n, const uint8_t ip[4])
{
    return snprintf(dst, n, "%u.%u.%u.%u", ip[0], ip[1], ip[2], ip[3]);
}
