# Direction-finder RTL regression

Simulation checks for the polar DF indicator: `cordic_vec.v`, `freqmap.v`,
`polar_view.v` and `df_amp.v`. Each testbench is checked against an
**independent reference model** in Python rather than against golden vectors captured from the RTL, so
a check passing means the hardware agrees with the maths, not with its own
previous output.

## Running

    source /tools/2025.2/Vivado/settings64.sh     # if xvlog is not on PATH
    ./sim/run_sims.sh                             # all four
    ./sim/run_sims.sh cordic                      # cordic | freqmap | polar | df

Exits non-zero if anything fails, so it can gate a build. All scratch goes in
`sim/work/`, which is gitignored.

## Layout

| path | what |
|---|---|
| `rtl/sim/tb_*.v` | the testbenches |
| `sim/gen_*.py` | stimulus generators |
| `sim/check_*.py` | reference models and pass/fail thresholds |
| `sim/run_sims.sh` | build stimulus, simulate, check |

The testbenches deliberately live in `rtl/sim`, **not** `rtl/sources`.
`run_impl.tcl` globs `rtl/sources/*.v` and re-adds anything missing to the
synthesis fileset, so a testbench parked there would be pulled in as a design
source and break the build.

## What each check actually proves

**`cordic_vec`** - 792 vectors: full angle sweeps at |v| = 5/37/1000/32000, the
axis and full-scale corner cases, and 300 fixed-seed random ones. Compared
against exact `atan2`/`hypot`. Note the reference for magnitude is `K*hypot`,
not `hypot`: the CORDIC processing gain K = 1.64676 is left in on purpose and
folded into downstream scaling constants (see the module header).

The small-magnitude sweeps are the entire point of this stimulus. Without guard
bits the per-stage right shifts truncate to -1, the iteration stops converging,
and input `(1,0)` returns magnitude 16 instead of 1.65 while `(4,2)` comes out
20 degrees wrong - invisible at large |v|, and both the renderer (pixel offsets
near the centre) and the DF engine (dB differences of a few tens) live exactly
in that regime. Thresholds are set per magnitude band so a regression there
fails loudly instead of being averaged away.

**`freqmap`** - all 256 codes against the ramp it is meant to be: five evenly
spaced anchors, blue-green-yellow-red-violet, linear between them. Anchors have
to be exact, no channel may jump more than one step between adjacent codes, and
each channel must move one way only within a segment. The step check is the one
that earns its keep - a seam at a segment boundary is a visible band edge in the
middle of a smooth ramp and is the classic failure of a hand-written piecewise
map, while a sign error that still hits both anchors is what the monotonicity
check is for.

**`polar_view`** - renders two frames into a small pane and checks the lit
pixels. A uniform angle table must draw a disc whose **area matches pi\*r^2**;
that is the real test, because a radius check alone would pass a broken CORDIC
magnitude or a wrong K compensation while the shape quietly went elliptical. A
table populated only near 90 degrees must draw a ray pointing **up** the
screen, which pins the angle convention down end to end - DF differences,
CORDIC quadrant, screen dy sign, all of it.

The remaining checks are on the two masks top.v composites with, which is where
the bugs have actually been.

`o_active`, the alpha mask for blending the indicator over the spectra, must be
high **only where the module draws**. The testbench therefore prints every
claimed pixel rather than only the non-black ones, and any claimed black pixel
is a failure - it would punch a black hole in a spectrum. While `o_active` still
meant "inside the pane" nothing in the regression noticed, because the geometry
checks filter on colour and a whole-pane mask draws the same disc.

`o_shade`, the disc the spectra are darkened under, gets the same area test as
the ray disc and must **cover every drawn pixel** - one outside it would be
blended over an unveiled background.

Ray **colour** is checked on rendered pixels, not on the map in isolation: the
testbench drives one frequency code per frame and every ray pixel of that frame
must carry the colour it maps to. That covers the whole path - table, the
register that has to stay in step with the length, `freqmap`, the output mux.
The two frames drive the two ENDS of the ramp on purpose. Code 0 is what a
cleared table entry carries, so a plumbing bug that zeroes the code still paints
a perfectly plausible blue ray; only the violet frame catches it.

The shade check immediately earned itself: it caught a `LOOKAHEAD`-wide stripe
of stale mask down the left edge of the screen, from the pipeline being primed
through blanking with `active_x` parked at 0. That bug was always in the module
and had been invisible for a geometric reason - with the indicator in the
bottom-right pane the stale radius was 1419px, far outside the disc. The
testbench's 128px region puts it at 47px against `R_MAX` 48, i.e. right inside,
which is why a small region is worth simulating even though the real one is
1920x1080. The fix qualifies both masks with DE as it was at feed time, so the
first `LOOKAHEAD` columns of a line are simply never drawn; that clips the
leftmost column of the testbench's disc, and nothing at all at the real centre.

**`df_amp`** - drives one populated FFT bin with the four channel amplitudes a
source at a known bearing would produce, and checks the recovered bearing from
the angle table. 24 bearings at 15-degree steps, plus **bearing 0 repeated at
the end**.

Each entry also carries the frequency code of the winning bin, and the check
requires every entry to report the code of `SIGBIN` - the only bin the stimulus
ever populates. The colour code rides its own delay line beside the amplitude
through five pipeline stages and the CORDIC, and if the two come out of step the
result is a ray of the wrong colour rather than a missing one: nothing else in
the regression would notice, and on screen it would just look like a signal at
some other frequency.

That repeat is not redundant. Bearing 0 is also the first test, and the first
sweep after reset once produced nothing at all while every later sweep looked
fine - the angle table read-modify-write consumed `dp_ram`'s registered port A
output one cycle early, so it compared against the previous address's data and
latched X on the first pass. Running the same stimulus first and last separates
"broken at this bearing" from "broken on the first sweep". A **missing** entry
is treated as a failure, not just a wrong one.

The pattern model is `G = 1 + a*cos(delta)`, the one the four-beam DFT is exact
for, so any error the check reports belongs to the implementation rather than
the model. Real element patterns deviate from it - see the beamwidth note in
`df_amp.v` - so this bounds the arithmetic, not the absolute field accuracy.

## Keeping the testbenches in step

`tb_cordic_vec.v` and `tb_df_amp.v` hardcode `NVEC` / `NTEST` to match their
stimulus files; both generators print the value to set if you change the
stimulus. `STAGES` and `CGUARD` are also hardcoded in the testbench
instantiations and must track whatever `top.v` passes to the real instances -
they were reduced from 16/12 to 12/10 when the 16-stage version cost timing.

`check_df.py` hardcodes `SIGBIN` and `FRQSHIFT` (= `FFTLEN - FRQBITS`) to derive
the frequency code it expects; both must follow the testbench and `top.v`.

`tb_polar_view.v` deliberately does **not** track `top.v`'s region: the real one
is the whole 1920x1080 screen, and rendering it here would cost 60x the
simulation for the same geometry. `RMAX`/`CX`/`CY` in `check_polar.py` mirror
the testbench's own 128x128 region and must be changed together with it.
