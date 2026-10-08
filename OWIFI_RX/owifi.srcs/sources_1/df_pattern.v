//////////////////////////////////////////////////////////////////////////////////
//
// Design Name: OWIFI_RX
// Module Name: df_pattern
// Project Name: RA-Sentinel 802.11 receiver + direction finder
// Target Devices: Artix 7, XC7A100T (RASBB U10 + RASRF2400WBMC)
// Description:
//   Pattern-table bearing refinement for df_frame (2026-09-25). df_frame's
//   amplitude formula atan2(P_N - P_S, P_E - P_W) errs by up to ~45 deg on
//   the RASANT2400 carrier (front/back ratio only 1..4 dB in a room). This
//   block instead compares the frame's four normalised antenna amplitudes
//   with a MEASURED table of the array's response - one unit vector per
//   display bin (512 per turn, CCW from east, df_frame's convention), built
//   by IQCAP/iqcap_fpga_pattern.py from a tripod sweep in exactly
//   df_frame's arithmetic - and picks the bin with the largest dot product.
//
//   The search covers only +-i_halfwin bins around the formula's bearing:
//   the formula is biased but almost never lands on the wrong side, the
//   table is accurate but can confuse front and back where the array's
//   pattern repeats. Leave-one-out on the 2026-09-25 sweep, FPGA arithmetic:
//   formula median 12.0 deg / 45 % within 10 deg, table +-64 bins median
//   4.9 deg / 68 % within 10 deg, errors > 45 deg 0.4 % vs 0.6 %.
//   i_halfwin >= 255 searches the whole circle.
//
//   Inputs are df_frame's s3 values: d_c = (strongest log2q3 level) - (this
//   channel's), clamped to 63 (1 count = 0.376 dB of power). Amplitude
//   a_c = 255 * 10^(-0.376 d / 20). Score = sum_c a_c * T_c, T_c the ROM's
//   12-bit unit vector (* 4095); the first maximum (scanning upward from
//   center - halfwin) wins. One BRAM, four 8x12 multipliers, 2*halfwin+1+5
//   clocks per frame (1.3 us at 64 / 100 MHz). A new i_start restarts it.
//
// Dependencies: TABLE_FILE ($readmemh, 512 words of 48 bits {J4,J3,J2,J1})
//
// Additional Comments: https://github.com/Tobias-DG3YEV/RA-Sentinel
//
//////////////////////////////////////////////////////////////////////////////////
// Copyright (C) 2026 Tobias Weber
// License: GNU GPL v3
//////////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps

module df_pattern #(
    parameter ANGBITS    = 9,
    parameter TABLE_FILE = ""
)(
    input  wire               i_clk,
    input  wire               i_rst,
    input  wire               i_start,     // one clock: i_center valid (formula bearing done)
    input  wire [ANGBITS-1:0] i_center,
    input  wire [7:0]         i_halfwin,   // search +- this many bins; >= 255: whole circle
    input  wire [5:0]         i_d0, i_d1, i_d2, i_d3,   // normalised log differences, J1..J4
    output reg                o_valid,     // one clock
    output reg  [ANGBITS-1:0] o_bin,
    output reg  [21:0]        o_score      // best dot product (diagnostic)
);

localparam NB = 1 << ANGBITS;

/* amplitude of a normalised level: 255 * 10^(-0.376 d / 20) */
function [7:0] ampl;
    input [5:0] d;
    begin
        case (d)
            0: ampl = 8'd255; 1: ampl = 8'd244; 2: ampl = 8'd234; 3: ampl = 8'd224;
            4: ampl = 8'd214; 5: ampl = 8'd205; 6: ampl = 8'd197; 7: ampl = 8'd188;
            8: ampl = 8'd180; 9: ampl = 8'd173; 10: ampl = 8'd165; 11: ampl = 8'd158;
            12: ampl = 8'd152; 13: ampl = 8'd145; 14: ampl = 8'd139; 15: ampl = 8'd133;
            16: ampl = 8'd128; 17: ampl = 8'd122; 18: ampl = 8'd117; 19: ampl = 8'd112;
            20: ampl = 8'd107; 21: ampl = 8'd103; 22: ampl = 8'd98;  23: ampl = 8'd94;
            24: ampl = 8'd90;  25: ampl = 8'd86;  26: ampl = 8'd83;  27: ampl = 8'd79;
            28: ampl = 8'd76;  29: ampl = 8'd73;  30: ampl = 8'd70;  31: ampl = 8'd67;
            32: ampl = 8'd64;  33: ampl = 8'd61;  34: ampl = 8'd58;  35: ampl = 8'd56;
            36: ampl = 8'd54;  37: ampl = 8'd51;  38: ampl = 8'd49;  39: ampl = 8'd47;
            40: ampl = 8'd45;  41: ampl = 8'd43;  42: ampl = 8'd41;  43: ampl = 8'd40;
            44: ampl = 8'd38;  45: ampl = 8'd36;  46: ampl = 8'd35;  47: ampl = 8'd33;
            48: ampl = 8'd32;  49: ampl = 8'd31;  50: ampl = 8'd29;  51: ampl = 8'd28;
            52: ampl = 8'd27;  53: ampl = 8'd26;  54: ampl = 8'd25;  55: ampl = 8'd24;
            56: ampl = 8'd23;  57: ampl = 8'd22;  58: ampl = 8'd21;  59: ampl = 8'd20;
            60: ampl = 8'd19;  61: ampl = 8'd18;  62: ampl = 8'd17;  default: ampl = 8'd17;
        endcase
    end
