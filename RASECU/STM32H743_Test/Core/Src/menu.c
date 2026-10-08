/* menu.c - see menu.h. Buttons on J8 (plus ESC), a two-column menu (main entries on the
 * left, the selected entry's items on the right), rendered through the
 * pop-up frame API of iqcap_cfg.c (text + rectangles, one COMMIT per
 * picture). Runs in the console task; everything that touches SPI4 holds
 * the shared bus lock (logw_seq.h), exactly like a console command.
 *
 *   focus MAIN   up/down pick the main entry (its items show on the right,
 *                dimmed), right/OK enter the submenu, left closes the menu
 *   focus SUB    the right panel brightens and gets the bar; up/down pick an
 *                item, OK/right toggle or execute it (a value item goes into
 *                EDIT), left returns to the main column
 *   focus EDIT   up/down change the value (red on white), OK/left/right keep
 *                it and return to SUB
 *   20 s without a button closes the menu, the stored pop-up text returns.
 */
#include "menu.h"
#include "main.h"
#include "cmsis_os.h"
#include "logw_seq.h"
#include "iqcap_cfg.h"
#include <stdio.h>
#include <string.h>

/* ---- buttons ----------------------------------------------------------- */
static GPIO_TypeDef *const s_port[MENU_BTN_N] = { GPIOD, GPIOD, GPIOD, GPIOD, GPIOD, GPIOD };
static const uint16_t      s_pin[MENU_BTN_N]  = { PD0_DEBUG_Pin, PD1_DEBUG_Pin, PD2_DEBUG_Pin,
                                                  PD4_DEBUG_Pin, PD7_DEBUG_Pin, PD15_DEBUG_Pin };
#define BTN_COMMON_PORT GPIOD
#define BTN_COMMON_PIN  PD10_DEBUG_Pin

#define POLL_MS        5u
#define DEBOUNCE_N     3u            /* consecutive samples */
#define REPEAT_DELAY   120u          /* polls (600 ms) before auto-repeat */
#define REPEAT_EVERY   30u           /* polls (150 ms) between repeats */
#define TIMEOUT_POLLS  4000u         /* 20 s without a button closes the menu */

static uint8_t  s_cnt[MENU_BTN_N];   /* debounce counters */
static bool     s_down[MENU_BTN_N];  /* debounced state */
static uint16_t s_held[MENU_BTN_N];  /* polls held */

/* ---- menu model -------------------------------------------------------- */
typedef enum { K_TOGGLE, K_VALUE, K_ACTION, K_INFO } kind_t;
typedef struct { const char *name; kind_t kind; int id; } item_t;
typedef struct { const char *name; const item_t *items; int n; } entry_t;

enum {  /* item ids */
    I_RATE, I_PHRATE, I_PAUSE, I_BAD, I_CLEAR,       /* Display */
    I_TEXT, I_SCALE, I_CENTER,                       /* Pop-up */
    I_CAP, I_PASS, I_FCS, I_SOLO,                    /* Capture */
    I_TRIG, I_MATCH, I_SENT, I_LINK                  /* Info */
};

