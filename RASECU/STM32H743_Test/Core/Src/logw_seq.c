/*
 * logw_seq.c - LOGW start-up / link sequencer task. See logw_seq.h.
 *
 * Runs at 10 Hz. Every step is a handful of 2..12-byte transactions on the
 * two housekeeping buses, so the load is negligible; the rate is set by how
 * fast the STATES change (the FPGA trains in ~50 ms, a bitstream loads in
 * ~1 s) and by how quickly a reprogrammed FPGA should be picked up again.
 */
#include "logw_seq.h"
#include "main.h"
#include "cmsis_os.h"
#include "rasbb_fpga.h"
#include "rasrf.h"
#include "rasrf6000_proto.h"
#include <string.h>
#include <stdio.h>

/* ---- policy knobs -------------------------------------------------------- */
#define LOGW_SEQ_PERIOD_MS      100u
#define LOGW_SEQ_LINK_OK_POLLS  3u      /* LINK_OK must hold this many polls */
#define LOGW_SEQ_TRAIN_TIMEOUT_MS 10000u
#define LOGW_SEQ_RELINK_MS      2000u   /* LINK_OK lost this long in RUN -> re-train */
#define LOGW_SEQ_RAMP_SETTLE_MS 20u     /* HKU main-loop latency for reg 0x09 */
#define LOGW_SEQ_GOOD_TRIM_HITS 600u    /* of 4097: a training done on the ramp. The trim
                                           runs BEFORE the per-lane tap training, so a marginal
                                           LSB lane caps it (~1024 on this board, HDMI sane);
                                           on live noise it is ~65. */

/* ---- FPGA STATUS decoding (spi_ctrl_if.v) -------------------------------- */
#define LOGW_FPGA_SIGNATURE(st)  (((st) & 0xE0u) == 0xA0u)   /* bits 7:5 = 101 */
#define LOGW_FPGA_LINK_OK(st)    (((st) & RASBB_ST_LINK_OK)  != 0u) /* trained    */
#define LOGW_FPGA_FE_VALID(st)   (((st) & RASBB_ST_FE_VALID) != 0u) /* DCLK PLL   */
#define LOGW_CTRL_RETRAIN        0x01u
#define LOGW_CTRL_CLEAR          0x02u
#define LOGW_FPGA_ID             0x4C4F4757u

logw_seq_t g_logw_seq = { .magic = LOGW_FPGA_ID };

static osMutexId_t s_bus_mutex;
static const osMutexAttr_t s_bus_mutex_attr = { .name = "hkbus" };

/* ------------------------------------------------------------ plumbing */

void logw_seq_init(void)
{
    s_bus_mutex = osMutexNew(&s_bus_mutex_attr);
}

void logw_bus_lock(void)
{
    if (s_bus_mutex != NULL) { (void)osMutexAcquire(s_bus_mutex, osWaitForever); }
}

void logw_bus_unlock(void)
{
    if (s_bus_mutex != NULL) { (void)osMutexRelease(s_bus_mutex); }
}

const char *logw_seq_state_name(logw_seq_state_t s)
{
    switch (s)
    {
        case LOGW_SEQ_WAIT_FE:   return "WAIT_FE";
        case LOGW_SEQ_WAIT_FPGA: return "WAIT_FPGA";
        case LOGW_SEQ_RAMP_ON:   return "RAMP_ON";
        case LOGW_SEQ_TRAIN:     return "TRAIN";
        case LOGW_SEQ_RAMP_OFF:  return "RAMP_OFF";
        case LOGW_SEQ_RUN:       return "RUN";
        default:                 return "?";
    }
}

void logw_seq_request_retrain(void)
{
    g_logw_seq.retrain_request = 1u;
}

void logw_seq_set_manual(uint8_t mode)
{
    g_logw_seq.manual = mode;
}

static void event(const char *text)
{
    logw_seq_event_t *e = &g_logw_seq.events[g_logw_seq.event_head];

    e->tick_ms = HAL_GetTick();
    strncpy(e->text, text, sizeof(e->text) - 1u);
    e->text[sizeof(e->text) - 1u] = '\0';
    g_logw_seq.event_head = (uint8_t)((g_logw_seq.event_head + 1u) % LOGW_SEQ_EVENTS);
}

static void go(logw_seq_state_t s, const char *why)
{
    char line[40];

    if (s == g_logw_seq.state) { return; }
    snprintf(line, sizeof(line), "%s: %s", logw_seq_state_name(s), why);
    event(line);
    g_logw_seq.state          = s;
    g_logw_seq.state_since_ms = HAL_GetTick();
}

static uint32_t in_state_ms(void)
{
    return HAL_GetTick() - g_logw_seq.state_since_ms;
}

/* ------------------------------------------------------------ probes */

