/*HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH

 Design Name: RASBB_ECU
 Module Name: RAS_protocol.h
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
 * RAS_protocol.h
 *
 *  Created on: Dec 6, 2025
 *      Author: tobiw
 */

#ifndef INC_RAS_PROTOCOL_H_
#define INC_RAS_PROTOCOL_H_

#include "platform_types.h"


typedef union {
    u8 byte;           // Access the whole byte
    struct {
        u8 tracked : 1;   // is tracked, means meta data is forwarded oder network
        u8 fingerp: 1;   // is fingerprinted
        u8 tagged : 1;   // is tagged (for later use)
        u8 susp : 1; //this node triggered an alarm, hence tagged as suspicious
    } bits;
} RAS_SUSBECT_CFG_T; // RAS suspect configuration

typedef struct {
	u8 addr[6]; // MAC address of the WiFi device received
} RAS_SUSPECT_MAC_T;

typedef struct {
	u32 patternID; //internal ID created by timestamp to identify recurring occurance when MAC is obfuscated
	RAS_SUSPECT_MAC_T MAC; // MAC address of the WiFi device received
	u32 ts; //UNIX timestamp of arrival
	u32 fts; //fine timestamp of arrival, granularity 1s/fts
	u8 ant; //Antenna that received this frame (0 to 3)
	u8 rssi; //RSSI in negative value 100 = -100dBm
	u8 dir; //direction from where the MAC is received
	u8 dtThrs; //Detection threshold
	RAS_SUSBECT_CFG_T cfg; // configuration what to do with the suspected
} RAS_SUSPECT_T;


#endif /* INC_RAS_PROTOCOL_H_ */
