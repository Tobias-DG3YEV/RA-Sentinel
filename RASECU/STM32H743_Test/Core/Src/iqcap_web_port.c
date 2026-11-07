/* iqcap_web_port.c - web page hooks for the STM32H743_Test tree: the config
 * module is initialised in main(); FPGA access from the HTTP thread must hold
 * the shared SPI4 bus guard like the console does (logw_seq.c). */
#include "logw_seq.h"
void iqcap_web_prepare(void) {}
void iqcap_web_lock(void)    { logw_bus_lock(); }
void iqcap_web_unlock(void)  { logw_bus_unlock(); }
