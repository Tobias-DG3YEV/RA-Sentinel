/*HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH
 *
 *  Elektronik-idee Weber GmbH (c);
 *
 *  File: upnp.h
 *
 *  Version 1.0
 *
 *  Project: LHB
 *
 *  Description: implementation of the UPNP protocol
 *
 *  tw@elektronik-idee.com
 *
 *  Copyright (C) 2022 - 2022 Elektronik-Idee, Tobias Weber
 *  All rights reserved, alle Rechte vorbehalten.
 *
 HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH*/

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
