/*
 * menu.h - on-screen settings menu in FPGA1's HDMI pop-up box, driven by five
 * buttons on the ECU's debug header J8 (RASBB), TV-remote style:
 *
 *   J8 pin  STM32  button          J8 is a 2x5 1.27 mm header without a
 *   ------  -----  ------          ground pin, so pin 10 (PD10) is driven
 *     1     PD0    UP              LOW as the buttons' common: wire each
 *     3     PD1    DOWN            button between its pin and pin 10 (or
 *     5     PD2    LEFT            any GND). Inputs have the internal
 *     7     PD4    RIGHT           pull-up, a press reads low.
 *     9     PD7    OK
 *     2     PD15   ESC (escape)
 *    10     PD10   common (low)
 *
 * The ECU owns the menu (items, values, navigation, timeout); FPGA1 only
 * draws text and rectangles (ovl_box.v, doc/iq_capture/SPEC.md section 4).
 * Any button opens the menu, UP/DOWN move in the main column, RIGHT/OK
 * enter the submenu, OK toggles / executes / edits, LEFT goes back, ESC
 * closes the menu; with the menu closed ESC hides the pop-up box and OK
 * brings it back (the next OK opens the menu). 20 s without a button
 * closes the menu and the stored pop-up text returns. Items: update rate (label
 * averaging), pause, FCS-bad frames shown, clear table, pop-up text, exit.
 * Console: BT <UP|DN|L|R|OK|E> presses a button (E = escape, closes the
 * menu; MB <u|d|l|r|o> is the short alias), DP / DB / DA / DC set the same
 * switches directly.
 */
#ifndef MENU_H
#define MENU_H

#include <stdbool.h>
#include <stddef.h>

enum menu_button { MENU_BTN_UP, MENU_BTN_DOWN, MENU_BTN_LEFT, MENU_BTN_RIGHT, MENU_BTN_OK, MENU_BTN_ESC, MENU_BTN_N };

void menu_init(void);                       /* J8 pins; after MX_GPIO_Init */
void menu_poll(void);                       /* every ~5 ms from the console task: buttons, repeat, timeout */
void menu_button(enum menu_button b);       /* one press (console BT); caller holds the bus lock */
bool menu_is_open(void);
void menu_redraw(void);                     /* repaint if open (after a console setter changed a value) */
int  menu_status(char *dst, size_t n);      /* "closed" or "open, bar on <item> = <value>" */

#endif