endfunction

/* table ROM, synchronous read (one BRAM) */
(* rom_style = "block" *) reg [47:0] rom [0:NB-1];
integer ri;
initial begin
    for (ri = 0; ri < NB; ri = ri + 1) rom[ri] = 48'd0;
    if (TABLE_FILE != "") $readmemh(TABLE_FILE, rom);
end
reg [ANGBITS-1:0] raddr;
reg [47:0]        rq;
always @(posedge i_clk) rq <= rom[raddr];

/* search sequencer */
reg [7:0]         a0, a1, a2, a3;
reg               run;
reg [ANGBITS:0]   left;            // addresses still to issue
reg [ANGBITS-1:0] addr;
/* pipeline: issue (addr) -> rq (BRAM) -> products -> sum -> compare */
reg               v1, v2, v3;
reg [ANGBITS-1:0] k1, k2, k3;
reg [19:0]        p0, p1, p2, p3;
reg [21:0]        sum3;
reg [21:0]        best;
reg [ANGBITS-1:0] best_k;
reg               have;

wire [ANGBITS:0] span = (i_halfwin >= 8'd255) ? NB[ANGBITS:0] : {1'b0, i_halfwin, 1'b0} + 1'b1;
wire [ANGBITS-1:0] first = (i_halfwin >= 8'd255) ? {ANGBITS{1'b0}} : i_center - i_halfwin;

always @(posedge i_clk) begin
    if (i_rst) begin
        run <= 1'b0; left <= 0; v1 <= 1'b0; v2 <= 1'b0; v3 <= 1'b0; have <= 1'b0;
        o_valid <= 1'b0; o_bin <= {ANGBITS{1'b0}}; o_score <= 22'd0;
        raddr <= {ANGBITS{1'b0}}; addr <= {ANGBITS{1'b0}};
        best <= 22'd0; best_k <= {ANGBITS{1'b0}};
    end
    else begin
        o_valid <= 1'b0;

        /* stage 0: issue addresses */
        if (i_start) begin
            a0 <= ampl(i_d0); a1 <= ampl(i_d1); a2 <= ampl(i_d2); a3 <= ampl(i_d3);
            raddr <= first;
            addr  <= first;
            left  <= span;
            run   <= 1'b1;
            have  <= 1'b0;
            v1 <= 1'b0; v2 <= 1'b0; v3 <= 1'b0;     // drop a search in flight
        end
        else begin
            v1 <= run && (left != 0);
            k1 <= addr;
            if (run && left != 0) begin
                left  <= left - 1'b1;
                addr  <= addr + 1'b1;
                raddr <= addr + 1'b1;
            end

            /* stage 2: rq (addressed two clocks ago) holds the table word of k1's predecessor
               stage - k1 was issued last clock, rq now holds it */
            v2 <= v1;
            k2 <= k1;
            p0 <= a0 * rq[11:0];
            p1 <= a1 * rq[23:12];
            p2 <= a2 * rq[35:24];
            p3 <= a3 * rq[47:36];

            /* stage 3: sum */
            v3   <= v2;
            k3   <= k2;
            sum3 <= p0 + p1 + p2 + p3;

            /* stage 4: running maximum, first one wins */
            if (v3 && (!have || sum3 > best)) begin
                best   <= sum3;
                best_k <= k3;
                have   <= 1'b1;
            end

            /* done: nothing left to issue and the pipeline has drained */
            if (run && left == 0 && !v1 && !v2 && !v3) begin
                run     <= 1'b0;
                o_valid <= have;
                o_bin   <= best_k;
                o_score <= best;
            end
        end
    end
end

endmodule
