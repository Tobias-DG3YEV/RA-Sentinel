/*CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC

 Design Name: RASBB_ECU
 Module Name: webpage.c
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

#include "platform_types.h"
#include "config.h"
#include "lwip/opt.h"
#include "lwip/arch.h"
#include "lwip/api.h"
#include "lwip/apps/fs.h"
#include "string.h"
#include "httpserver_netconn.h"
#include "DPFPGA.h"
#include "lwip/netif.h"
#include "lwip/ip_addr.h"
#include "main.h"
#include "webpage.h"
#include "webpage_syscfg.h"
#include <string.h>
#include <stdio.h>

/****************************************************************************
*                              DEFINES
*****************************************************************************/
extern struct netif gnetif;

// Global or static variable for suspect timeout (in seconds)

/****************************************************************************
*                              MACROS
*****************************************************************************/
/****************************************************************************
*                              LOCAL VARIABLES
*****************************************************************************/
static const char PAGE_HEADER_PRE[] = "HTTP/1.1 200 OK\n\n<!DOCTYPE html><html>\n"
		"<head><title>" WP_TITLE "</title>\n"
		"<meta http-equiv=\"Content-Type\" content=\"text/html; charset=windows-1252\">";

static const char PAGE_HEADER_REFRESH[] = "<meta http-equiv=\"refresh\" content=\"2\">";

static const char PAGE_HEADER_POST[] = "<style =\"font-weight: normal; font-family: Verdana;\"></style></head>\n";


/* Format of dynamic web page: the page header */
static const char PAGE_START_PRE[] = \
"<body><style>body,table,input,select{font-family:Arial,sans-serif;}</style>" \
"<h4 style=\"color: rgb(51, 51, 255);\"><small style=\"font-family: Verdana;\">" \
"<small><big><big><big style=\"font-weight: bold;\"><big><strong><em>\n" \
"RA-Sentinel Config Interface - ";

static const char PAGE_START_POST[] = \
		"</em></strong></big></big></big></big></small></small></h4>" \
		"<hr style=\"width: 100%; height: 1px;\"><span style=\"font-weight: bold;\">\n" \
		"</span></small>\n";

static const char PAGE_END[] = "</body></html>\n";

static const char PAGE_LINKS[] =
	"<div style=\"padding: 10px; background-color: #f0f0f0;\">\r\n"
	"<a href=\"/\">Main</a> | \r\n"
	"<a href=\"/currspt\">Current Suspects</a> | \r\n"
	"<a href=\"/rascfg\">RA-Sentinel Config</a> | \r\n"
	"<a href=\"/syscfg\">System Config</a>\r\n"
	"</div>\r\n";


//
/****************************************************************************
* FUNC:		WP_get_query_param_u32
* PARAM:	const char *query, const char *param, u32 *value
* RET:		int - number of bytes
* DESC:		Helper function to parse query parameters
*****************************************************************************/
int WP_get_query_param_u32(const char *query, const char *param, u32 *value)
{
    char search[32];
    const char *pos;

    snprintf(search, sizeof(search), "%s=", param);
    pos = strstr(query, search);

    if (pos != NULL) {
        return sscanf(pos + strlen(search), "%u", value) == 1;
    }
    return 0;
}

int WP_add_table_styles(char *ptr)
{
    return sprintf(ptr,
        "<style>"
        "table{border:1px solid #ccc;border-collapse:collapse;}"
        "td,th{border:1px solid #ccc;padding:5px;}"
        "</style>\r\n");
}

