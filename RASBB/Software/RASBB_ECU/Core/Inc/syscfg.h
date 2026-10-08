/*HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH

 Design Name: RASBB_ECU
 Module Name: syscfg.h
 Project Name: Radio Access Sentinel
 Engineer: Tobias Weber
 Target Devices: STM32H743 on RASBB
 Tool Versions: CubeIDE 1.18
 Description:  RA-Sentinel is a WiFi activity and threat detection platform

 Additional Comments: https://github.com/Tobias-DG3YEV/RA-Sentinel

 This project was funded through the NGI0 Entrust Fund, a fund established
 by NLnet with financial support from the European Commission's
 Next Generation Internet programme, under the aegis of DG Communications
 Networks, Content and Technology under grant agreement No 101069594.
 https://nlnet.nl/project/RA-Sentinel/

 SPDX-FileCopyrightText: 2026 Tobias Weber
 SPDX-License-Identifier: GPL-3.0-only

 This project is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 See the GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with this program. If not, see
 <http://www.gnu.org/licenses/> for a copy.

HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH*/

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
