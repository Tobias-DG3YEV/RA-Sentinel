////////////////////////////////////////////////////////////////////////////////
//
// Project Name: RA-Sentinel
//
// Module Name: 802_11.h
//
// Engineer: Tobias Weber
// Target Devices: ST32H7
// Tool Versions: any C compiler
// Description:  Definitions of RFC 802.11 frames
//
// Fork of the openofdm project
// https://github.com/jhshi/openofdm
//
// Dependencies:
//
// Revision 1.00 - File Created
// Project: https://github.com/Tobias-DG3YEV/RA-Sentinel
//
////////////////////////////////////////////////////////////////////////////////
// Copyright (C) 2024 Tobias Weber
// License: GNU GPL v3
//
// This project is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTIBILITY or FITNESS FOR A PARTICULAR PURPOSE.
// See the GNU General Public License for more details.
//
// You should have received a copy of the GNU Lesser General Public License
// along with this program. If not, see
// <http://www.gnu.org/licenses/> for a copy.
////////////////////////////////////////////////////////////////////////////////
#ifndef __802_11_H__
#define __802_11_H__

typedef PACKED struct {
  u8 order : 1;
  u8 WEP : 1;
  u8 moreDate : 1;
  u8 powerMng : 1;
  u8 retry : 1;
  u8 moreFrag : 1;
  u8 fromDS : 1;
  u8 toDS : 1;
} DOT11_FHDR_FCTL1_T;

typedef PACKED struct {
  u8 subType : 4;
  u8 type : 2;
  u8 protoVersion : 2;
} DOT11_FHDR_FCTL0_T;


#endif //__802_11_H__
