/*
 * rasrf6000_proto.h - STM32H743 <-> RASRF6000 (6 GHz single-channel front
 * end) I2C register-file protocol. The authority is the front end's own
 * RASRF6000/HKU/User/SMBus.h - keep in step with it.
 *
 * Same bus, address and access rules as the 2.4 GHz boards (rasrf_proto.h:
 * I2C1 PB6/PB9 -> RASBB J4 B05/B06, slave 0x42, pointer auto-increment) and
 * the same identity registers 0x00..0x03, but a DIFFERENT map above that:
 * the 2.4 GHz map's 0x05..0x08 (MAX2831 locks, RSSI, ramp) are this board's
 * STATUS and Si5324 alarm registers, and its 0x11/0x12 LO pair does not exist
 * here (the LMX2572 LO is fixed in the HKU firmware). Always read 0x00 first
 * and dispatch on the band nibble before touching anything else.
 *
 * The pointer wraps at 0x10 on this board.
 */
#ifndef RASRF6000_PROTO_H
#define RASRF6000_PROTO_H

#include <stdint.h>

#define RASRF6000_MODEL          0x21u /* band 2 (6 GHz) << 4 | 1 channel */
#define RASRF6000_BAND(model)    ((model) >> 4)
#define RASRF6000_BAND_6GHZ      0x2u

/* ---- register map ------------------------------------------------------- */
#define RASRF6000_REG_STATUS     0x05u /* RO  RASRF6000_ST_* below           */
#define RASRF6000_REG_CLK_LOS    0x06u /* RO  Si5324 reg129: b0 XTAL, b1 CKIN1, b2 CKIN2 loss */
#define RASRF6000_REG_CLK_LOL    0x07u /* RO  Si5324 reg130: b0 LOL (1 = unlocked) */
#define RASRF6000_REG_CLK_ACTV   0x08u /* RO  Si5324 reg128: active input    */
#define RASRF6000_REG_RAMP       0x09u /* RW  b0 = ADC ramp pattern on. READS
                                          BACK THE ACTUAL STATE; applied from
                                          the HKU main loop within ~ms. The
                                          first write hands ramp control to
                                          this host (STATUS b6) - the HKU's
                                          own 3 s boot window is then off. */
#define RASRF6000_REG_SCRATCH    0x0Fu /* RW                                 */
#define RASRF6000_REG_COUNT      0x10u

/* ---- STATUS (0x05) ------------------------------------------------------ */
#define RASRF6000_ST_ADC_OK      0x01u /* ADC3224 config read back OK        */
#define RASRF6000_ST_LTC_OK      0x02u /* LTC5594 chip id OK                 */
#define RASRF6000_ST_CLK_LINK    0x04u /* Si5324 SPI link OK                 */
#define RASRF6000_ST_CLK_LOCK    0x08u /* Si5324 DSPLL locked = ADC clock up */
#define RASRF6000_ST_LO_LOCK     0x10u /* LMX2572 lock detect                */
#define RASRF6000_ST_RAMP_ON     0x20u /* ADC on the digital ramp            */
#define RASRF6000_ST_HOST_RAMP   0x40u /* ramp under host control            */
#define RASRF6000_ST_INIT_DONE   0x80u /* boot sequence finished             */

/* register-map version (0x02/0x03) that first carries 0x09 + the two new
 * status bits; older HKU builds ignore writes to 0x09 and read it as 0 */
#define RASRF6000_MAP_MIN_MINOR  2u

#endif /* RASRF6000_PROTO_H */