/* Front-end identity + status. Returns true if a RASRF6000 answered. */
static bool probe_fe(void)
{
    uint8_t id[4];
    uint8_t st;

    if (!rasrf_read_regs(RASRF_REG_BOARD_MODEL, id, sizeof(id)))
    {
        g_logw_seq.i2c_errors++;
        g_logw_seq.fe_present = false;
        return false;
    }
    g_logw_seq.fe_present   = true;
    g_logw_seq.fe_model     = id[0];
    g_logw_seq.fe_rev       = id[1];
    g_logw_seq.fe_map_major = id[2];
    g_logw_seq.fe_map_minor = id[3];
    g_logw_seq.fe_is_6ghz   = (RASRF6000_BAND(id[0]) == RASRF6000_BAND_6GHZ);
    g_logw_seq.fe_ramp_ctrl = g_logw_seq.fe_is_6ghz &&
                              ((id[2] > 0u) || (id[3] >= RASRF6000_MAP_MIN_MINOR));

    if (!g_logw_seq.fe_is_6ghz) { return false; }

    if (!rasrf_read_reg(RASRF6000_REG_STATUS, &st))
    {
        g_logw_seq.i2c_errors++;
        return false;
    }
    g_logw_seq.fe_status = st;

    if (g_logw_seq.fe_ramp_ctrl)
    {
        uint8_t r;
        if (rasrf_read_reg(RASRF6000_REG_RAMP, &r)) { g_logw_seq.fe_ramp = r; }
    }
    return true;
}

static bool fe_clock_ok(void)
{
    return g_logw_seq.fe_present && g_logw_seq.fe_is_6ghz &&
           ((g_logw_seq.fe_status & (RASRF6000_ST_INIT_DONE | RASRF6000_ST_CLK_LOCK))
                                 == (RASRF6000_ST_INIT_DONE | RASRF6000_ST_CLK_LOCK));
}

/* Write the ramp register and confirm it took. False if the HKU has no such
 * register (reads back something else) or the bus failed. */
static bool fe_set_ramp(bool on)
{
    uint8_t rb = 0xFFu;

    if (!g_logw_seq.fe_ramp_ctrl) { return false; }
    if (!rasrf_write_reg(RASRF6000_REG_RAMP, on ? 1u : 0u))
    {
        g_logw_seq.i2c_errors++;
        return false;
    }
    osDelay(LOGW_SEQ_RAMP_SETTLE_MS);
    if (!rasrf_read_reg(RASRF6000_REG_RAMP, &rb))
    {
        g_logw_seq.i2c_errors++;
        return false;
    }
    g_logw_seq.fe_ramp = rb;
    return (rb == (on ? 1u : 0u));
}

/* FPGA status poll. Returns true if the LOGW bitstream answered. */
static bool probe_fpga(void)
{
    uint8_t st = rasbb_fpga_status();

    g_logw_seq.fpga_status = st;
    if (st == 0xFFu) { g_logw_seq.spi_errors++; }
    g_logw_seq.fpga_present = LOGW_FPGA_SIGNATURE(st);
    return g_logw_seq.fpga_present;
}

static void fpga_diag(void)
{
    rasbb_status_ext_t ext;

    if (rasbb_fpga_status_ext(&ext))
    {
        memcpy(g_logw_seq.fpga_ext, &ext, sizeof(g_logw_seq.fpga_ext));
    }
    (void)rasbb_fpga_read_reg(0u, &g_logw_seq.fpga_id);
    (void)rasbb_fpga_read_reg(3u, &g_logw_seq.fpga_lane_taps);
}

/* interpretation-trim agreement from the last STATUS_EXT (0..4097) */
static uint32_t fpga_trim_hits(void)
{
    return (uint32_t)g_logw_seq.fpga_ext[3] | ((uint32_t)g_logw_seq.fpga_ext[4] << 8);
}

static bool fpga_retrain(void)
{
    g_logw_seq.train_cycles++;
    return rasbb_fpga_control(LOGW_CTRL_RETRAIN);
}

/* ------------------------------------------------------------ the task */

