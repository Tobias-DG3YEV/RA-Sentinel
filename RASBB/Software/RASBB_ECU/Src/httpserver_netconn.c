/**
  ******************************************************************************
  * @file    LwIP/LwIP_HTTP_Server_Netconn_RTOS/Src/httpser-netconn.c
  * @author  MCD Application Team
  * @brief   Basic http server implementation using LwIP netconn API
  ******************************************************************************
  * @attention
  *
  * Copyright (c) 2017 STMicroelectronics.
  * All rights reserved.
  *
  * This software is licensed under terms that can be found in the LICENSE file
  * in the root directory of this software component.
  * If no LICENSE file comes with this software, it is provided AS-IS.
  *
  ******************************************************************************
  */

/* Includes ------------------------------------------------------------------*/

#include "platform_types.h"
#include "lwip/opt.h"
#include "lwip/arch.h"
#include "lwip/api.h"
#include "lwip/apps/fs.h"
#include "string.h"
#include "httpserver_netconn.h"
#include "cmsis_os.h"
#include "global_ports.h"
#include "config.h"
#include "webpage.h"

#include <stdio.h>

/* Private typedef -----------------------------------------------------------*/
/* Private define ------------------------------------------------------------*/
#define WEBSERVER_THREAD_PRIO    ( osPriorityAboveNormal )

/* Private macro -------------------------------------------------------------*/
/* Private variables ---------------------------------------------------------*/

static const char xmlInfo[] =
"HTTP/1.1 200 OK\r\n" \
"Cache-Control: max-age=120\r\n" \
"Content-Type: text/xml\r\n" \
"Mime-Version: 1.0\r\n\r\n" \
"<?xml version=\"1.0\"?>" \
"<root xmlns=\"urn:schemas-upnp-org:device-1-0\">" \
"<specVersion>" \
"<major>1</major>" \
"<minor>0</minor>" \
"</specVersion>" \
"<device>" \
"<deviceType>urn:schemas-upnp-org:device:logw:1</deviceType>" \
"<friendlyName>" DEVICE_FRIENDLYNAME "</friendlyName>" \
"<manufacturer>" MANUFACTURER "</manufacturer>" \
"<manufacturerURL>" MANUF_URL "</manufacturerURL>" \
"<modelDescription>" DEVICE_DESC "</modelDescription>" \
"<modelName>" DEVICE_NAME "</modelName>" \
"<modelNumber>2</modelNumber>" \
"<modelURL>" MODEL_URL "</modelURL>" \
"<UDN>uuid:123456789-bccb-5555-4321-0080E1700001</UDN>" \
"<serviceList>" \
"<service>" \
"<serviceType>urn:schemas-any-com:service:logw:1</serviceType>" \
"<serviceId>urn:any-com:serviceId:logw</serviceId>" \
"<controlURL>/upnp/ctrl</controlURL>" \
"<eventSubURL>/upnp/ctrl</eventSubURL>" \
"<SCPDURL>/logwSCPD.xml</SCPDURL>" \
"</service>" \
"</serviceList>" \
"<presentationURL>http://10.0.10.77:4842</presentationURL>" \
"</device>" \
"</root>" \
"";

static const char notFound_str[] = \
"HTTP/1.1 404 Not Found" \
"Date: Mon, 11 Mar 2024 23:08:10 GMT" \
"Server: Apache" \
"Content-Length: 256" \
"Keep-Alive: timeout=15, max=100" \
"Connection: Keep-Alive" \
"Content-Type: text/html; charset=iso-8859-1" \
"<html><head>" \
"<title>404 Not Found</title>" \
"</head><body>" \
"<h1>Not Found</h1>" \
"<p>The requested URL was not found on this server.</p>" \
"<hr>" \
"</body></html>" \
;

/* Private functions ---------------------------------------------------------*/

/**
  * @brief serve HTTP tcp connection
  * @param conn: pointer on connection structure
  * @retval None
  */

const char c_URL_currspt[] = "GET /currspt";
const char c_URL_editspt[] = "GET /editspt";
const char c_URL_syscfg[] = "GET /syscfg";
const char c_URL_rascfg[] = "GET /rascfg";
const char c_URL_main[] = "GET / ";

