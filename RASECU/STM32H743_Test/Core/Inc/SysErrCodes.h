/*HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
 *
 *  Author: Tobias Weber
 *
 *  File: SysErrCodes.h
 *
 *  Version 1.0
 *
 *  Project: RA-Sentinel  RASECU @ RASBB
 *
 *  Description: Global System Error Codes
 *
 *  Released under GNU GPL 2.0 license
 *
 HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH*/

#ifndef SysErrCodes_H
#define SysErrCodes_H

/****************************************************************************
*                              INCLUDES
*****************************************************************************/
/* NO INCLUDES FROM WITHIN THIS FILE! */
/****************************************************************************
*                              GLOBAL DEFINES
*****************************************************************************/

typedef enum {
	ERR_ALLOK					=			0,
	ERR_PARAMETER_INVALID 		=			-2,
	ERR_NETWORK_ERROR			=			-23
} RESULT_T;

#define ERR_ALLOK 											0
#define ERR_PARAMETER_INVALID 							-2
#define ERR_MEDIUM_ERROR										-3
#define ERR_FILE_ERROR											-4
#define ERR_DATA_INVALID										-5
#define ERR_NOT_FOUND												-6
#define ERR_EOF															-7
#define ERR_BUFFER_UNDERRUN									-8
#define ERR_VERIFY_FAILED										-9
#define ERR_OUT_OF_MEMORY										-10
#define ERR_OUT_OF_RANGE										-11
#define ERR_CONGESTION											-12
#define ERR_HARDWARE_PROBLEM								-13
#define ERR_NOT_SUPPORTED										-14
#define ERR_NULLPOINTER_EXCEPTION           -15
#define ERR_REALLOC_ERROR                   -16
#define ERR_TIMEOUT_TRIGGERED               -17
#define ERR_ALLOC_ERROR                     -18
#define ERR_NEED_MORE                       -19 /* I need more data, quick! */
#define ERR_WRITE_PROTECTION                -20
#define ERR_RESOURCE_BUSY                   -21
#define ERR_BUFFER_OVERRUN                  -22
#define ERR_NETWORK_ERROR					-23

/* from -128 codes are application specific */

#define ERR_APP_RESULT_1										-100
#define ERR_APP_RESULT_2										-101
#define ERR_APP_RESULT_3										-102
#define ERR_APP_RESULT_4										-103
#define ERR_APP_RESULT_5										-104

/****************************************************************************
*                              MACROS
*****************************************************************************/

/****************************************************************************
*                              GLOBAL VARIABLES
*****************************************************************************/

/****************************************************************************
*                            FUNCTION PROTOTYPES
*****************************************************************************/

#endif //SysErrCodes_H
/*** EOF ***/
