/*
 * console.c - USART3 command line for the RF frontend and the LOGW link
 * sequencer. See console.h. Derived from RASECU/STM32H743_Test.
 *
 * RECEPTION is interrupt-driven, one byte at a time, into a ring buffer that
 * console_poll() drains. The USART3 interrupt was already enabled and already
 * routed to HAL_UART_IRQHandler by the generated code - only the mode had to
 * change, since CubeMX had USART3 as MODE_TX (printf only) and RX was
 * therefore switched off in the peripheral despite PD9 being configured for it.
 *
 * The callbacks below deliberately call NO FreeRTOS/CMSIS-OS function.
 * USART3_IRQn sits at preemption priority 0, above configMAX_SYSCALL_INTERRUPT_
 * PRIORITY, so an osSomething() from there would trip the port's assertion (or
 * worse, corrupt a kernel list). A ring-buffer write needs nothing from the
 * kernel, so the priority can stay where the generated code put it.
 *
 * Polling was not an option here for the same reason it was fine on the
 * frontend: printf on this side blocks for the whole line at 115200 (~1ms for
 * 12 characters), and every character arriving inside that window would be an
 * overrun, which latches RXNE off until the error is cleared.
 */
#include "console.h"
#include "main.h"
#include "cmsis_os.h"
#include "rasrf.h"
#include "rasrf6000_proto.h"
#include "rasbb_fpga.h"
#include "logw_seq.h"
#include "menu.h"
#include <stdio.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

extern UART_HandleTypeDef huart3;

/* Deep enough that a paste of the longest command cannot outrun the poll
 * interval; a dropped byte here would silently corrupt a command, so the
 * buffer is sized to make that impossible rather than to save 60 bytes. */
#define RX_RING_LEN  256u
#define LINE_MAX     160u   /* OT <text>: up to IQCAP_OVL_MAX (120) text bytes plus the verb */

/* Longest a retune is given before it is called a failure. The frontend needs
 * ~50ms; this is an order of magnitude of headroom, and the only way to exceed
 * it is a frontend that is not relocking at all. */
#define RETUNE_TIMEOUT_MS 500u

static volatile uint8_t  s_ring[RX_RING_LEN];
static volatile uint16_t s_head;   /* written by the ISR  */
static volatile uint16_t s_tail;   /* written by the task  */
static uint8_t           s_rxByte; /* HAL's landing spot for one byte */

static char    s_line[LINE_MAX];
static uint8_t s_len;

/* ------------------------------------------------------------------ output */

static void tx_char(char c)
{
    /* Not printf: the echo has to interleave correctly with the command
     * responses, and going through the same blocking HAL call they end up in
     * keeps the ordering obvious. */
    (void)HAL_UART_Transmit(&huart3, (uint8_t *)&c, 1u, HAL_MAX_DELAY);
}

static void prompt(void)
{
    printf("> ");
}

/* ------------------------------------------------------------- parse helpers */

static void skip_spaces(const char **pp)
{
    while (**pp == ' ' || **pp == '\t') { (*pp)++; }
}

/* Decimal, for quantities. Returns 0 if there is no digit at *pp. */
static int parse_dec(const char **pp, uint32_t *out)
{
    const char *p = *pp;
    uint32_t    v = 0u;
    int         digits = 0;

    skip_spaces(&p);

    while (*p >= '0' && *p <= '9')
    {
        v = (v * 10u) + (uint32_t)(*p - '0');
        digits++;
        p++;
        if (v > 0xFFFFFFu) { return 0; }   /* nothing here is that big */
    }

    if (digits == 0) { return 0; }

    *out = v;
    *pp  = p;
    return 1;
}

/* Hex, optionally 0x-prefixed, for register bitfields. */
static int parse_hex(const char **pp, uint32_t *out)
{
    const char *p = *pp;
    uint32_t    v = 0u;
    int         digits = 0;

    skip_spaces(&p);

    if (p[0] == '0' && (p[1] == 'x' || p[1] == 'X')) { p += 2; }

    for (;;)
    {
        char     c = *p;
        uint32_t d;

        if      (c >= '0' && c <= '9') { d = (uint32_t)(c - '0'); }
        else if (c >= 'a' && c <= 'f') { d = (uint32_t)(c - 'a' + 10); }
        else if (c >= 'A' && c <= 'F') { d = (uint32_t)(c - 'A' + 10); }
        else                           { break; }

        v = (v << 4) | d;
        digits++;
        p++;
        if (digits > 8) { return 0; }
    }

    if (digits == 0) { return 0; }

    *out = v;
    *pp  = p;
    return 1;
}

static char upper(char c)
{
    return (c >= 'a' && c <= 'z') ? (char)(c - 'a' + 'A') : c;
}

/* Matches a two-letter command and leaves *pp on its arguments. */
static int is_cmd(const char **pp, char a, char b)
{
    const char *p = *pp;

    if (upper(p[0]) != a || upper(p[1]) != b) { return 0; }

    /* Reject "SFX": a command is two letters then a separator or the end. */
    if (p[2] != '\0' && p[2] != ' ' && p[2] != '\t') { return 0; }

    *pp = p + 2;
    return 1;
}

/* ------------------------------------------------------------- reporting */

static const char *lna_name(uint8_t code)
{
    switch ((code >> 5) & 0x3u)
    {
        case 3u:  return "high";
        case 2u:  return "-16dB";
        default:  return "-33dB";
    }
}

static void print_gain(uint8_t code)
{
    printf("RX gain 0x%02X (LNA %s, VGA %udB), all channels\n",
           (unsigned)code, lna_name(code), (unsigned)(2u * (code & 0x1Fu)));
}

/* The lock bits and what they mean, in one line. */
static void print_status(uint8_t st)
{
    printf("LD MAX1..4 = %u %u %u %u  ADC1 %s  ADC2 %s%s\n",
           (unsigned)((st & RASRF_ST_LD_MAX1) ? 1u : 0u),
           (unsigned)((st & RASRF_ST_LD_MAX2) ? 1u : 0u),
           (unsigned)((st & RASRF_ST_LD_MAX3) ? 1u : 0u),
           (unsigned)((st & RASRF_ST_LD_MAX4) ? 1u : 0u),
           (st & RASRF_ST_ADC1_OK) ? "ok" : "FAIL",
           (st & RASRF_ST_ADC2_OK) ? "ok" : "FAIL",
           (st & RASRF_ST_FREQ_BUSY) ? "  (retuning)" : "");
}

