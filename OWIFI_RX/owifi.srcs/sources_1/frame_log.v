//////////////////////////////////////////////////////////////////////////////////
//
// Design Name: OWIFI_RX
// Module Name: frame_log
// Project Name: RA-Sentinel 802.11 receiver
// Engineer: Tobias Weber
// Target Devices: Artix 7, XC7A100T (RASBB baseboard)
// Description:
//   Live STATION LIST in text_screen's character RAM: one line per transmitter
//   MAC (SA), updated IN PLACE rather than scrolled, most recently heard
//   station always on the top row. The list holds as many stations as there
//   are screen rows below the header (MAX_STA = 46); when it is full, the
//   least recently heard station is evicted.
//
//   Admission policy - the two rules that keep the list meaningful on air:
//     * a frame whose SA is ALREADY listed updates that line and moves it to
//       the top, WHETHER OR NOT its FCS passed - a known station going red is
//       information;
//     * a frame with an UNKNOWN SA is admitted only when its FCS is OK.
//       Bad-FCS frames carry unreliable SA bytes - in this band mostly
//       11ax/VHT PPDUs decoded as garbage - and every one of them would
//       otherwise insert a phantom station and evict a real one.
//     * ACK/CTS (no address-2 field) and frames shorter than 16 bytes carry
//       no SA at all and never touch the list.
//
//   The line format is unchanged from the scrolling log:
//
//     SEQ      TIME_US  LEN  RT FCS CFO  PWR SNR LTS_CORR FC   DEST. ADDR.  SOURCE ADDR. BYTES@16
//     0000012A 0A3F91C4   1C 0B OK  -12K -35 24    12ABCD C000 0000DEADBEEF 0000C0FEBABE 99 99 ...
//
//   so every station line shows the LAST frame heard from it. SEQ is still
//   the global frame counter - a station's SEQ standing still is its "last
//   seen" tell.
//
//   FC      frame control, bytes 0-1 (type/subtype live in byte 0).
//   DA      address 1, MAC header bytes 4-9: the RECEIVER / destination.
//   SA      address 2, bytes 10-15: the TRANSMITTER / source - the list key.
//   CFO     coarse STS frequency offset in whole kHz, TRUNCATED, e.g.
//           "-64K" / " -1K" / "  0K". One atan LSB is ~6.2kHz (20e6 /
//           (512*2*pi)), so kHz is already finer than the measurement -
//           the field used to print six Hz digits, of which the last three
//           were interpolation rather than measurement. Saturates at 99K.
//           The SIGN CONVENTION (whose oscillator is high) is untested -
//           calibrate once against the generator before trusting the
//           direction; the sign is kept even when the magnitude truncates
//           to zero (" -0K") so that calibration has something to read.
//   PWR     preamble power (sync_short's 64-sample |x|^2 average) in dB
//           relative to ADC full scale. RELATIVE only - the MAX2831 gain
//           is unknown here and its RSSI pin is not digitized.
//   SNR     estimated from the SIGNAL symbol: its 48 data carriers are
//           known BPSK, so after equalization the I rail is signal and the
//           Q rail is noise; 20*log10(sum|I|/sum|Q|) in whole dB. Clamped
//           to 0..99. HT frames measure L-SIG, which is BPSK too.
//   LTS_CORR sync_long's raw correlation metric (hex) - relative sync
//           quality, only comparable against other lines.
//
//   HOW THE IN-PLACE UPDATE WORKS. Each listed station owns a fixed SLOT in
//   a private line-store BRAM; a frame renders its line ONCE into that slot
//   (the same S_CONV/S_LINE path the scrolling log used). MRU order lives in
//   a small position->-{MAC,slot} table; reordering moves 54-bit table
//   entries, never line text. A copy engine then repaints display rows
//   0..K-1 from the line store - K = hit position + 1 on an update, list
//   length on an insert - so rows below the affected range are never
//   rewritten. text_screen's scroll pointer is pinned to 0: display row and
//   character-RAM row are identical, and text_screen itself is untouched.
//
//   A worst-case repaint (new station, full list) is 46 rows x ~130 cycles
//   = ~60us. A frame completing inside that window is not listed - accepted:
//   this is a view, not a recorder, and the next frame from that station
//   repairs it. The frame BUFFER path (what the STM32 sees) is unaffected.
//
//   Everything else stays HEX on purpose. The two decimal fields share one
//   serial double-dabble converter and a log2 priority encoder (0.376 dB
//   per LSB, the RASM2400 logfn trick, cruder) - a real divider or a
//   converter per field would cost more than the rest of the block.
//
//   Columns are colour-coded: every character cell carries its own 4:4:4
//   RGB, so this block owns the colours outright and text_screen has no
//   palette. FCS and FIRST BYTES render green/red by checksum, so the
//   at-a-glance good/bad reading survives.
//
//   THE SA FIELD IS TINTED PER STATION, with a colour hashed from the last
//   four bytes of that station's MAC. It is a stable identity handle: the
//   list reorders constantly as stations transmit, and the colour is what
//   lets the eye follow one transmitter from row to row without reading
//   twelve hex digits. Only the device-specific half of the address is
//   hashed - folding in the OUI would tint every phone of one make alike.
//   MAX(R,G,B) is floored at STA_MIN_LVL so a hash can never land on a
//   near-black colour and hide a station on a black background.
//
//   Header row 0 additionally shows the converged IQ-imbalance corrector
//   coefficients WP/EG (Q1.15 hex): the adaptive canceller's steady state
//   IS the measured analog quadrature imbalance. They arrive from the ADC
//   clock domain through a plain 2FF sync - quasi-static values, a torn
//   LSB during convergence is harmless. Refreshed after every update and
//   about once a second when idle.
//
//   IT TAPS dot11's EXISTING OUTPUTS AND NOTHING ELSE. It never drives,
//   backs up or gates the receiver, the frame buffer or the SPI port, so it
//   cannot change what the STM32 sees.
//
// Dependencies: text_screen.v
//
// Additional Comments: https://github.com/Tobias-DG3YEV/RA-Sentinel
//
//////////////////////////////////////////////////////////////////////////////////
// Copyright (C) 2026 Tobias Weber
// License: GNU GPL v3
//////////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps

