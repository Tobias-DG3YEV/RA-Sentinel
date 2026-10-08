/*HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH

 Design Name: RASBB_ECU
 Module Name: upnp.h
 Project Name: Radio Access Sentinel
 Engineer: Tobias Weber
 Target Devices: STM32H743 on RASBB
 Tool Versions: CubeIDE 1.18
 Description:  implementation of the UPNP protocol

 Additional Comments: https://github.com/Tobias-DG3YEV/RA-Sentinel

 This project was funded through the NGI0 Entrust Fund, a fund established
 by NLnet with financial support from the European Commission's
 Next Generation Internet programme, under the aegis of DG Communications
 Networks, Content and Technology under grant agreement No 101069594.
 https://nlnet.nl/project/RA-Sentinel/

 SPDX-FileCopyrightText: 2022 - 2026 Tobias Weber
 SPDX-License-Identifier: GPL-3.0-only

 This project is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 See the GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with this program. If not, see
 <http://www.gnu.org/licenses/> for a copy.

HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH*/

#ifndef _UPNP_H_
#define _UPNP_H_

 /****************************************************************************
 *                              INCLUDES
 *****************************************************************************/

 /****************************************************************************
 *                              DEFINES
 *****************************************************************************/

typedef enum {
	UPNPERR_OK					=	0,
	UPNPERR_ALLOCFAILED = -1
} UPNP_RESULT_T;

 /****************************************************************************
 *                              MACROS
 *****************************************************************************/

 /****************************************************************************
 *                              GLOBAL VARIABLES
 *****************************************************************************/

 /****************************************************************************
 *                            FUNCTION PROTOTYPES
 *****************************************************************************/

UPNP_RESULT_T UPNP_serverInit(void);

#endif /* _UPNP_H_*/
/*** EOF ***/