static void print_help(void)
{
    printf("SF <mhz>   set the LO, %u..%u, e.g. SF 2437 (802.11 ch 6)\n"
           "GF         get the LO\n"
           "ST         status: PLL lock, ADC config, RSSI\n"
           "ID         frontend model, revision, map version, build\n"
           "SG <hh>    set RX gain code (hex: D6:D5 LNA 3=high 2=-16dB 0=-33dB,\n"
           "           D4:D0 VGA 2dB/step). 68 = the frontend's default\n"
           "GG         get RX gain code\n"
           "SR <n>     ADC ramp self-test: 0 off, 1 ADC1 (CH1,CH2),\n"
           "           2 ADC2 (CH3,CH4), 3 both. Ramp one, keep the other live\n"
           "GR         get self-test state\n"
           "--- LOGW link sequencer (6 GHz front end + LOGW bitstream) ---\n"
           "LS         sequencer state, front end + FPGA link status, events\n"
           "LR         force one training cycle (ramp on, retrain, ramp off)\n"
           "LP <n>     0 automatic, 1 park with ramp ON, 2 park with ramp OFF\n"
           "--- IQ snapshot capture (FPGA1, SPEC.md section 9; settings persist) ---\n"
           "CS         capture status + counters      CZ    clear counters (both FPGAs)\n"
           "FR <1|2>   reload FPGA1/FPGA2 from its flash (PROG pulse) and re-apply the config\n"
           "TL / EI    FreeRTOS task list / Ethernet PHY link state\n"
           "CE <0|1>   capture enable                 CP <0|1>  pass-all (bypass MAC filter)\n"
           "CF <0|1>   require FCS                    CN <n>    instants per snapshot (1..1024)\n"
           "CB <n>     instants before the trigger (0..nsamp-1, default 128; the STF detect sits at index n)\n"
           "CM <k> <mac|off>  MAC filter slot 0..7    CL        list the filter\n"
           "CT <0|1>   FPGA1 test pattern (ramp snapshot every 100 ms)\n"
           "CW <start> <len>  phase-comparison window, instants after the trigger (96 128 = LTF)\n"
           "CA [deg|?]  align the cyan phase marker to the ray (no arg), set an offset, or show it\n"
           "CG [J1 J2 J3 J4]  amplitude-DF gain trim per port in dB (persisted), e.g. CG 0 -2.4 -1.9 -2.0\n"
           "--- FPGA2 network (SPEC.md section 9) ---\n"
           "NL         net status: PHY, link, SNAPLINK, counters, addresses\n"
           "NI <ip>    PC IP     NP <port>  PC UDP port   NM <mac|bcast>  PC MAC\n"
           "NS <ip>    own IP    NE <0|1>   UDP tx enable NT <0|1>  FPGA2 test pattern\n"
           "RR <aa> / RW <aa> <hhhhhhhh>   raw FPGA1 register read / write (hex)\n"
           "NR <aa> / NW <aa> <hhhhhhhh>   raw FPGA2 register read / write (hex)\n"
           "NF         receiver noise floor per channel, dBFS (FPGA1 0x6E/0x6F, last 0.21 s period)\n"
           "--- HDMI pop-up box (FPGA1 0x08..0x0B, logo + text lower right; settings persist) ---\n"
           "OT <text>  set the text, \\r = line break (OT alone shows it, OT - clears it)\n"
           "OS <0|1>   show / hide the box            OZ <0..4>  font scale (0 = default 2)\n"
           "OA <0|1>   centre the lines               OC <ttt> <bbb>  text / box colour, RGB 4:4:4 hex\n"
           "--- on-screen menu (buttons on J8: 1 up, 3 down, 5 left, 7 right, 9 OK, 2 esc, 10 common) + display switches ---\n"
           "BT <UP|DN|L|R|OK|E>  keypad press for the menu; E = escape closes it, or hides the pop-up box\n"
           "           when the menu is closed (OK brings it back). BT alone: state. MB u|d|l|r|o = alias\n"
           "DP <0|1>   pause the display (not stored)\n"
           "DB <0|1>   FCS-bad frames shown (stored)  DA <0..7> label position averaging 1/2^k (stored, default 4)\n"
           "DF <0..7>  phase dot averaging 1/2^k (stored, default 4)\n"
           "DS <0|1>   solo: rays and labels only for the MACs of the capture filter (CM), stored\n"
           "DC         clear the station list, labels and rays\n",
           (unsigned)RASRF_FREQ_MHZ_MIN, (unsigned)RASRF_FREQ_MHZ_MAX);
}

/* ------------------------------------------------------------- commands */

/* Writes the pair, then waits for the frontend to finish retuning and reports
 * what it settled on. The wait is here rather than in the driver so that it can
 * yield: osDelay lets the frame read-out task keep polling the FPGA through the
 * ~50ms, which HAL_Delay would not (this project's HAL tick is TIM4, entirely
 * independent of the scheduler). */
static void cmd_set_freq(const char *args)
{
    uint32_t mhz;
    uint32_t t0;
    uint16_t live;
    uint8_t  st = 0u;

    if (!parse_dec(&args, &mhz))
    {
        printf("SF: expected a frequency in MHz, e.g. SF 2437\n");
        return;
    }

    if (mhz < RASRF_FREQ_MHZ_MIN || mhz > RASRF_FREQ_MHZ_MAX)
    {
        printf("SF: %lu MHz is outside %u..%u\n", (unsigned long)mhz,
               (unsigned)RASRF_FREQ_MHZ_MIN, (unsigned)RASRF_FREQ_MHZ_MAX);
        return;
    }

    if (!rasrf_set_freq_mhz((uint16_t)mhz))
    {
        printf("SF: frontend did not accept the write (no I2C answer?)\n");
        return;
    }

    t0 = HAL_GetTick();
    for (;;)
    {
        if (!rasrf_status(&st))
        {
            printf("SF: %lu MHz written, but status is unreadable\n",
                   (unsigned long)mhz);
            return;
        }
        if ((st & RASRF_ST_FREQ_BUSY) == 0u) { break; }

        if ((HAL_GetTick() - t0) > RETUNE_TIMEOUT_MS)
        {
            printf("SF: still busy after %ums - frontend is not relocking\n",
                   (unsigned)RETUNE_TIMEOUT_MS);
            return;
        }
        osDelay(5);
    }

    if (!rasrf_get_freq_mhz(&live)) { live = 0u; }

    if (live == 0u)
    {
        /* Wrote, polled and read back nothing: the register file answered but
         * has no frequency pair, which is what a single-channel frontend looks
         * like from here. ID says which board is fitted. */
        printf("SF: frontend answers but reports no LO - is it a 4-channel "
               "board? (try ID)\n");
        return;
    }

    if (live != (uint16_t)mhz)
    {
        /* The frontend refuses out-of-range values by not retuning at all,
         * so a request it does not support reads back as the old LO. */
        printf("SF: frontend kept LO %u MHz - %lu MHz refused (below 2400 "
               "needs frontend fw 0.3+, see ID)\n", (unsigned)live,
               (unsigned long)mhz);
        return;
    }

    printf("SF: LO %u MHz in %lums, ", (unsigned)live,
           (unsigned long)(HAL_GetTick() - t0));

    if ((st & RASRF_ST_LD_ALL) == RASRF_ST_LD_ALL)
    {
        printf("all four locked\n");
    }
    else
    {
        /* Worth shouting about: an unlocked synthesizer is a dead RF channel,
         * and on a direction finder that is a hole in the aperture, not just
         * one quiet receiver. */
        printf("NOT LOCKED - ");
        print_status(st);
    }
}

static void cmd_get_freq(void)
{
    uint16_t mhz;

    if (!rasrf_get_freq_mhz(&mhz))
    {
        printf("GF: no answer from the frontend\n");
        return;
    }

    printf("LO %u MHz\n", (unsigned)mhz);
}

static void print_status_6g(uint8_t st)
{
    printf("6GHz FE: ADC %s  LTC %s  Si5324 link %s lock %s  LO %s  ramp %s%s%s\n",
           (st & RASRF6000_ST_ADC_OK)   ? "ok" : "FAIL",
           (st & RASRF6000_ST_LTC_OK)   ? "ok" : "FAIL",
           (st & RASRF6000_ST_CLK_LINK) ? "ok" : "FAIL",
           (st & RASRF6000_ST_CLK_LOCK) ? "LOCKED" : "unlocked",
           (st & RASRF6000_ST_LO_LOCK)  ? "LOCKED" : "unlocked",
           (st & RASRF6000_ST_RAMP_ON)  ? "ON" : "off",
           (st & RASRF6000_ST_HOST_RAMP) ? " (host)" : "",
           (st & RASRF6000_ST_INIT_DONE) ? "" : "  INIT NOT DONE");
}

static bool fe_is_6ghz(void)
{
    uint8_t model;

    return rasrf_read_reg(RASRF_REG_BOARD_MODEL, &model) &&
           (RASRF6000_BAND(model) == RASRF6000_BAND_6GHZ);
}

static void cmd_status(void)
{
    uint8_t  st;
    uint16_t rssi;
    uint8_t  vmaj, vmin, reinits, unlocks;

    if (!rasrf_status(&st))
    {
        printf("ST: no answer from the frontend\n");
        return;
    }

    if (fe_is_6ghz())
    {
        uint8_t los = 0u, lol = 0u;

        print_status_6g(st);
        if (rasrf_read_reg(RASRF6000_REG_CLK_LOS, &los) &&
            rasrf_read_reg(RASRF6000_REG_CLK_LOL, &lol))
        {
            printf("Si5324 LOS 0x%02X (b0 xtal b1 CKIN1/J2 b2 CKIN2)  LOL 0x%02X\n",
                   (unsigned)los, (unsigned)lol);
        }
        return;
    }

    print_status(st);

    if (rasrf_get_rssi(&rssi))
    {
        printf("RSSI %u (raw 12-bit, channel 2, up to 1s old)\n",
               (unsigned)rssi);
    }

    /* Register map 0.4 added the frontend's reference/ADC supervisor: how
     * often it had to re-run an ADC configuration (an ADC configured before
     * its 40MHz ran) and how often a PLL lost lock. Older maps read 0 there,
     * which would look like a clean bill of health, so ask only from 0.4 on. */
    if (rasrf_read_reg(RASRF_REG_FW_VER_MAJOR, &vmaj) &&
        rasrf_read_reg(RASRF_REG_FW_VER_MINOR, &vmin) &&
        ((vmaj > 0u) || (vmin >= 4u)) &&
        rasrf_read_reg(RASRF_REG_ADC_REINITS, &reinits) &&
        rasrf_read_reg(RASRF_REG_UNLOCKS, &unlocks))
    {
        printf("supervisor: ADC re-inits %u, PLL unlock events %u (since frontend boot)\n",
               (unsigned)reinits, (unsigned)unlocks);
    }
}