/****************************************************************************
* FUNC:		generate_suspects_table_minimal
* PARAM:	char *buffer, size_t bufsize
* RET:		void
* DESC:		generate a minimal html table list
*****************************************************************************/
static void generate_suspects_table_minimal(char *buffer, size_t bufsize)
{
    char *ptr = buffer;
    int len;

    len = WP_add_table_styles(ptr);
    ptr += len;

    // Compact table header - added Det.Thres. column
    len = sprintf(ptr,
        "<table border=\"1\"><tr>"
        "<th>MAC</th><th>PatternID</th><th>RSSI</th><th>Ant</th><th>Dir</th><th>Last heard</th><th>Flags</th><th>Det.Thres.</th><th>Edit</th>"
        "</tr>");
    ptr += len;

    // Rows
    for (u8 i = 0; i < DPFPGA_getSptListSize(); i++) {
        RAS_SUSPECT_T *e = DPFPGA_getEntry(i);
        if (e) {
            len = sprintf(ptr,
                "<tr><td>%02X:%02X:%02X:%02X:%02X:%02X</td>"
                "<td>%u</td>"
                "<td>-%u</td>"
                "<td>%u</td>"
                "<td>%u</td>"
                "<td>%u</td>"
                "<td>%c%c%c%c</td>"
                "<td>%u%%</td>"
                "<td><a href=\"/editspt?pid=%u\">Edit</a></td></tr>",
                e->MAC.addr[0], e->MAC.addr[1], e->MAC.addr[2],
                e->MAC.addr[3], e->MAC.addr[4], e->MAC.addr[5],
                e->patternID,
                e->rssi, e->ant, e->dir, e->ts,
                e->cfg.bits.tracked ? 'T' : '-',
                e->cfg.bits.fingerp ? 'F' : '-',
                e->cfg.bits.tagged ? 'G' : '-',
                e->cfg.bits.susp ? 'S' : '-',
                e->dtThrs,
                e->patternID);
            ptr += len;
        }
    }

    // Add legend after table
    len = sprintf(ptr,
        "</table>\r\n"
        "<p><small><b>Flags Legend:</b><br>\r\n"
        "T = Tracked (metadata forwarded over network)<br>\r\n"
        "F = Fingerprinted (RF baseband signal is fingerprinted and FP data is forwarded over UDP)<br>\r\n"
        "G = Tagged (node tagged by user, e.g. for moving it up in the list)<br>\r\n"
        "S = Suspicious (node triggered an alarm, hence tagged as suspicious)</small></p>\r\n");
    ptr += len;
}


/****************************************************************************
* FUNC:		generate_suspect_edit
* PARAM:	const char* pURL, char *buffer, size_t bufsize
* RET:		void
* DESC:		generate a suspect edit mask
*****************************************************************************/
void generate_suspect_edit(const char* pURL, char *buffer, size_t bufsize)
{
    char *ptr = buffer;
    int len;
    u32 pid = 0;
    u32 tracked = 0, fingerp = 0, tagged = 0, dtThrs = 0;
    RAS_SUSPECT_T *e;
    int is_update = 0;

    // Parse PID from URL
    if (!WP_get_query_param_u32(pURL, "pid", &pid)) {
        // Redirect to suspects list if no PID
        len = sprintf(ptr,
            "<html><head>"
            "<meta http-equiv=\"refresh\" content=\"0; url=/currspt.html\">"
            "</head><body>"
            "<p>No PID specified. <a href=\"/currspt.html\">Redirecting to suspects list...</a></p>"
            "</body></html>");
        return;
    }

    // Get the entry
    e = DPFPGA_getPIDEntry((u8)pid);
    if (e == NULL) {
        sprintf(ptr, "Error: Entry not found for PID %u", pid);
        return;
    }

    // Check if this is an update request (has tracked/fingerp/tagged/dtThrs parameters)
    if (strstr(pURL, "tracked=") != NULL) {
        is_update = 1;

        // Parse the flags
        WP_get_query_param_u32(pURL, "tracked", &tracked);
        WP_get_query_param_u32(pURL, "fingerp", &fingerp);
        WP_get_query_param_u32(pURL, "tagged", &tagged);
        WP_get_query_param_u32(pURL, "dtThrs", &dtThrs);

        // Update the entry
        e->cfg.bits.tracked = (tracked != 0) ? 1 : 0;
        e->cfg.bits.fingerp = (fingerp != 0) ? 1 : 0;
        e->cfg.bits.tagged = (tagged != 0) ? 1 : 0;

        // Update detection threshold (limit to 0-100%)
        if (dtThrs > 100) dtThrs = 100;
        e->dtThrs = (u8)dtThrs;
    }

    // Generate HTML response
    len = sprintf(ptr,
        "<html><head><title>Edit Suspect</title></head><body>\r\n"
        "<h2>Edit Suspect Entry</h2>\r\n");
    ptr += len;

    // Show update confirmation if this was an update
    if (is_update) {
        len = sprintf(ptr,
            "<p style=\"color:green;\"><b>Entry updated successfully!</b></p>\r\n");
        ptr += len;
    }

    // Display entry in table - ADDED dtThrs COLUMN
    len = sprintf(ptr,
        "<table border=\"1\" cellpadding=\"5\">\r\n"
        "<tr><th>MAC</th><th>PatternID</th><th>RSSI</th><th>Ant</th><th>Dir</th><th>Time</th><th>FTS</th><th>Det.Thrs</th></tr>\r\n"
        "<tr>"
        "<td>%02X:%02X:%02X:%02X:%02X:%02X</td>"
        "<td>%u</td>"
        "<td>-%u dBm</td>"
        "<td>%u</td>"
        "<td>%u</td>"
        "<td>%u</td>"
        "<td>%u</td>"
        "<td>%u%%</td>"
        "</tr>\r\n"
        "</table>\r\n",
        e->MAC.addr[0], e->MAC.addr[1], e->MAC.addr[2],
        e->MAC.addr[3], e->MAC.addr[4], e->MAC.addr[5],
        e->patternID,
        e->rssi,
        e->ant,
        e->dir,
        e->ts,
        e->fts,
        e->dtThrs);
    ptr += len;

    // Edit form with checkboxes - ADDED dtThrs INPUT FIELD
    len = sprintf(ptr,
        "<h3>Configuration</h3>\r\n"
        "<form method=\"GET\" action=\"/editspt\">\r\n"
        "<input type=\"hidden\" name=\"pid\" value=\"%u\">\r\n"
        "<table border=\"0\">\r\n"
        "<tr><td><input type=\"checkbox\" name=\"tracked\" value=\"1\"%s></td>"
        "<td>Tracked (metadata forwarded over network)</td></tr>\r\n"
        "<tr><td><input type=\"checkbox\" name=\"fingerp\" value=\"1\"%s></td>"
        "<td>Fingerprinted</td></tr>\r\n"
        "<tr><td><input type=\"checkbox\" name=\"tagged\" value=\"1\"%s></td>"
        "<td>Tagged</td></tr>\r\n"
        "<tr><td><input type=\"number\" name=\"dtThrs\" value=\"%u\" min=\"0\" max=\"100\" style=\"width:60px;\"> %%</td>"
        "<td>Detection Threshold (0-100%%)</td></tr>\r\n"
        "</table>\r\n"
        "<p><input type=\"submit\" value=\"Update\"></p>\r\n"
        "</form>\r\n",
        e->patternID,
        e->cfg.bits.tracked ? " checked" : "",
        e->cfg.bits.fingerp ? " checked" : "",
        e->cfg.bits.tagged ? " checked" : "",
        e->dtThrs);
    ptr += len;

    // Back link
    sprintf(ptr,
        "<p><a href=\"/currspt.html\">Back to Suspects List</a></p>\r\n"
        "</body></html>\r\n");
}

