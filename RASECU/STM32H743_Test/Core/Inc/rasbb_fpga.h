/*
 * rasbb_fpga.h - host-side driver for the OWIFI_RX frame read-out port.
 *
 * Self-contained: drop rasbb_fpga.c/.h and rasbb_fpga_proto.h into the STM32
 * project's User/ folder (scaffold: RASECU/STM32H743_Test, which already pins
 * SPI4 on PE12/13/14 and the mux controls on PA10/PB15). Nothing here touches
 * CubeMX-generated files, so regenerating the project cannot clobber it.
 *
 * The FPGA is a POLLED slave - RASBB has no FPGA->uC interrupt line (only CS,
 * MISO and FPGA01_PROG connect U10 to IC12), so this is a hardware fact, not
 * a design choice.
 */
#ifndef RASBB_FPGA_H
#define RASBB_FPGA_H

#include <stdint.h>
#include <stdbool.h>
#include "rasbb_fpga_proto.h"

/* Largest frame we will accept off the wire. dot11's SIGNAL length field is
 * 12 bits, but signal_watchdog rejects anything above 1700, so this is the
 * real ceiling plus slack. */
#define RASBB_MAX_FRAME 2048u

typedef struct {
    rasbb_frame_desc_t desc;
    uint8_t            payload[RASBB_MAX_FRAME];
} rasbb_frame_t;

/* Initialise GPIO state: CS high, config flash parked off the SPI bus.
 * Call once after MX_GPIO_Init()/MX_SPI4_Init(). */
void rasbb_fpga_init(void);

/* Single-byte status poll (2-byte transaction). Returns the STATUS byte, or
 * 0xFF on a SPI error (0xFF is not a producible status: it would mean 7
 * queued frames AND overflow AND demod all at once with link down). */
uint8_t rasbb_fpga_status(void);

/* Read the head frame WITHOUT retiring it. Returns true on success.
 * Safe to retry: the FPGA only advances its read pointer on rasbb_fpga_pop(). */
bool rasbb_fpga_read_frame(rasbb_frame_t *out);

/* Retire the head frame. Call only after a read you are happy with. */
bool rasbb_fpga_pop(void);

/* Convenience: poll, and if a frame is waiting, read + pop it.
 * Returns true if *out was filled. */
bool rasbb_fpga_poll_frame(rasbb_frame_t *out);

/* Diagnostics block (front-end link health, exact queue depth). */
bool rasbb_fpga_status_ext(rasbb_status_ext_t *out);

/* dot11 configuration registers (addresses in rasbb_fpga_proto.h). */
bool rasbb_fpga_write_reg(uint8_t addr, uint32_t value);
bool rasbb_fpga_read_reg(uint8_t addr, uint32_t *value);

/* FPGA2 (DFPGA) register slave on the same bus, chip select CS2 = PC12
 * (SPEC.md section 7). Same opcodes; a 32-bit access is the little-endian
 * word at addr..addr+3 of FPGA2's byte-wide map. */
uint8_t rasbb_fpga2_status(void);
bool rasbb_fpga2_write_reg(uint8_t addr, uint32_t value);
bool rasbb_fpga2_read_reg(uint8_t addr, uint32_t *value);

/* Control: flush the queue, clear the sticky overflow flag, choose whether
 * frames with a bad FCS are queued too. */
bool rasbb_fpga_control(uint8_t ctrl_bits);

/* Park the shared bus for a config-flash operation, and put it back.
 * While "borrowed", the flash is on the uC bus and the FPGA must not be
 * addressed (its opcodes are disjoint from the flash command set, so it will
 * ignore the traffic and keep MISO tri-stated - but do not rely on that to
 * mix the two). */
void rasbb_flash_bus_take(void);
void rasbb_flash_bus_release(void);

#endif /* RASBB_FPGA_H */
