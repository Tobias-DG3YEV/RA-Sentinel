/*
 * RAS_protocol.h
 *
 *  Created on: Dec 6, 2025
 *      Author: tobiw
 */

#ifndef INC_RAS_PROTOCOL_H_
#define INC_RAS_PROTOCOL_H_

#include "platform_types.h"


typedef union {
    u8 byte;           // Access the whole byte
    struct {
        u8 tracked : 1;   // is tracked, means meta data is forwarded oder network
        u8 fingerp: 1;   // is fingerprinted
        u8 tagged : 1;   // is tagged (for later use)
        u8 susp : 1; //this node triggered an alarm, hence tagged as suspicious
    } bits;
} RAS_SUSBECT_CFG_T; // RAS suspect configuration

typedef struct {
	u8 addr[6]; // MAC address of the WiFi device received
} RAS_SUSPECT_MAC_T;

typedef struct {
	u32 patternID; //internal ID created by timestamp to identify recurring occurance when MAC is obfuscated
	RAS_SUSPECT_MAC_T MAC; // MAC address of the WiFi device received
	u32 ts; //UNIX timestamp of arrival
	u32 fts; //fine timestamp of arrival, granularity 1s/fts
	u8 ant; //Antenna that received this frame (0 to 3)
	u8 rssi; //RSSI in negative value 100 = -100dBm
	u8 dir; //direction from where the MAC is received
	u8 dtThrs; //Detection threshold
	RAS_SUSBECT_CFG_T cfg; // configuration what to do with the suspected
} RAS_SUSPECT_T;


#endif /* INC_RAS_PROTOCOL_H_ */
