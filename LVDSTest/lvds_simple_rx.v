//////////////////////////////////////////////////////////////////////////////////
// 
// Design Name: RASM2400
// Module Name: LVDS_RX
// Project Name: Radio Access Spectrum Monitor 2400MHz
// Engineer: Tobias Weber
// Target Devices: Artix 7, XC7A100T
// Create Date: 25.04.2024 10:29:54
// Tool Versions: Vivado 2024.1
// Description:  Receives and deserializes sample data coming from
//               the ADC via 2x2 LVDS data lines.
// 
// Dependencies: none
// 
// Revision 1.01
// Additional Comments: https://github.com/Tobias-DG3YEV/RA-Sentinel
// 
//////////////////////////////////////////////////////////////////////////////////
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
//////////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps

/* this depicts the input data stream we get from the ADC322x
				  _________         ___
Frame FCLK		_|        |________|
                  ______      ___
Data			_|     |_____|  |______
				   ___   ___   ___   __
Data DCLK		__|  |__|  |__|  |__|  
Bit #			  0  1  2  3  4  5  0  
Value (LSB first) 1  1  0  0  1  0  0 => reversed to 10011 = 13 hex.
*/

//`define USE_BITCLKDLY
`define USE_FRAMECLKDLY

module lvds_rx #(
	parameter WORD_WIDTH = 12 //sample width in bits
)
(
    input wire i_lvds_dclk_P, // 120/60 MHz
    input wire i_lvds_dclk_N, // 120/60 MHz
    input wire i_lvds_fclk_P, // 40/20 MHz
    input wire i_lvds_fclk_N, // 40/20 MHz
    input wire i_lvds_di_P,  // data lane 0 in-phase (real) part
    input wire i_lvds_di_N,  // data lane 0 in-phase (real) part
    input wire i_lvds_dq_P,  // data lane 0 quadrature (imaginary) part
    input wire i_lvds_dq_N,  // data lane 0 quadrature (imaginary) part
    input wire i_masterClk,   // master clock for strobe generation. Valid at rising edge.
	input wire i_rst,       // module reset, active high
	input wire i_delayClk,  // 195-200MHz Delay Clock
    input wire [3:0] i_frameShift, // between 0 and 5
    output wire o_parFrameRdy, // parallel frame is ready when this goes high.
    output reg o_sampleStrobe, // parallel frame is ready when this goes high.
    output wire [11:0] o_dataOut_I,  // parallel data, real part
    output wire [11:0] o_dataOut_Q,   // parallel data, imaginary part
    output wire o_lvds_idat,
    output wire o_lvds_qdat,
    output wire o_lvds_dclk,
    output wire o_lvds_fclk
);


/*********************************************************************************
*
     #####   #######  #     #   #####   #######     #     #     #  #######   #####
    #     #  #     #  ##    #  #     #     #       # #    ##    #     #     #     #
    #        #     #  # #   #  #           #      #   #   # #   #     #     #
    #        #     #  #  #  #   #####      #     #     #  #  #  #     #      #####
    #        #     #  #   # #        #     #     #######  #   # #     #           #
    #     #  #     #  #    ##  #     #     #     #     #  #    ##     #     #     #
     #####   #######  #     #   #####      #     #     #  #     #     #      #####
*/

localparam C_DLYTYPE = "FIXED";
localparam C_IODELAY_GROUP = "adc_if_delay_group";
localparam C_IODELAY_MASTERCLOCK = 195; /* MHz */


`ifdef SIMULATION
localparam INIT_DELAY_POR = 72; /* number of cycles the Init waits to release the serdes reset*/
localparam INIT_DELAY_CS  = 4; /* number of cycles the Init waits to enable serdes CS */
localparam DELAY_VALUE_DCLK_P = 0; /* bit clock line delay */
localparam DELAY_VALUE_DCLK_N = 0;
localparam DELAY_VALUE_FCLK_P = 0; /* frame line delay */
localparam DELAY_VALUE_FCLK_N = 0;
localparam DELAY_VALUE_DI = 0; /* data line delay */
localparam DELAY_VALUE_DQ = 0;
`else
localparam INIT_DELAY_POR = 2048; /* number of cycles the Init waits to start the serdes */
localparam INIT_DELAY_CS  = 4; /* number of cycles the Init waits to enable serdes CS */
localparam DELAY_VALUE_DCLK_P = 0; /* bit clock line delay */
localparam DELAY_VALUE_DCLK_N = 0;
localparam DELAY_VALUE_FCLK_P = 10; /* frame line delay */
localparam DELAY_VALUE_FCLK_N = 10;
localparam DELAY_VALUE_DI = 26; /* data line delay */
localparam DELAY_VALUE_DQ = 26;
`endif

