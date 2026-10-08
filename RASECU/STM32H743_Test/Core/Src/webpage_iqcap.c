/*
 * webpage_iqcap.c - "IQ Capture" page: MAC filter table (8 rows), pass-all,
 * require-FCS, instants per snapshot, pre-trigger, PC IP/port/MAC, own IP,
 * transmit enable, test patterns, the HDMI pop-up box (text, show, scale,
 * alignment, colours) and the live counters of both FPGAs
 * (doc/iq_capture/SPEC.md sections 4, 7, 9). Same GET-form scheme as
 * webpage_syscfg.c: a query string with "cen=" is an update, applied through
 * iqcap_cfg (persisted + written to the FPGAs), then the page re-renders.
 */
#include "platform_types.h"
#include "webpage.h"
#include "webpage_iqcap.h"
#include "iqcap_cfg.h"
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

/* provided per tree: RASBB_ECU -> iqcap_port_sim.c (RAM shadow), STM32H743_Test ->
 * iqcap_web_port.c (real SPI4 behind the shared-bus lock) */
void iqcap_web_prepare(void);
void iqcap_web_lock(void);
void iqcap_web_unlock(void);

/* URL-decoded string parameter (handles %XX and '+'); returns 1 if present */
static int url_param_str(const char *query, const char *name, char *out, size_t n)
{
    size_t nl = strlen(name);
    const char *p = query;
    while ((p = strstr(p, name)) != NULL) {
        if ((p == query || p[-1] == '?' || p[-1] == '&') && p[nl] == '=') {
            size_t o = 0;
            p += nl + 1;
            while (*p && *p != '&' && *p != ' ' && o + 1 < n) {
                char ch = *p++;
                if (ch == '+') ch = ' ';
                else if (ch == '%' && p[0] && p[1]) {
                    char hex[3] = { p[0], p[1], 0 };
                    ch = (char)strtoul(hex, NULL, 16); p += 2;
                }
                out[o++] = ch;
            }
            out[o] = '\0';
            return 1;
        }
        p += nl;
    }
    return 0;
}

/* HTML attribute value: & " < > escaped */
static int html_attr(char *dst, size_t n, const char *s)
{
    size_t o = 0;
    for (; *s && o + 7 < n; s++) {
        const char *rep = (*s == '&') ? "&amp;" : (*s == '"') ? "&quot;" : (*s == '<') ? "&lt;" : (*s == '>') ? "&gt;" : NULL;
        if (rep) { size_t l = strlen(rep); memcpy(dst + o, rep, l); o += l; }
        else dst[o++] = *s;
    }
    dst[o] = '\0';
    return (int)o;
}

static int flag_param(const char *query, const char *name)
{
    u32 v;
    return WP_get_query_param_u32(query, name, &v) && v != 0u;
}