static void cmd_ident(void)
{
    rasrf_ident_t id;

    if (!rasrf_identify(&id))
    {
        printf("ID: no answer at I2C 0x%02X\n", (unsigned)RASRF_I2C_ADDR_7B);
        return;
    }

    printf("frontend 0x%02X (%s, %uch) rev %c  map %u.%u  build %s\n",
           (unsigned)id.model,
           ((id.model >> 4) == 0x1u) ? "2.4GHz" :
           ((id.model >> 4) == 0x2u) ? "6GHz" : "band?",
           (unsigned)(id.model & 0x0Fu),
           (id.revision >= ' ' && id.revision < 0x7Fu) ? (char)id.revision : '?',
           (unsigned)id.ver_major, (unsigned)id.ver_minor,
           (id.build[0] != '\0') ? id.build : "(none)");

    if (RASRF6000_BAND(id.model) == RASRF6000_BAND_6GHZ)
    {
        printf("note: 6GHz front end - fixed LO, no gain control; ST/LS apply, "
               "SF/GF/SG/SR do not%s\n",
               ((id.ver_major > 0u) || (id.ver_minor >= RASRF6000_MAP_MIN_MINOR))
                   ? "" : " - HKU too old for host ramp control (needs map 0.2)");
    }
    else if ((id.model & 0x0Fu) < 4u)
    {
        /* The single-channel frontend shares 0x00..0x04 but has no status or
         * frequency registers, so SF/GF/ST have nothing to talk to there -
         * they would read zeros rather than fail. Say so once, here, instead of
         * letting each command report its own confusing nothing. */
        printf("note: this frontend has no LO or status registers - "
               "SF/GF/ST do not apply, SG does\n");
    }
}

static void cmd_set_gain(const char *args)
{
    uint32_t code;

    if (!parse_hex(&args, &code) || code > 0x7Fu)
    {
        printf("SG: expected a gain code 00..7F in hex, e.g. SG 68\n");
        return;
    }

    if (!rasrf_set_rx_gain((uint8_t)code))
    {
        printf("SG: frontend did not accept the write\n");
        return;
    }

    print_gain((uint8_t)code);
}

static void cmd_get_gain(void)
{
    uint8_t code;

    if (!rasrf_get_rx_gain(&code))
    {
        printf("GG: no answer from the frontend\n");
        return;
    }

    print_gain(code);
}

static void print_test_mode(uint8_t mask)
{
    printf("self-test 0x%02X: ADC1 (CH1,CH2) %s, ADC2 (CH3,CH4) %s\n",
           (unsigned)mask,
           (mask & RASRF_TEST_RAMP_ADC1) ? "RAMP" : "live",
           (mask & RASRF_TEST_RAMP_ADC2) ? "RAMP" : "live");
}

static void cmd_set_test(const char *args)
{
    uint32_t mask;

    if (!parse_hex(&args, &mask) || (mask & ~(uint32_t)RASRF_TEST_RAMP_MASK))
    {
        printf("SR: expected 0..3 (bit0 ramp ADC1, bit1 ramp ADC2), e.g. SR 1\n");
        return;
    }

    if (!rasrf_set_test_mode((uint8_t)mask))
    {
        printf("SR: frontend did not accept the write\n");
        return;
    }

    /* Read back rather than echoing the request. A frontend older than
     * register-map 0.2 has no 0x08 at all and silently drops the write, and
     * reporting the requested state there would claim an ADC is ramping when
     * nothing happened - the worst possible lie in the middle of a fault
     * hunt. The frontend applies this from its main loop, so give it a moment
     * before asking. */
    HAL_Delay(50u);

    {
        uint8_t live;

        if (!rasrf_get_test_mode(&live))
        {
            printf("SR: written, but the state is unreadable\n");
            return;
        }

        if (live != (uint8_t)mask)
        {
            printf("SR: frontend ignored it (reads 0x%02X, not 0x%02X)"
                   " - too old for the self-test register? (try ID)\n",
                   (unsigned)live, (unsigned)mask);
            return;
        }

        print_test_mode(live);
    }
}

static void cmd_get_test(void)
{
    uint8_t mask;

    if (!rasrf_get_test_mode(&mask))
    {
        printf("GR: no answer from the frontend\n");
        return;
    }

    print_test_mode(mask);
}

/* ------------------------------------------------------------- LOGW link */

static void cmd_link_status(void)
{
    const logw_seq_t *q = &g_logw_seq;
    uint8_t i;

    printf("sequencer %s for %lus, polls %lu, manual %u\n",
           logw_seq_state_name(q->state),
           (unsigned long)((HAL_GetTick() - q->state_since_ms) / 1000u),
           (unsigned long)q->polls, (unsigned)q->manual);

    if (!q->fe_present)
    {
        printf("front end: no answer at I2C 0x%02X\n", (unsigned)RASRF_I2C_ADDR_7B);
    }
    else
    {
        printf("front end 0x%02X rev %c map %u.%u, ramp reg %s: ",
               (unsigned)q->fe_model,
               (q->fe_rev >= ' ' && q->fe_rev < 0x7Fu) ? (char)q->fe_rev : '?',
               (unsigned)q->fe_map_major, (unsigned)q->fe_map_minor,
               q->fe_ramp_ctrl ? "yes" : "NO");
        if (q->fe_is_6ghz) { print_status_6g(q->fe_status); }
        else               { printf("not a 6GHz board\n"); }
    }

    if (!q->fpga_present)
    {
        printf("FPGA1: no LOGW bitstream answering (status 0x%02X)\n",
               (unsigned)q->fpga_status);
    }
    else
    {
        printf("FPGA1 LOGW: DCLK PLL %s, capture %s, frames in last 1s: %s"
               "  [retrains %u, trim 0x%02X hits %u/4097, tap %u, fail_min %u]\n",
               (q->fpga_status & RASBB_ST_FE_VALID) ? "locked" : "NO CLOCK",
               (q->fpga_status & RASBB_ST_LINK_OK)  ? "TRAINED" : "not trained",
               (q->fpga_status & RASBB_ST_DEMOD)    ? "yes" : "none",
               (unsigned)q->fpga_ext[1], (unsigned)q->fpga_ext[2],
               (unsigned)(q->fpga_ext[3] | ((unsigned)q->fpga_ext[4] << 8)),
               (unsigned)q->fpga_ext[7],
               (unsigned)(q->fpga_ext[5] | ((unsigned)q->fpga_ext[6] << 8)));
        printf("      lane taps DA0 %u  DA1 %u  DB0 %u  DB1 %u  (I LSB/MSB, Q LSB/MSB)\n",
               (unsigned)(q->fpga_lane_taps & 0x1Fu),
               (unsigned)((q->fpga_lane_taps >> 5) & 0x1Fu),
               (unsigned)((q->fpga_lane_taps >> 10) & 0x1Fu),
               (unsigned)((q->fpga_lane_taps >> 15) & 0x1Fu));
    }

    printf("cycles %lu ok %lu timeouts %lu | fpga lost %lu fe lost %lu relinks %lu"
           " | i2c err %lu spi err %lu\n",
           (unsigned long)q->train_cycles, (unsigned long)q->train_ok,
           (unsigned long)q->train_timeouts, (unsigned long)q->fpga_losses,
           (unsigned long)q->fe_losses, (unsigned long)q->relinks,
           (unsigned long)q->i2c_errors, (unsigned long)q->spi_errors);

    for (i = 0u; i < LOGW_SEQ_EVENTS; i++)
    {
        const logw_seq_event_t *e =
            &q->events[(q->event_head + i) % LOGW_SEQ_EVENTS];

        if (e->text[0] != '\0')
        {
            printf("  %8lu.%03lu  %s\n", (unsigned long)(e->tick_ms / 1000u),
                   (unsigned long)(e->tick_ms % 1000u), e->text);
        }
    }
}

static void cmd_link_retrain(void)
{
    logw_seq_set_manual(0u);
    logw_seq_request_retrain();
    printf("LR: training cycle requested (watch LS)\n");
}

static void cmd_link_park(const char *args)
{
    uint32_t mode;

    if (!parse_dec(&args, &mode) || mode > 2u)
    {
        printf("LP: expected 0 (automatic), 1 (park, ramp ON) or 2 (park, ramp OFF)\n");
        return;
    }

    logw_seq_set_manual((uint8_t)mode);
    if (mode != 0u)
    {
        if (rasrf_write_reg(RASRF6000_REG_RAMP, (mode == 1u) ? 1u : 0u))
        {
            printf("LP: sequencer parked, ramp %s\n", (mode == 1u) ? "ON" : "OFF");
        }
        else
        {
            printf("LP: sequencer parked, but the front end did not take the ramp write\n");
        }
    }
    else
    {
        printf("LP: automatic\n");
    }
}

