/* webpage_iqcap.h - "IQ Capture" configuration/status page (JOB-06).
 * Generates the page body into a caller buffer; the send wrapper lives in
 * webpage.c next to the other pages. Data comes from iqcap_cfg.c (shared
 * with RASECU/STM32H743_Test) through the port set up in iqcap_port_sim.c. */
#ifndef WEBPAGE_IQCAP_H
#define WEBPAGE_IQCAP_H
#include <stddef.h>
void WP_generate_iqcap_edit(const char *pURL, char *buffer, size_t bufsize);
#endif