static const item_t s_display[] = {
    { "Position avg",  K_VALUE,  I_RATE },           /* label (MAC position) bearing, 2^k frames */
    { "Phase avg",     K_VALUE,  I_PHRATE },         /* phase dot, 2^k frames */
    { "Pause",         K_TOGGLE, I_PAUSE },
    { "FCS bad shown", K_TOGGLE, I_BAD },
    { "Clear table",   K_ACTION, I_CLEAR },
};
static const item_t s_popup[] = {
    { "Text",          K_TOGGLE, I_TEXT },
    { "Font scale",    K_VALUE,  I_SCALE },
    { "Centre lines",  K_TOGGLE, I_CENTER },
};
static const item_t s_capture[] = {
    { "Capture",       K_TOGGLE, I_CAP },
    { "Pass all",      K_TOGGLE, I_PASS },
    { "Require FCS",   K_TOGGLE, I_FCS },
    { "Rays MAC only", K_TOGGLE, I_SOLO },           /* display solo: only the filter list's MACs draw (it is their list) */
};
static const item_t s_info[] = {
    { "Triggers",      K_INFO,   I_TRIG },
    { "MAC matches",   K_INFO,   I_MATCH },
    { "Sent to link",  K_INFO,   I_SENT },
    { "FPGA2 link",    K_INFO,   I_LINK },
};
#define N_ITEMS(a) ((int)(sizeof(a) / sizeof((a)[0])))
static const entry_t s_main[] = {
    { "Display", s_display, N_ITEMS(s_display) },
    { "Pop-up",  s_popup,   N_ITEMS(s_popup) },
    { "Capture", s_capture, N_ITEMS(s_capture) },
    { "Info",    s_info,    N_ITEMS(s_info) },
    { "Exit",    NULL,      0 },
};
#define N_MAIN   N_ITEMS(s_main)
#define N_ROWS   5                   /* max(N_MAIN, items of any entry) */

/* text layout, characters: " <main 9> " | gap | " <item 14><value 7> " */
#define MAIN_W   9
#define LEFT_W   (1 + MAIN_W + 1)
#define GAP_W    1
#define NAME_W   14
#define VAL_W    7
#define RIGHT_W  (1 + NAME_W + VAL_W + 1)

typedef enum { F_MAIN, F_SUB, F_EDIT } focus_t;
static bool    s_open;
static focus_t s_focus;
static int     s_mi;                 /* main entry */
static int     s_si;                 /* item in the submenu */
static uint16_t s_idle;              /* polls since the last button */
static bool    s_cleared;            /* "Clear table" just executed: shown once */
static iqcap_stat1_t s_stat;         /* Info values, read at each draw */
static bool    s_stat_ok;

/* colours, RGB 4:4:4 */
#define C_RED    0xE22u              /* the logo's red */
#define C_WHITE  0xFFFu
#define C_DIMBAR 0x999u              /* main bar while the submenu has the focus */
#define C_PANEL  0xDDDu              /* submenu panel without focus */
#define C_TEXT   0x444u

static unsigned scale_px(void)
{
    unsigned s = iqcap_cfg()->ovl_scale;
    return (s == 0u || s > 4u) ? 2u : s;
}

static const char *onoff(unsigned v) { return v ? "on" : "off"; }

static void value_text(const item_t *it, char *dst, size_t n)
{
    const iqcap_cfg_t *c = iqcap_cfg();
    switch (it->id) {
    case I_RATE:   snprintf(dst, n, "%u", 1u << (c->disp_avg_shift & 7u)); break;
    case I_PHRATE: snprintf(dst, n, "%u", 1u << (c->disp_ph_shift & 7u)); break;
    case I_PAUSE:  snprintf(dst, n, "%s", onoff(iqcap_disp_pause())); break;
    case I_BAD:    snprintf(dst, n, "%s", onoff(c->disp_show_bad)); break;
    case I_CLEAR:  snprintf(dst, n, "%s", s_cleared ? "done" : ">"); break;
    case I_TEXT:   snprintf(dst, n, "%s", c->ovl_show ? "shown" : "hidden"); break;
    case I_SCALE:  snprintf(dst, n, "%u", scale_px()); break;
    case I_CENTER: snprintf(dst, n, "%s", onoff(c->ovl_center)); break;
    case I_CAP:    snprintf(dst, n, "%s", onoff(c->cap_enable)); break;
    case I_PASS:   snprintf(dst, n, "%s", onoff(c->pass_all)); break;
    case I_FCS:    snprintf(dst, n, "%s", onoff(c->require_fcs)); break;
    case I_SOLO:   snprintf(dst, n, "%s", onoff(c->disp_solo)); break;
    case I_TRIG:   if (s_stat_ok) snprintf(dst, n, "%lu", (unsigned long)s_stat.trig); else snprintf(dst, n, "-"); break;
    case I_MATCH:  if (s_stat_ok) snprintf(dst, n, "%lu", (unsigned long)s_stat.match); else snprintf(dst, n, "-"); break;
    case I_SENT:   if (s_stat_ok) snprintf(dst, n, "%lu", (unsigned long)s_stat.sent); else snprintf(dst, n, "-"); break;
    case I_LINK:   if (s_stat_ok) snprintf(dst, n, "%s", (s_stat.link & 1u) ? "ready" : "down"); else snprintf(dst, n, "-"); break;
    default:       dst[0] = '\0'; break;
    }
}