/* ---- IQ snapshot capture + network, SPEC.md section 9 (JOB-06) ----------- */
/* Every setter changes the persisted config, saves it to flash and applies
 * it to the FPGA it belongs to; CS / NL print the live registers. */
#include "iqcap_cfg.h"

static void print_cap_status(void)
{
    iqcap_stat1_t s;
    const iqcap_cfg_t *c = iqcap_cfg();
    char m[20];
    if (!iqcap_stat_fpga1(&s)) { printf("CS: FPGA1 does not answer\n"); return; }
    printf("CS: capture %s pass-all=%u req-fcs=%u test=%u%s nsamp=%lu pretrig=%lu\n",
           (s.ctrl & 1u) ? "ON" : "off", (unsigned)((s.ctrl >> 1) & 1u), (unsigned)((s.ctrl >> 2) & 1u),
           (unsigned)((s.ctrl >> 4) & 1u), (s.ctrl & 32u) ? "(fast)" : "",
           (unsigned long)s.nsamp, (unsigned long)s.pretrig);
    printf("    trig=%lu match=%lu drop=%lu sent=%lu  fpga2_ready=%lu tx_busy=%lu rd_xor=%08lX\n",
           (unsigned long)s.trig, (unsigned long)s.match, (unsigned long)s.drop, (unsigned long)s.sent,
           (unsigned long)(s.link & 1u), (unsigned long)((s.link >> 1) & 1u), (unsigned long)s.rd_xor);
    {   /* v0.4: front-half self-heal counters (0x72 fe_valid watchdog, 0x73 receiver-stall watchdog) */
        uint32_t hc = 0, sc = 0;   /* no bus lock here: the C-commands are dispatched under it (non-recursive mutex) */
        bool okc = rasbb_fpga_read_reg(0x72u, &hc) && rasbb_fpga_read_reg(0x73u, &sc);
        if (okc) printf("    fe heals=%lu (fe_valid watchdog)  stall heals=%lu (no-STF watchdog)\n",
                        (unsigned long)(hc & 0xFFu), (unsigned long)(sc & 0xFFu));
    }
    {   /* 4.b: phase comparison of the last committed frame (0x74..0x77) */
        iqcap_phase_t ph; uint32_t ws = 0, wl = 0;
        if (iqcap_phase_fpga1(&ph) && rasbb_fpga_read_reg(0x14u, &ws) && rasbb_fpga_read_reg(0x15u, &wl))
        {
            printf("    phase (frames=%u window=%lu+%lu)", (unsigned)ph.count, (unsigned long)(ws & 0xFFFFu), (unsigned long)(wl & 0xFFFFu));
            if (!ph.valid) printf(": none yet\n");
            else
            {
                for (int k = 0; k < 3; k++)
                {
                    int d = iqcap_phase_deg10(ph.ph[k]);
                    printf("  ch%d-ch0=%s%d.%d deg (2^%u)", k + 1, d < 0 ? "-" : "", abs(d) / 10, abs(d) % 10, (unsigned)ph.exp[k]);
                }
                printf("%s\n", ph.weak ? "  WEAK" : "");
            }
        }
    }
    for (unsigned k = 0; k < IQCAP_NMAC; k++)
        if (c->mac[k].en) { iqcap_fmt_mac(m, sizeof m, c->mac[k].mac); printf("    filter %u: %s\n", k, m); }
}

/* CA: align the polar rim marker to the amplitude ray. The marker draws
 * (phase - PH_CAL); 0x79 gives the raw phase bin and the ray bin of the same
 * committed frame, so cal = (raw - ray) << 7 puts the marker on the ray for
 * that source. Per boot (the LO phase re-randomises at every power-cycle),
 * not persisted. CA <deg> sets an explicit offset, CA 0 clears, CA ? prints. */
static void cmd_cap_phase_cal(const char *args)
{
    iqcap_mark_t m; uint16_t cal = 0; int aligned = 0;
    const char *p = args;
    skip_spaces(&p);
    if (*p == '?')
    {
        if (!iqcap_phase_cal_get_fpga1(&cal) || !iqcap_mark_fpga1(&m)) { printf("CA: FPGA1 does not answer\n"); return; }
        int d = iqcap_phase_deg10(cal);
        printf("CA: offset %s%d.%d deg, marker %s at %u deg, raw phase %u deg, ray %u deg, frames %u\n",
               d < 0 ? "-" : "", abs(d) / 10, abs(d) % 10, m.ok ? "valid" : "none",
               (unsigned)(m.ang * 360u / 512u), (unsigned)(m.raw * 360u / 512u), (unsigned)(m.brg * 360u / 512u), (unsigned)m.count);
        return;
    }
    if (*p == '\0')
    {
        if (!iqcap_mark_fpga1(&m)) { printf("CA: FPGA1 does not answer\n"); return; }
        if (!m.ok) { printf("CA: no frame with a phase yet\n"); return; }
        cal = (uint16_t)(((m.raw - m.brg) & 0x1FFu) << 7);      /* bins -> turns, modular */
        aligned = 1;
    }
    else
    {
        int neg = 0; uint32_t v;
        if (*p == '-') { neg = 1; p++; }
        if (!parse_dec(&p, &v) || v > 360u) { printf("CA: usage CA | CA <deg -360..360> | CA 0 | CA ?\n"); return; }
        int32_t t = (int32_t)((v * 65536u + 180u) / 360u); if (neg) t = -t;
        cal = (uint16_t)t;
    }
    if (!iqcap_phase_cal_set_fpga1(cal)) { printf("CA: FPGA1 does not answer\n"); return; }
    int d = iqcap_phase_deg10(cal);
    printf("CA: marker offset set to %s%d.%d deg%s\n", d < 0 ? "-" : "", abs(d) / 10, abs(d) % 10,
           aligned ? " (aligned to the current ray)" : "");
}

static void cap_commit(const char *tag);

/* signed decimal dB with at most one decimal ("-2.4", "0", "+1.5") -> tenths */
static int parse_ddb(const char **pp, int32_t *out)
{
    const char *p = *pp; int neg = 0; int32_t ip = 0, fr = 0; int dig = 0;
    skip_spaces(&p);
    if (*p == '-' || *p == '+') { neg = (*p == '-'); p++; }
    while (*p >= '0' && *p <= '9') { ip = ip * 10 + (*p - '0'); p++; dig++; if (ip > 999) return 0; }
    if (*p == '.') { p++; if (*p >= '0' && *p <= '9') { fr = *p - '0'; p++; dig++; } while (*p >= '0' && *p <= '9') p++; }
    if (!dig) return 0;
    *out = (ip * 10 + fr) * (neg ? -1 : 1); *pp = p; return 1;
}

/* CG [dJ1 dJ2 dJ3 dJ4]: amplitude-DF gain trim per receive path in dB, ADDED to
 * that channel's power before the bearing (FPGA1 0x18, persisted). From a split
 * test signal: if J2/J3/J4 read +2.4/+1.9/+2.0 dB above J1, use CG 0 -2.4 -1.9 -2.0. */
static void cmd_cap_gain_trim(const char *args)
{
    iqcap_cfg_t *c = iqcap_cfg();
    const char *p = args; int32_t v[4];
    skip_spaces(&p);
    if (*p != '\0')
    {
        for (int k = 0; k < 4; k++)
            if (!parse_ddb(&p, &v[k]) || v[k] > 200 || v[k] < -200)
            { printf("CG: usage CG <J1> <J2> <J3> <J4>  (dB, -20.0..20.0, e.g. CG 0 -2.4 -1.9 -2.0)\n"); return; }
        for (int k = 0; k < 4; k++) c->gain_trim_ddb[k] = (int16_t)v[k];
        cap_commit("CG");
    }
    uint32_t reg = 0; bool okr = rasbb_fpga_read_reg(0x18u, &reg);
    printf("CG: J1 %s%d.%d  J2 %s%d.%d  J3 %s%d.%d  J4 %s%d.%d dB",
           c->gain_trim_ddb[0] < 0 ? "-" : "+", abs(c->gain_trim_ddb[0]) / 10, abs(c->gain_trim_ddb[0]) % 10,
           c->gain_trim_ddb[1] < 0 ? "-" : "+", abs(c->gain_trim_ddb[1]) / 10, abs(c->gain_trim_ddb[1]) % 10,
           c->gain_trim_ddb[2] < 0 ? "-" : "+", abs(c->gain_trim_ddb[2]) / 10, abs(c->gain_trim_ddb[2]) % 10,
           c->gain_trim_ddb[3] < 0 ? "-" : "+", abs(c->gain_trim_ddb[3]) / 10, abs(c->gain_trim_ddb[3]) % 10);
    if (okr) printf("  (FPGA1 0x18 = %08lX%s)\n", (unsigned long)reg,
                    reg == iqcap_gain_trim_word(c->gain_trim_ddb) ? "" : " - differs from the stored trim!");
    else printf("  (FPGA1 does not answer)\n");
}

