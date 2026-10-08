/*CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC

 Design Name: RASBB_ECU
 Module Name: syscfg.c
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
#include "main.h"
#include "lwip/opt.h"
#include "lwip/arch.h"
#include "lwip/api.h"
#include "lwip/netif.h"
#include "lwip/ip_addr.h"
#include "syscfg.h"
#include "webpage.h"

#include <string.h>
#include <stdio.h>

/****************************************************************************
*                              DEFINES
*****************************************************************************/
extern struct netif gnetif;

/****************************************************************************
*                              MACROS
*****************************************************************************/
/****************************************************************************
*                              LOCAL VARIABLES
*****************************************************************************/

// Helper function to generate IP address input fields
static int wp_generate_ip_field(char *ptr, const char *param_prefix, u32 ip0, u32 ip1, u32 ip2, u32 ip3) {
    return sprintf(ptr,
        "<input type=\"number\" name=\"%s0\" value=\"%u\" min=\"0\" max=\"255\" style=\"width:50px;\">."
        "<input type=\"number\" name=\"%s1\" value=\"%u\" min=\"0\" max=\"255\" style=\"width:50px;\">."
        "<input type=\"number\" name=\"%s2\" value=\"%u\" min=\"0\" max=\"255\" style=\"width:50px;\">."
        "<input type=\"number\" name=\"%s3\" value=\"%u\" min=\"0\" max=\"255\" style=\"width:50px;\">",
        param_prefix, ip0, param_prefix, ip1, param_prefix, ip2, param_prefix, ip3);
}

// Helper function to generate table row start
/****************************************************************************
* FUNC:
* PARAM:
* RET:
* DESC:
*****************************************************************************/
static int wp_table_row_start(char *ptr, const char *label)
{
    return sprintf(ptr, "<tr><td>%s</td><td>", label);
}

// Helper function to generate table row end
/****************************************************************************
* FUNC:
* PARAM:
* RET:
* DESC:
*****************************************************************************/
static int wp_table_row_end(char *ptr)
{
    return sprintf(ptr, "</td></tr>\r\n");
}


