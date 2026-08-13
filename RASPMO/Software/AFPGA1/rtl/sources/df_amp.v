//////////////////////////////////////////////////////////////////////////////////
// df_amp.v
//
// Amplitude-comparison direction finder for the four RASANT2400 antennas, which
// point outward at 0/90/180/270 deg on a 25cm-radius circle. Produces the angle
// table that polar_view.v renders: len[theta] = strongest signal seen at that
// bearing.
//
// AMPLITUDE, NOT PHASE. The array is 2.03 lambda in radius at 2.44GHz -> 2.88
// lambda adjacent baseline, 4.07 diagonal. Phase interferometry wraps ~6x there
// and is hopeless, and the elements point four different ways anyway, which
// breaks the equal-element-pattern assumption interferometry rests on.
// Amplitude comparison is unambiguous over the full 360deg and needs no phase
// coherence between the four MAX2831 LOs (reference-locked, NOT LO-locked -
// relative phase is arbitrary and re-randomises on every relock). Nearly free
// too: the spectrum RAMs already hold calibrated amplitudes, and since every
// channel has its own FFT the four amplitudes at a bin share one time window.
// Phase can come later as a refinement on top of this coarse bearing.
//
// THE MATH AND THE TRAP IN IT. Beams at 0/90/180/270 -> the bearing is the
// argument of the pattern's fundamental Fourier component, which a 4-point DFT
// gives as
//      X = P_east - P_west,  Y = P_north - P_south,  bearing = atan2(Y, X)
// Exact for G(d) = 1 + a*cos(d). BUT ONLY ON LINEAR POWER. The RAMs hold LOG
// amplitude (0.376dB/count) and differencing logs makes ratios, not
// differences: for a quadratic-in-dB beam X and Y come out piecewise LINEAR in
// bearing, and atan2 of that is not the bearing, just something correlated with
// it. So normalise each bin to its own strongest beam first (kills the absolute
// level, leaves the shape), push it back to linear through explut(), THEN
// difference.
//
// Normalisation window is 64 counts = 24dB, way past a patch's useful
// front-to-back. Beyond it the LUT floors at 1 and the beam drops out.
//
// ANGLE CONVENTION, same as polar_view.v: X = east-west, Y = north-south, so
// the CORDIC gives binary turns CCW from east, north lands at 90deg and the ray
// points up the screen. No offsets, no flips, anywhere.
//
// TIMING. One sweep per round, all 1024 bins at a lazy 4 clocks each - the
// angle table RMW needs 3 on dp_ram's shared port A and at 4 there's simply no
// hazard to think about. 1024*4 = 4096 clocks = 34us at 120MHz, inside a 6144
// clock (51.2us) round with ~1900 to spare for the decay sweep. Results
// max-accumulate across rounds, so short bursts get caught instead of being
// sampled at 60Hz.
//
// TABLE ENTRY = {frequency, length}, not just a ray length: the strongest
// signal at that bearing AND the bin it came from. The bin rides the pipeline
// next to the amplitude and is written by the same max compare - compared on
// LENGTH ONLY, so the stored frequency is always the winner's and never a blend
// of two bins. Lets polar_view colour the ray by frequency (freqmap.v) instead
// of amplitude, which the length already shows.
//
// PERSISTENCE BY DECAY. Single 512-entry buffer, entries max-accumulate across
// sweeps and decay: every DECAY_CYCLES one sweep walks all 512 bins and shrinks
// each ray by 1/8 (step floor 1, down to zero). Fresh signal paints a full ray
// that fades over a couple of seconds; a persistent one holds solid.
// The decay sweep only issues while the bin sweep sits idle - ST_DRAIN has
// flushed the pipeline by then, so measurement RMW and decay RMW share one FSM
// and can never collide. Idle window is ~1900 clocks/round against the 512*3 =
// 1536 a full decay sweep wants, so it fits in one gap; decay_run is level and
// didx persists, so one that doesn't fit just resumes next gap instead of
// starving. At 50ms between sweeps there's ~975 rounds of slack either way.
// Display reads port B while port A writes - a same-cycle collision tears one
// bin for one pixel frame. Nobody will ever see it.
//
// Dependencies: cordic_vec.v, dp_ram.v
//////////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps

