/*
 * rasrf_proto.h - STM32H743 <-> RF frontend I2C register-file protocol.
 * Shared definition: keep in step with the frontend's smbus.h, which is the
 * authority (RASRF2400WBMC/Core/Inc/smbus.h for the four-channel board,
 * RASM2400/HKU/User/SMBus.h for the single-channel one).
 *
 * BUS (from RASBB.kicad_pcb and the frontend's own PCB)
 *   STM32 I2C1  PB6 SCL --> SMCLK, RASBB J4 B05 --> frontend J7 B5 --> its PA9
 *               PB9 SDA --> SMDAT, RASBB J4 B06 --> frontend J7 B6 --> its PA10
 *   4k7 pull-ups on both boards. RASBB brings out ONE such pair, so the
 *   segment is private to these two MCUs and carries no other slave - the
 *   AHT20 (0x38) is on I2C3, a different bus.
 *   ~100kHz standard mode (hi2c1.Init.Timing in main.c). The frontend is an
 *   STM32C031 slave that serves the file from its I2C interrupt WITH clock
 *   stretching enabled, so expect it to hold SCL occasionally; do not turn
 *   NoStretchMode on at this end's expense.
 *
 * WHICH FRONTENDS ANSWER
 *   Both the one-channel and the four-channel 2.4GHz boards use address 0x42
 *   and agree on registers 0x00..0x04 and 0x0F, so identity can be read before
 *   anything board-specific is touched: register 0x00 carries the RF band in
 *   its high nibble and the number of RF channels in its low nibble.
 *   Registers 0x05..0x07 and 0x11/0x12 exist on the four-channel board only.
 *
 * ACCESS
 *   write  S <0x84> <idx> <data> ... P
 *   read   S <0x84> <idx> Sr <0x85> <data> ... P
 *   The frontend's register pointer auto-increments and wraps at 0x20, so a
 *   block read in one transaction is fine - which is what HAL_I2C_Mem_Read
 *   and HAL_I2C_Mem_Write generate. No PEC: this is the SMBus register model
 *   on plain I2C, not the full SMBus protocol.
 */
#ifndef RASRF_PROTO_H
#define RASRF_PROTO_H

#include <stdint.h>

/* 7-bit slave address. HAL wants it shifted; use RASRF_I2C_ADDR. */
#define RASRF_I2C_ADDR_7B     0x42u
#define RASRF_I2C_ADDR        (RASRF_I2C_ADDR_7B << 1)

/* ---- register map ------------------------------------------------------- */
#define RASRF_REG_BOARD_MODEL   0x00u /* RO  band<<4 | channels, 0x14 = 4ch 2.4G */
#define RASRF_REG_BOARD_REV     0x01u /* RO  ASCII 'A'..'Z'                      */
#define RASRF_REG_FW_VER_MAJOR  0x02u /* RO  register-map version, not the build */
#define RASRF_REG_FW_VER_MINOR  0x03u /* RO                                      */
#define RASRF_REG_RX_GAIN       0x04u /* RW  MAX2831 reg 11 D6:D0, all channels  */
#define RASRF_REG_STATUS        0x05u /* RO  RASRF_ST_* below                    */
#define RASRF_REG_RSSI_L        0x06u /* RO  reading this latches the pair       */
#define RASRF_REG_RSSI_H        0x07u /* RO  raw 12-bit, resampled at 1Hz        */
#define RASRF_REG_TEST_MODE     0x08u /* RW  ADC ramp self-test, RASRF_TEST_*    */
#define RASRF_REG_ADC_REINITS   0x09u /* RO  map 0.4+: ADC re-inits by the frontend's supervisor */
#define RASRF_REG_UNLOCKS       0x0Au /* RO  map 0.4+: PLL unlock events (>=200ms), saturating  */
#define RASRF_REG_SCRATCH       0x0Fu /* RW  no function, reads back             */
#define RASRF_REG_FREQ_MHZ_L    0x11u /* RW  LO in whole MHz, WRITE STAGES ONLY  */
#define RASRF_REG_FREQ_MHZ_H    0x12u /* RW  WRITE COMMITS THE PAIR              */
#define RASRF_REG_GIT_VER       0x18u /* RO  8 ASCII bytes, NUL-padded           */

#define RASRF_GIT_VER_LEN       8u
#define RASRF_REG_COUNT         0x20u /* the frontend's pointer wraps here */

/* ---- self-test register (0x08) ----------------------------------------- */
/* One bit per ADC3424; 0x00 is normal converter output. Setting ONE bit ramps
 * one ADC while the other stays on live signal as a control - which is the
 * point of it: a ramp that arrives clean proves that ADC's configuration,
 * serialiser and LVDS path, so a channel that still misbehaves is failing in
 * front of the converter, in the analogue domain.
 *   ADC1 -> RF channels 1 and 2      ADC2 -> RF channels 3 and 4
 * Frontends older than register-map 0.2 do not have this register; it reads
 * back 0x00 there and writes are ignored. */
#define RASRF_TEST_NORMAL       0x00u
#define RASRF_TEST_RAMP_ADC1    0x01u
#define RASRF_TEST_RAMP_ADC2    0x02u
#define RASRF_TEST_RAMP_MASK    0x03u

/* ---- status register (0x05) -------------------------------------------- */
#define RASRF_ST_LD_MAX1        0x01u /* MAX2831 1 PLL locked */
#define RASRF_ST_LD_MAX2        0x02u
#define RASRF_ST_LD_MAX3        0x04u
#define RASRF_ST_LD_MAX4        0x08u
#define RASRF_ST_LD_ALL         0x0Fu
#define RASRF_ST_ADC1_OK        0x10u /* ADC3424 #1 config verified over SDOUT */
#define RASRF_ST_ADC2_OK        0x20u
#define RASRF_ST_FREQ_BUSY      0x40u /* a committed retune has not run yet */
#define RASRF_ST_ALL_LOCKED     0x80u

/* ---- LO tuning --------------------------------------------------------- *
 *
 * The frequency is one 16-bit number in whole MHz across 0x11/0x12, little
 * endian. Writing 0x11 only STAGES the low byte; the write to 0x12 is what
 * hands the completed pair to the frontend's tuner, so the natural two-byte
 * burst starting at 0x11 can never present a half-updated frequency to its
 * PLLs. Out-of-range values are refused outright, and 0x11/0x12 keep reading
 * the frequency the array is really on - they never read back the request.
 *
 * A retune blocks the frontend's main loop for ~50ms while its four
 * synthesizers relock, during which RASRF_ST_FREQ_BUSY stays set. The I2C
 * slave keeps answering throughout (it runs from the interrupt), so polling
 * status is the way to wait.
 *
 * 2300..2399 is beyond the MAX2831 datasheet and accepted only by RASRF2400WBMC
 * firmware 0.3 and later (out-of-band receiver noise reference, 2026-10-03);
 * an older frontend silently keeps its LO, which the read-back shows.
 */
#define RASRF_FREQ_MHZ_MIN      2300u
#define RASRF_FREQ_MHZ_MAX      2500u

/* 802.11b/g channel centres, for turning a channel number into a frequency. */
#define RASRF_CH_MHZ(ch)  (((ch) == 14u) ? 2484u : (2407u + 5u * (ch)))

#endif /* RASRF_PROTO_H */