/* CW <start> <len>: phase_cmp window in instants after the trigger (FPGA1 0x14/0x15,
 * defaults 96/128 = the LTF; not persisted, FPGA defaults return at reload) */
static void cmd_cap_phase_window(const char *args)
{
    uint32_t st, ln;
    if (!parse_dec(&args, &st) || !parse_dec(&args, &ln) || ln < 1u || ln > IQCAP_NSAMP_MAX || st > IQCAP_NSAMP_MAX)
    { printf("CW: usage CW <start 0..1024> <len 1..1024>\n"); return; }
    printf("CW: %s\n", iqcap_phase_window_fpga1((uint16_t)st, (uint16_t)ln) ? "ok" : "FPGA1 does not answer");
}

static void print_net_status(void)
{
    iqcap_stat2_t s;
    const iqcap_cfg_t *c = iqcap_cfg();
    char ip[16], mac[20];
    if (!iqcap_fpga2_present() || !iqcap_stat_fpga2(&s)) { printf("NL: FPGA2 does not answer on CS2\n"); return; }
    printf("NL: PHY %08lX link %s%s  SNAPLINK %s%s  tx_en=%lu bcast=%lu test=%lu\n",
           (unsigned long)s.phy_id, (s.stat & 1u) ? "UP" : "down", (s.stat & 2u) ? " 1000" : "",
           (s.stat & 4u) ? "alive" : "DEAD", (s.stat & 8u) ? " (data seen)" : "",
           (unsigned long)(s.ctrl & 1u), (unsigned long)((s.ctrl >> 1) & 1u), (unsigned long)((s.ctrl >> 3) & 1u));
    printf("    pkts=%lu snaps=%lu crc_err=%lu frame_err=%lu pending=%lu ready=%lu\n",
           (unsigned long)s.pkt, (unsigned long)s.snap, (unsigned long)s.crc_err, (unsigned long)s.frame_err,
           (unsigned long)(s.pending & 7u), (unsigned long)((s.pending >> 7) & 1u));
    iqcap_fmt_ip(ip, sizeof ip, c->dst_ip); iqcap_fmt_mac(mac, sizeof mac, c->dst_mac);
    printf("    dst %s:%u mac %s%s", ip, (unsigned)c->dst_port, mac, c->use_bcast ? " (broadcast)" : "");
    iqcap_fmt_ip(ip, sizeof ip, c->src_ip);
    printf("  src %s:%u\n", ip, (unsigned)c->src_port);
}

static void cap_commit(const char *tag)
{
    bool saved = iqcap_cfg_save();
    bool applied = iqcap_cfg_apply_fpga1();
    printf("%s: %s%s\n", tag, saved ? "saved" : "SAVE FAILED", applied ? ", applied" : ", FPGA1 not applied");
}
static void net_commit(const char *tag)
{
    bool saved = iqcap_cfg_save();
    bool applied = iqcap_cfg_apply_fpga2();
    printf("%s: %s%s\n", tag, saved ? "saved" : "SAVE FAILED", applied ? ", applied" : ", FPGA2 not applied");
}

static int parse_bool(const char *args, const char *tag, uint8_t *out)
{
    uint32_t v;
    if (!parse_dec(&args, &v) || v > 1u) { printf("%s: expected 0 or 1\n", tag); return 0; }
    *out = (uint8_t)v;
    return 1;
}

static void cmd_cap_flag(const char *args, uint8_t *field, const char *tag)
{
    if (parse_bool(args, tag, field)) cap_commit(tag);
}

static void cmd_cap_nsamp(const char *args)
{
    uint32_t v;
    if (!parse_dec(&args, &v) || v < 1u || v > IQCAP_NSAMP_MAX) { printf("CN: expected 1..%u\n", (unsigned)IQCAP_NSAMP_MAX); return; }
    iqcap_cfg()->nsamp = (uint16_t)v;
    if (iqcap_cfg()->pretrig >= v) iqcap_cfg()->pretrig = (uint16_t)(v - 1u);
    cap_commit("CN");
}

static void cmd_cap_pretrig(const char *args)
{
    uint32_t v;
    if (!parse_dec(&args, &v) || v >= iqcap_cfg()->nsamp) { printf("CB: expected 0..%u\n", (unsigned)(iqcap_cfg()->nsamp - 1u)); return; }
    iqcap_cfg()->pretrig = (uint16_t)v;
    cap_commit("CB");
}

static void cmd_cap_mac(const char *args)
{
    uint32_t slot;
    iqcap_cfg_t *c = iqcap_cfg();
    if (!parse_dec(&args, &slot) || slot >= IQCAP_NMAC) { printf("CM: usage CM <slot 0..7> <aa:bb:cc:dd:ee:ff | off>\n"); return; }
    while (*args == ' ' || *args == '\t') args++;
    if (upper(args[0]) == 'O' && upper(args[1]) == 'F')
    {
        c->mac[slot].en = 0u;
    }
    else if (iqcap_parse_mac(args, c->mac[slot].mac))
    {
        c->mac[slot].en = 1u;
    }
    else { printf("CM: bad MAC\n"); return; }
    cap_commit("CM");
}

/* ---- HDMI pop-up box (FPGA1 0x08..0x0B, OWIFI_RX ovl_box.v) ------------- */

/* OT <text>: set the box text (\r / \n = line break, \\ = backslash); OT alone
 * prints the stored text, OT - clears it. Persisted and applied like the
 * capture settings. */
static void cmd_ovl_text(const char *args)
{
    char shown[2 * IQCAP_OVL_MAX + 4];
    if (*args == ' ' || *args == '\t') args++;            /* one separator; further spaces belong to the text */
    if (*args != '\0')
    {
        size_t n;
        if (args[0] == '-' && args[1] == '\0') args = "";
        n = iqcap_ovl_set_text(args);
        if (n >= IQCAP_OVL_MAX) printf("OT: text cut at %u bytes\n", (unsigned)IQCAP_OVL_MAX);
        cap_commit("OT");
    }
    iqcap_ovl_fmt_text(shown, sizeof shown, iqcap_cfg()->ovl_text);
    printf("OT: \"%s\" (%s, scale %u, %s)\n", shown, iqcap_cfg()->ovl_show ? "shown" : "hidden",
           (unsigned)iqcap_cfg()->ovl_scale, iqcap_cfg()->ovl_center ? "centred" : "left-aligned");
}

static void cmd_ovl_scale(const char *args)
{
    uint32_t v;
    if (!parse_dec(&args, &v) || v > 4u) { printf("OZ: expected 0..4 (0 = the FPGA default, 2)\n"); return; }
    iqcap_cfg()->ovl_scale = (uint8_t)v;
    cap_commit("OZ");
}

/* OC <ttt> <bbb>: text and box colour as 3 hex digits each (RGB 4:4:4) */
static void cmd_ovl_colour(const char *args)
{
    uint32_t t, b;
    if (!parse_hex(&args, &t) || !parse_hex(&args, &b) || t > 0xFFFu || b > 0xFFFu)
    { printf("OC: usage OC <text rgb> <box rgb>, 3 hex digits each, e.g. OC 444 FFF\n"); return; }
    iqcap_cfg()->ovl_text_rgb = (uint16_t)t; iqcap_cfg()->ovl_box_rgb = (uint16_t)b;
    cap_commit("OC");
}

/* ---- on-screen menu + display switches (FPGA1 DISP_CTRL 0x0C) ------------ */
/* BT <UP|DN|L|R|OK|E>: one keypad press for the on-screen menu (E = escape:
 * closes the menu, or hides the pop-up box when the menu is closed; OK
 * brings the box back); BT alone prints the state. MB <u|d|l|r|o> is the
 * short alias. */