module df_amp #(
    parameter FFTLEN    = 10,       // 1024 FFT bins
    parameter ANGBITS   = 9,        // 512 angle bins (0.703deg each)
    parameter FRQBITS   = 8,        // colour code width; the top FRQBITS of the
                                    // bin index, so 8 keeps 4 bins per code
    parameter CH_E      = 0,        // channel index of the antenna facing east
    parameter CH_N      = 1,        //                                    north
    parameter CH_W      = 2,        //                                    west
    parameter CH_S      = 3,        //                                    south
    parameter [7:0] AMP_FLOOR = 8'd128, // bins at or below this draw nothing
    parameter AMP_SHIFT = 1,        // ray length = (amp - AMP_FLOOR) << this
    parameter [10:0] DIR_MIN = 11'd24,  // min |(X,Y)| for a trustworthy bearing
    parameter STAGES    = 12,   // CORDIC stages; 12 resolves ~0.03deg, far
                                // finer than the 0.703deg angle bin
    parameter CGUARD    = 10,   // CORDIC guard bits
    parameter [23:0] DECAY_CYCLES = 24'd6_000_000  // clocks between decay
                                // sweeps; 50ms at the 120MHz DCLK, matching
                                // df_frame's DECAY_US=50000 fade of ~2.5s
)(
    input  wire                  i_clk,        // ADC/DCLK domain
    input  wire                  i_rst,

    // mirror of the spectrum RAM write port. All four channels are written on
    // the same strobe (one FFT per channel), so this is one address and four
    // amplitudes, packed {ch3, ch2, ch1, ch0}, rather than the channel-tagged
    // single lane the round-robin FFT used to deliver.
    input  wire                  i_wr_en,
    input  wire [FFTLEN-1:0]     i_wr_addr,
    input  wire [8*4-1:0]        i_wr_data,

    input  wire                  i_round_done,  // pulse: one output frame written

    // angle table read port, pixel domain
    input  wire                  i_rdClk,
    input  wire [ANGBITS-1:0]    i_rdAddr,
    output wire [7:0]            o_rdLen,
    output wire [FRQBITS-1:0]    o_rdFrq   // bin that won this bearing
);

localparam NBINS = (1 << FFTLEN);

/* Normalised-log -> linear power, 255 * 10^(-0.376*d/10), d in log counts.
   64 entries = a 24dB normalisation window; past that a beam contributes ~0. */
function [7:0] explut;
    input [5:0] d;
    begin
        case (d)
            0: explut = 8'd255; 1: explut = 8'd234; 2: explut = 8'd214; 3: explut = 8'd197;
            4: explut = 8'd180; 5: explut = 8'd165; 6: explut = 8'd152; 7: explut = 8'd139;
            8: explut = 8'd128; 9: explut = 8'd117; 10: explut = 8'd107; 11: explut = 8'd98;
            12: explut = 8'd90; 13: explut = 8'd83; 14: explut = 8'd76; 15: explut = 8'd70;
            16: explut = 8'd64; 17: explut = 8'd59; 18: explut = 8'd54; 19: explut = 8'd49;
            20: explut = 8'd45; 21: explut = 8'd41; 22: explut = 8'd38; 23: explut = 8'd35;
            24: explut = 8'd32; 25: explut = 8'd29; 26: explut = 8'd27; 27: explut = 8'd25;
            28: explut = 8'd23; 29: explut = 8'd21; 30: explut = 8'd19; 31: explut = 8'd17;
            32: explut = 8'd16; 33: explut = 8'd15; 34: explut = 8'd13; 35: explut = 8'd12;
            36: explut = 8'd11; 37: explut = 8'd10; 38: explut = 8'd10; 39: explut = 8'd9;
            40: explut = 8'd8;  41: explut = 8'd7;  42: explut = 8'd7;  43: explut = 8'd6;
            44: explut = 8'd6;  45: explut = 8'd5;  46: explut = 8'd5;  47: explut = 8'd4;
            48: explut = 8'd4;  49: explut = 8'd4;  50: explut = 8'd3;  51: explut = 8'd3;
            52: explut = 8'd3;  53: explut = 8'd3;  54: explut = 8'd2;  55: explut = 8'd2;
            56: explut = 8'd2;  57: explut = 8'd2;  58: explut = 8'd2;  59: explut = 8'd2;
            default: explut = 8'd1;
        endcase
    end
