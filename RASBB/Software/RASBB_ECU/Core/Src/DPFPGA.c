/*CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC

 Design Name: RASBB_ECU
 Module Name: DPFPGA.c
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

CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC*/

/****************************************************************************
*                              INCLUDES
*****************************************************************************/

#include "lwip/opt.h"
#include "lwip/arch.h"
#include "lwip/api.h"
#include "platform_types.h"
#include "SysErrCodes.h"
#include "config.h"
#include "RAS_protocol.h"
#include "main.h"
#include "stm32h7xx_hal_rng.h"
#include "rng.h"
#include "DPFPGA.h"

/****************************************************************************
*                              DEFINES
*****************************************************************************/

/****************************************************************************
*                              MACROS
*****************************************************************************/
/****************************************************************************
*                              LOCAL VARIABLES
*****************************************************************************/

RAS_SUSPECT_T m_rasspt[MAX_SPTS_IN_LIST];
u32 m_lasttick;

const RAS_SUSPECT_MAC_T c_prefdef_rassptMAC[] = {
		{{0x11,0x21,0xFF,0xA3,0x54,0x33}},
		{{0x23,0xE4,0xDA,0x4E,0x81,0x66}},
		{{0xFF,0xFF,0xFE,0x12,0xE0,0x3A}},
		{{0x80,0x00,0x29,0x7A,0x44,0xEC}},
		{{0x23,0xE4,0xDA,0x4E,0x81,0x66}},
		{{0x4A,0xA2,0x08,0xEE,0x38,0xBC}}
};

/****************************************************************************
*                              LOCAL FUNCTIONS
*****************************************************************************/

/****************************************************************************
* FUNC:		getRndU8
* PARAM:	void
* RET:		u8
* DESC:		returns a random number between 0 and 255
*****************************************************************************/
static u8 getRndU8(void)
{
	uint32_t rnd;
	HAL_RNG_GenerateRandomNumber(HAL_RNG_getHnd(), &rnd);
	return 0xFF & rnd;
}

/****************************************************************************
* FUNC:		updateEntry
* PARAM:	u8 id
* RET:		void
* DESC:		update a specified suspect entry
*****************************************************************************/
static void updateEntry(u8 id)
{
	m_rasspt[id].dir += (s8)(getRndU8() % 10) - 5;
	m_rasspt[id].rssi = 70 + (getRndU8() % 20);
	m_rasspt[id].ts = HAL_GetTick()/1000;
	m_rasspt[id].fts = HAL_GetTick()%1000;
	m_rasspt[id].patternID = id+100;
}

/****************************************************************************
* FUNC:		updateList
* PARAM:	void
* RET:		void
* DESC:		update the suspect list
*****************************************************************************/
static void updateList(void)
{
	u8 rassptID;
	u32 i;

	rassptID = getRndU8() % NUMOFELEM(c_prefdef_rassptMAC);

	// search if this ID already exists
	for(i = 0; i < MAX_SPTS_IN_LIST; i++) {
		//empty entry?
		if( !memcmp( c_prefdef_rassptMAC[rassptID].addr, m_rasspt[i].MAC.addr, sizeof(m_rasspt[0].MAC) )) {
			updateEntry(i);
			return;
		}
	}
	//if this ID was not yet known, add it as new
	for(i = 0; i < MAX_SPTS_IN_LIST; i++) {
		if(m_rasspt[i].patternID == 0) {
			memcpy( m_rasspt[i].MAC.addr, c_prefdef_rassptMAC[rassptID].addr, sizeof(c_prefdef_rassptMAC[0]) );
			updateEntry(i);
			return;
		}
	}
}


/****************************************************************************
* FUNC:		DPFPGA_thread
* PARAM:	void *arg
* RET:		void
* DESC:		the main thread of the DPFPGA module. Never returns
*****************************************************************************/
static void DPFPGA_thread(void *arg)
{

	while(1) {
		if(m_lasttick + RAS_LISTUPDATE < HAL_GetTick()) {
			updateList();
			m_lasttick = HAL_GetTick();
		}
	}
}

/****************************************************************************
*                             GLOBAL FUNCTIONS
*****************************************************************************/

/****************************************************************************
* FUNC:		DPFPGA_getSptListSize
* PARAM:	void
* RET:		u8
* DESC:		get the amount of total entries space
*****************************************************************************/
u8 DPFPGA_getSptListSize(void)
{
	return MAX_SPTS_IN_LIST;
}

/****************************************************************************
* FUNC:		DPFPGA_getSptCount
* PARAM:	void
* RET:		u8
* DESC:		returns the number recently suspects
*****************************************************************************/
u8 DPFPGA_getSptCount(void)
{
	u32 i = 0;
	u8 found = 0;
	RAS_SUSPECT_MAC_T emptymac;
	MEMCLR(emptymac);

	for(i = 0; i < MAX_SPTS_IN_LIST; i++) {
		//empty entry?
		if( memcmp(&emptymac, &m_rasspt[i].MAC, sizeof(emptymac))) {
			found++;
		}
	}
	return found;
}

/****************************************************************************
* FUNC:		DPFPGA_getEntry
* PARAM:	u8 id
* RET:		RAS_SUSPECT_T*
* DESC:		get the link to a RAS suspect
*****************************************************************************/
RAS_SUSPECT_T* DPFPGA_getEntry(u8 id)
{
	RAS_SUSPECT_MAC_T emptymac;
	MEMCLR(emptymac);

	if(id >= MAX_SPTS_IN_LIST) {
		return  NULL;
	}

	if( memcmp(&emptymac, &m_rasspt[id].MAC, sizeof(emptymac)) ) {
		return &m_rasspt[id];
	}
	return NULL;
}

/****************************************************************************
* FUNC:		DPFPGA_getPIDEntry
* PARAM:	u8 pattern ID (internal unique identifier of a suspect)
* RET:		RAS_SUSPECT_T* pointer to a
* DESC:		returns a pointer to the description
*****************************************************************************/
RAS_SUSPECT_T* DPFPGA_getPIDEntry(u8 pid)
{
	RAS_SUSPECT_MAC_T emptymac;
	MEMCLR(emptymac);
	u8 id;

	for(id = 0; id < MAX_SPTS_IN_LIST; id++) {
		if(pid == m_rasspt[id].patternID) {
			return &m_rasspt[id];
		}
	}
	return NULL;
}

/****************************************************************************
* FUNC:		DPFPGA_init
* PARAM:	void
* RET:		void
* DESC:		initialises the Digital Processor FPGA interface
*****************************************************************************/
void DPFPGA_init(void)
{
	MEMCLR(m_rasspt);
	printf("starting RAS Frontend Simulation. %u artificial suspects. MAC size: %u\n", NUMOFELEM(c_prefdef_rassptMAC), sizeof(m_rasspt[0].MAC));
	sys_thread_new("RAS", DPFPGA_thread, NULL, 512, osPriorityNormal);

}