/****************************************************************************
* FUNC:
* PARAM:
* RET:		void
* DESC:
*****************************************************************************/
static void http_server_serve(struct netconn *conn)
{
  struct netbuf *inbuf;
  err_t recv_err;
  char* buf;
  u16_t buflen;
  //struct fs_file file;

  /* Read the data from the port, blocking if nothing yet there.
   We assume the request (the part we care about) is in one netbuf */
  recv_err = netconn_recv(conn, &inbuf);

  if (recv_err == ERR_OK)
  {
    if (netconn_err(conn) == ERR_OK)
    {
      netbuf_data(inbuf, (void**)&buf, &buflen);

      /* Is this an HTTP GET command? (only check the first 5 chars, since
      there are other formats for GET, and we're keeping it very simple )*/
      if ((buflen >=5) && (strncmp(buf, "GET /", 5) == 0))
      {
        if(strncmp(buf, "GET / ", 6) == 0)
        {
           /* Load dynamic page */
        	WP_sendMainPage(conn);
        }
        else if((strncmp(buf, c_URL_currspt, sizeof(c_URL_currspt)-1) == 0)) {
        	WP_sendSptPage(conn);
        }
        else if((strncmp(buf, c_URL_editspt, sizeof(c_URL_editspt)-1) == 0)) {
            WP_sendSptEditPage(&buf[sizeof(c_URL_editspt)], conn);
        }
        else if((strncmp(buf, c_URL_syscfg, sizeof(c_URL_syscfg)-1) == 0)) {
            WP_sendSyscfgEditPage(&buf[sizeof(c_URL_syscfg)], conn);
        }
        else if((strncmp(buf, c_URL_rascfg, sizeof(c_URL_rascfg)-1) == 0)) {
        	WP_sendRascfgEditPage(&buf[sizeof(c_URL_rascfg)], conn);
        }
        else if((strncmp(buf, "GET /upnp/logw.xml", 18) == 0))
        {
          /* Load XML info page */
          netconn_write(conn, xmlInfo, sizeof(xmlInfo)-1, NETCONN_NOCOPY);
        }
        else
        {
          /* Load Error page */
          netconn_write(conn, notFound_str, sizeof(notFound_str)-1, NETCONN_NOCOPY);
        }
      }
    }
  }
  /* Close the connection (server closes in HTTP) */
  netconn_close(conn);

  /* Delete the buffer (netconn_recv gives us ownership,
   so we have to make sure to deallocate the buffer) */
  netbuf_delete(inbuf);
}



/**
  * @brief  http server thread
  * @param arg: pointer on argument(not used here)
  * @retval None
  */
/****************************************************************************
* FUNC:
* PARAM:
* RET:		void
* DESC:
*****************************************************************************/
static void http_server_netconn_thread(void *arg)
{
  struct netconn *httpConn;
  struct netconn *newconn;
  err_t err;
  err_t accept_err;

  /* Create a new TCP connection handle */
  httpConn = netconn_new(NETCONN_TCP);

  if (httpConn!= NULL)
  {
    /* Bind to port 80 (HTTP) with default IP address */
    err = netconn_bind(httpConn, NULL, PORT_TCP_UPNPINFO);

    if (err == ERR_OK)
    {
      /* Put the connection into LISTEN state */
      netconn_listen(httpConn);

      while(1)
      {
        /* accept any incoming connection */
        accept_err = netconn_accept(httpConn, &newconn);
        if(accept_err == ERR_OK)
        {
          /* serve connection */
          http_server_serve(newconn);

          /* delete connection */
          netconn_delete(newconn);
        }
      }
    }
  }
}

/**
  * @brief  Initialize the HTTP server (start its thread)
  * @param  none
  * @retval None
  */
/****************************************************************************
* FUNC:
* PARAM:
* RET:		void
* DESC:
*****************************************************************************/
void http_server_netconn_init()
{
  printf("starting webserver\n");

  sys_thread_new("HTTP", http_server_netconn_thread, NULL, WEBSERVER_STACKSIZE, WEBSERVER_THREAD_PRIO);
}