endfunction

/****************************************************************************/
/* Per-channel amplitude snapshot. Both ports of the spectrum RAMs are already */
/* spoken for (A writes from this domain, B is the display read), so the DF    */
/* sweep gets its own copy: four 1024x8 mirrors written in lockstep with       */
/* specMem, 4 x RAMB18. One address, one write enable for all four -> a bin's  */
/* four amplitudes land atomically and the sweep can never read a mix of two   */
/* frames.                                                                     */
/****************************************************************************/
wire [FFTLEN-1:0] sweep_addr;
wire [7:0] snap_q [0:3];

genvar c;
generate
for (c = 0; c < 4; c = c + 1) begin : gen_snap
    dp_ram #(.ADDRBITS(FFTLEN), .BITS(8)) snapMem (
        .i_clka(i_clk),
        .i_wea(i_wr_en),
        .i_addra(i_wr_addr),
        .i_dina(i_wr_data[8*c +: 8]),
        .o_douta(),
        .i_clkb(i_clk),
        .i_addrb(sweep_addr),
        .o_doutb(snap_q[c])
    );
end
endgenerate

/****************************************************************************/
/* Sweep sequencer                                                          */
/****************************************************************************/
localparam ST_IDLE  = 2'd0,
           ST_SWEEP = 2'd1,
           ST_DRAIN = 2'd2;

reg [1:0]        state;
reg [FFTLEN-1:0] bin_ctr;
reg [1:0]        phase;        // 4-clock cadence within a bin
reg [5:0]        drain_ctr;

assign sweep_addr = bin_ctr;

