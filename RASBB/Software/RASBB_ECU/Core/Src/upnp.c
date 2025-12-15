/*CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC
 *
 *  Elektronik-idee Weber GmbH (c)
 *
 *  File: UPNP.c
 *
 *  Version 1.0
 *
 *  Project: LHB
 *
 *  Description:
 *
 *  tw@elektronik-idee.com
 *
 *  Copyright (C) 2022 - 2021 Elektronik-Idee, Tobias Weber
 *  All rights reserved, alle Rechte vorbehalten.
 *
 CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC*/

/****************************************************************************
*                              INCLUDES
*****************************************************************************/
#include "platform_types.h"
#include "SysErrCodes.h"
#include "upnp.h"
#include "lwip/opt.h"
#include "lwip/arch.h"
#include "lwip/api.h"
#include "lwip/init.h"
#include "lwip/netif.h"
#include "lwip/ip_addr.h"
#include "lwip/udp.h"
#include "lwip/igmp.h"
#include <string.h>
#include "task.h"
#include "main.h"

/****************************************************************************
*                              DEFINES
*****************************************************************************/

#define UPNP_MCAST_GRP  ("239.255.255.250")
#define UPNP_MCAST_PORT (1900)
/****************************************************************************
*                              MACROS
*****************************************************************************/
/****************************************************************************
*                              LOCAL VARIABLES
*****************************************************************************/
static const char searchReply_str_preIP[] = "HTTP/1.1 200 OK\r\n" \
  "Location: http://";

static const char searchReply_str_postIP[] = "/upnp/logw.xml\r\n" \
  "Ext:\r\n" \
  "USN: uuid:rasbb.rasentinel.12345678::upnp:rootdevice\r\n" \
  "Server: FreeRTOS Kernel " tskKERNEL_VERSION_NUMBER "\r\n" \
  "Cache-Control: max-age=60\r\n" \
  "ST: upnp:rootdevice\r\n" \
  "Content-Length: 0\r\n" \
  "\r\n";

/****************************************************************************
*                              GLOBAL VARIABLES
*****************************************************************************/

/****************************************************************************
*                              LOCAL FUNCTIONS
*****************************************************************************/

/**
  * @brief This function joins a multicast group with the specified ip/port
  * @param group_ip the specified multicast group ip
  * @param group_port the specified multicast port number
  * @param recv the lwip UDP callback
  * @retval udp_pcb* or NULL if joining failed
  */
static struct udp_pcb* mcast_join_group(const char *group_ip, uint16_t group_port, void (* recv)(void *arg, struct udp_pcb *upcb, struct pbuf *p, const ip_addr_t *addr, u16_t port))
{
    bool status = false;
    struct udp_pcb *upcb;

    printf("Joining mcast group %s:%d\n", group_ip, group_port);
    do {
        upcb = udp_new();
        if (!upcb) {
            printf("Error, udp_new failed");
            break;
        }
        udp_bind(upcb, IP4_ADDR_ANY, group_port);
        struct netif* netif = system_get_netif();
        if (!netif) {
            printf("Error, netif is null");
            break;
        }
        if (!(netif->flags & NETIF_FLAG_IGMP)) {
            netif->flags |= NETIF_FLAG_IGMP;
            igmp_start(netif);
        }
        ip4_addr_t ipgroup;
        ip4addr_aton(group_ip, &ipgroup);
        err_t err = igmp_joingroup_netif(netif, &ipgroup);
        if (ERR_OK != err) {
            printf("Failed to join multicast group: %d", err);
            break;
        }
        status = true;
    } while(0);

    if (status) {
        printf("Join success\n");
        udp_recv(upcb, recv, upcb);
    } else {
        if (upcb) {
            udp_remove(upcb);
        }
        upcb = NULL;
    }
    return upcb;
}

static void send_udp(struct udp_pcb *upcb, const ip_addr_t *addr, u16_t port)
{
    struct pbuf *p;
    char sbuf[1024];
    const ip4_addr_t *ip = netif_ip4_addr(system_get_netif());

    snprintf(sbuf, sizeof(sbuf), "%s%i.%i.%i.%i:%i%s",
    		searchReply_str_preIP,
			ip4_addr1(ip),
			ip4_addr2(ip),
			ip4_addr3(ip),
			ip4_addr4(ip),
			UPNP_PORT,
			searchReply_str_postIP
    );

    p = pbuf_alloc(PBUF_TRANSPORT, strlen(sbuf), PBUF_RAM);

    if (!p) {
        printf("Failed to allocate transport buffer\n");
    } else {
        memcpy(p->payload, sbuf, strlen(sbuf));
        err_t err = udp_sendto(upcb, p, addr, port);
        if (err < 0) {
            printf("Error sending message: %s (%d)\n", lwip_strerr(err), err);
        } else {
            printf("Sent message '%s'\n", sbuf);
        }
        pbuf_free(p);
    }
}

/**
  * @brief This function is called when an UDP datagrm has been received on the port UDP_PORT.
  * @param arg user supplied argument (udp_pcb.recv_arg)
  * @param pcb the udp_pcb which received data
  * @param p the packet buffer that was received
  * @param addr the remote IP address from which the packet was received
  * @param port the remote port from which the packet was received
  * @retval None
  */
static void receive_callback(void *arg, struct udp_pcb *upcb, struct pbuf *p, const ip_addr_t *addr, u16_t port)
{
    if (p) {
        printf("Msg received port:%d len:%d\n", port, p->len);
        uint8_t *buf = (uint8_t*) p->payload;
        printf("Msg received port:%d len:%d\nbuf: %s\n", port, p->len, buf);

        send_udp(upcb, addr, port);

        pbuf_free(p);
    }
}


/****************************************************************************
*                             GLOBAL FUNCTIONS
*****************************************************************************/

/****************************************************************************
* FUNC:		UPNP_serverInit
* PARAM:
* RET:
* DESC:		Initialises a UPNP server that listens on UDP port 1900
*****************************************************************************/
UPNP_RESULT_T UPNP_serverInit(void)
{
	/***** DEFINITION *******/
  UPNP_RESULT_T res;
  struct udp_pcb *upcb;
	/**** INITIALIZATION ****/
  res = UPNPERR_OK;
	/**** PARAMETER CHECK ***/
	/**** PROGRAM CODE ******/

  upcb = mcast_join_group(UPNP_MCAST_GRP, UPNP_MCAST_PORT, receive_callback);

  if(upcb != NULL)
  {
    res = UPNPERR_ALLOCFAILED;
  }

  return res;
}