/* one picture. Row r (0..N_ROWS-1) starts at r * 16 * scale below the text
   origin; the left column holds the main entries, the right column the
   selected entry's items. */
static void draw(void)
{
    char buf[N_ROWS * (LEFT_W + GAP_W + RIGHT_W + 2) + 8];
    char val[VAL_W + 1];
    unsigned s = scale_px(), ch = 16u * s, cw = 8u * s;
    const entry_t *e = &s_main[s_mi];
    size_t o = 0;

    if (e->items == s_info) s_stat_ok = iqcap_stat_fpga1(&s_stat);
    for (int r = 0; r < N_ROWS; r++) {
        const char *mname = (r < N_MAIN) ? s_main[r].name : "";
        o += (size_t)snprintf(buf + o, sizeof buf - o, " %-*s %*s", MAIN_W, mname, GAP_W, "");
        if (r < e->n) {
            value_text(&e->items[r], val, sizeof val);
            o += (size_t)snprintf(buf + o, sizeof buf - o, " %-*s%*s ", NAME_W, e->items[r].name, VAL_W, val);
        }
        if (r != N_ROWS - 1) o += (size_t)snprintf(buf + o, sizeof buf - o, "\r");
    }

    int panel_x = (int)((LEFT_W + GAP_W) * cw) - (int)(cw / 2u);
    unsigned panel_w = RIGHT_W * cw + cw;
    bool ok = iqcap_ovl_frame_begin();
    ok = ok && iqcap_ovl_frame_text(buf, o);
    /* the FPGA gives the LOWEST rectangle index priority where they overlap,
       so the most specific one goes first and the panel last */
    /* the value being edited: red on white inside the bar */
    if (s_focus == F_EDIT && e->n)
        ok = ok && iqcap_ovl_frame_rect((int)((LEFT_W + GAP_W + 1 + NAME_W) * cw), (int)(s_si * ch),
                                        VAL_W * cw, ch, C_RED, C_WHITE);
    /* bar on the focused item */
    if (s_focus != F_MAIN && e->n)
        ok = ok && iqcap_ovl_frame_rect(panel_x, (int)(s_si * ch) - (int)s, panel_w, ch + 2u * s, C_WHITE, C_RED);
    /* bar on the main entry: red with the focus, grey without */
    ok = ok && iqcap_ovl_frame_rect(-IQCAP_OVL_PAD, (int)(s_mi * ch) - (int)s,
                                    (unsigned)(panel_x + IQCAP_OVL_PAD) - cw / 2u, ch + 2u * s,
                                    C_WHITE, s_focus == F_MAIN ? C_RED : C_DIMBAR);
    /* submenu panel, bright when it has the focus */
    ok = ok && iqcap_ovl_frame_rect(panel_x, -(int)(2u * s), panel_w, N_ROWS * ch + 4u * s,
                                    C_TEXT, s_focus == F_MAIN ? C_PANEL : C_WHITE);
    ok = ok && iqcap_ovl_frame_commit(true, false, iqcap_cfg()->ovl_scale);
    if (!ok) printf("menu: FPGA1 does not answer\n");
}

static void close_menu(void)
{
    s_open = false;
    s_cleared = false;
    (void)iqcap_ovl_apply_fpga1();           /* the stored text (plus [PAUSED] if paused) */
}