void WP_generate_iqcap_edit(const char *pURL, char *buffer, size_t bufsize)
{
    char *ptr = buffer;
    char *end = buffer + bufsize - 1;
    iqcap_cfg_t *c;
    iqcap_stat1_t s1; iqcap_stat2_t s2;
    int ok1, ok2, is_update = 0, saved = 0;
    char tmp[40], ip[16], mac[20];
    char ovl[2 * IQCAP_OVL_MAX + 8];          /* escaped box text, both directions */
    unsigned k;

    iqcap_web_prepare();
    iqcap_web_lock();
    c = iqcap_cfg();

    if (strstr(pURL, "cen=") != NULL) {
        u32 v;
        char name[8];
        is_update = 1;
        c->cap_enable  = flag_param(pURL, "cen") ? 1u : 0u;
        c->pass_all    = flag_param(pURL, "cpa") ? 1u : 0u;
        c->require_fcs = flag_param(pURL, "cfc") ? 1u : 0u;
        c->test_pattern= flag_param(pURL, "ctp") ? 1u : 0u;
        if (WP_get_query_param_u32(pURL, "nsamp", &v) && v >= 1u && v <= IQCAP_NSAMP_MAX) c->nsamp = (u16)v;
        if (WP_get_query_param_u32(pURL, "pretrig", &v) && v < c->nsamp) c->pretrig = (u16)v;
        for (k = 0; k < IQCAP_NMAC; k++) {
            sprintf(name, "m%u", k);
            if (url_param_str(pURL, name, tmp, sizeof tmp) && tmp[0] != '\0') {
                if (iqcap_parse_mac(tmp, c->mac[k].mac)) {
                    sprintf(name, "e%u", k);
                    c->mac[k].en = flag_param(pURL, name) ? 1u : 0u;
                }
            } else {
                c->mac[k].en = 0u;
            }
        }
        if (url_param_str(pURL, "dip", tmp, sizeof tmp)) (void)iqcap_parse_ip(tmp, c->dst_ip);
        if (url_param_str(pURL, "sip", tmp, sizeof tmp)) (void)iqcap_parse_ip(tmp, c->src_ip);
        if (WP_get_query_param_u32(pURL, "dport", &v) && v >= 1u && v <= 65535u) c->dst_port = (u16)v;
        if (url_param_str(pURL, "dmac", tmp, sizeof tmp) && iqcap_parse_mac(tmp, c->dst_mac)) { /* keep */ }
        c->use_bcast  = flag_param(pURL, "bc") ? 1u : 0u;
        c->tx_enable  = flag_param(pURL, "txe") ? 1u : 0u;
        c->net_test   = flag_param(pURL, "ntp") ? 1u : 0u;
        /* HDMI pop-up box */
        if (url_param_str(pURL, "ovt", ovl, sizeof ovl)) (void)iqcap_ovl_set_text(ovl);
        c->ovl_show   = flag_param(pURL, "ovs") ? 1u : 0u;
        c->ovl_center = flag_param(pURL, "ova") ? 1u : 0u;
        if (WP_get_query_param_u32(pURL, "ovz", &v) && v <= 4u) c->ovl_scale = (u8)v;
        if (url_param_str(pURL, "ovtc", tmp, sizeof tmp) && tmp[0]) { v = strtoul(tmp, NULL, 16); if (v <= 0xFFFu) c->ovl_text_rgb = (u16)v; }
        if (url_param_str(pURL, "ovbc", tmp, sizeof tmp) && tmp[0]) { v = strtoul(tmp, NULL, 16); if (v <= 0xFFFu) c->ovl_box_rgb = (u16)v; }
        saved = iqcap_cfg_save() ? 1 : 0;
        (void)iqcap_cfg_apply_fpga1();
        (void)iqcap_cfg_apply_fpga2();
    }

    ok1 = iqcap_stat_fpga1(&s1) ? 1 : 0;
    iqcap_phase_t ph; int okp = (ok1 && iqcap_phase_fpga1(&ph)) ? 1 : 0;
    ok2 = (iqcap_fpga2_present() && iqcap_stat_fpga2(&s2)) ? 1 : 0;
    iqcap_web_unlock();

#define APPEND(...) do { int _l = snprintf(ptr, (size_t)(end - ptr), __VA_ARGS__); if (_l > 0) ptr += (_l < end - ptr) ? _l : (int)(end - ptr); } while (0)

    ptr += WP_add_table_styles(ptr);
    APPEND("<h2>IQ Capture</h2>\r\n");
    if (is_update)
        APPEND("<p style=\"color:%s;\"><b>%s</b></p>\r\n", saved ? "green" : "red",
               saved ? "Configuration saved and applied." : "Configuration applied but NOT saved!");

    APPEND("<h3>Status</h3>\r\n<table>\r\n<tr><th>FPGA1 capture</th><th>Value</th><th>FPGA2 network</th><th>Value</th></tr>\r\n");
    if (ok1 && ok2) {
        APPEND("<tr><td>Capture</td><td>%s</td><td>PHY</td><td>%08lX, link %s%s</td></tr>\r\n",
               (s1.ctrl & 1u) ? "ON" : "off", (unsigned long)s2.phy_id,
               (s2.stat & 1u) ? "UP" : "down", (s2.stat & 2u) ? " 1000" : "");
        APPEND("<tr><td>Triggers</td><td>%lu</td><td>SNAPLINK</td><td>%s%s</td></tr>\r\n",
               (unsigned long)s1.trig, (s2.stat & 4u) ? "alive" : "DEAD", (s2.stat & 8u) ? " (data seen)" : "");
        APPEND("<tr><td>MAC matches</td><td>%lu</td><td>UDP packets</td><td>%lu</td></tr>\r\n",
               (unsigned long)s1.match, (unsigned long)s2.pkt);
        APPEND("<tr><td>Dropped (no slot)</td><td>%lu</td><td>Snapshots sent</td><td>%lu</td></tr>\r\n",
               (unsigned long)s1.drop, (unsigned long)s2.snap);
        APPEND("<tr><td>Sent to link</td><td>%lu</td><td>Link CRC / frame errors</td><td>%lu / %lu</td></tr>\r\n",
               (unsigned long)s1.sent, (unsigned long)s2.crc_err, (unsigned long)s2.frame_err);
        if (okp) {   /* 4.b: inter-channel phase of the last committed frame */
            int d1 = iqcap_phase_deg10(ph.ph[0]), d2 = iqcap_phase_deg10(ph.ph[1]), d3 = iqcap_phase_deg10(ph.ph[2]);
            if (ph.valid)
                APPEND("<tr><td>Phase ch1/ch2/ch3 vs ch0 (frames %u)</td><td colspan=\"3\">%d.%d / %d.%d / %d.%d deg%s</td></tr>\r\n",
                       (unsigned)ph.count, d1 / 10, abs(d1) % 10, d2 / 10, abs(d2) % 10, d3 / 10, abs(d3) % 10,
                       ph.weak ? " (weak)" : "");
            else
                APPEND("<tr><td>Phase ch1/ch2/ch3 vs ch0</td><td colspan=\"3\">no frame yet</td></tr>\r\n");
        }
    } else {
        APPEND("<tr><td colspan=\"4\">%s%s</td></tr>\r\n", ok1 ? "" : "FPGA1 does not answer. ", ok2 ? "" : "FPGA2 does not answer.");
    }
    APPEND("</table>\r\n");

    APPEND("<form method=\"GET\" action=\"/iqcap\">\r\n<h3>Capture (FPGA1)</h3>\r\n<table>\r\n"
           "<tr><td>Capture enable</td><td><input type=\"checkbox\" name=\"cen\" value=\"1\"%s></td></tr>\r\n"
           "<tr><td>Pass all (bypass MAC filter)</td><td><input type=\"checkbox\" name=\"cpa\" value=\"1\"%s></td></tr>\r\n"
           "<tr><td>Require good FCS</td><td><input type=\"checkbox\" name=\"cfc\" value=\"1\"%s></td></tr>\r\n"
           "<tr><td>Instants per snapshot (1..1024)</td><td><input type=\"number\" name=\"nsamp\" value=\"%u\" min=\"1\" max=\"1024\"></td></tr>\r\n"
           "<tr><td>Pre-trigger instants</td><td><input type=\"number\" name=\"pretrig\" value=\"%u\" min=\"0\" max=\"1023\"></td></tr>\r\n"
           "<tr><td>Test pattern (ramp every 100 ms)</td><td><input type=\"checkbox\" name=\"ctp\" value=\"1\"%s></td></tr>\r\n"
           "</table>\r\n",
           c->cap_enable ? " checked" : "", c->pass_all ? " checked" : "", c->require_fcs ? " checked" : "",
           (unsigned)c->nsamp, (unsigned)c->pretrig, c->test_pattern ? " checked" : "");

    APPEND("<h3>MAC filter (transmitter address, empty = unused)</h3>\r\n<table>\r\n<tr><th>Slot</th><th>MAC</th><th>Enable</th></tr>\r\n");
    for (k = 0; k < IQCAP_NMAC; k++) {
        int used = 0; unsigned j;
        for (j = 0; j < 6; j++) used |= c->mac[k].mac[j];
        if (used) iqcap_fmt_mac(mac, sizeof mac, c->mac[k].mac); else mac[0] = '\0';
        APPEND("<tr><td>%u</td><td><input type=\"text\" name=\"m%u\" value=\"%s\" size=\"17\" placeholder=\"aa:bb:cc:dd:ee:ff\"></td>"
               "<td><input type=\"checkbox\" name=\"e%u\" value=\"1\"%s></td></tr>\r\n",
               k, k, mac, k, c->mac[k].en ? " checked" : "");
    }
    APPEND("</table>\r\n");

    iqcap_fmt_ip(ip, sizeof ip, c->dst_ip); iqcap_fmt_mac(mac, sizeof mac, c->dst_mac);
    APPEND("<h3>Network (FPGA2)</h3>\r\n<table>\r\n"
           "<tr><td>PC IP</td><td><input type=\"text\" name=\"dip\" value=\"%s\" size=\"15\"></td></tr>\r\n"
           "<tr><td>PC UDP port</td><td><input type=\"number\" name=\"dport\" value=\"%u\" min=\"1\" max=\"65535\"></td></tr>\r\n"
           "<tr><td>PC MAC</td><td><input type=\"text\" name=\"dmac\" value=\"%s\" size=\"17\"> "
           "broadcast instead <input type=\"checkbox\" name=\"bc\" value=\"1\"%s></td></tr>\r\n",
           ip, (unsigned)c->dst_port, mac, c->use_bcast ? " checked" : "");
    iqcap_fmt_ip(ip, sizeof ip, c->src_ip);
    APPEND("<tr><td>Own IP (FPGA2)</td><td><input type=\"text\" name=\"sip\" value=\"%s\" size=\"15\"></td></tr>\r\n"
           "<tr><td>UDP transmit enable</td><td><input type=\"checkbox\" name=\"txe\" value=\"1\"%s></td></tr>\r\n"
           "<tr><td>FPGA2 test pattern</td><td><input type=\"checkbox\" name=\"ntp\" value=\"1\"%s></td></tr>\r\n"
           "</table>\r\n",
           ip, c->tx_enable ? " checked" : "", c->net_test ? " checked" : "");

    /* HDMI pop-up box (FPGA1 ovl_box.v): text shown re-escaped (\r = line break) */
    {
        char esc[2 * IQCAP_OVL_MAX + 8];
        iqcap_ovl_fmt_text(esc, sizeof esc, c->ovl_text);
        html_attr(ovl, sizeof ovl, esc);
    }
    APPEND("<h3>HDMI pop-up box (FPGA1, lower right corner)</h3>\r\n<table>\r\n"
           "<tr><td>Text (\\r = line break)</td><td><input type=\"text\" name=\"ovt\" value=\"%s\" size=\"60\" maxlength=\"%u\"></td></tr>\r\n"
           "<tr><td>Show the box</td><td><input type=\"checkbox\" name=\"ovs\" value=\"1\"%s></td></tr>\r\n"
           "<tr><td>Font scale (0 = default 2)</td><td><input type=\"number\" name=\"ovz\" value=\"%u\" min=\"0\" max=\"4\"></td></tr>\r\n"
           "<tr><td>Centre the lines</td><td><input type=\"checkbox\" name=\"ova\" value=\"1\"%s></td></tr>\r\n"
           "<tr><td>Text / box colour (RGB 4:4:4 hex)</td><td><input type=\"text\" name=\"ovtc\" value=\"%03X\" size=\"4\"> "
           "<input type=\"text\" name=\"ovbc\" value=\"%03X\" size=\"4\"></td></tr>\r\n"
           "</table>\r\n<p><input type=\"submit\" value=\"Save and apply\" style=\"padding:8px 20px;font-size:14px;\"></p>\r\n</form>\r\n"
           "<p style=\"color:blue;\"><b>Note:</b> at full rate use the PC's MAC, not broadcast (a switch floods broadcast to every port and drops frames).</p>\r\n",
           ovl, (unsigned)IQCAP_OVL_MAX, c->ovl_show ? " checked" : "", (unsigned)c->ovl_scale,
           c->ovl_center ? " checked" : "", (unsigned)c->ovl_text_rgb, (unsigned)c->ovl_box_rgb);
#undef APPEND
    *ptr = '\0';
}