static void cmd_menu_button(const char *args)
{
    char st[64], tok[8];
    int n = 0;
    skip_spaces(&args);
    while (args[n] && args[n] != ' ' && args[n] != '\t' && n < 7) { tok[n] = (char)upper(args[n]); n++; }
    tok[n] = '\0';
    if (n == 0)                                                   { /* state only */ }
    else if (!strcmp(tok, "UP") || !strcmp(tok, "U"))             menu_button(MENU_BTN_UP);
    else if (!strcmp(tok, "DN") || !strcmp(tok, "DOWN") || !strcmp(tok, "D")) menu_button(MENU_BTN_DOWN);
    else if (!strcmp(tok, "L")  || !strcmp(tok, "LEFT"))          menu_button(MENU_BTN_LEFT);
    else if (!strcmp(tok, "R")  || !strcmp(tok, "RIGHT"))         menu_button(MENU_BTN_RIGHT);
    else if (!strcmp(tok, "OK") || !strcmp(tok, "O"))             menu_button(MENU_BTN_OK);
    else if (!strcmp(tok, "E")  || !strcmp(tok, "ESC"))           menu_button(MENU_BTN_ESC);
    else { printf("BT: usage BT <UP|DN|L|R|OK|E>  (E = escape; BT alone shows the state)\n"); return; }
    menu_status(st, sizeof st);
    printf("BT: menu %s\n", st);
}

static void disp_commit(const char *tag)
{
    bool saved = iqcap_cfg_save();
    bool applied = iqcap_disp_apply_fpga1();
    menu_redraw();
    printf("%s: %s%s\n", tag, saved ? "saved" : "SAVE FAILED", applied ? ", applied" : ", FPGA1 not applied");
}

static void cmd_disp_flag(const char *args, uint8_t *field, const char *tag)
{
    if (parse_bool(args, tag, field)) disp_commit(tag);
}

static void cmd_disp_pause(const char *args)
{
    uint8_t v;
    if (!parse_bool(args, "DP", &v)) return;
    bool ok = iqcap_disp_set_pause(v != 0u);
    if (!menu_is_open()) (void)iqcap_ovl_apply_fpga1();    /* the [PAUSED] line in the pop-up */
    menu_redraw();
    printf("DP: display %s%s\n", v ? "paused" : "running", ok ? "" : " (FPGA1 does not answer)");
}

static void cmd_disp_avg(const char *args, int phase)
{
    uint32_t v;
    const char *tag = phase ? "DF" : "DA";
    if (!parse_dec(&args, &v) || v > 7u) { printf("%s: expected 0..7 (%s averages over 2^k frames)\n", tag, phase ? "the phase dot" : "the label position"); return; }
    if (phase) iqcap_cfg()->disp_ph_shift = (uint8_t)v; else iqcap_cfg()->disp_avg_shift = (uint8_t)v;
    disp_commit(tag);
}

static void cmd_disp_clear(void)
{
    printf("DC: %s\n", iqcap_disp_clear_fpga1() ? "station list, labels and rays cleared" : "FPGA1 does not answer");
}

static void cmd_cap_list(void)
{
    const iqcap_cfg_t *c = iqcap_cfg();
    char m[20];
    for (unsigned k = 0; k < IQCAP_NMAC; k++)
    {
        iqcap_fmt_mac(m, sizeof m, c->mac[k].mac);
        printf("CL: %u %s %s\n", k, m, c->mac[k].en ? "on" : "off");
    }
    printf("CL: pass-all=%u (filter %s)\n", c->pass_all, c->pass_all ? "bypassed" : "active");
}

static void cmd_cap_clear(void)
{
    printf("CZ: counters %s\n", iqcap_clear_counters() ? "cleared on both FPGAs" : "clear FAILED");
}

static void cmd_net_ip(const char *args, uint8_t *ip, const char *tag)
{
    if (!iqcap_parse_ip(args, ip)) { printf("%s: expected a.b.c.d\n", tag); return; }
    net_commit(tag);
}

static void cmd_net_port(const char *args)
{
    uint32_t v;
    if (!parse_dec(&args, &v) || v < 1u || v > 65535u) { printf("NP: expected 1..65535\n"); return; }
    iqcap_cfg()->dst_port = (uint16_t)v;
    net_commit("NP");
}

static void cmd_net_mac(const char *args)
{
    iqcap_cfg_t *c = iqcap_cfg();
    while (*args == ' ' || *args == '\t') args++;
    if (upper(args[0]) == 'B')
    {
        memset(c->dst_mac, 0xFF, 6); c->use_bcast = 1u;
    }
    else if (iqcap_parse_mac(args, c->dst_mac))
    {
        c->use_bcast = 0u;
    }
    else { printf("NM: usage NM <aa:bb:cc:dd:ee:ff | bcast>\n"); return; }
    net_commit("NM");
}

static void cmd_net_flag(const char *args, uint8_t *field, const char *tag)
{
    if (parse_bool(args, tag, field)) net_commit(tag);
}

/* ---- raw register access, both FPGAs (bring-up) -------------------------- */
static void cmd_raw_reg(const char *args, int fpga2, int write)
{
    uint32_t addr, val = 0;
    const char *tag = fpga2 ? (write ? "NW" : "NR") : (write ? "RW" : "RR");

    if (!parse_hex(&args, &addr) || addr > 0xFFu || (write && !parse_hex(&args, &val)))
    {
        printf("%s: usage %s <addr hex>%s\n", tag, tag, write ? " <value hex>" : "");
        return;
    }
    if (write)
    {
        bool ok = fpga2 ? rasbb_fpga2_write_reg((uint8_t)addr, val)
                        : rasbb_fpga_write_reg((uint8_t)addr, val);
        if (!ok) { printf("%s: write failed\n", tag); return; }
    }
    {
        bool ok = fpga2 ? rasbb_fpga2_read_reg((uint8_t)addr, &val)
                        : rasbb_fpga_read_reg((uint8_t)addr, &val);
        if (!ok) { printf("%s: read failed\n", tag); return; }
        printf("%s: [%02lX] = %08lX\n", tag, (unsigned long)addr, (unsigned long)val);
    }
}

/* ---- receiver noise floor (FPGA1 noise_floor.v, NF_CTRL 0x6E / NF_DATA 0x6F)
 * One snapshot of the last published 0.21 s period: per channel the variance
 * of the quiet block with the lowest total (receiver idle, link alive), in
 * LSB^2 * 256 per sample. Printed as dBFS against a full-scale complex sample
 * (|x| = 2047), in tenths without float printf. The bitstream before
 * 2026-10-03 has no such block: the bus then reads 0 (enable bit clear). */
#define NF_REG_CTRL  0x6Eu
#define NF_REG_DATA  0x6Fu

static void print_tenths(int t)
{
    printf("%s%d.%d", (t < 0) ? "-" : " ", abs(t) / 10, abs(t) % 10);
}

static void cmd_noise_floor(void)
{
    uint32_t st, v[4];
    uint8_t  c;

    if (!rasbb_fpga_write_reg(NF_REG_CTRL, 0x101u) ||          /* enable + snapshot */
        !rasbb_fpga_read_reg(NF_REG_CTRL, &st))
    {
        printf("NF: FPGA1 does not answer\n");
        return;
    }
    if ((st & 1u) == 0u)
    {
        printf("NF: no noise-floor block in this FPGA1 bitstream (NF_CTRL reads %08lX)\n",
               (unsigned long)st);
        return;
    }
    for (c = 0u; c < 4u; c++)
    {
        if (!rasbb_fpga_write_reg(NF_REG_CTRL, 0x1u | ((uint32_t)c << 4)) ||
            !rasbb_fpga_read_reg(NF_REG_DATA, &v[c]))
        {
            printf("NF: read failed\n");
            return;
        }
    }

    printf("NF: period #%lu, %lu of 4096 blocks usable", (unsigned long)((st >> 12) & 0xFFu),
           (unsigned long)(st >> 20));
    if ((st & (1u << 11)) == 0u)
    {
        printf(" - no quiet block (receiver busy all period, or link down)\n");
        return;
    }
    printf("\n    dBFS ");
    for (c = 0u; c < 4u; c++)
    {
        printf("  ch%u ", (unsigned)c);
        if (v[c] == 0u) { printf("  --"); }
        else { print_tenths((int)lroundf(100.0f * log10f((float)v[c] / (2047.0f * 2047.0f * 256.0f)))); }
    }
    printf("\n    raw   ");
    for (c = 0u; c < 4u; c++) { printf("  %lu", (unsigned long)v[c]); }
    printf("  (LSB^2 * 256 per sample)\n");
}

/* ---- raw MDIO read of the LAN8742 through the MAC's MDIO block (bring-up) --
 * Needs only the MAC clocks (enabled by HAL_ETH_MspInit), not the RMII
 * reference clock, so it works while HAL_ETH_Init still fails. */