wire bin_issue = (state == ST_SWEEP) && (phase == 2'd0);

always @(posedge i_clk) begin
    if (i_rst) begin
        state         <= ST_IDLE;
        bin_ctr       <= {FFTLEN{1'b0}};
        phase         <= 2'd0;
        drain_ctr     <= 6'd0;
    end
    else begin
        case (state)
        ST_IDLE: begin
            phase   <= 2'd0;
            bin_ctr <= {FFTLEN{1'b0}};
            if (i_round_done)
                state <= ST_SWEEP;
        end

        ST_SWEEP: begin
            phase <= phase + 2'd1;
            if (phase == 2'd3) begin
                if (bin_ctr == {FFTLEN{1'b1}}) begin
                    drain_ctr <= 6'd0;
                    state     <= ST_DRAIN;
                end
                else
                    bin_ctr <= bin_ctr + 1'b1;
            end
        end

        ST_DRAIN: begin
            /* let the CORDIC and the table RMW empty; only then may the decay
               sweep touch port A (see the table FSM below) */
            drain_ctr <= drain_ctr + 6'd1;
            if (drain_ctr == 6'd40)
                state <= ST_IDLE;
        end

        default: state <= ST_IDLE;
        endcase
    end
end

/****************************************************************************/
/* Bin pipeline: normalise -> linear -> differences -> CORDIC               */
/* snap_q is valid one clock after sweep_addr, i.e. at phase 1.             */
/****************************************************************************/
reg        s1_vld;
reg [7:0]  s1_a [0:3];
/* Colour code latched WITH the amplitudes and carried all the way down, not
   recomputed at the far end. bin_ctr only moves on phase 3 so it still reads
   the issued bin here on phase 1, and everything below is fixed-latency - the
   code arriving at the table write is by construction the bin that produced
   that bearing. Nothing to get out of step. */
reg [FRQBITS-1:0] s1_f;
always @(posedge i_clk) begin
    s1_vld <= i_rst ? 1'b0 : bin_issue;
    s1_f    <= sweep_addr[FFTLEN-1 -: FRQBITS];
    s1_a[0] <= snap_q[0];
    s1_a[1] <= snap_q[1];
    s1_a[2] <= snap_q[2];
    s1_a[3] <= snap_q[3];
end

/* FOUR SEPARATE STAGES, one operation each. Don't collapse them: max ->
   subtract -> clamp -> LUT -> subtract in one cycle is 14 logic levels and 6
   carry chains, ~9.2ns against an 8.33ns budget. Latency here is free anyway -
   4 clocks per bin, 1024 bins per round - only the amp delay line has to
   track it. */

/* stage 2: strongest beam of the four - both the normalisation reference and
   the ray length source */
wire [7:0] m01 = (s1_a[0] > s1_a[1]) ? s1_a[0] : s1_a[1];
wire [7:0] m23 = (s1_a[2] > s1_a[3]) ? s1_a[2] : s1_a[3];

reg        s2_vld;
reg [7:0]  s2_amax;
reg [7:0]  s2_a [0:3];
reg [FRQBITS-1:0] s2_f;
always @(posedge i_clk) begin
    s2_vld  <= i_rst ? 1'b0 : s1_vld;
    s2_f    <= s1_f;
    s2_amax <= (m01 > m23) ? m01 : m23;
    s2_a[0] <= s1_a[0];
    s2_a[1] <= s1_a[1];
    s2_a[2] <= s1_a[2];
    s2_a[3] <= s1_a[3];
end

/* stage 3: normalised log difference per channel, clamped to the LUT window */
wire [7:0] dd0 = s2_amax - s2_a[0];
wire [7:0] dd1 = s2_amax - s2_a[1];
wire [7:0] dd2 = s2_amax - s2_a[2];
wire [7:0] dd3 = s2_amax - s2_a[3];

reg       s3_vld;
reg [7:0] s3_amp;
reg [5:0] s3_c [0:3];
reg [FRQBITS-1:0] s3_f;
always @(posedge i_clk) begin
    s3_vld  <= i_rst ? 1'b0 : s2_vld;
    s3_f    <= s2_f;
    s3_amp  <= s2_amax;
    s3_c[0] <= (dd0 > 8'd63) ? 6'd63 : dd0[5:0];
    s3_c[1] <= (dd1 > 8'd63) ? 6'd63 : dd1[5:0];
    s3_c[2] <= (dd2 > 8'd63) ? 6'd63 : dd2[5:0];
    s3_c[3] <= (dd3 > 8'd63) ? 6'd63 : dd3[5:0];
end

/* stage 4: back to linear power through the LUT */
reg       s4_vld;
reg [7:0] s4_amp;
reg [7:0] s4_lin [0:3];
reg [FRQBITS-1:0] s4_f;
always @(posedge i_clk) begin
    s4_vld    <= i_rst ? 1'b0 : s3_vld;
    s4_f      <= s3_f;
    s4_amp    <= s3_amp;
    s4_lin[0] <= explut(s3_c[0]);
    s4_lin[1] <= explut(s3_c[1]);
    s4_lin[2] <= explut(s3_c[2]);
    s4_lin[3] <= explut(s3_c[3]);
end

/* stage 5: the two Fourier differences. Indexing by the CH_* map keeps the
   compass assignment in one place. */
reg  signed [9:0] s5_x, s5_y;
reg  [7:0]        s5_amp;
reg  [FRQBITS-1:0] s5_f;
reg               s5_vld;
always @(posedge i_clk) begin
    s5_vld <= i_rst ? 1'b0 : s4_vld;
    s5_f   <= s4_f;
    s5_amp <= s4_amp;
    s5_x   <= $signed({2'b00, s4_lin[CH_E]}) - $signed({2'b00, s4_lin[CH_W]});
    s5_y   <= $signed({2'b00, s4_lin[CH_N]}) - $signed({2'b00, s4_lin[CH_S]});
end

wire [11:0] cd_mag;
wire [15:0] cd_ang;
wire        cd_vld;

cordic_vec #(.XYW(10), .STAGES(STAGES), .GUARD(CGUARD)) cordic_df (
    .i_clk(i_clk),
    .i_ce(1'b1),
    .i_valid(s5_vld),
    .i_x(s5_x),
    .i_y(s5_y),
    .o_mag(cd_mag),
    .o_ang(cd_ang),
    .o_valid(cd_vld)
);

/* The ray length and its colour code both have to arrive with the CORDIC
   result, so they ride matched delay lines rather than being recomputed. */
localparam CDLAT = STAGES + 1;
reg [7:0]         amp_dly [0:CDLAT-1];
reg [FRQBITS-1:0] frq_dly [0:CDLAT-1];
integer q;
always @(posedge i_clk) begin
    amp_dly[0] <= s5_amp;
    frq_dly[0] <= s5_f;
    for (q = 0; q < CDLAT-1; q = q + 1) begin
        amp_dly[q+1] <= amp_dly[q];
        frq_dly[q+1] <= frq_dly[q];
    end
end
wire [7:0]         amp_at_out = amp_dly[CDLAT-1];
wire [FRQBITS-1:0] frq_at_out = frq_dly[CDLAT-1];

/* Ray length: floor-subtract, gain, saturate. Below the floor draw nothing -
   without that the noise floor paints a ray at every bearing and you get a
   filled disc instead of a display. */
wire        above_floor = (amp_at_out > AMP_FLOOR);
wire [8:0]  len_raw     = {1'b0, (amp_at_out - AMP_FLOOR)} << AMP_SHIFT;
wire [7:0]  len_sat     = len_raw[8] ? 8'hFF : len_raw[7:0];

/* A bearing only means something if the four beams actually disagree, and
   cd_mag = |(X,Y)| is exactly that confidence measure for free. Omnidirectional
   or pure noise gives X ~ Y ~ 0 and would otherwise fling a ray off in some
   random direction. */
wire draw_ok = cd_vld && above_floor && (cd_mag > {1'b0, DIR_MIN});

/****************************************************************************/
/* Angle table: 512 x {frq,len}, read-modify-write for the max accumulate,  */
/* plus the decay sweep (df_frame.v's scheme) sharing the same RMW FSM.     */
/****************************************************************************/
localparam TBLW = 8 + FRQBITS;      // {frequency code, ray length}

reg  [ANGBITS-1:0] tbl_addr;
reg  [TBLW-1:0]    tbl_din;
reg                tbl_we;
wire [TBLW-1:0]    tbl_douta;

reg [1:0]         rmw_st;   // 0 idle, 1 address presented, 2 read data valid
reg               rmw_decay; // this RMW is a decay step, not a measurement
reg [ANGBITS-1:0] rmw_idx;
reg [7:0]         rmw_len;
reg [FRQBITS-1:0] rmw_frq;

/* Decay cadence: free-running counter arms decay_run, then didx walks all 512
   bins whenever port A has nothing better to do. A new period expiring while a
   sweep is still pending just drops the extra - decay_run is a level, not a
   count. */
reg [23:0]        decay_ctr;
reg               decay_run;
reg [ANGBITS-1:0] didx;

/* len -= max(len/8, 1), floor 0 */
function [7:0] decay_next;
    input [7:0] len;
    reg   [7:0] step;
    begin
        step = (len[7:3] == 5'd0) ? 8'd1 : {3'd0, len[7:3]};
        decay_next = (len > step) ? (len - step) : 8'd0;
    end
endfunction

wire [ANGBITS-1:0] ang_idx = cd_ang[15 -: ANGBITS];

/* THREE phases, not two - dp_ram registers its port A read, so an address put
   up in cycle n only yields o_douta in n+1 and has to be consumed a full cycle
   after the address settles. Squash it to two and every entry gets compared
   against the PREVIOUS address's data: max accumulate keeps the wrong value
   everywhere and latches X on the first sweep. That is why the bin cadence is
   4 clocks.

   Decay reuses the same three phases but only ISSUES in ST_IDLE, where the
   pipeline is provably empty (ST_DRAIN outlasts its ~26-clock latency). So a
   decay RMW can't steal a measurement's slot, and a measurement can't land
   between a decay bin's read and its write. */
always @(posedge i_clk) begin
    if (i_rst) begin
        tbl_we    <= 1'b0;
        rmw_st    <= 2'd0;
        rmw_decay <= 1'b0;
        tbl_addr  <= {ANGBITS{1'b0}};
        tbl_din   <= {TBLW{1'b0}};
        decay_ctr <= 24'd0;
        decay_run <= 1'b0;
        didx      <= {ANGBITS{1'b0}};
    end
    else begin
        tbl_we <= 1'b0;

        if (decay_ctr == DECAY_CYCLES - 24'd1) begin
            decay_ctr <= 24'd0;
            decay_run <= 1'b1;
        end
        else
            decay_ctr <= decay_ctr + 24'd1;

        case (rmw_st)
        2'd0: if (draw_ok) begin              // present the read address
                  tbl_addr  <= ang_idx;
                  rmw_idx   <= ang_idx;
                  rmw_len   <= len_sat;
                  rmw_frq   <= frq_at_out;
                  rmw_decay <= 1'b0;
                  rmw_st    <= 2'd1;
              end
              else if (decay_run && (state == ST_IDLE)) begin
                  tbl_addr  <= didx;
                  rmw_idx   <= didx;
                  rmw_decay <= 1'b1;
                  rmw_st    <= 2'd1;
              end
        2'd1: rmw_st <= 2'd2;                 // RAM is reading this cycle
        2'd2: begin                           // tbl_douta is valid now
                  tbl_addr <= rmw_idx;
                  if (rmw_decay) begin
                      /* empty bins skip the write */
                      tbl_din <= {tbl_douta[TBLW-1:8],
                                  decay_next(tbl_douta[7:0])};
                      tbl_we  <= (tbl_douta[7:0] != 8'd0);
                      if (didx == {ANGBITS{1'b1}})
                          decay_run <= 1'b0;
                      didx <= didx + 1'b1;
                  end
                  else begin
                      /* LENGTH ONLY. Compare the whole word and the frequency
                         code, sitting above the length, decides the max - a
                         weak high-frequency bin then evicts a strong
                         low-frequency one and both ray and colour go wrong. */
                      tbl_din <= (tbl_douta[7:0] > rmw_len) ? tbl_douta
                                                            : {rmw_frq, rmw_len};
                      tbl_we  <= 1'b1;
                  end
                  rmw_st <= 2'd0;
              end
        default: rmw_st <= 2'd0;
        endcase
    end
end

dp_ram #(.ADDRBITS(ANGBITS), .BITS(TBLW)) angTbl (
    .i_clka(i_clk),
    .i_wea(tbl_we),
    .i_addra(tbl_addr),
    .i_dina(tbl_din),
    .o_douta(tbl_douta),
    .i_clkb(i_rdClk),
    .i_addrb(i_rdAddr),
    .o_doutb({o_rdFrq, o_rdLen})
);

endmodule
