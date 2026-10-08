////////////////////////////////////////////////////////////////////////////////
// Design Name: OWIFI_RX
// Module Name: syscfg.v
// Project Name: Radio Access Sentinel
// Engineer: Tobias Weber
// Target Devices: Artix-7 XC7A100T (RASBB U10)
// Tool Versions: Vivado 2025.2
// Description:  RA-Sentinel is a WiFi activity and threat detection platform
//
// Additional Comments: https://github.com/Tobias-DG3YEV/RA-Sentinel
//
// This project was funded through the NGI0 Entrust Fund, a fund established
// by NLnet with financial support from the European Commission's
// Next Generation Internet programme, under the aegis of DG Communications
// Networks, Content and Technology under grant agreement No 101069594.
// https://nlnet.nl/project/RA-Sentinel/
//
// SPDX-FileCopyrightText: 2024 Tobias Weber
// SPDX-License-Identifier: GPL-3.0-only
//
// This project is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
// See the GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see
// <http://www.gnu.org/licenses/> for a copy.
////////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03.07.2024 17:20:14
// Design Name: 
// Module Name: syscfg
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


//`define HAS_SIDE_CH 1
`define NO_SIDE_CH 1

//set small_fpga 1 for 7020 FPGA, set small_fpga 0 for the rest
`define SIDE_CH_LESS_BRAM 1
`define SMALL_FPGA 1
