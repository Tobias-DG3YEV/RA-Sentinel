/*
 * console.h - USART3 command line for the RF frontend.
 *
 * A line-oriented console on the port printf already goes out of (PD8/PD9,
 * 115200 8N1). It exists because the frontend's own console had to be given
 * up: on the four-channel board the two console pins ARE the I2C pins (its
 * PA9/PA10 carry SMCLK/SMDAT), so the frontend can be talked to over the
 * register file or over a serial console, never both. This is the console
 * that replaces it, one MCU further up.
 *
 *   SF <mhz>   set the LO, e.g. "SF 2437\r" for 802.11 channel 6
 *   GF         get the LO
 *   ST         status: PLL lock, ADC config, RSSI
 *   ID         frontend model, revision, register-map version, build stamp
 *   SG <hh>    set RX gain code (hex), all channels
 *   GG         get RX gain code
 *   ?          this list
 *
 * Commands are case-insensitive. Frequencies are decimal MHz; the gain code is
 * hex because it is a register bitfield, not a quantity.
 */
#ifndef CONSOLE_H
#define CONSOLE_H

/* Arms UART reception and makes stdout unbuffered. Call BEFORE the first
 * printf (see the setvbuf note in console.c) and after MX_USART3_UART_Init. */
void console_init(void);

/* Greeting, whatever the frontend says it is, and the first prompt. Call from
 * the console task: it probes the frontend over I2C, which blocks. */
void console_banner(void);

/* Consumes whatever has arrived and executes any completed line. Call from a
 * task: a command can block for the length of an I2C transaction, and SF waits
 * out the frontend's ~50ms retune with osDelay. */
void console_poll(void);

#endif /* CONSOLE_H */
