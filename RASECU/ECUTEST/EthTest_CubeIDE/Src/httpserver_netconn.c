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
#include "lwip/opt.h"
#include "lwip/arch.h"
#include "lwip/api.h"
#include "lwip/apps/fs.h"
#include "string.h"
#include "httpserver_netconn.h"
#include "cmsis_os.h"
#include "global_ports.h"

#include <stdio.h>

/* Private typedef -----------------------------------------------------------*/
/* Private define ------------------------------------------------------------*/
#define WEBSERVER_THREAD_PRIO    ( osPriorityAboveNormal )

/* Private macro -------------------------------------------------------------*/
/* Private variables ---------------------------------------------------------*/
u32_t nPageHits = 0;

/* Format of dynamic web page: the page header */
static const unsigned char PAGE_START[] = "HTTP/1.1 200 OK\n\n<!DOCTYPE html>\n" \
"<html><head><title>STM32H7xxTASKS</title>\n" \
"<meta http-equiv=\"Content-Type\" content=\"text/html; charset=windows-1252\">" \
"<meta http-equiv=\"refresh\" content=\"1\">" \
"<style =\"font-weight: normal; font-family: Verdana;\"></style>\n" \
"</head>\n" \
"<body>\n" \
"<h4 style=\"color: rgb(51, 51, 255);\"><small style=\"font-family: Verdana;\">" \
"<small><big><big><big style=\"font-weight: bold;\"><big><strong><em><span style=\"font-style: italic;\">\n" \
"STM32H7xx List of tasks and their status</span></em></strong></big></big></big></big></small></small></h4>" \
"<hr style=\"width: 100%; height: 2px;\"><span style=\"font-weight: bold;\">\n" \
"</span><span style=\"font-weight: bold;\">\n" \
"<table style=\"width: 961px; height: 30px;\" border=\"1\" cellpadding=\"2\" cellspacing=\"2\">\n" \
"<tbody>" \
"<tr>" \
"<td style=\"font-family: Verdana; font-weight: bold; font-style: italic; background-color: rgb(51, 51, 255); text-align: center;\">" \
"<small><span style=\"color: white;\">Running Task list (auto refresh)</small></td>" \
"</tr>\n" \
"</tbody>" \
"</table>" \
"<br>\n" \
"</span><span style=\"font-weight: bold;\"></span><small><span style=\"font-family: Verdana;\">Number of page hits:&nbsp;" \
"</span></small>\n" \
"</body></html>\n"
;

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
"<friendlyName>Locime Gateway</friendlyName>" \
"<manufacturer>Cartain</manufacturer>" \
"<manufacturerURL>http://www.cartain.de</manufacturerURL>" \
"<modelDescription>LOGW 2</modelDescription>" \
"<modelName>Locime LOGW</modelName>" \
"<modelNumber>2</modelNumber>" \
"<modelURL>http://www.cartain.de</modelURL>" \
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
           DynWebPage(conn);
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
void http_server_netconn_init()
{
  sys_thread_new("HTTP", http_server_netconn_thread, NULL, DEFAULT_THREAD_STACKSIZE, WEBSERVER_THREAD_PRIO);
}

/**
  * @brief  Create and send a dynamic Web Page. This page contains the list of
  *         running tasks and the number of page hits.
  * @param  conn pointer on connection structure
  * @retval None
  */
void DynWebPage(struct netconn *conn)
{
  portCHAR PAGE_BODY[512];
  portCHAR pagehits[10] = {0};

  memset(PAGE_BODY, 0,512);

  /* Update the hit count */
  nPageHits++;
  sprintf(pagehits, "%d", (int)nPageHits);
  strcat(PAGE_BODY, pagehits);
  strcat((char *)PAGE_BODY, "<pre><br>Name          State  Priority  Stack   Num" );
  strcat((char *)PAGE_BODY, "<br>---------------------------------------------<br>");

  /* The list of tasks and their status */
  osThreadList((unsigned char *)(PAGE_BODY + strlen(PAGE_BODY)));
  strcat((char *)PAGE_BODY, "<br><br>---------------------------------------------");
  strcat((char *)PAGE_BODY, "<br>B : Blocked, R : Ready, D : Deleted, S : Suspended<br>");

  /* Send the dynamically generated page */
  netconn_write(conn, PAGE_START, strlen((char*)PAGE_START), NETCONN_COPY);
  netconn_write(conn, PAGE_BODY, strlen(PAGE_BODY), NETCONN_COPY);
}


