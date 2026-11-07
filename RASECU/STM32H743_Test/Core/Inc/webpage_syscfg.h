/*HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH

 Design Name: RASBB_ECU
 Module Name: webpage_syscfg.h
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

#ifndef _WEBPAGE_SYSCFG_H_
#define _WEBPAGE_SYSCFG_H_

/****************************************************************************
 *                            FUNCTION PROTOTYPES
 ****************************************************************************/

void WP_generate_syscfg_edit(const char* pURL, char *buffer, size_t bufsize);
void WP_generate_rascfg_edit(const char* pURL, char *buffer, size_t bufsize);

#endif //_WEBPAGE_SYSCFG_H_

