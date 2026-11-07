//////////////////////////////////////////////////////////////////////////////////
//
// Design Name: OWIFI_RX
// Module Name: noise_floor
// Project Name: RA-Sentinel 802.11 receiver + direction finder
// Engineer: Tobias Weber
// Target Devices: Artix 7, XC7A100T (RASBB U10 + RASRF2400WBMC)
// Description:
//   Per-channel receiver noise floor for tracking the MAX2831 gain drift
//   (doc/iq_capture/VALIDATION.md 7.6, 2026-10-03). The noise power at a
//   receiver output is G*F*kTB, so its drift between the four channels is
//   the drift of their gain - the quantity the amplitude DF needs and that
//   GAIN_TRIM (0x18) corrects - without a transmitter at a known bearing.
//
//   Per channel and block of 2^BLOCK_LOG2 samples (1024 = 51.2 us) the
//   VARIANCE is formed, sum|x|^2/N - |sum x/N|^2: the noise sits at only
//   ~2.6 LSB RMS at RX gain 0x68, so an ADC offset of a few LSB would otherwise
//   be most of the "noise", and a block's own mean removes it exactly. (A
//   leaky DC tracker was tried first: frames pull it, and the residual DC it
//   leaves after each frame adds the same absolute power to every channel -
//   +9 % on the quietest one in the bench.) The block's squared sums are
//   formed afterwards by one shared multiplier. A block is QUIET when the
//   receiver sat in S_WAIT_POWER_TRIGGER (i_idle) for all of it - no frame,
//   nothing above the power trigger.
//
//   SPLIT HALVES. Each block is evaluated as two halves, A (first 512 samples)
//   and B (last 512). Of the quiet blocks of each period (2^PERIOD_LOG2
//   samples = 0.21 s) the one whose half A has the LOWEST TOTAL over the four
//   channels is kept - minimum statistics, so a weak directional interferer
//   below the trigger is skipped rather than averaged in - and the four
//   variances of its half B are published. Selecting on A and measuring on B
//   keeps the noise that won the selection out of the result: published
//   straight from the selected samples, the channel that dominates the total
//   reads low (-5 % at 4x the noise power of the others in the bench), a
//   level-dependent bias the gain comparison would inherit. A block also has
//   to be CONSISTENT - totals of A and B within 25 % of each other - so one in
//   which an interferer starts or stops cannot have a clean A and a dirty B.
//   A block with a dead channel-half (variance below MIN_PW - the all-zero
//   samples of a link heal) is not usable either. The ECU combines the
//   published periods.
//
//   A period whose quiet blocks ALL carried an interferer publishes that
//   interferer too - the ECU therefore takes a median / minimum over periods,
//   not a mean.
//
//   Units: mean |x - mean|^2 per sample in LSB^2 * 256 (8 fractional bits,
//   I^2 + Q^2), saturating at 32 bits; 0 dBFS (|x| = 2047) = 2047^2 * 256.
//
//   ADDR   NF_CTRL  write: [0] enable (default 1; 0 freezes the published
//                   set), [5:4] channel shown in NF_DATA, [8] snapshot (self-
//                   clearing) - copies the last published set into the read
//                   registers, so the four channels read afterwards belong
//                   to one period.
//                   read: [0] enable, [5:4] select, [11] snapshot valid (the
//                   period had at least one quiet block), [19:12] period
//                   sequence number (wraps), [31:20] quiet blocks in that
//                   period (saturates at 4095; 4096 blocks per period).
//   ADDR+1 NF_DATA  noise power of the selected channel in the snapshot (RO).
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

module noise_floor #(
    parameter       NCH         = 4,     // the totals below are written for 4
    parameter       ADCBITS     = 12,
    parameter       BLOCK_LOG2  = 10,    // samples per block (1024 = 51.2 us at 20 MSPS); >= 9
    parameter       PERIOD_LOG2 = 22,    // samples per published period (0.21 s); > BLOCK_LOG2
    parameter [31:0] MIN_PW     = 32'd16, // below this a channel is dead, not quiet (1/16 LSB^2)
    parameter [6:0] ADDR        = 7'h6E  // NF_CTRL; ADDR+1 = NF_DATA
)(
    input  wire                      i_clk,      // receiver domain (100MHz)
    input  wire                      i_rst,
    input  wire                      i_strobe,   // 20MHz sample strobe
    /* all channels in one word: [c*2*ADCBITS +: 2*ADCBITS] = {I, Q} of ch c (ant_select's layout) */
    input  wire [NCH*2*ADCBITS-1:0]  i_iq,
    input  wire                      i_idle,     // dot11 in S_WAIT_POWER_TRIGGER

    input  wire [6:0]                i_SPI_addr,
    input  wire                      i_SPI_wrStrobe,
    input  wire [31:0]               i_SPIdata,
    inout  wire [31:0]               o_SPIdata
);