static void cmd_eth_phy(const char *args)
{
    uint32_t reg, phy = 0u, t0;
    if (!parse_hex(&args, &reg) || reg > 31u) { printf("EP: usage EP <reg hex 0..1F> [phyaddr]\n"); return; }
    (void)parse_hex(&args, &phy);
    __HAL_RCC_ETH1MAC_CLK_ENABLE();
    /* CR = 0b100 (CSR clock 150-250 MHz -> MDC ~ 2 MHz), GOC = 3 = read, GB */
    ETH->MACMDIOAR = (phy << 21) | (reg << 16) | (4u << 8) | (3u << 2) | 1u;
    t0 = HAL_GetTick();
    while ((ETH->MACMDIOAR & 1u) != 0u) { if ((HAL_GetTick() - t0) > 20u) { printf("EP: MDIO busy timeout\n"); return; } }
    printf("EP: phy %lu reg %02lX = %04lX\n", (unsigned long)phy, (unsigned long)reg, (unsigned long)(ETH->MACMDIODR & 0xFFFFu));
}

/* ---- lwIP / MAC state (Ethernet bring-up) -------------------------------- */
#include "lwip/netif.h"
extern struct netif gnetif;
extern ETH_HandleTypeDef heth;
extern volatile uint32_t g_eth_fail, g_eth_txcplt, g_eth_rxcplt, g_eth_err, g_eth_txcalls;
extern volatile uint32_t g_eth_rx_pbufs, g_eth_rx_drop, g_eth_rx_tous, g_eth_rx_fromus, g_eth_rx_len, g_eth_rx_hdr;
static void cmd_eth_status(void)
{
    const ip4_addr_t *ip = netif_ip4_addr(&gnetif);
    printf("ES: netif %s%s  ip %u.%u.%u.%u  mac %02X:%02X:%02X:%02X:%02X:%02X  eth_fail=%lu\n",
           netif_is_up(&gnetif) ? "UP" : "down", netif_is_link_up(&gnetif) ? " link" : " nolink",
           ip4_addr1(ip), ip4_addr2(ip), ip4_addr3(ip), ip4_addr4(ip),
           gnetif.hwaddr[0], gnetif.hwaddr[1], gnetif.hwaddr[2], gnetif.hwaddr[3], gnetif.hwaddr[4], gnetif.hwaddr[5],
           (unsigned long)g_eth_fail);
    printf("    HAL ETH gState=%lu  MACCR=%08lX DMAMR=%08lX DMACSR=%08lX RxDesc=%08lX\n",
           (unsigned long)heth.gState, (unsigned long)ETH->MACCR, (unsigned long)ETH->DMAMR,
           (unsigned long)ETH->DMACSR, (unsigned long)ETH->DMACRDLAR);
    printf("    tx calls=%lu txcplt=%lu rxcplt=%lu errcb=%lu HAL err=%08lX dmaerr=%08lX  MMC tx=%lu rx_ucast=%lu\n",
           (unsigned long)g_eth_txcalls, (unsigned long)g_eth_txcplt, (unsigned long)g_eth_rxcplt, (unsigned long)g_eth_err,
           (unsigned long)heth.ErrorCode, (unsigned long)heth.DMAErrorCode,
           (unsigned long)(*(volatile uint32_t *)0x40028768u), (unsigned long)(*(volatile uint32_t *)0x400287C4u));   /* MMC TX good, RX unicast good */
    printf("    rx pbufs=%lu drop=%lu to_us=%lu from_us=%lu last tot/len=%lu/%lu hdr=%08lX\n",
           (unsigned long)g_eth_rx_pbufs, (unsigned long)g_eth_rx_drop, (unsigned long)g_eth_rx_tous, (unsigned long)g_eth_rx_fromus,
           (unsigned long)(g_eth_rx_len >> 16), (unsigned long)(g_eth_rx_len & 0xFFFFu), (unsigned long)g_eth_rx_hdr);
}

/* ---- Ethernet traffic probes (bring-up) ---------------------------------- */
#include "lwip/etharp.h"
#include "lan8742.h"
#include "task.h"
extern lan8742_Object_t LAN8742;
static void cmd_eth_link(void)                 /* EI: what the link thread sees */
{
    int32_t st = LAN8742_GetLinkState(&LAN8742);
    printf("EI: LAN8742 init=%lu addr=%lu  GetLinkState=%ld (1=down 2=100FD 3=100HD 4=10FD 5=10HD <0=err)  netif link=%d up=%d  gState=%lu\n",
           (unsigned long)LAN8742.Is_Initialized, (unsigned long)LAN8742.DevAddr, (long)st,
           netif_is_link_up(&gnetif), netif_is_up(&gnetif), (unsigned long)heth.gState);
}
#include "logw_seq.h"
static void cmd_fpga_reconf(const char *args)   /* FR <1|2>: pulse FPGA0x_PROG (reload from its flash), re-apply config */
{
    uint32_t n;
    if (!parse_hex(&args, &n) || (n != 1u && n != 2u)) { printf("FR: usage FR <1|2>\n"); return; }
    GPIO_TypeDef *port = (n == 1u) ? FPGA01_PROG_GPIO_Port : FPGA02_PROG_GPIO_Port;
    uint16_t      pin  = (n == 1u) ? FPGA01_PROG_Pin      : FPGA02_PROG_Pin;
    /* the console dispatcher already holds the bus mutex for this whole command
       line (non-recursive - locking again here deadlocked the console), so SPI4
       stays silent while the FPGA reads its flash */
    HAL_GPIO_WritePin(port, pin, GPIO_PIN_RESET);
    osDelay(2);
    HAL_GPIO_WritePin(port, pin, GPIO_PIN_SET);
    osDelay(3000);                                /* 3.8 MB bitstream at CONFIGRATE 50 x1 ~ 0.7 s, margin */
    /* the config is re-applied by the presence logic (owifiRx task for FPGA1,
       boot-apply for FPGA2) - calling apply here hung the console once (2026-09-19) */
    printf("FR: FPGA%lu PROG pulsed - reloads from its flash; check CS / NL in a few seconds\n", (unsigned long)n);
}
static void cmd_task_list(void)                /* TL: FreeRTOS task list (state, prio, free stack words) */
{
    static char buf[1024];
    vTaskList(buf);
    printf("TL: name            state prio  stack  id\n%s", buf);
}
#include "lwip/tcpip.h"
static ip4_addr_t s_arp_target;
static void arp_req_cb(void *arg) { (void)arg; etharp_request(&gnetif, &s_arp_target); }
static void cmd_eth_arp(const char *args)
{
    uint8_t ip[4];
    if (!iqcap_parse_ip(args, ip)) { printf("EA: usage EA <ip>\n"); return; }
    IP4_ADDR(&s_arp_target, ip[0], ip[1], ip[2], ip[3]);
    tcpip_callback(arp_req_cb, NULL);
    printf("EA: ARP request for %u.%u.%u.%u queued\n", ip[0], ip[1], ip[2], ip[3]);
}
static void cmd_eth_reg(const char *args)      /* ER <offset hex>: raw ETH MAC/MTL/DMA register read */
{
    uint32_t off;
    if (!parse_hex(&args, &off) || off > 0x1FFCu || (off & 3u)) { printf("ER: usage ER <offset hex, word aligned>\n"); return; }
    printf("ER: ETH+%04lX = %08lX\n", (unsigned long)off, (unsigned long)(*(volatile uint32_t *)(0x40028000u + off)));
}
static void cmd_eth_phy_write(const char *args)
{
    uint32_t reg, val, t0;
    if (!parse_hex(&args, &reg) || reg > 31u || !parse_hex(&args, &val)) { printf("EW: usage EW <reg hex> <val hex>\n"); return; }
    ETH->MACMDIODR = val & 0xFFFFu;
    ETH->MACMDIOAR = (0u << 21) | (reg << 16) | (4u << 8) | (1u << 2) | 1u;   /* GOC = 1 = write */
    t0 = HAL_GetTick();
    while ((ETH->MACMDIOAR & 1u) != 0u) { if ((HAL_GetTick() - t0) > 20u) { printf("EW: MDIO busy timeout\n"); return; } }
    printf("EW: reg %02lX <= %04lX\n", (unsigned long)reg, (unsigned long)val);
}

