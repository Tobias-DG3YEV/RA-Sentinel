//////////////////////////////////////////////////////////////////////////////////
//
// Design Name: OWIFI_RX
// Module Name: ant_select
// Project Name: RA-Sentinel 802.11 receiver + direction finder
// Target Devices: Artix 7, XC7A100T (RASBB U10 + RASRF2400WBMC)
// Description:
//   Antenna selection for the single decode chain: per-channel |s|^2 through a
//   leaky moving average, argmax with hysteresis. The four RASANT2400s point
//   N/E/S/W, so "strongest average power" IS the correct antenna for decoding
//   a frame from any bearing - no per-antenna frame detectors needed.
//
//   FREEZE. The selection may only move while dot11 sits in
//   S_WAIT_POWER_TRIGGER (i_freeze low). Once a frame is being received the
//   mux must hold perfectly still: switching antennas mid-frame would hand
//   the equalizer a different channel response mid-packet. The averages keep
//   updating through a freeze, so the next inter-frame gap immediately selects
//   correctly. With AVG_SHIFT=4 (~16-sample time constant = 0.8us) selection
//   settles well inside the 8us short training field, so a frame's own STF
//   pulls the mux onto the right antenna before sync_short needs it.
//
//   The averages are also the direction finder's input (o_pwr): df_frame.v
//   latches all four at the short-preamble detect and turns them into a
//   bearing. That is why they are true POWER averages (I^2+Q^2, 2 DSPs per
//   channel), not a cheaper |I|+|Q| approximation - the bearing math needs
//   honest linear power ratios.
//
//   The MAX2831 gains are fixed and equal across the aperture (front-end
//   firmware policy) - unequal gain would corrupt both the selection and the
//   bearing, so keep it that way.
//
// Dependencies: none
//
// Additional Comments: https://github.com/Tobias-DG3YEV/RA-Sentinel
//
//////////////////////////////////////////////////////////////////////////////////
// Copyright (C) 2026 Tobias Weber
// License: GNU GPL v3
//////////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps

module ant_select #(
    parameter NCH       = 4,
    parameter ADCBITS   = 12,
    parameter PWRW      = 25,  // |s|^2 max = 2*2047^2 needs 23 bits; +margin
    parameter AVG_SHIFT = 4    // leaky-average time constant, 2^N samples
)(
    input  wire                      i_clk,     // receiver domain (100MHz)
    input  wire                      i_rst,
    input  wire                      i_strobe,  // 20MHz sample strobe
    /* all channels in one word: [c*2*ADCBITS +: 2*ADCBITS] = {I, Q} of ch c */
    input  wire [NCH*2*ADCBITS-1:0]  i_iq,
    input  wire                      i_freeze,  // dot11 mid-frame: hold o_sel
    output reg  [1:0]                o_sel,
    /* per-channel averaged power, [c*PWRW +: PWRW] */
    output wire [NCH*PWRW-1:0]       o_pwr
);

/* stage 1 (on strobe): |s|^2 per channel. Registered so the DSP multipliers
   get their pipeline register; the accumulate happens on the delayed strobe. */
reg strobe_d;
always @(posedge i_clk) strobe_d <= i_rst ? 1'b0 : i_strobe;

reg  [PWRW-1:0] pwr_r [0:NCH-1];
reg  [PWRW-1:0] acc   [0:NCH-1];

genvar c;
generate for (c = 0; c < NCH; c = c + 1) begin : gen_pwr
    wire signed [ADCBITS-1:0] s_i = i_iq[c*2*ADCBITS + ADCBITS +: ADCBITS];
    wire signed [ADCBITS-1:0] s_q = i_iq[c*2*ADCBITS           +: ADCBITS];

    wire [2*ADCBITS-1:0] sq_i = s_i * s_i;   // unsigned by construction
    wire [2*ADCBITS-1:0] sq_q = s_q * s_q;

    always @(posedge i_clk) begin
        if (i_rst) begin
            pwr_r[c] <= {PWRW{1'b0}};
            acc[c]   <= {PWRW{1'b0}};
        end
        else begin
            if (i_strobe)
                pwr_r[c] <= {1'b0, sq_i} + {1'b0, sq_q};
            /* leaky average: acc += (pwr - acc) / 2^AVG_SHIFT, done as two
               unsigned shifts so no signed subtraction can underflow */
            if (strobe_d)
                acc[c] <= acc[c] - (acc[c] >> AVG_SHIFT)
                                 + (pwr_r[c] >> AVG_SHIFT);
        end
    end

    assign o_pwr[c*PWRW +: PWRW] = acc[c];
end
endgenerate

/* argmax over the four averages */
wire cmp01 = (acc[1] > acc[0]);
wire cmp23 = (acc[3] > acc[2]);
wire [1:0]      m01_i = cmp01 ? 2'd1 : 2'd0;
wire [1:0]      m23_i = cmp23 ? 2'd3 : 2'd2;
wire [PWRW-1:0] m01_v = cmp01 ? acc[1] : acc[0];
wire [PWRW-1:0] m23_v = cmp23 ? acc[3] : acc[2];
wire            cmp_f = (m23_v > m01_v);
wire [1:0]      best_i = cmp_f ? m23_i : m01_i;
wire [PWRW-1:0] best_v = cmp_f ? m23_v : m01_v;

/* Switch with hysteresis: only to a channel at least 1.5x (~1.8dB) stronger
   than the current one, and never while frozen. 1.8dB is well below the
   front-to-back ratio of the patches, so a frame from a new direction always
   clears it, while noise between two similar beams cannot flutter the mux. */
wire [PWRW-1:0] cur_v = acc[o_sel];

always @(posedge i_clk) begin
    if (i_rst)
        o_sel <= 2'd0;
    else if (strobe_d && !i_freeze && (best_i != o_sel) &&
             (best_v > cur_v + (cur_v >> 1)))
        o_sel <= best_i;
end

endmodule