module frame_log #(
    parameter COLS     = 128,
    parameter ROWS     = 48,
    parameter HDR_ROWS = 2,
    parameter LINE_W   = 128,
    /* readability floor for the hashed station colour: the brightest of its
       three 4-bit channels is never allowed below this. 4'hA renders as 0xAA,
       in the same band as the fixed colours around it (grey is 0xCC), and
       lifts 1000 of the 4096 possible hashes (24%). Lower it for more
       saturation at the cost of dim lines - 4'h2 is 0x22, the darkest that is
       still legible on a black background, and lifts only 8 of 4096. */
    parameter [3:0] STA_MIN_LVL = 4'hA
)(
    input  wire        i_clk,          // receiver domain (100MHz)
    input  wire        i_rst,
    input  wire        i_us_tick,

    /* read-only taps on dot11 */
    input  wire        i_hdr_stb,
    input  wire        i_hdr_valid,
    input  wire [15:0] i_pkt_len,
    input  wire [7:0]  i_pkt_rate,
    input  wire        i_byte_stb,
    input  wire [7:0]  i_byte,
    input  wire        i_fcs_stb,
    input  wire        i_fcs_ok,
    input  wire [15:0] i_cfo_phase,    // o_phase_offset: rad/512 per sample
    input  wire        i_stf_det,      // short preamble detected
    input  wire [31:0] i_pwr,          // sync_short mag_sq_avg
    input  wire        i_lts_det,      // long preamble detected
    input  wire [31:0] i_lts_metric,
    input  wire        i_lts_metric_stb,
    input  wire [31:0] i_eq,           // equalizer out {i[15:0], q[15:0]}
    input  wire        i_eq_stb,

    /* iq_balance coefficients - ADC clock domain, 2FF-synced HERE */
    input  wire [15:0] i_iqbal_wp,
    input  wire [15:0] i_iqbal_eg,

    /* character RAM write port */
    output reg         o_wr,
    output reg  [12:0] o_wrAddr,
    output reg  [17:0] o_wrData,
    output wire [5:0]  o_topRowGray
);

localparam LOG_ROWS = ROWS - HDR_ROWS;
localparam MAX_STA  = LOG_ROWS;      // stations = rows below the header

/* line layout:
     0  .. 51   pre-rendered from `line`
     52 .. 55   FC   (bytes 0-1)      56 blank
     57 .. 68   DA   (bytes 4-9)      69 blank
     70 .. 81   SA   (bytes 10-15)    82 blank
     83 ..127   byte dump from byte 16, "XX " cells - 15 bytes fill the
                remaining 45 columns exactly.
   The three hex fields are muxed straight out of ren_bytes by column, so
   they cost a nibble mux rather than 31 more bytes of `line` register.
   NOTE the prefix used to be 55 wide; narrowing CFO from seven Hz digits to
   four kHz ones moved everything right of it three columns LEFT, which is
   why the dump now starts at 83 and gets one more byte. */
localparam PFX_W     = 52;
localparam FC_COL    = 52;
localparam DA_COL    = 57;
localparam SA_COL    = 70;
localparam PAY_COL   = 83;
localparam PAY_START = 16;   // first byte in the dump (skips FC/dur/DA/SA)
localparam PAY_N     = 31;   // bytes captured: PAY_START + 15 shown

/* Colours are 4:4:4 RGB carried in every character cell - text_screen has no
   palette left to index. These are the old 8-bit palette entries with each
   channel truncated to its top nibble; the worst shift is 0xE0 -> 0xEE, which
   is 14/255 and invisible on the monitor. */
localparam [11:0] C_GREY = 12'hCCC,   // was C8C8C8
                  C_GOOD = 12'h3F3,   // was 30FF30
                  C_BAD  = 12'hF53,   // was FF5030
                  C_HDR  = 12'h4EF,   // was 40E0FF, header/cyan
                  C_YEL  = 12'hFE4,   // was FFE040
                  C_ORN  = 12'hF92,   // was FF9020
                  C_VIO  = 12'hC7F,   // was C878FF
                  C_WHT  = 12'hFFF;