static void toggle(const item_t *it)
{
    iqcap_cfg_t *c = iqcap_cfg();
    switch (it->id) {
    case I_PAUSE:  (void)iqcap_disp_set_pause(!iqcap_disp_pause()); return;
    case I_BAD:    c->disp_show_bad = !c->disp_show_bad; (void)iqcap_cfg_save(); (void)iqcap_disp_apply_fpga1(); return;
    case I_SOLO:   c->disp_solo = !c->disp_solo; (void)iqcap_cfg_save(); (void)iqcap_disp_apply_fpga1(); return;
    case I_TEXT:   c->ovl_show = !c->ovl_show; (void)iqcap_cfg_save(); return;
    case I_CENTER: c->ovl_center = !c->ovl_center; (void)iqcap_cfg_save(); return;
    case I_CAP:    c->cap_enable = !c->cap_enable; break;
    case I_PASS:   c->pass_all = !c->pass_all; break;
    case I_FCS:    c->require_fcs = !c->require_fcs; break;
    default:       return;
    }
    (void)iqcap_cfg_save();
    (void)iqcap_cap_apply_fpga1();
}

static void adjust(const item_t *it, int dir)
{
    iqcap_cfg_t *c = iqcap_cfg();
    switch (it->id) {
    case I_RATE:
        if (dir > 0 && c->disp_avg_shift < 7u) c->disp_avg_shift++;
        else if (dir < 0 && c->disp_avg_shift > 0u) c->disp_avg_shift--;
        (void)iqcap_cfg_save(); (void)iqcap_disp_apply_fpga1();
        break;
    case I_PHRATE:
        if (dir > 0 && c->disp_ph_shift < 7u) c->disp_ph_shift++;
        else if (dir < 0 && c->disp_ph_shift > 0u) c->disp_ph_shift--;
        (void)iqcap_cfg_save(); (void)iqcap_disp_apply_fpga1();
        break;
    case I_SCALE: {
        unsigned v = scale_px();
        if (dir > 0 && v < 4u) v++;
        else if (dir < 0 && v > 1u) v--;
        c->ovl_scale = (uint8_t)v;
        (void)iqcap_cfg_save();
        break;
    }
    default: break;
    }
}

static void action(const item_t *it)
{
    if (it->id == I_CLEAR) { (void)iqcap_disp_clear_fpga1(); s_cleared = true; }
}

void menu_button(enum menu_button b)
{
    const entry_t *e = &s_main[s_mi];
    const item_t *it = (e->n && s_si < e->n) ? &e->items[s_si] : NULL;

    s_idle = 0;
    if (!s_open) {
        if (b == MENU_BTN_ESC) {                  /* escape with the menu closed: hide the box */
            if (!iqcap_ovl_hidden()) (void)iqcap_ovl_set_hidden(true);
            return;
        }
        if (iqcap_ovl_hidden()) {                 /* hidden: OK only brings the box back ... */
            (void)iqcap_ovl_set_hidden(false);
            if (b == MENU_BTN_OK) return;         /* ... any other button also opens the menu */
        }
        s_open = true; s_focus = F_MAIN; s_mi = 0; s_si = 0; s_cleared = false;
        draw();
        return;
    }
    if (b == MENU_BTN_ESC) { close_menu(); return; }
    if (!(it && it->id == I_CLEAR && b == MENU_BTN_OK)) s_cleared = false;

    switch (s_focus) {
    case F_MAIN:
        switch (b) {
        case MENU_BTN_UP:    s_mi = (s_mi + N_MAIN - 1) % N_MAIN; s_si = 0; break;
        case MENU_BTN_DOWN:  s_mi = (s_mi + 1) % N_MAIN; s_si = 0; break;
        case MENU_BTN_LEFT:  close_menu(); return;
        case MENU_BTN_RIGHT:
        case MENU_BTN_OK:
            if (e->items == NULL) { close_menu(); return; }      /* Exit */
            s_focus = F_SUB; s_si = 0;
            break;
        default: break;
        }
        break;
    case F_SUB:
        switch (b) {
        case MENU_BTN_UP:    s_si = (s_si + e->n - 1) % e->n; break;
        case MENU_BTN_DOWN:  s_si = (s_si + 1) % e->n; break;
        case MENU_BTN_LEFT:  s_focus = F_MAIN; break;
        case MENU_BTN_RIGHT:
        case MENU_BTN_OK:
            if (!it) break;
            if (it->kind == K_TOGGLE) toggle(it);
            else if (it->kind == K_ACTION) action(it);
            else if (it->kind == K_VALUE) s_focus = F_EDIT;
            break;
        default: break;
        }
        break;
    case F_EDIT:
        switch (b) {
        case MENU_BTN_UP:    if (it) adjust(it, +1); break;
        case MENU_BTN_DOWN:  if (it) adjust(it, -1); break;
        default:             s_focus = F_SUB; break;             /* OK, left, right keep the value */
        }
        break;
    }
    draw();
}

