/*CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC

 Design Name: RASBB_ECU
 Module Name: iqcap_port_sim.c
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

CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC*/

/*
 * iqcap_port_sim.c - iqcap_cfg port for the RASBB_ECU web tree, which has NO
 * SPI4 driver yet (its FPGA data source is DPFPGA.c, a simulator). Both
 * register maps are RAM shadows: writes land, reads come back, counters stay
 * 0 except PHY_ID (so the page shows "FPGA2 present"). When the trees merge,
 * replace the four accessors with rasbb_fpga_*() / rasbb_fpga2_*() and the
 * NV pair with iqcap_nv_h7_*() from STM32H743_Test - nothing else changes.
 */
#include "iqcap_cfg.h"
#include <string.h>

static uint32_t f1[128];
static uint32_t f2[256 / 4];
static int inited = 0;

static bool f1_read(uint8_t a, uint32_t *v)  { *v = f1[a & 0x7Fu]; return true; }
static bool f1_write(uint8_t a, uint32_t v)  { f1[a & 0x7Fu] = v; return true; }
static bool f2_read(uint8_t a, uint32_t *v)
{
    if (a == 0x30u) { *v = IQCAP_PHY_ID_RTL8211E; return true; }
    *v = f2[(a >> 2) & 0x3Fu]; return true;
}
static bool f2_write(uint8_t a, uint32_t v)  { f2[(a >> 2) & 0x3Fu] = v; return true; }

void iqcap_web_lock(void) {}
void iqcap_web_unlock(void) {}
void iqcap_web_prepare(void)
{
    static const iqcap_port_t port = { f1_read, f1_write, f2_read, f2_write, NULL, NULL };
    if (!inited) { inited = 1; memset(f1, 0, sizeof f1); memset(f2, 0, sizeof f2); iqcap_cfg_init(&port); }
}
