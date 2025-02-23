/*HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
 *
 *  Elektronik-idee Weber GmbH (c);
 *
 *  File: platform_types.h
 *
 *  Version 1.0
 *
 *  Project: CP700
 *
 *  Description: Platform dependand type definitions
 *
 *  tw@elektronik-idee.com
 *
 *  Copyright (C) 2013 - 2016 Elektronik-Idee, Tobias Weber
 *  All rights reserved, alle Rechte vorbehalten.
 *
 HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH*/


#ifndef PLATFORM_TYPES_H
#define PLATFORM_TYPES_H

/****************************************************************************
*                              INCLUDES
*****************************************************************************/

#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>
#ifndef __POLYSPACE__
#include <ysizet.h>
#endif
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


typedef u8						          HANDLE;
typedef u8						          EVENT;
typedef const char				      ROMSTRING;
//typedef const void*				      (*T_MENU)(EVENT, HANDLE);

#if defined(__ICCARM__)
#define PACKED          __packed
#define PACKED_STRUCT   __packed
#elif defined(__GNUC__)
#define PACKED          __attribute__((packed))
#define PACKED_STRUCT   __attribute__((packed))
#endif

//#define vmalloc   pvPortMalloc
//#define vfree 	  vPortFree

/****************************************************************************
*                              MACROS
*****************************************************************************/

#ifndef MIN
#define MIN( a, b ) ( ( ( a ) < ( b ) ) ? ( a ) : ( b ) )
#endif
#ifndef MAX
#define MAX( a, b ) ( ( ( a ) > ( b ) ) ? ( a ) : ( b ) )
#endif
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

#define NOP()                   { __asm volatile ("nop\n"); }

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

#ifndef DIVR
#define DIVR( X, N )                ( ( ( X ) + ( ((X)>0?(N):(N))>>1 ) ) / ( N ) )
#endif

#define MEMCLR(x)                memset((void*)x, 0, sizeof(*x))

/***** linux extensions ****/
//#define typedef		typedef

#ifndef __POLYSPACE__

//typedef u32 __dev_t;	/* Type of device numbers.  */
//typedef u32 __uid_t;	/* Type of user identifications.  */
//typedef u32 __gid_t;	/* Type of group identifications.  */
//typedef u32 __ino_t;	/* Type of file serial numbers.  */
//typedef u32 __ino64_t;	/* Type of file serial numbers (LFS).*/
//typedef u32 __mode_t;	/* Type of file attribute bitmasks.  */
//typedef u32 __nlink_t;	/* Type of file link counts.  */
//typedef s32 __off_t;	/* Type of file sizes and offsets.  */
//typedef s32 __off64_t;	/* Type of file sizes and offsets (LFS).  */
//typedef s32 __pid_t;	/* Type of process identifications.  */
//typedef struct{ int __val[2]; } __fsid_t;	/* Type of file system IDs.  */
//typedef s32 __clock_t;	/* Type of CPU usage counts.  */
//typedef u32 __rlim_t;	/* Type for resource measurement.  */
//typedef u64 __rlim64_t;	/* Type for resource measurement (LFS).  */
//typedef u32 __id_t;		/* General type for IDs.  */
//typedef s32 __time_t;	/* Seconds since the Epoch.  */
//typedef u32 __useconds_t; /* Count of microseconds.  */
//typedef u32 __suseconds_t; /* Signed count of microseconds.  */

//typedef s32 __daddr_t;	/* The type of a disk address.  */
//typedef s32 __key_t;	/* Type of an IPC key.  */
//typedef u32 __ssize_t; /* Type of a byte count, or error.  */

typedef s32 ssize_t;
#define FILE SFS_FILE
typedef s32 off_t;

//typedef long long __quad_t;
//typedef unsigned long long __u_quad_t;

#endif


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

#endif //PLATFORM_TYPES_H
/*** EOF ***/