localparam HL   = BLOCK_LOG2 - 1;                 // log2 samples per half
localparam S2W  = 2 * ADCBITS + 1 + HL;           // half-block sum of I^2 + Q^2
localparam SXW  = ADCBITS + HL;                   // half-block sum of I (or Q), signed
localparam SQW  = 2 * SXW;                        // its square
localparam QW   = SQW + 1;                        // sx^2 + sy^2
localparam NBLK = PERIOD_LOG2 - BLOCK_LOG2;       // log2 blocks per period
localparam NS   = 2 * NCH;                        // channel-halves: index 2c = A, 2c+1 = B

/****************************************************************************/
/* Per sample: squares and sums (one pipeline for all four channels)        */
/****************************************************************************/
reg                    a_v, b_v, c_v;
reg                    a_idle, b_idle, c_idle;
reg [BLOCK_LOG2-1:0]   smp_cnt;           // sample within the block
reg [NBLK-1:0]         blk_cnt;           // block within the period
reg                    blk_quiet;         // every sample of this block idle
wire                   half_b    = smp_cnt[HL];
wire                   half_first = (smp_cnt[HL-1:0] == {HL{1'b0}});
wire                   blk_first = (smp_cnt == {BLOCK_LOG2{1'b0}});
wire                   blk_end   = c_v && (smp_cnt == {BLOCK_LOG2{1'b1}});

/* sums per channel-half, [2c] = half A, [2c+1] = half B */
reg [S2W-1:0]          s2 [0:NS-1];
reg signed [SXW-1:0]   sx [0:NS-1];
reg signed [SXW-1:0]   sy [0:NS-1];

genvar c;
generate for (c = 0; c < NCH; c = c + 1) begin : gen_ch
    wire signed [ADCBITS-1:0] s_i = i_iq[c*2*ADCBITS + ADCBITS +: ADCBITS];
    wire signed [ADCBITS-1:0] s_q = i_iq[c*2*ADCBITS           +: ADCBITS];

    reg signed [ADCBITS-1:0] a_i, a_q, b_i, b_q, c_i, c_q;
    reg [2*ADCBITS-1:0]      b_ii, b_qq;
    reg [2*ADCBITS:0]        c_p;
    always @(posedge i_clk) begin
        if (i_strobe) begin a_i <= s_i; a_q <= s_q; end
        if (a_v) begin                         // squares (DSP, registered)
            b_ii <= a_i * a_i;
            b_qq <= a_q * a_q;
            b_i  <= a_i; b_q <= a_q;
        end
        if (b_v) begin
            c_p <= b_ii + b_qq;
            c_i <= b_i; c_q <= b_q;
        end
    end

    /* half-block sums, restarted on each half's first sample. Explicit sign
       extension: a ?: with an unsigned zero in it would make the whole sum
       unsigned and zero-extend a negative sample. */
    wire signed [SXW-1:0] ext_i = {{(SXW-ADCBITS){c_i[ADCBITS-1]}}, c_i};
    wire signed [SXW-1:0] ext_q = {{(SXW-ADCBITS){c_q[ADCBITS-1]}}, c_q};
    wire [S2W-1:0]        ext_p = {{(S2W-2*ADCBITS-1){1'b0}}, c_p};
    always @(posedge i_clk) begin
        if (i_rst) begin
            s2[2*c] <= {S2W{1'b0}}; sx[2*c] <= {SXW{1'b0}}; sy[2*c] <= {SXW{1'b0}};
            s2[2*c+1] <= {S2W{1'b0}}; sx[2*c+1] <= {SXW{1'b0}}; sy[2*c+1] <= {SXW{1'b0}};
        end
        else if (c_v) begin
            if (!half_b) begin
                s2[2*c] <= half_first ? ext_p : s2[2*c] + ext_p;
                sx[2*c] <= half_first ? ext_i : sx[2*c] + ext_i;
                sy[2*c] <= half_first ? ext_q : sy[2*c] + ext_q;
            end
            else begin
                s2[2*c+1] <= half_first ? ext_p : s2[2*c+1] + ext_p;
                sx[2*c+1] <= half_first ? ext_i : sx[2*c+1] + ext_i;
                sy[2*c+1] <= half_first ? ext_q : sy[2*c+1] + ext_q;
            end
        end
    end
end
endgenerate

always @(posedge i_clk) begin
    if (i_rst) begin
        a_v <= 1'b0; b_v <= 1'b0; c_v <= 1'b0;
    end
    else begin
        a_v <= i_strobe; b_v <= a_v; c_v <= b_v;
    end
    if (i_strobe) a_idle <= i_idle;
    if (a_v)      b_idle <= a_idle;
    if (b_v)      c_idle <= b_idle;
end

always @(posedge i_clk) begin
    if (i_rst) begin
        smp_cnt   <= {BLOCK_LOG2{1'b0}};
        blk_cnt   <= {NBLK{1'b0}};
        blk_quiet <= 1'b1;
    end
    else if (c_v) begin
        smp_cnt   <= smp_cnt + 1'b1;
        blk_quiet <= (blk_first ? 1'b1 : blk_quiet) & c_idle;
        if (blk_end) blk_cnt <= blk_cnt + 1'b1;
    end
end

/****************************************************************************/
/* Per block: variance of each channel-half, by one shared multiplier       */
/****************************************************************************/
/* The sums are final one clock after blk_end; hold them, then square the
   sixteen sx/sy one per clock (ph 1..16, products two clocks later). The
   next block ends >= 1024 samples later. */
reg                    h_go, h_quiet, h_last;
reg [S2W-1:0]          h2 [0:NS-1];
reg signed [SXW-1:0]   hx [0:NS-1];
reg signed [SXW-1:0]   hy [0:NS-1];
reg [5:0]              ph;                // block sequencer, 0 = idle
reg signed [SXW-1:0]   m_op;
reg                    m_v, p_v;
reg [3:0]              m_idx, p_idx;      // [3:1] channel-half, [0] y
reg [SQW-1:0]          m_prod;
reg [QW-1:0]           q [0:NS-1];
reg [31:0]             pw [0:NS-1];       // variance, LSB^2 * 256 per sample
reg [33:0]             tot_a, tot_b;

localparam [5:0] PH_VAR = 6'd20, PH_TOT = 6'd21, PH_DONE = 6'd22;

function [31:0] sat32;
    input [S2W+8-1:0] v;
    begin
        sat32 = (|v[S2W+8-1:32]) ? 32'hFFFF_FFFF : v[31:0];
    end
endfunction

wire [3:0] iss = ph[3:0] - 4'd1;          // issue index while ph = 1..16

integer k;
always @(posedge i_clk) begin
    h_go <= i_rst ? 1'b0 : blk_end;
    if (blk_end) begin
        h_quiet <= blk_quiet & c_idle;
        h_last  <= (blk_cnt == {NBLK{1'b1}});
    end
    if (h_go)
        for (k = 0; k < NS; k = k + 1) begin
            h2[k] <= s2[k]; hx[k] <= sx[k]; hy[k] <= sy[k]; q[k] <= {QW{1'b0}};
        end

    m_v <= 1'b0;
    if (ph >= 6'd1 && ph <= 6'd16) begin
        m_idx <= iss;
        m_op  <= iss[0] ? hy[iss[3:1]] : hx[iss[3:1]];
        m_v   <= 1'b1;
    end
    p_v    <= m_v;
    p_idx  <= m_idx;
    m_prod <= m_op * m_op;
    if (p_v) q[p_idx[3:1]] <= q[p_idx[3:1]] + m_prod;

    /* variance * 256 per sample = (s2 * 256 - (sx^2 + sy^2) * 256 / H) / H */
    if (ph == PH_VAR)
        for (k = 0; k < NS; k = k + 1)
            pw[k] <= sat32((({h2[k], 8'd0}) - (q[k] >> (HL - 8))) >> HL);
    if (ph == PH_TOT) begin
        tot_a <= {2'b00, pw[0]} + {2'b00, pw[2]} + {2'b00, pw[4]} + {2'b00, pw[6]};
        tot_b <= {2'b00, pw[1]} + {2'b00, pw[3]} + {2'b00, pw[5]} + {2'b00, pw[7]};
    end
end

always @(posedge i_clk) begin
    if (i_rst)
        ph <= 6'd0;
    else if (h_go)
        ph <= 6'd1;
    else if (ph != 6'd0)
        ph <= (ph == PH_DONE) ? 6'd0 : ph + 6'd1;
end

/* usable: quiet, the two halves agree within 25 %, and every channel-half
   alive. A link heal hands over all-zero samples while the receiver sits
   idle (ADC1, 2026-10-03); variance 0 would win the lowest-total selection
   and publish 0 for that channel. Real noise reads ~3300 here. */
reg  alive;
always @(*) begin
    alive = 1'b1;
    for (k = 0; k < NS; k = k + 1)
        if (pw[k] < MIN_PW) alive = 1'b0;
end
wire blk_done   = (ph == PH_DONE);
wire consistent = ({2'b00, tot_b} <= {2'b00, tot_a} + (tot_a >> 2)) &&
                  ({2'b00, tot_a} <= {2'b00, tot_b} + (tot_b >> 2));
wire usable     = h_quiet && consistent && alive;

/****************************************************************************/
/* Per period: the usable block with the lowest half-A total, then publish  */
/* its half-B variances                                                     */
/****************************************************************************/
reg  [33:0]  min_total;
reg  [31:0]  min_pw [0:NCH-1];
reg  [12:0]  n_use;                        // usable blocks this period before the current one

reg          enable;
reg  [31:0]  pub [0:NCH-1];
reg  [11:0]  pub_n;
reg          pub_valid;
reg  [7:0]   pub_seq;

always @(posedge i_clk) begin
    if (i_rst) begin
        min_total <= {34{1'b1}};
        n_use     <= 13'd0;
        pub_n     <= 12'd0;
        pub_valid <= 1'b0;
        pub_seq   <= 8'd0;
        for (k = 0; k < NCH; k = k + 1) begin
            min_pw[k] <= 32'd0;
            pub[k]    <= 32'd0;
        end
    end
    else if (blk_done) begin
        /* this block's verdict, then - on the period's last block - publish
           with it included and start the next period empty */
        if (usable && (tot_a < min_total)) begin
            if (h_last) begin
                if (enable)
                    for (k = 0; k < NCH; k = k + 1) pub[k] <= pw[2*k+1];
            end
            else begin
                min_total <= tot_a;
                for (k = 0; k < NCH; k = k + 1) min_pw[k] <= pw[2*k+1];
            end
        end
        else if (h_last && enable && (n_use != 13'd0)) begin
            for (k = 0; k < NCH; k = k + 1) pub[k] <= min_pw[k];
        end
        if (h_last) begin
            if (enable) begin
                pub_n     <= ((n_use + usable) > 13'd4095) ? 12'd4095 : (n_use[11:0] + usable);
                pub_valid <= (n_use != 13'd0) || usable;
                pub_seq   <= pub_seq + 8'd1;
            end
            min_total <= {34{1'b1}};
            n_use     <= 13'd0;
        end
        else if (usable)
            n_use <= n_use + 13'd1;
    end
end

/****************************************************************************/
/* Registers                                                                */
/****************************************************************************/
reg  [1:0]  sel;
reg  [31:0] sh [0:NCH-1];
reg  [11:0] sh_n;
reg         sh_valid;
reg  [7:0]  sh_seq;

wire wr_ctrl = i_SPI_wrStrobe && (i_SPI_addr == ADDR);

always @(posedge i_clk) begin
    if (i_rst) begin
        enable <= 1'b1; sel <= 2'd0;
        sh_n <= 12'd0; sh_valid <= 1'b0; sh_seq <= 8'd0;
        for (k = 0; k < NCH; k = k + 1) sh[k] <= 32'd0;
    end
    else if (wr_ctrl) begin
        enable <= i_SPIdata[0];
        sel    <= i_SPIdata[5:4];
        if (i_SPIdata[8]) begin
            for (k = 0; k < NCH; k = k + 1) sh[k] <= pub[k];
            sh_n <= pub_n; sh_valid <= pub_valid; sh_seq <= pub_seq;
        end
    end
end

reg [31:0] rd;
reg        rsel;
always @(*) begin
    rsel = 1'b1; rd = 32'd0;
    case (i_SPI_addr)
        ADDR:         rd = {sh_n, sh_seq, sh_valid, 5'd0, sel, 3'd0, enable};
        ADDR + 7'd1:  rd = sh[sel];
        default:      rsel = 1'b0;
    endcase
end
assign o_SPIdata = rsel ? rd : 32'bz;

endmodule
