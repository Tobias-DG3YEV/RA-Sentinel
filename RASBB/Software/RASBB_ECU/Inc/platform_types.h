/*HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH

 Design Name: RASBB_ECU
 Module Name: platform_types.h
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

#ifndef PLATFORM_TYPES_H
#define PLATFORM_TYPES_H

/****************************************************************************
*                              INCLUDES
*****************************************************************************/

#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>
#include <string.h>

/****************************************************************************
*                              DEFINES
*****************************************************************************/

/* our base types */
typedef unsigned char           u8;
typedef signed char             s8;
typedef unsigned short int      u16;
typedef signed short int        s16;
typedef unsigned int       			u32;
typedef signed long long			  s64;
typedef unsigned long long			u64;
typedef signed int         			s32;
typedef _Bool										t_BOOL;
#ifndef bool
#define bool							t_bool;
#endif
#define __WORDSIZE      				32

#define t_utiny		u32 /* this type can be a positive value from 0 to 255   */
//#define t_usmall	u32 /* this type can be a positive value from 0 to 65536 */
#define t_stiny 	s32 /* this type can be any value from -127 to 128 */
#define t_ssmall 	s32 /* this type can be any value from -32767 to 32768 */

#define UTINY			u32
#define STINY			s32
#define USMALL		u32
#define SSMALL		s32


typedef char                    t_string;

#define NULLPOINTER				      ((void*)(0x00000000))

#ifndef NULL
  #define NULL   0
#endif /* NULL */

/* string type handling */
#ifdef _WIN32
#define STR(x) L##x
#define STR_T char
#else
#define STR(x) x
#define STR_T char
#endif

typedef u8						          HANDLE;
typedef u8						          EVENT;
typedef const char				      ROMSTRING;
//typedef const void*				      (*T_MENU)(EVENT, HANDLE);

#if defined(__ICCARM__)
#define PACKED           __packed
#elif defined(__GNUC__)
#define PACKED           __attribute__((packed))
#define PACKED_STRUCT    __attribute__((packed))
#else
#define PACKED
#define PACKED_STRUCT
#endif

#define MEMCLR(x) memset(&(x), 0, sizeof(x))

//#define vmalloc   pvPortMalloc
//#define vfree 	  vPortFree

/****************************************************************************
*                              MACROS
*****************************************************************************/

#define MIN(x,y)								(((x)>(y))?(y):(x))
#define MAX(x,y)								(((x)<(y))?(y):(x))
#define NUMOFELEM(x)						(sizeof((x))/sizeof((x)[0]))
#define SIZEOFELEM(x)						(sizeof((x)[0]))
#define HIGH16(x)								(((x)>>8)&0xFF)
#define LOWBYTE(x)							((x)&0xFF)

#define HIGH_WORD(x)						(((x)>>16)&0xFFFF)
#define LOW_WORD(x)							((x)&0xFFFF)
#define HIGH_BYTE(x)						(((x)>>8)&0xFF)
#define LOW_BYTE(x)							((x)&0xFF)

#define GET_BYTE_0(x)           LOW_BYTE(x)
#define GET_BYTE_1(x)           HIGH_BYTE(x)
#define GET_BYTE_2(x)           LOW_BYTE(HIGH_WORD(x))
#define GET_BYTE_3(x)           HIGH_BYTE(HIGH_WORD(x))

#define WRITE_DWORD(d, s)       { \
                                  (d)[0] = ((s)      ) & 0xFF; \
                                  (d)[1] = ((s) >> 8 ) & 0xFF; \
                                  (d)[2] = ((s) >> 16) & 0xFF; \
                                  (d)[3] = ((s) >> 24) & 0xFF; }

#define Swap16(x) ((u16)(((u16)(x) >> 8) |\
                           ((u16)(x) << 8)))

#define Swap32(x) ((u32)(GET_BYTE_0(x)<<24|GET_BYTE_1(x)<<16|GET_BYTE_2(x)<<8|GET_BYTE_3(x)))

#define  BE16(x)        Swap16(x)
//#define  LE16(x)        (x)

#define  le16_to_cpu(x) (x)
#define  cpu_to_le16(x) (x)
#define  LE16_TO_CPU(x) (x)
#define  CPU_TO_LE16(x) (x)

#define  be16_to_cpu(x) Swap16(x)
#define  cpu_to_be16(x) Swap16(x)
#define  BE16_TO_CPU(x) Swap16(x)
#define  CPU_TO_BE16(x) Swap16(x)
#define  BE32_TO_CPU(x) Swap32(x)
#define  CPU_TO_BE32(x) Swap32(x)

#define NOP()                   { __asm__ __volatile__ ("nop"); }

#ifndef TRUE
# define TRUE 1
#endif

#ifndef FALSE
# define FALSE 0
#endif

#define BM(x)										(1<<(x)) /* create Bitmask from position number */
#define CLRBIT(x,y)						{(x) &= ~(1<<(y));}
#define SETBIT(x,y)						{(x) |= (1<<(y));}
#define ISBIT(x,y)							((x) & (1<<(y))) /* test if bit nr x is set */

#ifdef __ICCAVR__
# define ISR(x) __interrupt static void x(void)
#endif


typedef s32 ssize_t;

/* Define RAMFUNC attribute */
#if defined   ( __CC_ARM   ) /* Keil µVision 4 */
#   define RAMFUNC __attribute__ ((section(".ramfunc")))
#elif defined ( __ICCARM__ ) /* IAR Ewarm 5.41+ */
#   define RAMFUNC __ramfunc
#elif defined (  __GNUC__  ) /* GCC CS3 2009q3-68 */
#   define RAMFUNC __attribute__ ((section(".ramfunc")))
#endif

#define __off_t_defined
//typedef s32 off_p;

#define FREERTOS_CALC_TICKS(x) ((CONFIG_FREERTOS_HZ * x) / 1000 )
#define FREERTOS_CALC_MS(x) ((1000 * x) / CONFIG_FREERTOS_HZ)

#endif //PLATFORM_TYPES_H
/*** EOF ***/
