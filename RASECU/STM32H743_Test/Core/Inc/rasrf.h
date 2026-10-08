/*
 * rasrf.h - host-side driver for the RF frontend's I2C register file.
 *
 * Self-contained: drop rasrf.c/.h and rasrf_proto.h into the project's User/
 * folder. Nothing here touches CubeMX-generated files beyond needing hi2c1 to
 * exist, so regenerating the project cannot clobber it.
 *
 * These are plain blocking transactions and nothing more - no waiting, no
 * retry policy, no OS calls - so the driver stays usable from any context that
 * can afford a few hundred microseconds. Waiting out a retune is the caller's
 * job (console.c does it with osDelay, which yields; HAL_Delay would not,
 * because this project's HAL tick comes from TIM4 independently of the
 * scheduler and would busy-wait through the frame read-out task's slot).
 */
#ifndef RASRF_H
#define RASRF_H

#include <stdint.h>
#include <stdbool.h>
#include "rasrf_proto.h"

/* Everything the identity registers carry, in one read. */
typedef struct {
    uint8_t model;                          /* 0x00, band<<4 | channels */
    uint8_t revision;                       /* 0x01, ASCII              */
    uint8_t ver_major;                      /* 0x02                     */
    uint8_t ver_minor;                      /* 0x03                     */
    char    build[RASRF_GIT_VER_LEN + 1u];  /* 0x18.., NUL-terminated   */
} rasrf_ident_t;

/* Register primitives. n bytes from/to consecutive registers in one
 * transaction - the frontend's pointer auto-increments. Return false on any
 * I2C error (NAK, timeout, arbitration lost). */
bool rasrf_read_regs(uint8_t idx, uint8_t *buf, uint16_t n);
bool rasrf_write_regs(uint8_t idx, const uint8_t *buf, uint16_t n);
bool rasrf_read_reg(uint8_t idx, uint8_t *val);
bool rasrf_write_reg(uint8_t idx, uint8_t val);

/* Identity and firmware build stamp. Doubles as the presence check: it fails
 * if nothing answers 0x42. The low nibble of .model is the number of RF
 * channels - worth looking at, because the status and frequency registers
 * exist on the four-channel board only. */
bool rasrf_identify(rasrf_ident_t *out);

/* Status byte, RASRF_ST_* bits. */
bool rasrf_status(uint8_t *st);

/* Commits a new LO frequency for all RF channels. Refuses out-of-range values
 * locally rather than letting the frontend silently ignore them.
 *
 * Returns as soon as the pair is written - the frontend then takes ~50ms to
 * retune and relock, with RASRF_ST_FREQ_BUSY set. Poll rasrf_status() until
 * that clears, then check the lock bits. */
bool rasrf_set_freq_mhz(uint16_t mhz);

/* The LO the frontend is really on, never a pending request. */
bool rasrf_get_freq_mhz(uint16_t *mhz);

/* RX gain code: D6:D5 LNA (3 = high, 2 = -16dB, 0 = -33dB), D4:D0 VGA in 2dB
 * steps. Applies to every RF channel - they are kept equal deliberately, since
 * unequal gain across the aperture is unequal amplitude and group delay.
 * Reads back the frontend's latched request, which it applies within a
 * main-loop pass. */
bool rasrf_set_rx_gain(uint8_t code);
bool rasrf_get_rx_gain(uint8_t *code);

/* Raw 12-bit RSSI. The frontend resamples this at 1Hz, so it is up to a second
 * stale, and it is the second RF channel's detector only - the one net wired to
 * an ADC input on that board. */
/* ADC3424 built-in digital ramp, one bit per ADC (RASRF_TEST_* in
 * rasrf_proto.h). Applied from the frontend's main loop, so allow a few
 * hundred ms; the FPGA link supervisor re-sweeps its taps when the data
 * pattern changes, so the affected panes disturb briefly. */
bool rasrf_set_test_mode(uint8_t mask);
bool rasrf_get_test_mode(uint8_t *mask);

bool rasrf_get_rssi(uint16_t *raw);

#endif /* RASRF_H */