static void execute(const char *line)
{
    const char *p = line;

    skip_spaces(&p);

    if (*p == '\0')                 { return; }                 /* bare Enter */
    else if (is_cmd(&p, 'S', 'F'))  { cmd_set_freq(p); }
    else if (is_cmd(&p, 'G', 'F'))  { cmd_get_freq(); }
    else if (is_cmd(&p, 'S', 'T'))  { cmd_status(); }
    else if (is_cmd(&p, 'I', 'D'))  { cmd_ident(); }
    else if (is_cmd(&p, 'S', 'G'))  { cmd_set_gain(p); }
    else if (is_cmd(&p, 'G', 'G'))  { cmd_get_gain(); }
    else if (is_cmd(&p, 'S', 'R'))  { cmd_set_test(p); }
    else if (is_cmd(&p, 'G', 'R'))  { cmd_get_test(); }
    else if (is_cmd(&p, 'L', 'S'))  { cmd_link_status(); }
    else if (is_cmd(&p, 'L', 'R'))  { cmd_link_retrain(); }
    else if (is_cmd(&p, 'L', 'P'))  { cmd_link_park(p); }
    else if (is_cmd(&p, 'C', 'S'))  { print_cap_status(); }
    else if (is_cmd(&p, 'C', 'Z'))  { cmd_cap_clear(); }
    else if (is_cmd(&p, 'C', 'E'))  { cmd_cap_flag(p, &iqcap_cfg()->cap_enable, "CE"); }
    else if (is_cmd(&p, 'C', 'P'))  { cmd_cap_flag(p, &iqcap_cfg()->pass_all, "CP"); }
    else if (is_cmd(&p, 'C', 'F'))  { cmd_cap_flag(p, &iqcap_cfg()->require_fcs, "CF"); }
    else if (is_cmd(&p, 'C', 'T'))  { cmd_cap_flag(p, &iqcap_cfg()->test_pattern, "CT"); }
    else if (is_cmd(&p, 'C', 'N'))  { cmd_cap_nsamp(p); }
    else if (is_cmd(&p, 'C', 'B'))  { cmd_cap_pretrig(p); }
    else if (is_cmd(&p, 'C', 'M'))  { cmd_cap_mac(p); }
    else if (is_cmd(&p, 'C', 'L'))  { cmd_cap_list(); }
    else if (is_cmd(&p, 'C', 'W'))  { cmd_cap_phase_window(p); }
    else if (is_cmd(&p, 'C', 'A'))  { cmd_cap_phase_cal(p); }
    else if (is_cmd(&p, 'C', 'G'))  { cmd_cap_gain_trim(p); }
    else if (is_cmd(&p, 'N', 'L'))  { print_net_status(); }
    else if (is_cmd(&p, 'N', 'I'))  { cmd_net_ip(p, iqcap_cfg()->dst_ip, "NI"); }
    else if (is_cmd(&p, 'N', 'S'))  { cmd_net_ip(p, iqcap_cfg()->src_ip, "NS"); }
    else if (is_cmd(&p, 'N', 'P'))  { cmd_net_port(p); }
    else if (is_cmd(&p, 'N', 'M'))  { cmd_net_mac(p); }
    else if (is_cmd(&p, 'N', 'E'))  { cmd_net_flag(p, &iqcap_cfg()->tx_enable, "NE"); }
    else if (is_cmd(&p, 'N', 'T'))  { cmd_net_flag(p, &iqcap_cfg()->net_test, "NT"); }
    else if (is_cmd(&p, 'R', 'R'))  { cmd_raw_reg(p, 0, 0); }
    else if (is_cmd(&p, 'R', 'W'))  { cmd_raw_reg(p, 0, 1); }
    else if (is_cmd(&p, 'N', 'R'))  { cmd_raw_reg(p, 1, 0); }
    else if (is_cmd(&p, 'N', 'W'))  { cmd_raw_reg(p, 1, 1); }
    else if (is_cmd(&p, 'N', 'F'))  { cmd_noise_floor(); }
    else if (is_cmd(&p, 'E', 'P'))  { cmd_eth_phy(p); }
    else if (is_cmd(&p, 'E', 'S'))  { cmd_eth_status(); }
    else if (is_cmd(&p, 'E', 'A'))  { cmd_eth_arp(p); }
    else if (is_cmd(&p, 'E', 'W'))  { cmd_eth_phy_write(p); }
    else if (is_cmd(&p, 'E', 'R'))  { cmd_eth_reg(p); }
    else if (is_cmd(&p, 'E', 'I'))  { cmd_eth_link(); }
    else if (is_cmd(&p, 'T', 'L'))  { cmd_task_list(); }
    else if (is_cmd(&p, 'F', 'R'))  { cmd_fpga_reconf(p); }
    else if (is_cmd(&p, 'O', 'T'))  { cmd_ovl_text(p); }
    else if (is_cmd(&p, 'O', 'S'))  { cmd_cap_flag(p, &iqcap_cfg()->ovl_show, "OS"); }
    else if (is_cmd(&p, 'O', 'A'))  { cmd_cap_flag(p, &iqcap_cfg()->ovl_center, "OA"); }
    else if (is_cmd(&p, 'O', 'Z'))  { cmd_ovl_scale(p); }
    else if (is_cmd(&p, 'O', 'C'))  { cmd_ovl_colour(p); }
    else if (is_cmd(&p, 'B', 'T'))  { cmd_menu_button(p); }
    else if (is_cmd(&p, 'M', 'B'))  { cmd_menu_button(p); }     /* alias */
    else if (is_cmd(&p, 'D', 'P'))  { cmd_disp_pause(p); }
    else if (is_cmd(&p, 'D', 'B'))  { cmd_disp_flag(p, &iqcap_cfg()->disp_show_bad, "DB"); }
    else if (is_cmd(&p, 'D', 'S'))  { cmd_disp_flag(p, &iqcap_cfg()->disp_solo, "DS"); }
    else if (is_cmd(&p, 'D', 'A'))  { cmd_disp_avg(p, 0); }
    else if (is_cmd(&p, 'D', 'F'))  { cmd_disp_avg(p, 1); }
    else if (is_cmd(&p, 'D', 'C'))  { cmd_disp_clear(); }
    else                            { print_help(); }
}

/* ------------------------------------------------------------- plumbing */

void console_init(void)
{
    /* Unbuffered stdout. newlib fully buffers a stream it cannot prove is a
     * terminal, which is why the existing "Firmware starts" needed an explicit
     * fflush; a console whose every reply had to be flushed by hand would lose
     * one sooner or later, and the echo below - which does not go through
     * stdio at all - would interleave wrongly with anything still sitting in
     * the buffer. Called before the first printf, as setvbuf requires. */
    (void)setvbuf(stdout, NULL, _IONBF, 0);

    s_head = 0u;
    s_tail = 0u;
    s_len  = 0u;

    (void)HAL_UART_Receive_IT(&huart3, &s_rxByte, 1u);
}

void console_banner(void)
{
    printf("\nLOGW ECU console - '?' for commands\n");
    logw_bus_lock();
    cmd_ident();
    logw_bus_unlock();
    prompt();
}

void console_poll(void)
{
    while (s_tail != s_head)
    {
        char ch = (char)s_ring[s_tail];

        s_tail = (uint16_t)((s_tail + 1u) % RX_RING_LEN);

        if (ch == '\r' || ch == '\n')
        {
            tx_char('\r');
            tx_char('\n');
            s_line[s_len] = '\0';
            /* whole command under the bus guard: the sequencer task shares
               I2C1 and SPI4 (logw_seq.h) */
            logw_bus_lock();
            execute(s_line);
            logw_bus_unlock();
            s_len = 0u;
            prompt();
        }
        else if (ch == '\b' || ch == 0x7F)
        {
            if (s_len > 0u)
            {
                s_len--;
                tx_char('\b');
                tx_char(' ');
                tx_char('\b');
            }
        }
        else if (ch >= ' ' && s_len < (LINE_MAX - 1u))
        {
            s_line[s_len++] = ch;
            tx_char(ch);   /* the far end has no local echo */
        }
    }
}

/* ------------------------------------------------------------- callbacks */

void HAL_UART_RxCpltCallback(UART_HandleTypeDef *huart)
{
    if (huart->Instance != USART3) { return; }

    {
        uint16_t next = (uint16_t)((s_head + 1u) % RX_RING_LEN);

        /* Drop rather than overwrite when full: losing the newest character
         * costs one mistyped command, while overwriting the tail would corrupt
         * a command already being assembled. */
        if (next != s_tail)
        {
            s_ring[s_head] = s_rxByte;
            s_head         = next;
        }
    }

    (void)HAL_UART_Receive_IT(huart, &s_rxByte, 1u);
}

void HAL_UART_ErrorCallback(UART_HandleTypeDef *huart)
{
    if (huart->Instance != USART3) { return; }

    /* An overrun - trivially provoked by holding a key down while a reply is
     * being transmitted - aborts the reception and leaves RXNE latched off. Not
     * re-arming here is the difference between losing one character and losing
     * the console until the next reset. */
    (void)HAL_UART_Receive_IT(huart, &s_rxByte, 1u);
}