bool menu_is_open(void) { return s_open; }

void menu_redraw(void) { if (s_open) draw(); }

int menu_status(char *dst, size_t n)
{
    char val[VAL_W + 1];
    const entry_t *e = &s_main[s_mi];
    if (!s_open) return snprintf(dst, n, iqcap_ovl_hidden() ? "closed, box hidden" : "closed");
    if (s_focus == F_MAIN || !e->n) return snprintf(dst, n, "open, main: %s", e->name);
    value_text(&e->items[s_si], val, sizeof val);
    return snprintf(dst, n, "open, %s > %s%s%s%s", e->name, e->items[s_si].name, val[0] ? " = " : "", val,
                    s_focus == F_EDIT ? " (editing)" : "");
}

void menu_init(void)
{
    GPIO_InitTypeDef g = { 0 };
    uint16_t pins = 0;
    for (int i = 0; i < MENU_BTN_N; i++) pins |= s_pin[i];
    /* MX_GPIO_Init made every J8 pin a push-pull output driven low; the six
       button pins become pulled-up inputs, pin 10 stays low as the common */
    g.Pin = pins; g.Mode = GPIO_MODE_INPUT; g.Pull = GPIO_PULLUP;
    HAL_GPIO_Init(GPIOD, &g);
    HAL_GPIO_WritePin(BTN_COMMON_PORT, BTN_COMMON_PIN, GPIO_PIN_RESET);
    memset(s_cnt, 0, sizeof s_cnt); memset(s_down, 0, sizeof s_down); memset(s_held, 0, sizeof s_held);
    s_open = false; s_idle = 0; s_focus = F_MAIN; s_mi = 0; s_si = 0;
}

void menu_poll(void)
{
    enum menu_button fire = MENU_BTN_N;
    for (int i = 0; i < MENU_BTN_N; i++) {
        bool raw = HAL_GPIO_ReadPin(s_port[i], s_pin[i]) == GPIO_PIN_RESET;   /* pressed = low */
        if (raw != s_down[i]) {
            if (++s_cnt[i] >= DEBOUNCE_N) {
                s_cnt[i] = 0; s_down[i] = raw; s_held[i] = 0;
                if (raw && fire == MENU_BTN_N) fire = (enum menu_button)i;
            }
        }
        else {
            s_cnt[i] = 0;
            if (s_down[i] && i != MENU_BTN_OK && i != MENU_BTN_ESC) {   /* auto-repeat for the arrows */
                if (s_held[i] < 0xFFFFu) s_held[i]++;
                if (s_held[i] >= REPEAT_DELAY && ((s_held[i] - REPEAT_DELAY) % REPEAT_EVERY) == 0u &&
                    fire == MENU_BTN_N)
                    fire = (enum menu_button)i;
            }
        }
    }
    if (fire != MENU_BTN_N) {
        logw_bus_lock();
        menu_button(fire);
        logw_bus_unlock();
    }
    else if (s_open) {
        if (++s_idle >= TIMEOUT_POLLS) {
            logw_bus_lock();
            close_menu();
            logw_bus_unlock();
        }
    }
}