/*------------------------------------------------------------------*/
/* helpers                                                          */
/*------------------------------------------------------------------*/
function [7:0] nib;              // nibble -> ASCII hex
    input [3:0] v;
    begin
        nib = (v < 4'd10) ? (8'h30 + {4'd0, v}) : (8'h41 + {4'd0, v} - 8'd10);
    end
endfunction

/* ASCII -> character RAM word. The font holds 0x20..0x5F only, so anything
   outside that range becomes a space rather than a wrong glyph. */
function [17:0] chcell;
    input [7:0]  ascii;
    input [11:0] rgb;
    begin
        /* glyph = ascii - 0x20, a REAL subtraction. ascii[5:0] is not the same
           thing: 0x20..0x3F would map to 0x20..0x3F and 0x40..0x5F to
           0x00..0x1F, i.e. the two halves swapped, so every digit would render
           as punctuation. */
        chcell = (ascii >= 8'h20 && ascii <= 8'h5F) ?
                 {rgb, (ascii[5:0] - 6'h20)} : {rgb, 6'd0};
    end
endfunction

/* log2 in Q5.3: MSB position plus the next three bits. One LSB is 0.376dB
   of power. log2q3(0) = 0 by construction. */
function [7:0] log2q3;
    input [31:0] v;
    integer k;
    reg [4:0] p;
    reg [31:0] sh;
    begin
        p = 5'd0;
        for (k = 0; k < 32; k = k + 1)
            if (v[k]) p = k[4:0];
        sh = v << (5'd31 - p);
        log2q3 = {p, sh[30:28]};
    end
endfunction

function [7:0] bcd99;            // 0..99 -> {tens, ones} BCD
    input [6:0] v;
    reg [3:0] tens;
    reg [6:0] rem;
    begin
        tens  = v / 7'd10;
        rem   = v - {tens, 3'b0} - {1'b0, tens, 1'b0};   // v - tens*8 - tens*2
        bcd99 = {tens, rem[3:0]};
    end
endfunction

/* one double-dabble step's add-3 adjustment, all six BCD digits at once */
function [23:0] dab_adj;
    input [23:0] b;
    integer k;
    reg [3:0] d;
    begin
        for (k = 0; k < 6; k = k + 1) begin
            d = b[k*4 +: 4];
            dab_adj[k*4 +: 4] = (d >= 4'd5) ? (d + 4'd3) : d;
        end
    end
endfunction

/* column -> colour. FCS-verdict fields (FCS itself and the payload) take
   green/red so a bad frame is still spottable across the room; the SA field
   takes the station's own hashed colour, passed in because it is a property
   of the line rather than of the column. */
function [11:0] rgb_of;
    input [6:0]  ci;
    input        fcs;
    input [11:0] sta;
    begin
        if      (ci <= 7'd8)  rgb_of = C_GREY;               // SEQ
        else if (ci <= 7'd17) rgb_of = C_HDR;                // TIME_US
        else if (ci <= 7'd22) rgb_of = C_WHT;                // LEN
        else if (ci <= 7'd25) rgb_of = C_YEL;                // RT
        else if (ci <= 7'd29) rgb_of = fcs ? C_GOOD : C_BAD; // FCS
        else if (ci <= 7'd34) rgb_of = C_VIO;                // CFO
        else if (ci <= 7'd38) rgb_of = C_ORN;                // PWR
        else if (ci <= 7'd42) rgb_of = C_YEL;                // SNR
        else if (ci <= 7'd51) rgb_of = C_HDR;                // LTS_CORR
        else if (ci <= 7'd56) rgb_of = C_GREY;               // FC
        else if (ci <= 7'd69) rgb_of = C_WHT;                // DA
        else if (ci <= 7'd82) rgb_of = sta;                  // SA - per station
        else                  rgb_of = fcs ? C_GOOD : C_BAD; // byte dump
    end
endfunction

/*------------------------------------------------------------------*/
/* free-running microsecond clock                                   */
/*------------------------------------------------------------------*/
reg [31:0] us_ctr;
always @(posedge i_clk)
    if (i_rst)          us_ctr <= 32'd0;
    else if (i_us_tick) us_ctr <= us_ctr + 32'd1;

/* ~1Hz tick for the idle refresh of the IQ header field */
wire tick_1s = i_us_tick && (us_ctr[19:0] == 20'hFFFFF);

/*------------------------------------------------------------------*/
/* IQ-imbalance coefficients: 2FF from the ADC clock domain          */
/*------------------------------------------------------------------*/
(* ASYNC_REG = "true" *) reg [15:0] wp_m, wp_s, eg_m, eg_s;
always @(posedge i_clk) begin
    wp_m <= i_iqbal_wp;  wp_s <= wp_m;
    eg_m <= i_iqbal_eg;  eg_s <= eg_m;
end

/*------------------------------------------------------------------*/
/* preamble-time taps: power at STF detect, last sync_long metric,   */
/* and the SIGNAL-symbol EVM accumulators                            */
/*------------------------------------------------------------------*/
reg        stf_d, lts_d;
reg [31:0] hold_pwr, hold_lts;
reg [5:0]  eq_cnt;
reg [21:0] acc_i, acc_q;

wire signed [15:0] eq_i  = i_eq[31:16];
wire signed [15:0] eq_q  = i_eq[15:0];
wire        [15:0] abs_i = eq_i[15] ? (~eq_i + 1'b1) : eq_i;
wire        [15:0] abs_q = eq_q[15] ? (~eq_q + 1'b1) : eq_q;

always @(posedge i_clk) begin
    if (i_rst) begin
        stf_d <= 1'b0; lts_d <= 1'b0;
        hold_pwr <= 32'd0; hold_lts <= 32'd0;
        eq_cnt <= 6'd0; acc_i <= 22'd0; acc_q <= 22'd0;
    end
    else begin
        stf_d <= i_stf_det;
        lts_d <= i_lts_det;

        /* latch power AT STF detection - sync_short is reset shortly after,
           taking its moving average with it */
        if (i_stf_det && !stf_d) hold_pwr <= i_pwr;

        /* the metric stream stops once sync_long locks, so the last value
           standing is the one at the detection point */
        if (i_lts_metric_stb) hold_lts <= i_lts_metric;

        /* the equalizer emits data subcarriers only (pilots are masked), so
           the first 48 outputs after LTS lock are exactly the SIGNAL symbol */
        if (i_lts_det && !lts_d) begin
            eq_cnt <= 6'd0; acc_i <= 22'd0; acc_q <= 22'd0;
        end
        else if (i_eq_stb && eq_cnt != 6'd48) begin
            acc_i  <= acc_i + {6'd0, abs_i};
            acc_q  <= acc_q + {6'd0, abs_q};
            eq_cnt <= eq_cnt + 6'd1;
        end
    end
end

/*------------------------------------------------------------------*/
/* per-frame capture                                                */
/*------------------------------------------------------------------*/
reg [31:0]        cap_time;
reg [15:0]        cap_len;
reg [7:0]         cap_rate;
reg [PAY_N*8-1:0] cap_bytes;     // byte n lands in slot n, MSB slot = first
reg [4:0]         byte_cnt;
reg               active;
reg [31:0]        seq;
reg [15:0]        cap_cfo;
reg [31:0]        cap_pwr, cap_lts;
reg [21:0]        cap_ai, cap_aq;

always @(posedge i_clk) begin
    if (i_rst) begin
        active <= 1'b0; byte_cnt <= 5'd0; seq <= 32'd0;
        cap_bytes <= {PAY_N*8{1'b0}}; cap_time <= 32'd0;
        cap_len <= 16'd0; cap_rate <= 8'd0;
        cap_cfo <= 16'd0; cap_pwr <= 32'd0; cap_lts <= 32'd0;
        cap_ai <= 22'd0; cap_aq <= 22'd0;
    end
    else begin
        if (i_hdr_stb) begin
            active    <= i_hdr_valid;
            byte_cnt  <= 5'd0;
            cap_bytes <= {PAY_N*8{1'b0}};
            if (i_hdr_valid) begin
                cap_time <= us_ctr;
                cap_len  <= i_pkt_len;
                cap_rate <= i_pkt_rate;
                cap_cfo  <= i_cfo_phase;   // held by sync_short since STF
                cap_pwr  <= hold_pwr;
                cap_lts  <= hold_lts;
                cap_ai   <= acc_i;         // SIGNAL done long before hdr_stb
                cap_aq   <= acc_q;
            end
        end
        else if (i_byte_stb && active && byte_cnt != PAY_N[4:0]) begin
            cap_bytes[(PAY_N - 1 - byte_cnt)*8 +: 8] <= i_byte;
            byte_cnt <= byte_cnt + 5'd1;
        end
        else if (i_fcs_stb && active) begin
            active <= 1'b0;
            seq    <= seq + 32'd1;
        end
    end
end

/* admission gate, evaluated LIVE at fcs_stb: an SA exists only when 16+
   bytes arrived and the frame is not an ACK/CTS (type control, subtype D/C
   - their bytes 10..13 are the FCS, not an address). */
wire [7:0] cap_fc0      = cap_bytes[(PAY_N - 1)*8 +: 8];
wire       cap_no_addr2 = (cap_fc0[3:2] == 2'b01) &&
                          ((cap_fc0[7:4] == 4'hD) || (cap_fc0[7:4] == 4'hC));
wire       cap_has_sa   = (byte_cnt >= 5'd16) && !cap_no_addr2;

/*------------------------------------------------------------------*/
/* decimal conversion datapath (runs in S_CONV, ~23 cycles - frames  */
/* are tens of microseconds apart, so this is free time)             */
/*------------------------------------------------------------------*/
reg signed [29:0] cfo_prod;      // cap_cfo * 6217
reg               cfo_neg;
reg [19:0]        dab_bin;
reg [23:0]        dab_bcd;
reg [7:0]         pwr_l2, ai_l2, aq_l2;
reg [6:0]         pwr_db, snr_db;

/* |product| clamped to 6 digits. 6217 = 20e6 / (512 * 2pi): rad/512 per
   20MHz sample -> Hz. */
wire        cfo_neg_w = cfo_prod[29];
wire [29:0] cfo_mag   = cfo_neg_w ? (~cfo_prod + 1'b1) : cfo_prod;
wire [19:0] cfo_clamp = (cfo_mag > 30'd999999) ? 20'd999999 : cfo_mag[19:0];

/* dB below full scale: FS is a 16-bit I/Q pair, |x|^2 ~ 2^31 -> l2q3 248.
   771/2048 = 0.3765 dB per l2q3 LSB. */
wire [7:0]  fs_gap  = (pwr_l2 > 8'd248) ? 8'd0 : (8'd248 - pwr_l2);
wire [17:0] pwr_mul = fs_gap * 10'd771;

/* SNR: 20log10(sum|I|/sum|Q|) = 6.02 * (log2 I - log2 Q); 1541/2048 =
   0.7524 dB per l2q3 LSB. Negative clamps to 0, top clamps to 99. */
wire signed [8:0]  snr_diff = {1'b0, ai_l2} - {1'b0, aq_l2};
wire        [7:0]  snr_pos  = snr_diff[8] ? 8'd0 : snr_diff[7:0];
wire        [18:0] snr_mul  = snr_pos * 11'd1541;
wire        [7:0]  snr_raw  = snr_mul[18:11];

/*------------------------------------------------------------------*/
/* CFO rendering: whole kHz in a FOUR-column field.                  */
/*                                                                   */
/* The Hz magnitude is already sitting in dab_bcd as six BCD digits, */
/* so kHz is simply its top three - d5 d4 d3 - and the narrower field */
/* costs no divider and not one extra converter step. The three low  */
/* digits are just dropped.                                          */
/*                                                                   */
/* TRUNCATED, not rounded, and deliberately so: one atan LSB is      */
/* ~6.2kHz, so rounding to the nearest kHz would dress a quantity up */
/* to six times finer than its own quantisation.                     */
/*                                                                   */
/* Format is [sign][tens][ones]'K', right-aligned, the sign floating  */
/* against the first significant digit exactly as the wide Hz field  */
/* did: "-64K", " 64K", " -1K", "  5K", "  0K". Note 'K' is UPPER    */
/* case - the font is ASCII 0x20..0x5F only, and chcell turns any    */
/* character outside that range into a SPACE, so a lower-case 'k'    */
/* would silently render as a blank column.                          */
/*                                                                   */
/* The sign SURVIVES truncation to zero (-900Hz prints " -0K"). The  */
/* direction is the whole point of this field and the sign convention */
/* is still uncalibrated, so dropping it below 1kHz would hide        */
/* exactly what a calibration run against the generator needs to see. */
/*                                                                   */
/* d5 != 0 means >= 100kHz, which no longer fits three characters, so */
/* it SATURATES at 99 rather than print a narrower, wrong number.    */
/*------------------------------------------------------------------*/
wire [3:0] d5 = dab_bcd[23:20], d4 = dab_bcd[19:16], d3 = dab_bcd[15:12];

wire       khz_sat = (d5 != 4'd0);
wire [3:0] khz_t   = khz_sat ? 4'd9 : d4;      // tens of kHz
wire [3:0] khz_o   = khz_sat ? 4'd9 : d3;      // units of kHz
wire       khz_st  = (khz_t != 4'd0);          // is the tens digit significant

wire [7:0] cfo_c2 = (cfo_neg && khz_st) ? 8'h2D : 8'h20;
wire [7:0] cfo_c1 = khz_st ? nib(khz_t) : (cfo_neg ? 8'h2D : 8'h20);
wire [7:0] cfo_c0 = nib(khz_o);
wire [7:0] cfo_ck = 8'h4B;                     // 'K'

wire [7:0] pwr_bcd = bcd99(pwr_db);
wire [7:0] snr_bcd = bcd99(snr_db);

/* a function call cannot be part-selected, so the dabble adjust needs a
   named intermediate */
wire [23:0] dab_w = dab_adj(dab_bcd);

/*------------------------------------------------------------------*/
/* the rendered line prefix (columns 0..54), built in one shot       */
/*------------------------------------------------------------------*/
localparam [23:0] TXT_OK  = {8'h4F, 8'h4B, 8'h20};   // "OK "
localparam [23:0] TXT_BAD = {8'h42, 8'h41, 8'h44};   // "BAD"

reg [PFX_W*8-1:0] line;
reg [31:0]        cap_seq;
reg               cap_fcs;
reg [4:0]         cap_n;

/* LEN with its leading zeros blanked: 001C reads "  1C", 0400 reads " 400".
   The field keeps its four columns and stays RIGHT-aligned, so every column
   position in the layout table above is unchanged - only the glyphs differ.
   A digit blanks only when every digit above it is zero too, and the last
   digit never blanks, so a zero-length frame reads "   0" instead of
   disappearing into four spaces. */
wire len_z3 = (cap_len[15:12] == 4'd0);
wire len_z2 = len_z3 && (cap_len[11:8] == 4'd0);
wire len_z1 = len_z2 && (cap_len[7:4]  == 4'd0);

wire [7:0] len_c3 = len_z3 ? 8'h20 : nib(cap_len[15:12]);
wire [7:0] len_c2 = len_z2 ? 8'h20 : nib(cap_len[11:8]);
wire [7:0] len_c1 = len_z1 ? 8'h20 : nib(cap_len[7:4]);
wire [7:0] len_c0 =                  nib(cap_len[3:0]);

/* LTS_CORR, same rule over eight digits: 0012ABCD reads "  12ABCD". It is a
   RELATIVE sync-quality metric only comparable between lines, so the blanked
   zeros cost no information and the eye lands on the magnitude instead. */
wire lts_z7 = (cap_lts[31:28] == 4'd0);
wire lts_z6 = lts_z7 && (cap_lts[27:24] == 4'd0);
wire lts_z5 = lts_z6 && (cap_lts[23:20] == 4'd0);
wire lts_z4 = lts_z5 && (cap_lts[19:16] == 4'd0);
wire lts_z3 = lts_z4 && (cap_lts[15:12] == 4'd0);
wire lts_z2 = lts_z3 && (cap_lts[11:8]  == 4'd0);
wire lts_z1 = lts_z2 && (cap_lts[7:4]   == 4'd0);

wire [7:0] lts_c7 = lts_z7 ? 8'h20 : nib(cap_lts[31:28]);
wire [7:0] lts_c6 = lts_z6 ? 8'h20 : nib(cap_lts[27:24]);
wire [7:0] lts_c5 = lts_z5 ? 8'h20 : nib(cap_lts[23:20]);
wire [7:0] lts_c4 = lts_z4 ? 8'h20 : nib(cap_lts[19:16]);
wire [7:0] lts_c3 = lts_z3 ? 8'h20 : nib(cap_lts[15:12]);
wire [7:0] lts_c2 = lts_z2 ? 8'h20 : nib(cap_lts[11:8]);
wire [7:0] lts_c1 = lts_z1 ? 8'h20 : nib(cap_lts[7:4]);
wire [7:0] lts_c0 =                  nib(cap_lts[3:0]);

wire [PFX_W*8-1:0] line_next = {
    nib(cap_seq[31:28]), nib(cap_seq[27:24]), nib(cap_seq[23:20]), nib(cap_seq[19:16]),
    nib(cap_seq[15:12]), nib(cap_seq[11:8]),  nib(cap_seq[7:4]),   nib(cap_seq[3:0]),
    8'h20,
    nib(cap_time[31:28]), nib(cap_time[27:24]), nib(cap_time[23:20]),
    nib(cap_time[19:16]), nib(cap_time[15:12]), nib(cap_time[11:8]),
    nib(cap_time[7:4]),   nib(cap_time[3:0]),
    8'h20,
    len_c3, len_c2, len_c1, len_c0,
    8'h20,
    nib(cap_rate[7:4]), nib(cap_rate[3:0]),
    8'h20,
    (cap_fcs ? TXT_OK : TXT_BAD),
    8'h20,
    cfo_c2, cfo_c1, cfo_c0, cfo_ck,
    8'h20,
    8'h2D, nib(pwr_bcd[7:4]), nib(pwr_bcd[3:0]),
    8'h20,
    nib(snr_bcd[7:4]), nib(snr_bcd[3:0]), 8'h20, 8'h20,
    lts_c7, lts_c6, lts_c5, lts_c4, lts_c3, lts_c2, lts_c1, lts_c0,
    8'h20
};

/*------------------------------------------------------------------*/
/* header text - exactly COLS characters each, assembled from        */
/* explicit pieces so the column arithmetic stays checkable          */
/*------------------------------------------------------------------*/
localparam integer HW = COLS;
localparam [HW*8-1:0] HDR0 = {
    "RA-SENTINEL OWIFI_RX   802.11 STATIONS BY LAST SEEN",   // cols 0..50
    {49{8'h20}},                                 // cols 51..99
    "IQ WP:", "----",                            // cols 100..105, 106..109
    " EG:",   "----",                            // cols 110..113, 114..117
    {10{8'h20}}                                  // cols 118..127
};
/* column-exact against the layout table above: 55 + 5 + 13 + 13 + 8 = 94,
   padded to 128. */
localparam [HW*8-1:0] HDR1 = {
    "SEQ      TIME_US  LEN  RT FCS CFO  PWR SNR LTS_CORR ",     // 0..51
    "FC   ",                                                    // 52..56
    "DEST. ADDR.  ",                                            // 57..69
    "SOURCE ADDR. ",                                            // 70..82
    "BYTES@16",                                                 // 83..90
    {37{8'h20}}
};

/* the dynamic WP/EG hex digits live at these header-row-0 columns */
localparam [6:0] IQ_WP_COL = 7'd106;
localparam [6:0] IQ_EG_COL = 7'd114;

/*------------------------------------------------------------------*/
/* MRU station table: position -> {MAC, line-store slot}.            */
/* 46 x 54-bit distributed RAM, one sync write port, one async read  */
/* port whose address is muxed by state. Reordering shifts these     */
/* 54-bit entries one per cycle - line text never moves.             */
/*------------------------------------------------------------------*/
reg [53:0] tab [0:MAX_STA-1];
reg [5:0]  sta_cnt;              // valid entries, 0..MAX_STA
reg [5:0]  sp;                   // search position
reg [5:0]  si;                   // shift index
reg [5:0]  cd;                   // copy-engine display row
reg [5:0]  rows_k;               // rows to repaint this event
reg [5:0]  new_slot;             // line-store slot receiving the render
reg [5:0]  cp_slot;              // slot being copied out
reg [7:0]  cp_ci;                // copy column counter, 0..128

/*------------------------------------------------------------------*/
/* writer state machine                                             */
/*------------------------------------------------------------------*/
localparam S_FILL   = 4'd0,  S_HDR   = 4'd1,  S_IDLE  = 4'd2,  S_CONV = 4'd3,
           S_SEARCH = 4'd4,  S_EVICT = 4'd5,  S_SHIFT = 4'd6,  S_TAB0 = 4'd7,
           S_LINE   = 4'd8,  S_CSET  = 4'd9,  S_COPY  = 4'd10, S_IQ   = 4'd11;

reg [3:0]  st;
reg [12:0] fill_addr;
reg [6:0]  ci;             // character index within the line / header
reg        hdr_row;
reg [4:0]  conv_cnt;
reg [2:0]  iq_cnt;
reg [4:0]  pay_idx;        // payload byte being rendered
reg [1:0]  pay_sub;        // 0: high nibble, 1: low nibble, 2: space
reg        refresh_due;

wire [5:0] rd_idx = (st == S_SEARCH) ? sp :
                    (st == S_EVICT)  ? MAX_STA[5:0] - 6'd1 :
                    (st == S_SHIFT)  ? si : cd;
wire [47:0] tab_mac_rd  = tab[rd_idx][53:6];
wire [5:0]  tab_slot_rd = tab[rd_idx][5:0];

/*------------------------------------------------------------------*/
/* render-side frozen copy of the payload. cap_bytes can start        */
/* refilling with the NEXT MPDU of an A-MPDU within ~1us of fcs_stb   */
/* (no new preamble), while search/shift/render below takes longer -  */
/* the line and the list key must come from a copy that holds still.  */
/*------------------------------------------------------------------*/
reg [PAY_N*8-1:0] ren_bytes;

/* the list key: SA = bytes 10..15, first-byte-MSB order (same order the
   SA column prints in) */
wire [47:0] ren_sa = { ren_bytes[(PAY_N - 1 - 10)*8 +: 8],
                       ren_bytes[(PAY_N - 1 - 11)*8 +: 8],
                       ren_bytes[(PAY_N - 1 - 12)*8 +: 8],
                       ren_bytes[(PAY_N - 1 - 13)*8 +: 8],
                       ren_bytes[(PAY_N - 1 - 14)*8 +: 8],
                       ren_bytes[(PAY_N - 1 - 15)*8 +: 8] };

/*------------------------------------------------------------------*/
/* STATION COLOUR: 4:4:4 RGB hashed from the LAST FOUR BYTES of the   */
/* SA, so every listed station tints its own MAC field and the eye    */
/* can follow one transmitter as it moves up and down the list.       */
/*                                                                    */
/* Only the device-specific half of the address is hashed. Folding in  */
/* the OUI would tint every phone of one make alike, which is the      */
/* opposite of what the colour is for.                                 */
/*                                                                    */
/* The eight nibbles are dealt round-robin to R, G and B so all 32     */
/* bits move the colour, and the LAST byte's low nibble is dealt       */
/* TWICE (to R and to B) so that no channel is blind to the fastest-   */
/* varying end of the address. That case is not academic: one AP       */
/* radiating several BSSIDs puts out MACs differing in the last two    */
/* bits, and those must not all come out the same colour.              */
/*------------------------------------------------------------------*/
wire [3:0] sta_n0 = ren_sa[3:0],   sta_n1 = ren_sa[7:4];    // byte 15
wire [3:0] sta_n2 = ren_sa[11:8],  sta_n3 = ren_sa[15:12];  // byte 14
wire [3:0] sta_n4 = ren_sa[19:16], sta_n5 = ren_sa[23:20];  // byte 13
wire [3:0] sta_n6 = ren_sa[27:24], sta_n7 = ren_sa[31:28];  // byte 12

/* rev4 is the avalanche, and it is free - pure wiring. Without it the XOR
   fold keeps LSBs in LSBs, so two MACs one apart would differ by ONE step
   in one channel: two shades of the same colour, useless as a handle.
   Reversed, that same bit lands in the channel's MSB and swings it across
   half its range. (rev4 distributes over XOR, so reversing each channel
   once at the end is the same as reversing all eight nibbles first.) */
function [3:0] rev4;
    input [3:0] v;
    begin
        rev4 = {v[0], v[1], v[2], v[3]};
    end
endfunction

wire [3:0] sta_r_raw = rev4(sta_n0 ^ sta_n3 ^ sta_n6);
wire [3:0] sta_g_raw = rev4(sta_n1 ^ sta_n4 ^ sta_n7);
wire [3:0] sta_b_raw = rev4(sta_n2 ^ sta_n5 ^ sta_n0);

/* Readability floor. A hash lands on 12'h100 - all but black on a black
   screen - exactly as readily as on white, so MAX(R,G,B) is measured and,
   if it falls short of STA_MIN_LVL, the SAME delta is added to all three
   channels until it reaches it. Lifting rather than scaling keeps the
   DIFFERENCES between the channels, so the hue survives and only the
   saturation bleaches; scaling would hold the saturation instead but needs
   a divider per channel, which this field is not worth. */
wire [3:0] sta_max  = (sta_r_raw >= sta_g_raw)
                      ? ((sta_r_raw >= sta_b_raw) ? sta_r_raw : sta_b_raw)
                      : ((sta_g_raw >= sta_b_raw) ? sta_g_raw : sta_b_raw);
wire [3:0] sta_lift = (sta_max < STA_MIN_LVL) ? (STA_MIN_LVL - sta_max) : 4'd0;

/* No overflow to check for: every channel is <= sta_max by definition, so
   every channel + sta_lift is <= STA_MIN_LVL, which is itself <= 4'hF. */
wire [3:0] sta_r = sta_r_raw + sta_lift;
wire [3:0] sta_g = sta_g_raw + sta_lift;
wire [3:0] sta_b = sta_b_raw + sta_lift;

wire [11:0] sta_rgb = {sta_r, sta_g, sta_b};

/* payload character for the current column. pay_idx reaches PAY_N on the
   very last (blank) column - clamp so the part-select never goes negative. */
wire [4:0] pay_i_c  = (pay_idx > PAY_N[4:0] - 5'd1) ? PAY_N[4:0] - 5'd1 : pay_idx;
wire [7:0] cur_byte = ren_bytes[(PAY_N - 1 - pay_i_c)*8 +: 8];
wire [7:0] pay_char = (pay_idx >= cap_n) ? 8'h20 :
                      (pay_sub == 2'd0)  ? nib(cur_byte[7:4]) :
                      (pay_sub == 2'd1)  ? nib(cur_byte[3:0]) : 8'h20;

/*------------------------------------------------------------------*/
/* FC / DA / SA: one nibble per column, muxed out of ren_bytes        */
/*------------------------------------------------------------------*/
wire in_fc = (ci >= FC_COL[6:0]) && (ci <= FC_COL[6:0] + 7'd3);
wire in_da = (ci >= DA_COL[6:0]) && (ci <= DA_COL[6:0] + 7'd11);
wire in_sa = (ci >= SA_COL[6:0]) && (ci <= SA_COL[6:0] + 7'd11);

wire [6:0] d_fc = ci - FC_COL[6:0];
wire [6:0] d_da = ci - DA_COL[6:0];
wire [6:0] d_sa = ci - SA_COL[6:0];

/* two hex digits per byte, so the digit index halves into a byte index.
   Outside the three fields the result is unused but must stay < PAY_N -
   the widest it can reach is 10+15 = 25, so the part-select is always
   in range and needs no extra clamp. */
wire [4:0] hex_idx = in_fc ? {2'd0, d_fc[3:1]}          :
                     in_da ? (5'd4  + {1'b0, d_da[4:1]}) :
                             (5'd10 + {1'b0, d_sa[4:1]});
wire       hex_lo  = in_fc ? d_fc[0] : in_da ? d_da[0] : d_sa[0];
wire [7:0] hex_byte = ren_bytes[(PAY_N - 1 - hex_idx)*8 +: 8];

/* frames without an address 2 never pass the admission gate, so this only
   guards the render path against ever inventing a station string */
wire [7:0] fc0       = ren_bytes[(PAY_N - 1)*8 +: 8];
wire       no_addr2  = (fc0[3:2] == 2'b01) &&
                       ((fc0[7:4] == 4'hD) || (fc0[7:4] == 4'hC));

wire [7:0] hex_char = (in_sa && no_addr2) ? 8'h2D :          // "-"
                      (hex_idx >= cap_n)  ? 8'h20 :
                      nib(hex_lo ? hex_byte[3:0] : hex_byte[7:4]);

wire [7:0] line_char = (ci < PFX_W[6:0])       ? line[(PFX_W-1-ci)*8 +: 8] :
                       (in_fc | in_da | in_sa) ? hex_char :
                       (ci >= PAY_COL[6:0])    ? pay_char : 8'h20;

/* WP/EG hex digit for the current S_IQ step */
wire [6:0] iq_col = (iq_cnt < 3'd4) ? (IQ_WP_COL + {4'd0, iq_cnt})
                                    : (IQ_EG_COL - 7'd4 + {4'd0, iq_cnt});
wire [3:0] iq_nib = (iq_cnt < 3'd4) ? wp_s[(2'd3 - iq_cnt[1:0])*4 +: 4]
                                    : eg_s[(2'd3 - iq_cnt[1:0])*4 +: 4];

/* the display no longer scrolls: display row == character-RAM row, and
   text_screen's ring arithmetic degenerates to identity at top = 0 */
assign o_topRowGray = 6'd0;

/*------------------------------------------------------------------*/
/* line store: one 128-character rendered line per station slot.      */
/* Same geometry as the character RAM ({slot, col} addressing), both  */
/* ports on i_clk. XPM for the same reason text_screen uses it - an   */
/* inferred array went to distributed RAM there despite ram_style.    */
/*------------------------------------------------------------------*/
reg         ls_wr;
reg  [12:0] ls_wrAddr;
reg  [17:0] ls_wrData;
wire [17:0] ls_q;
wire [12:0] ls_rdAddr = {cp_slot, cp_ci[6:0]};

xpm_memory_sdpram #(
    .ADDR_WIDTH_A(13),
    .ADDR_WIDTH_B(13),
    .BYTE_WRITE_WIDTH_A(18),
    .CLOCKING_MODE("common_clock"),
    .MEMORY_PRIMITIVE("block"),
    .MEMORY_SIZE(147456),         // 8192 x 18 bit, same word as the char RAM
    .READ_DATA_WIDTH_B(18),
    .READ_LATENCY_B(1),
    .WRITE_DATA_WIDTH_A(18),
    .WRITE_MODE_B("read_first"),
    .USE_MEM_INIT(0)
) line_store (
    .clka(i_clk),
    .ena(ls_wr),
    .wea(1'b1),
    .addra(ls_wrAddr),
    .dina(ls_wrData),
    .clkb(i_clk),
    .enb(1'b1),
    .addrb(ls_rdAddr),
    .doutb(ls_q),
    .rstb(1'b0),
    .regceb(1'b1),
    .sleep(1'b0)
    /* no ECC ports: with the default ECC_MODE("no_ecc") xpm_memory_sdpram
       does not declare injectsbiterr/injectdbiterr/sbiterr/dbiterr at all,
       and connecting them by name is an error rather than a no-op. */
);

always @(posedge i_clk) begin
    if (i_rst) begin
        st        <= S_FILL;
        fill_addr <= 13'd0;
        ci        <= 7'd0;
        hdr_row   <= 1'b0;
        o_wr      <= 1'b0;
        o_wrAddr  <= 13'd0;
        o_wrData  <= 18'd0;
        ls_wr     <= 1'b0;
        ls_wrAddr <= 13'd0;
        ls_wrData <= 18'd0;
        line      <= {PFX_W*8{1'b0}};
        ren_bytes <= {PAY_N*8{1'b0}};
        cap_seq   <= 32'd0;
        cap_fcs   <= 1'b0;
        cap_n     <= 5'd0;
        conv_cnt  <= 5'd0;
        iq_cnt    <= 3'd0;
        pay_idx   <= PAY_START[4:0];
        pay_sub   <= 2'd0;
        refresh_due <= 1'b0;
        sta_cnt   <= 6'd0;
        sp        <= 6'd0;
        si        <= 6'd0;
        cd        <= 6'd0;
        rows_k    <= 6'd0;
        new_slot  <= 6'd0;
        cp_slot   <= 6'd0;
        cp_ci     <= 8'd0;
        cfo_prod  <= 30'd0;
        cfo_neg   <= 1'b0;
        dab_bin   <= 20'd0;
        dab_bcd   <= 24'd0;
        pwr_l2    <= 8'd0; ai_l2 <= 8'd0; aq_l2 <= 8'd0;
        pwr_db    <= 7'd0; snr_db <= 7'd0;
    end
    else begin
        o_wr  <= 1'b0;
        ls_wr <= 1'b0;
        if (tick_1s) refresh_due <= 1'b1;

        case (st)
        /* blank the whole character RAM once, so rows beyond the station
           count never show stale glyphs */
        S_FILL: begin
            o_wr     <= 1'b1;
            o_wrAddr <= fill_addr;
            o_wrData <= chcell(8'h20, C_GREY);
            if (fill_addr == {13{1'b1}}) begin
                st <= S_HDR;
                ci <= 7'd0;
                hdr_row <= 1'b0;
            end
            else
                fill_addr <= fill_addr + 13'd1;
        end

        S_HDR: begin
            o_wr     <= 1'b1;
            o_wrAddr <= {5'd0, hdr_row, ci};
            o_wrData <= chcell(hdr_row ? HDR1[(HW-1-ci)*8 +: 8]
                                     : HDR0[(HW-1-ci)*8 +: 8], C_HDR);
            if (ci == HW-1) begin
                ci <= 7'd0;
                if (hdr_row) begin
                    st <= S_IQ;        // paint the initial WP/EG values
                    iq_cnt <= 3'd0;
                end
                else
                    hdr_row <= 1'b1;
            end
            else
                ci <= ci + 7'd1;
        end

        S_IDLE: begin
            /* One update per completed frame that carries an SA. A frame
               that never reaches its FCS (a false SIGNAL detection) is not
               an update, and neither is an ACK/CTS or a runt - there is no
               station to attribute them to. */
            if (i_fcs_stb && active && cap_has_sa) begin
                cap_fcs  <= i_fcs_ok;
                cap_seq  <= seq;        // pre-increment value
                cap_n    <= byte_cnt;
                conv_cnt <= 5'd0;
                st       <= S_CONV;
            end
            else if (refresh_due) begin
                iq_cnt <= 3'd0;
                st     <= S_IQ;
            end
        end

        /* number crunching before the line renders. The cap_* scalars hold
           still long enough: even in an A-MPDU the next MPDU needs its
           4-byte delimiter before hdr_stb can fire again, and the payload
           is frozen into ren_bytes on the first cycle here. */
        S_CONV: begin
            conv_cnt <= conv_cnt + 5'd1;
            if (conv_cnt == 5'd0) begin
                ren_bytes <= cap_bytes;
                cfo_prod <= $signed(cap_cfo) * 15'sd6217;
                pwr_l2   <= log2q3(cap_pwr);
                ai_l2    <= log2q3({10'd0, cap_ai});
                aq_l2    <= log2q3({10'd0, cap_aq});
            end
            else if (conv_cnt == 5'd1) begin
                cfo_neg <= cfo_neg_w && (cfo_mag != 30'd0);
                dab_bin <= cfo_clamp;
                dab_bcd <= 24'd0;
                pwr_db  <= pwr_mul[17:11];
                snr_db  <= (snr_raw > 8'd99) ? 7'd99 : snr_raw[6:0];
            end
            else if (conv_cnt <= 5'd21) begin
                /* 20 double-dabble steps for the 20-bit CFO magnitude */
                dab_bcd <= {dab_w[22:0], dab_bin[19]};
                dab_bin <= {dab_bin[18:0], 1'b0};
            end
            else begin
                line <= line_next;
                sp   <= 6'd0;
                st   <= S_SEARCH;
            end
        end

        /* walk the MRU table looking for this SA - one entry per cycle,
           worst case 46 cycles against frames tens of microseconds long */
        S_SEARCH: begin
            if (sp == sta_cnt) begin
                /* unknown station */
                if (!cap_fcs) begin
                    /* a bad-FCS frame may not CREATE a station: its SA bytes
                       are exactly what the FCS says they are - unreliable.
                       (Mostly 11ax/VHT PPDUs decoded as 6M garbage.) */
                    iq_cnt <= 3'd0;
                    st     <= S_IQ;
                end
                else if (sta_cnt != MAX_STA[5:0]) begin
                    new_slot <= sta_cnt;          // fresh slot
                    rows_k   <= sta_cnt + 6'd1;
                    sta_cnt  <= sta_cnt + 6'd1;
                    if (sta_cnt == 6'd0)
                        st <= S_TAB0;
                    else begin
                        si <= sta_cnt - 6'd1;     // shift 0..cnt-1 down
                        st <= S_SHIFT;
                    end
                end
                else
                    st <= S_EVICT;                // full: evict the LRU
            end
            else if (tab_mac_rd == ren_sa) begin
                /* known station: reuse its slot, repaint rows 0..sp */
                new_slot <= tab_slot_rd;
                rows_k   <= sp + 6'd1;
                if (sp == 6'd0)
                    st <= S_TAB0;
                else begin
                    si <= sp - 6'd1;              // shift 0..sp-1 down
                    st <= S_SHIFT;
                end
            end
            else
                sp <= sp + 6'd1;
        end

        /* rd_idx points at the last entry: inherit the LRU's slot, then
           shift everything down over it */
        S_EVICT: begin
            new_slot <= tab_slot_rd;
            rows_k   <= MAX_STA[5:0];
            si       <= MAX_STA[5:0] - 6'd2;
            st       <= S_SHIFT;
        end

        /* tab[si+1] <= tab[si], si counting down - the read (async, at si)
           and the write land on different addresses every cycle */
        S_SHIFT: begin
            tab[si + 6'd1] <= {tab_mac_rd, tab_slot_rd};
            if (si == 6'd0)
                st <= S_TAB0;
            else
                si <= si - 6'd1;
        end

        S_TAB0: begin
            tab[0]  <= {ren_sa, new_slot};
            ci      <= 7'd0;
            pay_idx <= PAY_START[4:0];
            pay_sub <= 2'd0;
            st      <= S_LINE;
        end

        /* render the line into the station's line-store slot (not the
           screen - the copy engine below owns the screen rows) */
        S_LINE: begin
            ls_wr     <= 1'b1;
            ls_wrAddr <= {new_slot, ci};
            ls_wrData <= chcell(line_char, rgb_of(ci, cap_fcs, sta_rgb));
            if (ci >= PAY_COL[6:0]) begin
                if (pay_sub == 2'd2) begin
                    pay_sub <= 2'd0;
                    pay_idx <= pay_idx + 5'd1;
                end
                else
                    pay_sub <= pay_sub + 2'd1;
            end
            if (ci == LINE_W-1) begin
                cd <= 6'd0;
                st <= S_CSET;
            end
            else
                ci <= ci + 7'd1;
        end

        /* repaint display rows 0..rows_k-1 from the line store, in MRU
           order. Rows below rows_k did not move and are left alone. */
        S_CSET: begin
            cp_slot <= tab_slot_rd;               // rd_idx = cd here
            cp_ci   <= 8'd0;
            st      <= S_COPY;
        end

        /* stream one row: address {cp_slot, n} is presented in cycle n, the
           BRAM's registered output holds column n-1 during cycle n, so the
           write lags the address by exactly one column */
        S_COPY: begin
            if (cp_ci != 8'd0) begin
                o_wr     <= 1'b1;
                o_wrAddr <= {HDR_ROWS[5:0] + cd, cp_ci[6:0] - 7'd1};
                o_wrData <= ls_q;
            end
            if (cp_ci == 8'd128) begin
                if (cd + 6'd1 == rows_k) begin
                    iq_cnt <= 3'd0;
                    st     <= S_IQ;
                end
                else begin
                    cd <= cd + 6'd1;
                    st <= S_CSET;
                end
            end
            else
                cp_ci <= cp_ci + 8'd1;
        end

        /* refresh the WP/EG hex digits in header row 0 */
        S_IQ: begin
            o_wr        <= 1'b1;
            o_wrAddr    <= {6'd0, iq_col};
            o_wrData    <= chcell(nib(iq_nib), C_WHT);
            refresh_due <= 1'b0;
            if (iq_cnt == 3'd7)
                st <= S_IDLE;
            else
                iq_cnt <= iq_cnt + 3'd1;
        end

        default: st <= S_IDLE;
        endcase
    end
end

endmodule
