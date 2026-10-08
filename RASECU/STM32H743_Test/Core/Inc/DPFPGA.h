/*HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH

 Design Name: RASBB_ECU
 Module Name: DPFPGA.h
 Project Name: Radio Access Sentinel
 Engineer: Tobias Weber
 Target Devices: STM32H743 on RASBB
 Tool Versions: CubeIDE 1.18
 Description:  RA-Sentinel is a WiFi activity and thread detection platform

 Revision 1.00 - File Created
 Additional Comments: https://github.com/Tobias-DG3YEV/RA-Sentinel

 This project was funded through the NGI0 Entrust Fund, a fund established
 by NLnet with financial support from the European Commission's
 Next Generation Internet programme, under the aegis of DG Communications
 Networks, Content and Technology under grant agreement No 101069594.
 https://nlnet.nl/project/RA-Sentinel/

 Copyright (C): Tobias Weber
 License: GNU GPL v3

 This project is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTIBILITY or FITNESS FOR A PARTICULAR PURPOSE.
 See the GNU General Public License for more details.

 You should have received a copy of the GNU Lesser General Public License
 along with this program. If not, see
 <http://www.gnu.org/licenses/> for a copy.

HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH*/

#ifndef INC_DPFPGA_H_
#define INC_DPFPGA_H_

/****************************************************************************
 *                              INCLUDES
 ****************************************************************************/
#include "platform_types.h"
#include "config.h"
#include "RAS_protocol.h"

/****************************************************************************
 *                            FUNCTION PROTOTYPES
 ****************************************************************************/

void DPFPGA_init(void);
u8 DPFPGA_getSptListSize(void);
RAS_SUSPECT_T* DPFPGA_getEntry(u8 id);
u8 DPFPGA_getSptCount(void);
RAS_SUSPECT_T* DPFPGA_getPIDEntry(u8 pid);

#endif /* INC_DPFPGA_H_ */