/****************************************************************************
* FUNC:		sendPageHeaderAndTitle
* PARAM:	struct netconn *conn, const char *pTitle, t_BOOL bRefresh
* RET:		void
* DESC:		send the standard page header
*****************************************************************************/
static void sendPageHeaderAndTitle(struct netconn *conn, const char *pTitle, t_BOOL bRefresh)
{
	netconn_write(conn, PAGE_HEADER_PRE, strlen((char*)PAGE_HEADER_PRE), NETCONN_COPY);
	if(bRefresh) {
		netconn_write(conn, PAGE_HEADER_REFRESH, strlen((char*)PAGE_HEADER_REFRESH), NETCONN_COPY);
	}
	netconn_write(conn, PAGE_HEADER_POST, strlen((char*)PAGE_HEADER_POST), NETCONN_COPY);
	netconn_write(conn, PAGE_LINKS, strlen(PAGE_LINKS), NETCONN_COPY);
	netconn_write(conn, PAGE_START_PRE, strlen((char*)PAGE_START_PRE), NETCONN_COPY);
	netconn_write(conn, pTitle, strlen((char*)pTitle), NETCONN_COPY);
	netconn_write(conn, PAGE_START_POST, strlen((char*)PAGE_START_POST), NETCONN_COPY);
}

/****************************************************************************
* FUNC:		sendPageEnd
* PARAM:	struct netconn *conn
* RET:		void
* DESC:		send the end part of the page html page
*****************************************************************************/
static void sendPageEnd(struct netconn *conn)
{
	netconn_write(conn, PAGE_END, strlen((char*)PAGE_END), NETCONN_COPY);
}