void StartLogwSeqTask(void *argument)
{
    uint8_t  link_polls   = 0u;
    uint32_t link_lost_ms = 0u;   /* tick at which LINK_OK was last seen */
    uint8_t  train_tries  = 0u;

    UNUSED(argument);

    g_logw_seq.state          = LOGW_SEQ_WAIT_FE;
    g_logw_seq.state_since_ms = HAL_GetTick();
    event("sequencer start");

    for (;;)
    {
        bool fe_ok, fpga_ok;

        osDelay(LOGW_SEQ_PERIOD_MS);
        g_logw_seq.polls++;

        logw_bus_lock();
        fe_ok   = probe_fe() && fe_clock_ok();
        fpga_ok = probe_fpga();

        /* ---- console overrides ------------------------------------ */
        if (g_logw_seq.manual != 0u)
        {
            /* parked: keep the probes fresh, touch nothing else */
            logw_bus_unlock();
            continue;
        }
        if (g_logw_seq.retrain_request && fe_ok && fpga_ok &&
            g_logw_seq.state == LOGW_SEQ_RUN)
        {
            g_logw_seq.retrain_request = 0u;
            go(LOGW_SEQ_RAMP_ON, "console");
        }
        else if (g_logw_seq.retrain_request && g_logw_seq.state != LOGW_SEQ_RUN)
        {
            g_logw_seq.retrain_request = 0u;   /* a cycle is under way anyway */
        }

        /* ---- the state machine ------------------------------------ */
        switch (g_logw_seq.state)
        {
        case LOGW_SEQ_WAIT_FE:
            if (fe_ok)
            {
                event(g_logw_seq.fe_ramp_ctrl ? "FE clock locked"
                                              : "FE locked, HKU lacks reg 0x09");
                go(LOGW_SEQ_WAIT_FPGA, "front end up");
            }
            break;

        case LOGW_SEQ_WAIT_FPGA:
            if (!fe_ok)
            {
                go(LOGW_SEQ_WAIT_FE, "FE clock lost");
            }
            else if (fpga_ok)
            {
                fpga_diag();
                if (!g_logw_seq.fe_ramp_ctrl)
                {
                    /* cannot drive the ramp: observe only */
                    go(LOGW_SEQ_RUN, "observe only");
                }
                else if (LOGW_FPGA_LINK_OK(g_logw_seq.fpga_status) &&
                         (g_logw_seq.fe_ramp == 0u) &&
                         (fpga_trim_hits() >= LOGW_SEQ_GOOD_TRIM_HITS))
                {
                    /* already trained on the HKU's own boot window and on
                       live data, and the training is a real one (the trim
                       agreement is near 4097/4097 on the ramp, ~1% on
                       noise): nothing to redo */
                    go(LOGW_SEQ_RUN, "already trained");
                }
                else
                {
                    train_tries = 0u;
                    go(LOGW_SEQ_RAMP_ON, "FPGA answers");
                }
            }
            break;

        case LOGW_SEQ_RAMP_ON:
            if (!fe_ok)        { go(LOGW_SEQ_WAIT_FE, "FE clock lost"); break; }
            if (!fpga_ok)      { go(LOGW_SEQ_WAIT_FPGA, "FPGA gone"); break; }
            if (!fe_set_ramp(true))
            {
                if (in_state_ms() > 2000u)
                {
                    event("ramp on: no read-back");
                    go(LOGW_SEQ_WAIT_FE, "ramp write failed");
                }
                break;
            }
            /* ramp confirmed on the ADC -> restart the capture training */
            if (!fpga_retrain())
            {
                g_logw_seq.spi_errors++;
                break;
            }
            train_tries++;
            link_polls = 0u;
            go(LOGW_SEQ_TRAIN, "ramp on, retrain sent");
            break;

        case LOGW_SEQ_TRAIN:
            if (!fe_ok)        { go(LOGW_SEQ_WAIT_FE, "FE clock lost"); break; }
            if (!fpga_ok)      { go(LOGW_SEQ_WAIT_FPGA, "FPGA gone"); break; }
            if (LOGW_FPGA_LINK_OK(g_logw_seq.fpga_status))
            {
                if (++link_polls >= LOGW_SEQ_LINK_OK_POLLS)
                {
                    g_logw_seq.train_ok++;
                    fpga_diag();
                    go(LOGW_SEQ_RAMP_OFF, "LINK_OK");
                }
            }
            else
            {
                link_polls = 0u;
                if (in_state_ms() > LOGW_SEQ_TRAIN_TIMEOUT_MS)
                {
                    g_logw_seq.train_timeouts++;
                    event("training timeout");
                    if (train_tries < 3u)
                    {
                        go(LOGW_SEQ_RAMP_ON, "retry");
                    }
                    else
                    {
                        /* give the front end a fresh look (its clock may
                           be flapping) and start over */
                        train_tries = 0u;
                        go(LOGW_SEQ_WAIT_FE, "3 timeouts");
                    }
                }
            }
            break;

        case LOGW_SEQ_RAMP_OFF:
            if (fe_set_ramp(false))
            {
                link_lost_ms = HAL_GetTick();
                go(LOGW_SEQ_RUN, "live data");
            }
            else if (in_state_ms() > 2000u)
            {
                event("ramp off: no read-back");
                go(LOGW_SEQ_WAIT_FE, "ramp write failed");
            }
            break;

        case LOGW_SEQ_RUN:
        default:
            if (!fe_ok)
            {
                g_logw_seq.fe_losses++;
                go(LOGW_SEQ_WAIT_FE, "FE clock lost");
            }
            else if (!fpga_ok)
            {
                /* a bitstream reload (JTAG / flash reprogramming): wait for
                   it to answer again, then train it on a fresh ramp */
                g_logw_seq.fpga_losses++;
                go(LOGW_SEQ_WAIT_FPGA, "FPGA gone");
            }
            else if (LOGW_FPGA_LINK_OK(g_logw_seq.fpga_status))
            {
                link_lost_ms = HAL_GetTick();
            }
            else if (g_logw_seq.fe_ramp_ctrl &&
                     (HAL_GetTick() - link_lost_ms) > LOGW_SEQ_RELINK_MS)
            {
                g_logw_seq.relinks++;
                train_tries = 0u;
                go(LOGW_SEQ_RAMP_ON, "LINK_OK lost");
            }
            break;
        }

        logw_bus_unlock();
    }
}
