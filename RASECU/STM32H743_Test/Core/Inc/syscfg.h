/*
 * syscfg.h
 *
 *  Created on: Dec 7, 2025
 *      Author: tobiw
 */

#ifndef _SYSCFG_H_
#define _SYSCFG_H_

#include "platform_types.h"
#include "lwip/ip_addr.h"

typedef struct {
	ip4_addr_t  localip; //The IP of the RASBB
	ip4_addr_t hostip; //Host who gets suspects data from us
	u16 sptTO; //suspect timeout how long a suspect is marked as suspicious after it was first marked.
	u8 wlanCh; //wifi Channel to observer
} SYSCFG_T;


SYSCFG_T* SYSCFG_getCfg(void);

#endif /* _SYSCFG_H_ */
