//////////////////////////////////////////////////////////////////////////////////^M
// ^M
// Project Name: RA-Sentinel^M
// ^M
// Module Name: glbl^M
//^M
// Engineer: Tobias Weber^M
// Target Devices: Artix 7, XC7A100T^M
// Tool Versions: Vivado 2024.1^M
// Description:
// ^M
// Dependencies:
// ^M
// Funded by NGI0 Entrust nlnet foundation
// https://nlnet.nl/project/RA-Sentinel/
//
// Revision 1.00 - File Created^M
//
// Project: https://github.com/Tobias-DG3YEV/RA-Sentinel^M
//////////////////////////////////////////////////////////////////////////////////^M
// Copyright (C) 2024 Tobias Weber^M
// License: GNU GPL v3^M
//^M
// This project is distributed in the hope that it will be useful,^M
// but WITHOUT ANY WARRANTY; without even the implied warranty of^M
// MERCHANTIBILITY or FITNESS FOR A PARTICULAR PURPOSE.^M
// See the GNU General Public License for more details.^M
// ^M
// You should have received a copy of the GNU Lesser General Public License^M
// along with this program. If not, see^M
// <http://www.gnu.org/licenses/> for a copy.^M
//////////////////////////////////////////////////////////////////////////////////^M

module glbl ();

    parameter ROC_WIDTH = 100000;
    parameter TOC_WIDTH = 0;

//--------   JTAG Globals --------------
    wire GSR;
    wire GTS;
    wire PRLD;
    tri1 p_up_tmp;
    tri (weak1, strong0) PLL_LOCKG = p_up_tmp;

    wire PROGB_GLBL;
    wire CCLKO_GLBL;
    wire FCSBO_GLBL;
    wire [3:0] DO_GLBL;
    wire [3:0] DI_GLBL;
   
    reg GSR_int;
    reg GTS_int;
    reg PRLD_int;

//--------   JTAG Instantiation --------------
    assign (strong1, weak0) GSR = GSR_int;
    assign (strong1, weak0) GTS = GTS_int;
    assign (weak1, weak0) PRLD = PRLD_int;

    initial begin
	GSR_int = 1'b1;
	PRLD_int = 1'b1;
	#(ROC_WIDTH)
	GSR_int = 1'b0;
	PRLD_int = 1'b0;
    end

    initial begin
	GTS_int = 1'b1;
	#(TOC_WIDTH)
	GTS_int = 1'b0;
    end

endmodule
