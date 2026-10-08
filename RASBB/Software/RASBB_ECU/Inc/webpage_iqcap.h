/*HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH

 Design Name: RASBB_ECU
 Module Name: webpage_iqcap.h
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

/* webpage_iqcap.h - "IQ Capture" configuration/status page (JOB-06).
 * Generates the page body into a caller buffer; the send wrapper lives in
 * webpage.c next to the other pages. Data comes from iqcap_cfg.c (shared
 * with RASECU/STM32H743_Test) through the port set up in iqcap_port_sim.c. */
#ifndef WEBPAGE_IQCAP_H
#define WEBPAGE_IQCAP_H
#include <stddef.h>
void WP_generate_iqcap_edit(const char *pURL, char *buffer, size_t bufsize);
#endif