/****************************************************************************
* FUNC:		WP_sendMainPage
* PARAM:	struct netconn *conn
* RET:		void
* DESC:		Create and send a dynamic Web Page. This page contains the list of
* 	        running tasks and the number of page hits.
*****************************************************************************/
void WP_sendMainPage(struct netconn *conn)
{
	char htmlbuf[2048];

	sprintf(htmlbuf, "<br><b>Number of WiFi Suspects received: %u</b><br>", DPFPGA_getSptCount());

	sprintf(htmlbuf, "<br><b>System Controller Status</b>");

	/* Update the hit count */
	strcat(htmlbuf, "<pre><br>Name          State  Priority  Stack   TaskID" );
	strcat(htmlbuf, "<br>---------------------------------------------<br>");

	/* The list of tasks and their status */
	osThreadList((unsigned char *)(htmlbuf + strlen(htmlbuf)));
	strcat(htmlbuf, "<br>---------------------------------------------");
	strcat(htmlbuf, "<br>B: Blocked, R: Ready, D: Deleted, S: Suspended X :Active<br>");

	/* Add IP frame statistics */
#if LWIP_STATS
	char statsbuf[128];
	sprintf(statsbuf, "<br>IP Frames - Sent: %u, Received: %u<br>",
	        (unsigned int)lwip_stats.ip.xmit,
	        (unsigned int)lwip_stats.ip.recv);
	strcat(htmlbuf, statsbuf);
#else
	strcat(htmlbuf, "<br>IP statistics not available (LWIP_STATS disabled)<br>");
#endif

	/* Send the dynamically generated page */
	sendPageHeaderAndTitle(conn, "Main Page", true);
	sendPageEnd(conn);
	netconn_write(conn, htmlbuf, strlen(htmlbuf), NETCONN_COPY);
}

/****************************************************************************
* FUNC:		WP_sendSptPage
* PARAM:	struct netconn *conn
* RET:		void
* DESC:		Send the list with received suspects
*****************************************************************************/
void WP_sendSptPage(struct netconn *conn)
{
	  portCHAR PAGE_BODY[2048];

	  sendPageHeaderAndTitle(conn, "Suspected WiFi nodes", true);


	  generate_suspects_table_minimal(PAGE_BODY, strlen(PAGE_BODY));

	  netconn_write(conn, PAGE_BODY, strlen(PAGE_BODY), NETCONN_COPY);
	  sendPageEnd(conn);
}

/****************************************************************************
* FUNC:		WP_sendSptEditPage
* PARAM:	const char *pURL, struct netconn *conn
* RET:		void
* DESC:		Send the suspect edit page
*****************************************************************************/
void WP_sendSptEditPage(const char *pURL, struct netconn *conn)
{
	  portCHAR PAGE_BODY[2048];

	  sendPageHeaderAndTitle(conn, "Edit suspected WiFi node", false);

	  generate_suspect_edit(pURL, PAGE_BODY, strlen(PAGE_BODY));
	  netconn_write(conn, PAGE_BODY, strlen(PAGE_BODY), NETCONN_COPY);
	  sendPageEnd(conn);
}

/****************************************************************************
* FUNC:		WP_sendRascfgEditPage
* PARAM:	const char *pURL, struct netconn *conn
* RET:		void
* DESC:		Send the RA-Sentinel parameter Edit page
*****************************************************************************/
void WP_sendRascfgEditPage(const char *pURL, struct netconn *conn)
{
	char htmlbuf[4000];

	sendPageHeaderAndTitle(conn, "RA-Sentinel Configuration", false);
	WP_generate_rascfg_edit(pURL, htmlbuf, strlen(htmlbuf));
	netconn_write(conn, htmlbuf, strlen(htmlbuf), NETCONN_COPY);
	sendPageEnd(conn);
}

/****************************************************************************
* FUNC:		WP_sendSyscfgEditPage
* PARAM:	const char *pURL, struct netconn *conn
* RET:		void
* DESC:		Send the System Edit page
*****************************************************************************/
void WP_sendSyscfgEditPage(const char *pURL, struct netconn *conn)
{
	char htmlbuf[4000];

	sendPageHeaderAndTitle(conn, "System Configuration", false);
	WP_generate_syscfg_edit(pURL, htmlbuf, strlen(htmlbuf));
	netconn_write(conn, htmlbuf, strlen(htmlbuf), NETCONN_COPY);
	sendPageEnd(conn);
}

