##############################################################################
# Design Name: DP_FPGA
# Module Name: DP_FPGA.xdc
# Project Name: Radio Access Sentinel
# Engineer: Tobias Weber
# Target Devices: Artix-7 XC7A100T (RASBB U11)
# Tool Versions: Vivado 2025.2
# Description:  RA-Sentinel is a WiFi activity and threat detection platform
#
# Additional Comments: https://github.com/Tobias-DG3YEV/RA-Sentinel
#
# This project was funded through the NGI0 Entrust Fund, a fund established
# by NLnet with financial support from the European Commission's
# Next Generation Internet programme, under the aegis of DG Communications
# Networks, Content and Technology under grant agreement No 101069594.
# https://nlnet.nl/project/RA-Sentinel/
#
# SPDX-FileCopyrightText: 2025 Tobias Weber
# SPDX-License-Identifier: GPL-3.0-only
#
# This project is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see
# <http://www.gnu.org/licenses/> for a copy.
##############################################################################
set_property PACKAGE_PIN E3 [get_ports i_masterClock]
set_property PACKAGE_PIN D3 [get_ports o_DEBUG_A0]
set_property IOSTANDARD LVCMOS33 [get_ports i_masterClock]
set_property IOSTANDARD LVCMOS33 [get_ports o_DEBUG_A0]

create_clock -period 20.000 -name masterClk -waveform {0.000 10.000} [get_ports -filter { NAME =~  "*" && DIRECTION == "IN" }]
create_debug_core u_ila_0 ila
set_property ALL_PROBE_SAME_MU true [get_debug_cores u_ila_0]
set_property ALL_PROBE_SAME_MU_CNT 1 [get_debug_cores u_ila_0]
set_property C_ADV_TRIGGER false [get_debug_cores u_ila_0]
set_property C_DATA_DEPTH 1024 [get_debug_cores u_ila_0]
set_property C_EN_STRG_QUAL false [get_debug_cores u_ila_0]
set_property C_INPUT_PIPE_STAGES 0 [get_debug_cores u_ila_0]
set_property C_TRIGIN_EN false [get_debug_cores u_ila_0]
set_property C_TRIGOUT_EN false [get_debug_cores u_ila_0]
set_property port_width 1 [get_debug_ports u_ila_0/clk]
connect_debug_port u_ila_0/clk [get_nets [list i_masterClock_IBUF_BUFG]]
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe0]
set_property port_width 26 [get_debug_ports u_ila_0/probe0]
connect_debug_port u_ila_0/probe0 [get_nets [list {counter_reg[0]} {counter_reg[1]} {counter_reg[2]} {counter_reg[3]} {counter_reg[4]} {counter_reg[5]} {counter_reg[6]} {counter_reg[7]} {counter_reg[8]} {counter_reg[9]} {counter_reg[10]} {counter_reg[11]} {counter_reg[12]} {counter_reg[13]} {counter_reg[14]} {counter_reg[15]} {counter_reg[16]} {counter_reg[17]} {counter_reg[18]} {counter_reg[19]} {counter_reg[20]} {counter_reg[21]} {counter_reg[22]} {counter_reg[23]} {counter_reg[24]} {counter_reg[25]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe1]
set_property port_width 1 [get_debug_ports u_ila_0/probe1]
connect_debug_port u_ila_0/probe1 [get_nets [list o_DEBUG_A0_OBUF]]
set_property C_CLK_INPUT_FREQ_HZ 300000000 [get_debug_cores dbg_hub]
set_property C_ENABLE_CLK_DIVIDER false [get_debug_cores dbg_hub]
set_property C_USER_SCAN_CHAIN 1 [get_debug_cores dbg_hub]
connect_debug_port dbg_hub/clk [get_nets i_masterClock_IBUF_BUFG]