// Main configuration page generator
/****************************************************************************
* FUNC:
* PARAM:
* RET:
* DESC:
*****************************************************************************/
void WP_generate_syscfg_edit(const char* pURL, char *buffer, size_t bufsize)
{
    char *ptr = buffer;
    int len;
    int is_update = 0;

    // Current values
    const ip4_addr_t *ip = netif_ip4_addr(&gnetif);
    const ip4_addr_t *netmask = netif_ip4_netmask(&gnetif);
    const ip4_addr_t *gw = netif_ip4_gw(&gnetif);
    u8 mac[6];
    memcpy(mac, gnetif.hwaddr, 6);

    u32 ip0 = ip4_addr1(ip), ip1 = ip4_addr2(ip), ip2 = ip4_addr3(ip), ip3 = ip4_addr4(ip);
    u32 nm0 = ip4_addr1(netmask), nm1 = ip4_addr2(netmask), nm2 = ip4_addr3(netmask), nm3 = ip4_addr4(netmask);
    u32 gw0 = ip4_addr1(gw), gw1 = ip4_addr2(gw), gw2 = ip4_addr3(gw), gw3 = ip4_addr4(gw);

    // IDS Host IP
    u32 ids0 = ip4_addr1(&SYSCFG_getCfg()->hostip), ids1 = ip4_addr2(&SYSCFG_getCfg()->hostip);
    u32 ids2 = ip4_addr3(&SYSCFG_getCfg()->hostip), ids3 = ip4_addr4(&SYSCFG_getCfg()->hostip);

    // Check if this is an update request
    if (strstr(pURL, "ip0=") != NULL) {
        is_update = 1;

        u32 new_ip0, new_ip1, new_ip2, new_ip3;
        u32 new_nm0, new_nm1, new_nm2, new_nm3;
        u32 new_gw0, new_gw1, new_gw2, new_gw3;
        u32 new_ids0, new_ids1, new_ids2, new_ids3;

        // Parse IP address
        if (WP_get_query_param_u32(pURL, "ip0", &new_ip0) &&
            WP_get_query_param_u32(pURL, "ip1", &new_ip1) &&
            WP_get_query_param_u32(pURL, "ip2", &new_ip2) &&
            WP_get_query_param_u32(pURL, "ip3", &new_ip3)) {
            ip4_addr_t new_ip;
            IP4_ADDR(&new_ip, new_ip0, new_ip1, new_ip2, new_ip3);
            netif_set_ipaddr(&gnetif, &new_ip);
            ip0 = new_ip0; ip1 = new_ip1; ip2 = new_ip2; ip3 = new_ip3;
        }

        // Parse Netmask
        if (WP_get_query_param_u32(pURL, "nm0", &new_nm0) &&
            WP_get_query_param_u32(pURL, "nm1", &new_nm1) &&
            WP_get_query_param_u32(pURL, "nm2", &new_nm2) &&
            WP_get_query_param_u32(pURL, "nm3", &new_nm3)) {
            ip4_addr_t new_netmask;
            IP4_ADDR(&new_netmask, new_nm0, new_nm1, new_nm2, new_nm3);
            netif_set_netmask(&gnetif, &new_netmask);
            nm0 = new_nm0; nm1 = new_nm1; nm2 = new_nm2; nm3 = new_nm3;
        }

        // Parse Gateway
        if (WP_get_query_param_u32(pURL, "gw0", &new_gw0) &&
            WP_get_query_param_u32(pURL, "gw1", &new_gw1) &&
            WP_get_query_param_u32(pURL, "gw2", &new_gw2) &&
            WP_get_query_param_u32(pURL, "gw3", &new_gw3)) {
            ip4_addr_t new_gateway;
            IP4_ADDR(&new_gateway, new_gw0, new_gw1, new_gw2, new_gw3);
            netif_set_gw(&gnetif, &new_gateway);
            gw0 = new_gw0; gw1 = new_gw1; gw2 = new_gw2; gw3 = new_gw3;
        }

        // Parse IDS Host IP
        if (WP_get_query_param_u32(pURL, "ids0", &new_ids0) &&
            WP_get_query_param_u32(pURL, "ids1", &new_ids1) &&
            WP_get_query_param_u32(pURL, "ids2", &new_ids2) &&
            WP_get_query_param_u32(pURL, "ids3", &new_ids3)) {
            IP4_ADDR(&SYSCFG_getCfg()->hostip, new_ids0, new_ids1, new_ids2, new_ids3);
            ids0 = new_ids0; ids1 = new_ids1; ids2 = new_ids2; ids3 = new_ids3;
        }

        // MAC address parsing removed - read-only field
    }

    // Calculate uptime
    u32 uptime_ms = HAL_GetTick();
    u32 uptime_sec = uptime_ms / 1000;
    u32 days = uptime_sec / 86400;
    u32 hours = (uptime_sec % 86400) / 3600;
    u32 minutes = (uptime_sec % 3600) / 60;
    u32 seconds = uptime_sec % 60;

    // Add CSS styles at the beginning
    len = WP_add_table_styles(ptr);
    ptr += len;

    // Generate HTML response
    len = sprintf(ptr, "<h2>System Configuration</h2>\r\n");
    ptr += len;

    // Show update confirmation
    if (is_update) {
        len = sprintf(ptr, "<p style=\"color:green;\"><b>Configuration updated successfully!</b></p>\r\n");
        ptr += len;
    }

    // System uptime (read-only) - using CSS styling
    len = sprintf(ptr,
        "<h3>System Status</h3>\r\n"
        "<table>\r\n"
        "<tr><th>Parameter</th><th>Value</th></tr>\r\n"
        "<tr><td>System Uptime</td><td>%u days, %02u:%02u:%02u</td></tr>\r\n"
        "<tr><td>Firmware Version</td><td>%s</td></tr>\r\n"
        "<tr><td>FreeRTOS Version</td><td>%s</td></tr>\r\n"
        "<tr><td>MAC Address</td><td>%02X:%02X:%02X:%02X:%02X:%02X</td></tr>\r\n"
        "</table>\r\n",
        days, hours, minutes, seconds, FW_VERSION, tskKERNEL_VERSION_NUMBER,
        mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
    ptr += len;

    // Configuration form - using CSS styling
    len = sprintf(ptr,
        "<h3>Network Configuration</h3>\r\n"
        "<form method=\"GET\" action=\"/syscfg.html\">\r\n"
        "<table>\r\n");
    ptr += len;

    // IP Address
    len = wp_table_row_start(ptr, "IP Address");
    ptr += len;
    len = wp_generate_ip_field(ptr, "ip", ip0, ip1, ip2, ip3);
    ptr += len;
    len = wp_table_row_end(ptr);
    ptr += len;

    // Netmask
    len = wp_table_row_start(ptr, "Netmask");
    ptr += len;
    len = wp_generate_ip_field(ptr, "nm", nm0, nm1, nm2, nm3);
    ptr += len;
    len = wp_table_row_end(ptr);
    ptr += len;

    // Gateway
    len = wp_table_row_start(ptr, "Gateway");
    ptr += len;
    len = wp_generate_ip_field(ptr, "gw", gw0, gw1, gw2, gw3);
    ptr += len;
    len = wp_table_row_end(ptr);
    ptr += len;

    // IDS Host
    len = wp_table_row_start(ptr, "IDS Host");
    ptr += len;
    len = wp_generate_ip_field(ptr, "ids", ids0, ids1, ids2, ids3);
    ptr += len;
    len = wp_table_row_end(ptr);
    ptr += len;

    // Save button
    len = sprintf(ptr,
        "</table>\r\n"
        "<p><input type=\"submit\" value=\"Save Configuration\" style=\"padding:8px 20px;font-size:14px;\"></p>\r\n"
        "</form>\r\n");
    ptr += len;

    // Warning note
    sprintf(ptr, "<p style=\"color:red;\"><b>Note:</b> Changing IP/Netmask/Gateway may require device restart.</p>\r\n");
}

// RAS Configuration page generator
/****************************************************************************
* FUNC:
* PARAM:
* RET:
* DESC:
*****************************************************************************/
void WP_generate_rascfg_edit(const char* pURL, char *buffer, size_t bufsize)
{
    char *ptr = buffer;
    int len;
    int is_update = 0;

    // Current values
    u32 sptTO = SYSCFG_getCfg()->sptTO;
    u8 wlanCh = SYSCFG_getCfg()->wlanCh;

    // Check if this is an update request
    if (strstr(pURL, "sptTO=") != NULL || strstr(pURL, "channel=") != NULL) {
        is_update = 1;

        u32 new_sptTO;
        u32 new_channel;

        // Parse Suspicious Timeout
        if (WP_get_query_param_u32(pURL, "sptTO", &new_sptTO)) {
            SYSCFG_getCfg()->sptTO = new_sptTO;
            sptTO = new_sptTO;
        }

        // Parse WiFi Channel
        if (WP_get_query_param_u32(pURL, "channel", &new_channel)) {
            if (new_channel >= 1 && new_channel <= 13) {
                SYSCFG_getCfg()->wlanCh = (u8)new_channel;
                wlanCh = (u8)new_channel;
            }
        }
    }

    // Add CSS styles once at the beginning
    len = WP_add_table_styles(ptr);
    ptr += len;

    // Generate HTML response
    len = sprintf(ptr, "<h2>RAS Configuration</h2>\r\n");
    ptr += len;

    // Show update confirmation
    if (is_update) {
        len = sprintf(ptr, "<p style=\"color:green;\"><b>Configuration updated successfully!</b></p>\r\n");
        ptr += len;
    }

    // Configuration form - simplified without inline styles
    len = sprintf(ptr,
        "<h3>RAS Parameters</h3>\r\n"
        "<form method=\"GET\" action=\"/rascfg.html\">\r\n"
        "<table>\r\n"
        "<tr><th>Parameter</th><th>Value</th></tr>\r\n");
    ptr += len;

    // Suspicious Timeout
    len = sprintf(ptr,
        "<tr><td>Suspicious Timeout (ms)</td>"
        "<td><input type=\"text\" name=\"sptTO\" value=\"%u\" style=\"width:150px;\"></td></tr>\r\n",
        sptTO);
    ptr += len;

    // WiFi Channel
    len = sprintf(ptr, "<tr><td>WiFi Channel</td><td><select name=\"channel\" style=\"width:200px;\">");
    ptr += len;

    for (u8 ch = 1; ch <= 13; ch++) {
        len = sprintf(ptr, "<option value=\"%u\"%s>Ch %u (%u MHz)</option>",
            ch, (ch == wlanCh) ? " selected" : "", ch, 2407 + (ch * 5));
        ptr += len;
    }

    len = sprintf(ptr, "</select></td></tr>\r\n");
    ptr += len;

    // Save button
    len = sprintf(ptr,
        "</table>\r\n"
        "<p><input type=\"submit\" value=\"Save Configuration\" style=\"padding:8px 20px;font-size:14px;\"></p>\r\n"
        "</form>\r\n");
    ptr += len;

    // Info note
    sprintf(ptr, "<p style=\"color:blue;\"><b>Note:</b> Changes take effect immediately.</p>\r\n");
}