/**********************/
/*    Delay Control   */
/**********************/

IDELAYCTRL IDELAYCTRL_LVDS (
   .RDY(),       // 1-bit output: Ready output
   .REFCLK(i_delayClk), // 1-bit input: Reference clock input
   .RST(i_rst)        // 1-bit input: Active high reset input
);


/****************************************************************************/
//
//    #######  ######      #     #     #  #######
//    #        #     #    # #    ##   ##  #
//    #        #     #   #   #   # # # #  #
//    #####    ######   #     #  #  #  #  #####
//    #        #   #    #######  #     #  #
//    #        #    #   #     #  #     #  #
//    #        #     #  #     #  #     #  #######

wire [1:0] lvds_fclk_BUFDS;

IBUFDS_DIFF_OUT #(
    //.CAPACITANCE("DONT_CARE"),
	.DIFF_TERM("TRUE"),
	.IOSTANDARD("DEFAULT")
)  IBUFDS_adc_frame0 (
	.I(i_lvds_fclk_P),
	.IB(i_lvds_fclk_N),
	.O(lvds_fclk_BUFDS[0]), // 40/20 MHz
	.OB(lvds_fclk_BUFDS[1]) // 40/20 MHz
);

wire [1:0] fclk_delayed;

genvar f;
generate
	for (f = 0; f < 2; f = f + 1) begin : gen_fclk_idelaye2
    IDELAYE2 #(
    .CINVCTRL_SEL ("FALSE"),
    .DELAY_SRC ("IDATAIN"),
    .HIGH_PERFORMANCE_MODE ("TRUE"),
    .IDELAY_TYPE( C_DLYTYPE ),
    .IDELAY_VALUE( f==0 ? DELAY_VALUE_FCLK_P : DELAY_VALUE_FCLK_N ),
    .REFCLK_FREQUENCY( C_IODELAY_MASTERCLOCK ),
    .PIPE_SEL ("FALSE"),
    .SIGNAL_PATTERN ("CLOCK")
    )
    IDELAYE2_fclk (
    .CE ( 0 ),
    .INC( 0 ),
    .DATAIN(1'b0),
    .CINVCTRL(1'b0),
    .REGRST(1'b0),
    .C( i_delayClk ),
    .IDATAIN( lvds_fclk_BUFDS[f] ),
    .DATAOUT( fclk_delayed[f] ),
    .LD (1'b0),
    .CNTVALUEIN (1'b0),
    .CNTVALUEOUT(),
    .LDPIPEEN(1'b0) // added to keep Vivado quiet
    );
    end
endgenerate

assign o_lvds_fclk = fclk_delayed[0];

/****************************************************************************
    ######   ###  #######         #####   #        #######   #####   #    #
    #     #   #      #           #     #  #        #     #  #     #  #   #
    #     #   #      #           #        #        #     #  #        #  #
    ######    #      #           #        #        #     #  #        ###
    #     #   #      #           #        #        #     #  #        #  #
    #     #   #      #           #     #  #        #     #  #     #  #   #
    ######   ###     #            #####   #######  #######   #####   #    #
*/  

wire [1:0] lvds_dclk_BUFDS;
wire [1:0] dclk_delayed;

IBUFDS_DIFF_OUT #(
    //.CAPACITANCE("DONT_CARE"),
	.DIFF_TERM("TRUE"),
	.IOSTANDARD("DEFAULT")
)  IBUFDS_adc_dclk (
	.O(lvds_dclk_BUFDS[0]), // 120/60MHz
	.OB(lvds_dclk_BUFDS[1]), // 120/60MHz
	.I(i_lvds_dclk_P),
	.IB(i_lvds_dclk_N)
);

genvar c;
generate
	for (c = 0; c < 2; c = c + 1) begin : gen_dclk_idelaye2
/*    
		IDELAYE2 #(
			.CINVCTRL_SEL ("FALSE"),
			.DELAY_SRC ("IDATAIN"),
			.HIGH_PERFORMANCE_MODE ("TRUE"),
			.IDELAY_TYPE(C_DLYTYPE),
			.IDELAY_VALUE((c == 0) ? DELAY_VALUE_DCLK_P :	
                                     DELAY_VALUE_DCLK_N), // Specify the input delay tap setting			
			.REFCLK_FREQUENCY( C_IODELAY_MASTERCLOCK ),
			.PIPE_SEL( "FALSE" ),
			.SIGNAL_PATTERN( "DATA" )
		)
		IDELAYE2_data_inst (
			.CE (1'b0),
			.INC(0),
			.DATAIN (1'b0),
			.LDPIPEEN (1'b0),
			.CINVCTRL (1'b0),
			.REGRST (1'b0),
			.C (i_delayClk),
			.IDATAIN (lvds_dclk_BUFDS[c]),
			.DATAOUT (dclk_delayed[c]),
			.LD ("VARIABLE"),
			.CNTVALUEIN(0),
			.CNTVALUEOUT()
		);    
*/
        assign dclk_delayed[c] = lvds_dclk_BUFDS[c];
    end

endgenerate

assign o_lvds_dclk = dclk_delayed[0];

/*********************************************************
     #####   #     #  #     #   #####
    #     #   #   #   ##    #  #     #
    #          # #    # #   #  #
     #####      #     #  #  #  #
          #     #     #   # #  #
    #     #     #     #    ##  #     #
     #####      #     #     #   #####
*/

// sync states
localparam state_powerOn 	= 2'b00;
localparam state_init       = 2'b01;
localparam state_syncing 	= 2'b10;
localparam state_initdone   = 2'b11;

reg [1:0] initSM; // sync state machine counter
initial initSM = 0;
reg serdes_rst;
initial serdes_rst = 1'b1;
reg serdes_CS;
initial serdes_CS = 1'b0;
wire serdes_chipSelect;
assign serdes_chipSelect = serdes_CS;
wire serdes_reset;
assign serdes_reset = serdes_rst;
wire serdes_wordClock;
assign serdes_wordClock = fclk_delayed[0];

assign dbgFrameRdy = 0; //~serdes_wordClock;
assign o_parFrameRdy = fclk_delayed[0];
reg [15:0] initCtr;


always @(posedge fclk_shifted_1st or posedge i_rst) // 60MHz driven
begin
    if(i_rst == 1) begin
        initSM <= state_powerOn;
        serdes_rst <= 1;
        serdes_CS <= 0;
        initCtr <= 0;
    end
    // sync everything with frame start
    else begin
        case (initSM)
            state_powerOn: begin
                // first wait 1000 word cycles and a high phase of fclkuntil releasing Reset.
                if(initCtr >= (INIT_DELAY_POR + INIT_DELAY_CS)) begin
                    initSM <= state_initdone;
                end
                else if(initCtr >= INIT_DELAY_POR) begin
                    serdes_rst <= 0; // release reset
                end
                initCtr <= initCtr + 1;
            end

            state_initdone: begin
                serdes_CS <= 1;
            end
            
        endcase
    end
end 

/*
*/
/*
assign fclk_shifted_ev = fclk_delayed[1];
assign fclk_shifted_od = fclk_delayed[1];
*/

reg fclk_shifted_ev;
reg fclk_shifted_od;

reg fclk_shifted_1st;
reg fclk_shifted_2nd;


reg [3:0] bitCtr;
reg lastBit;


// sync states

always @(negedge dclk_delayed[0] or posedge i_rst) begin
    if(i_rst == 1) begin
        bitCtr <= 0;
        fclk_shifted_ev <= 0;
        fclk_shifted_od <= 0;
        lastBit <= 0;
    end
    else begin
        // sync bit counter
        if(fclk_delayed[0] == 1 && lastBit == 0) begin
            lastBit <= 1;
            bitCtr <= 0;
        end
        else if(fclk_delayed[0] == 0) begin
            lastBit <= 0;
            bitCtr <= bitCtr + 1;
        end
        else begin
            bitCtr <= bitCtr + 1;
        end
        // frame signal generator
        if(bitCtr >= i_frameShift && bitCtr <= i_frameShift+2) begin
            fclk_shifted_ev <= 1;
            fclk_shifted_od <= 1;
        end
        else begin
            fclk_shifted_ev <= 0;
            fclk_shifted_od <= 0;
        end
    end 
end

always @(negedge dclk_delayed[0] or posedge i_rst ) begin
    if(i_rst == 1) begin
        fclk_shifted_1st <= 0;
    end
    else begin
        if(bitCtr == 3 || bitCtr == 4) begin
            fclk_shifted_1st <= 1;
        end
        else begin
            fclk_shifted_1st <= 0;
        end
    end
end

always @(negedge dclk_delayed[0] or posedge i_rst ) begin
    if(i_rst == 1) begin
        fclk_shifted_2nd <= 0;
    end
    else begin
        if(bitCtr == 1 || bitCtr == 2) begin
            fclk_shifted_2nd <= 1;
        end
        else begin
            fclk_shifted_2nd <= 0;
        end
    end
end

/*
always @(posedge dclk_delayed[1] or posedge serdes_rst ) begin
    if(i_rst == 1) begin
        bitCtr <= 0;
        fclk_shifted <= 0;
    end
    else begin
        
        if(fclk_delayed[0] == 1 && bitCtr > 3) begin
            bitCtr <= 0;
        end
        else begin
            if(bitCtr == 2 || bitCtr == 3)
                fclk_shifted <= 1;
            else
                fclk_shifted <= 0;
            bitCtr <= bitCtr + 1;
        end

    end
end
*/

/****************************************************************************/
//
//	######   ######   ######          ######      #     #######     #
//	#     #  #     #  #     #         #     #    # #       #       # #
//	#     #  #     #  #     #         #     #   #   #      #      #   #
//	#     #  #     #  ######          #     #  #     #     #     #     #
//	#     #  #     #  #   #           #     #  #######     #     #######
//	#     #  #     #  #    #          #     #  #     #     #     #     #
//	######   ######   #     #         ######   #     #     #     #     #

//wire [1:0] din_p;
//wire [1:0] din_n;

// dr0   dr1,  di0,  di1
//assign din_p[0] = i_lvds_di_P;
//assign din_n[0] = i_lvds_di_N;
//assign din_p[1] = i_lvds_dq_P;
//assign din_n[1] = i_lvds_dq_N;

wire [3:0] lvds_data_BUFDS; // IP IN QP QN

// I channel 
IBUFDS_DIFF_OUT #(
    //.CAPACITANCE("DONT_CARE"),
    .DIFF_TERM("TRUE"),
    .IOSTANDARD("DEFAULT")
)  IBUFDS_idata_inst (
    .O(lvds_data_BUFDS[0]), // Buffer output
    .OB(lvds_data_BUFDS[1]), //[i*2+1]), // Buffer output
    .I(i_lvds_di_P),      // Diff_p buffer input (connect directly to top-level port)
    .IB(i_lvds_di_N)      // Diff_n buffer input (connect directly to top-level port)
);

// Q channel 
IBUFDS_DIFF_OUT #(
    //.CAPACITANCE("DONT_CARE"),
    .DIFF_TERM("TRUE"),
    .IOSTANDARD("DEFAULT")
)  IBUFDS_qdata_inst (
    .O(lvds_data_BUFDS[2]), // Buffer output
    .OB(lvds_data_BUFDS[3]), //[i*2+1]), // Buffer output
    .I(i_lvds_dq_P),      // Diff_p buffer input (connect directly to top-level port)
    .IB(i_lvds_dq_N)      // Diff_n buffer input (connect directly to top-level port)
);

wire [3:0] data_delayed; // IP IN QP QN

genvar j;
generate for (j = 0; j < 4; j = j + 1) begin : gen_data_IDELAYE2 // j is p/n
        IDELAYE2 #(
            .CINVCTRL_SEL ("FALSE"),
            .DELAY_SRC ("IDATAIN"),
            .HIGH_PERFORMANCE_MODE ("TRUE"),
            .IDELAY_TYPE( C_DLYTYPE ),
            .IDELAY_VALUE( (j < 2) ? DELAY_VALUE_DI : DELAY_VALUE_DQ ),
            .REFCLK_FREQUENCY( C_IODELAY_MASTERCLOCK ),
            .PIPE_SEL ("FALSE"),
            .SIGNAL_PATTERN ("DATA")
        )
        IDELAYE2_data_inst (
            .CE (1'b0),
            .INC(0),
            .DATAIN(1'b0),
            .LDPIPEEN(1'b0),
            .CINVCTRL(1'b0),
            .REGRST(1'b0),
            .C( i_delayClk ),
            .IDATAIN( lvds_data_BUFDS[j] ),
            .DATAOUT( data_delayed[j]    ),
            .LD("VARIABLE"),
            .CNTVALUEIN (1'b0)
            //.CNTVALUEOUT()
        );
    end
endgenerate

/*******************************************************************************
    ###   #####   #######  ######   ######   #######   #####
     #   #     #  #        #     #  #     #  #        #     #
     #   #        #        #     #  #     #  #        #
     #    #####   #####    ######   #     #  #####     #####
     #         #  #        #   #    #     #  #              #
     #   #     #  #        #    #   #     #  #        #     #
    ###   #####   #######  #     #  ######   #######   #####
*/

// Parameters for the ISERDESE2 configuration
localparam SERDES_MODE = "MASTER";
localparam DATA_RATE = "SDR";
localparam DATA_WIDTH = 6;
localparam INTERFACE_TYPE = "NETWORKING";
localparam IOBDELAY = "BOTH";

assign o_lvds_idat = data_delayed[0];
assign o_lvds_qdat = data_delayed[2];
(* keep = "true" *) wire [11:0] ev;
(* keep = "true" *) wire [11:0] od;

//wire clk_buf, clkdiv_ev_buf, clkdiv_od_buf;
//BUFG bufg_inst_ev0 (.I( fclk_shifted_ev), .O(clkdiv_ev_buf));
//BUFG bufg_inst_od0 (.I( fclk_shifted_od), .O(clkdiv_od_buf));
//assign o_sampleStrobe = fclk_shifted_ev;

//wire [1:0] shift1;
//wire [1:0] shift2;
wire [23:0] par;

genvar k;
generate
    for (k = 0; k < 2; k = k + 1) begin : gen_data_block
    ISERDESE2 #(
        .DATA_RATE("DDR"),       // Data rate (SDR or DDR)
        .DATA_WIDTH(6),     // Parallel data width (2 to 8)
        .INTERFACE_TYPE(INTERFACE_TYPE), // Interface type (NETWORKING, RETIMED)
        .NUM_CE(1),                  // Number of clock enables
        .OFB_USED("FALSE"),          // OFB usage
        .SERDES_MODE("MASTER"),   // Master or Slave mode
        .DYN_CLKDIV_INV_EN("FALSE"),
        .DYN_CLK_INV_EN("FALSE"),
        .IOBDELAY(IOBDELAY)
    ) ISERDESE2_FIRST_inst (
        .Q6(par[0+k*12]),
        .Q5(par[1+k*12]),
        .Q4(par[2+k*12]),
        .Q3(par[3+k*12]),
        .Q2(par[4+k*12]),
        .Q1(par[5+k*12]),
        .BITSLIP(1'b0),   // 1-bit input: Bitslip pin for word alignment
        .DYNCLKSEL(1'b0), // Dynamically select CLK and CLKB inversion. 
        .DYNCLKDIVSEL(1'b0), // Dynamically select CLKDIV inversion. 
        .CE1( serdes_chipSelect ),   // 1-bit input: Clock enable input
        .CE2(1'b0),         // 1-bit input: Clock enable input
        .CLK( dclk_delayed[0] ),     // 1-bit input: High-speed clock input
        .CLKB( dclk_delayed[1] ),   // 1-bit input: Inverted high-speed clock input
        .CLKDIV( fclk_shifted_1st ), // 1-bit input: Divided clock input
        .CLKDIVP( 0 ),          // 1-bit input: Phase-aligned divided clock input
        .D( 0 ), //lvds_data_BUFDS[0+k*2] ),         // 1-bit input: Serial data input
        .DDLY( data_delayed[k*2+0] ),    // 1-bit input: Delayed serial data input
        .OFB(1'b0),       // 1-bit input: Feedback path
        //.SHIFTOUT1( shift1[k] ),
        //.SHIFTOUT2( shift2[k] ),
        .RST( serdes_reset ) // 1-bit input: Reset input
    );

    ISERDESE2 #(
        .DATA_RATE("DDR"),       // Data rate (SDR or DDR)
        .DATA_WIDTH(6),     // Parallel data width (2 to 8)
        .INTERFACE_TYPE(INTERFACE_TYPE), // Interface type (NETWORKING, RETIMED)
        .NUM_CE(1),                  // Number of clock enables
        .OFB_USED("FALSE"),          // OFB usage
        .SERDES_MODE("MASTER"),   // Master or Slave mode
        .DYN_CLKDIV_INV_EN("FALSE"),
        .DYN_CLK_INV_EN("FALSE"),
        .IOBDELAY(IOBDELAY)
    ) ISERDESE2_SECOND_inst (
        .Q6(par[6+k*12]),       // 1-bit output: First parallel data output
        .Q5(par[7+k*12]),       // 1-bit output: Second parallel data output
        .Q4(par[8+k*12]),       // 1-bit output: Third parallel data output
        .Q3(par[9+k*12]),       // 1-bit output: Fourth parallel data output
        .Q2(par[10+k*12]),
        .Q1(par[11+k*12]),
        .BITSLIP(1'b0),   // 1-bit input: Bitslip pin for word alignment
        .DYNCLKSEL(1'b0), // Dynamically select CLK and CLKB inversion. 
        .DYNCLKDIVSEL(1'b0), // Dynamically select CLKDIV inversion. 
        .CE1( serdes_chipSelect ),   // 1-bit input: Clock enable input
        .CE2(1'b0),         // 1-bit input: Clock enable input
        .CLK( dclk_delayed[0] ),     // 1-bit input: High-speed clock input
        .CLKB( dclk_delayed[1] ),   // 1-bit input: Inverted high-speed clock input
        .CLKDIV( fclk_shifted_2nd ), // 1-bit input: Divided clock input
        .CLKDIVP( 0 ),          // 1-bit input: Phase-aligned divided clock input
        .D( 0 ),         // 1-bit input: Serial data input
        .DDLY( data_delayed[k*2+1] ),    // 1-bit input: Delayed serial data input
        .OFB(1'b0),       // 1-bit input: Feedback path
        .SHIFTIN1( 0 ),
        .SHIFTIN2( 0 ),
        .RST( serdes_reset ) // 1-bit input: Reset input
    );
    end
endgenerate


/*
genvar k;
generate
    for (k = 0; k < 2; k = k + 1) begin : gen_data_block
    // Instantiate ISERDESE2 EVEN
    ISERDESE2 #(
        .DATA_RATE(DATA_RATE),       // Data rate (SDR or DDR)
        .DATA_WIDTH(6),     // Parallel data width (2 to 8)
        .INTERFACE_TYPE(INTERFACE_TYPE), // Interface type (NETWORKING, RETIMED)
        .NUM_CE(1),                  // Number of clock enables
        .OFB_USED("FALSE"),          // OFB usage
        .SERDES_MODE("MASTER"),   // Master or Slave mode
        .DYN_CLKDIV_INV_EN("FALSE"),
        .DYN_CLK_INV_EN("FALSE"),
        .IOBDELAY(IOBDELAY)
    ) ISERDESE2_EVEN_inst (
        .Q6(ev[0+(k*6)]),       // 1-bit output: First parallel data output
        .Q5(ev[1+(k*6)]),       // 1-bit output: Second parallel data output
        .Q4(ev[2+(k*6)]),       // 1-bit output: Third parallel data output
        .Q3(ev[3+(k*6)]),       // 1-bit output: Fourth parallel data output
        .Q2(ev[4+(k*6)]),
        .Q1(ev[5+(k*6)]),
        .BITSLIP(1'b0),   // 1-bit input: Bitslip pin for word alignment
        .DYNCLKSEL(1'b0), // Dynamically select CLK and CLKB inversion. 
        .DYNCLKDIVSEL(1'b0), // Dynamically select CLKDIV inversion. 
        .CE1( serdes_chipSelect ),   // 1-bit input: Clock enable input
        .CE2(1'b0),         // 1-bit input: Clock enable input
        .CLK( dclk_delayed[0] ),     // 1-bit input: High-speed clock input
        //.CLKB( ),   // 1-bit input: Inverted high-speed clock input
        .CLKDIV( fclk_shifted_ev ), // 1-bit input: Divided clock input
        //.CLKDIVP( ),          // 1-bit input: Phase-aligned divided clock input
        //.D( lvds_data_BUFDS[0+k*2] ),         // 1-bit input: Serial data input
        .DDLY(data_delayed[k*2+0]),    // 1-bit input: Delayed serial data input
        .OFB(1'b0),       // 1-bit input: Feedback path
        .RST( serdes_reset ) // 1-bit input: Reset input
    );

    // Instantiate ISERDESE2 ODD
    ISERDESE2 #(
        .DATA_RATE(DATA_RATE),       // Data rate (SDR or DDR)
        .DATA_WIDTH(6),     // Parallel data width (2 to 8)
        .INTERFACE_TYPE(INTERFACE_TYPE), // Interface type (NETWORKING, RETIMED)
        .NUM_CE(1),                  // Number of clock enables
        .OFB_USED("FALSE"),          // OFB usage
        .SERDES_MODE("MASTER"),   // Master or Slave mode
        .DYN_CLKDIV_INV_EN("FALSE"),
        .DYN_CLK_INV_EN("FALSE"),
        .IOBDELAY(IOBDELAY)
    ) ISERDESE2_ODD_inst (
        .Q6(od[0+k*6]),       // 1-bit output: First parallel data output
        .Q5(od[1+k*6]),       // 1-bit output: Second parallel data output
        .Q4(od[2+k*6]),       // 1-bit output: Third parallel data output
        .Q3(od[3+k*6]),       // 1-bit output: Fourth parallel data output
        .Q2(od[4+k*6]),
        .Q1(od[5+k*6]),
        .BITSLIP(1'b0),   // 1-bit input: Bitslip pin for word alignment
        .DYNCLKSEL(1'b0), // Dynamically select CLK and CLKB inversion. 
        .DYNCLKDIVSEL(1'b0), // Dynamically select CLKDIV inversion. 
        .CE1( serdes_chipSelect ),   // 1-bit input: Clock enable input
        .CE2(1'b0),         // 1-bit input: Clock enable input
        .CLK( dclk_delayed[1] ),     // 1-bit input: High-speed clock input
        //.CLKB( ),   // 1-bit input: Inverted high-speed clock input
        .CLKDIV( fclk_shifted_ev ), // 1-bit input: Divided clock input
        //.CLKDIVP( ),          // 1-bit input: Phase-aligned divided clock input
        //.D( lvds_data_BUFDS[1+k*2] ),         // 1-bit input: Serial data input
        .DDLY(data_delayed[k*2+1]),    // 1-bit input: Delayed serial data input
        .OFB(1'b0),       // 1-bit input: Feedback path
        .RST( serdes_reset ) // 1-bit input: Reset input
    );
    end
endgenerate
*/
// Signal mapping from SERDES output to read words
//assign o_dataOut_I = { ~od[5], ev[5], ~od[4], ev[4], ~od[3], ev[3], ~od[2], ev[2], ~od[1], ev[1], ~od[0], ev[0] };
//assign o_dataOut_Q = { ~od[11], ev[11], ~od[10], ev[10], ~od[9], ev[9], ~od[8], ev[8], ~od[7], ev[7], ~od[6], ev[6] };
//assign o_dataOut_I = { ev[5], od[5], ev[4], od[4], ev[3], od[3], ev[2], od[2], ev[1], od[1], ev[0], od[0] };
//assign o_dataOut_Q = { ev[11], od[11], ev[10], od[10], ev[9], od[9], ev[8], od[8], ev[7], ~od[7], ev[6], od[6] };
assign o_dataOut_I = { ~par[11:6], par[5:0] };
assign o_dataOut_Q = { ~par[23:18], par[17:12] };

endmodule
