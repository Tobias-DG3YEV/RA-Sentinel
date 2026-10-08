/*
 * logw_seq.h - LOGW start-up / link sequencer.
 *
 * WHY THIS EXISTS. The LOTAG gateway's receive chain has three parties that
 * each come up on their own clock: the RASRF6000 front end (Si5324 clock plan,
 * LMX2572 LO, ADC3224), FPGA1 (LOGW bitstream: self-training 2-wire LVDS
 * capture that needs the ADC's digital RAMP present while it trains), and this
 * uC. Left alone, the front end shows the ramp for a fixed window after its
 * clock locks and the FPGA trains once at configuration - which works at a
 * cold power-up and breaks in every other case: a bitstream reloaded over JTAG
 * or from a reprogrammed flash trains on live noise (front end already on
 * live data), an FPGA that lost its ISERDES grouping never gets a second ramp,
 * and a front end that boots after the FPGA trains the FPGA on nothing.
 *
 * This task owns the ordering instead:
 *
 *   WAIT_FE    poll the front end (I2C 0x42): identity 0x21, STATUS
 *              INIT_DONE + CLK_LOCK (the ADC clock; the LO lock is reported
 *              but does not gate the link).
 *   WAIT_FPGA  poll FPGA1 (SPI4): a STATUS byte with the LOGW signature.
 *              No answer = no bitstream running (a reprogramming in progress,
 *              an unconfigured FPGA) - keep polling.
 *   RAMP_ON    front end RAMP=1 (verified by read-back), then FPGA CONTROL
 *              RETRAIN: the capture resets and trains from scratch on the
 *              ramp.
 *   TRAIN      wait for FPGA LINK_OK held for a few polls (timeout -> retry
 *              the RETRAIN, with a count).
 *   RAMP_OFF   front end RAMP=0 -> live samples.
 *   RUN        keep polling both. FPGA signature gone -> WAIT_FPGA (and a new
 *              training cycle when it answers again = the reprogramming
 *              case). Front-end clock lock gone -> WAIT_FE. LINK_OK gone for
 *              more than LOGW_SEQ_RELINK_MS while the front end is fine ->
 *              RAMP_ON (the capture asked for help).
 *
 * A front end whose HKU predates register 0x09 cannot be put on the ramp by
 * us; the sequencer then only observes (state RUN, flag no_ramp_ctrl) and the
 * boot-window behaviour is what you get.
 *
 * Bus sharing: I2C1 and SPI4 are also used by the console task. Every
 * multi-transaction step here and every console command holds logw_bus_lock()
 * for its duration, so an SF/ST typed mid-sequence cannot tear a transaction.
 */
#ifndef LOGW_SEQ_H
#define LOGW_SEQ_H

#include <stdint.h>
#include <stdbool.h>

typedef enum {
    LOGW_SEQ_WAIT_FE = 0,
    LOGW_SEQ_WAIT_FPGA,
    LOGW_SEQ_RAMP_ON,
    LOGW_SEQ_TRAIN,
    LOGW_SEQ_RAMP_OFF,
    LOGW_SEQ_RUN,
} logw_seq_state_t;

/* One line of event history, shown by the console's LS command. */
typedef struct {
    uint32_t tick_ms;
    char     text[40];
} logw_seq_event_t;

#define LOGW_SEQ_EVENTS 8u

/* Everything the sequencer knows, for the console and for an SWD watch
 * (magic word first so it can be found in a memory dump). */
typedef struct {
    uint32_t magic;               /* 0x4C4F4757 "LOGW" */
    volatile logw_seq_state_t state;
    uint32_t state_since_ms;
    uint32_t polls;

    /* front end */
    bool     fe_present;
    bool     fe_is_6ghz;
    bool     fe_ramp_ctrl;        /* HKU map >= 0.2: register 0x09 exists */
    uint8_t  fe_model, fe_rev, fe_map_major, fe_map_minor;
    uint8_t  fe_status;           /* last STATUS byte, RASRF6000_ST_* */
    uint8_t  fe_ramp;             /* last read-back of register 0x09 */

    /* FPGA */
    bool     fpga_present;        /* STATUS carries the LOGW signature */
    uint8_t  fpga_status;         /* last STATUS byte */
    uint8_t  fpga_ext[8];         /* last STATUS_EXT block */
    uint32_t fpga_id;             /* register 0: 0x4C4F4757 when it is LOGW */
    uint32_t fpga_lane_taps;      /* register 3: per-lane IDELAY taps, lane n at [n*5 +: 5] */

    /* counters */
    uint32_t train_cycles;        /* RETRAIN commands issued */
    uint32_t train_ok;            /* ... that reached LINK_OK */
    uint32_t train_timeouts;
    uint32_t fpga_losses;         /* signature disappeared while in RUN */
    uint32_t fe_losses;           /* clock lock disappeared while in RUN */
    uint32_t relinks;             /* LINK_OK dropped in RUN -> re-train */
    uint32_t i2c_errors, spi_errors;

    /* manual override from the console: 0 = automatic, 1 = ramp forced ON
     * and the sequencer parked, 2 = forced OFF and parked */
    volatile uint8_t manual;
    volatile uint8_t retrain_request;

    logw_seq_event_t events[LOGW_SEQ_EVENTS];
    uint8_t  event_head;
} logw_seq_t;

extern logw_seq_t g_logw_seq;

/* Create the bus mutex. Call from the RTOS_MUTEX section of main(), i.e.
 * after osKernelInitialize() and before the tasks start. */
void logw_seq_init(void);

/* The task body (osThreadNew target). */
void StartLogwSeqTask(void *argument);

/* Shared-bus guard for I2C1 + SPI4 (see header comment). */
void logw_bus_lock(void);
void logw_bus_unlock(void);

/* Console hooks. */
const char *logw_seq_state_name(logw_seq_state_t s);
void logw_seq_request_retrain(void);          /* one forced training cycle */
void logw_seq_set_manual(uint8_t mode);       /* 0 auto, 1 ramp on, 2 ramp off */

#endif /* LOGW_SEQ_H */
