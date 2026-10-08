# openCDIV versus Xilinx div_gen 5.1 in the RA-Sentinel receiver

openofdm's four real divisions come from openCDIV now: the two of the
equalizer (inside `complex_divider`), the LVPE/SFO division (equalizer) and
the arctangent division (`phase.v`), both through `divider.v` ->
`signed_divider`. The Xilinx Divider Generator 5.1 and its
`div_gen_xlslice` are no longer part of any build; after openViterbi and
openCMUL, the FFT (`xfft_v9`) is the only Xilinx core left in the receiver.

## The complex division

The equalizer divides every subcarrier x by the channel estimate h. Division
by a complex number becomes two real divisions after multiplying numerator
and denominator by the conjugate of h:

```
       x      x * conj(h)
  q = --- = -------------
       h     h * conj(h)
```

`h * conj(h) = hr^2 + hi^2` is real, so the real and imaginary parts of
`x * conj(h)` are each divided by it. openCDIV's `complex_divider` does
exactly this with two openCMUL multipliers and two `signed_divider`s, in
openofdm's arithmetic bit for bit: 16-bit x and h, the top 32 bits of the
33-bit products, the numerator scaled by 2^11 (`CONS_SCALE_SHIFT + 1`),
the denominator cut to 24 bits, the quotient rounded toward zero. The same
two dividers also average the channel estimate (a sum of 3..5 LTS samples
divided by their number) through the module's direct `n / d` input.

## Measured comparison

Same conditions for all rows: xc7a100tcsg324-2, Vivado 2025.2
out-of-context synthesis + opt_design, Fmax estimated from the worst slack
against a 3 ns clock. The receiver runs at 100 MHz.

| core | datapath | latency | LUT | FF | DSP48E1 | Fmax est. |
|---|---|---|---|---|---|---|
| Xilinx div_gen 5.1 + xlslice | one real division, 32 / 24 bit | 36 | 952 | 2166 | 0 | ~229 MHz |
| openCDIV `signed_divider` | one real division, 32 / 24 bit | 36 | 968 | 1827 | 0 | ~312 MHz |
| 2x openCMUL + 2x div_gen 5.1 | `x * conj(h) / (h * conj(h))` | 39 | 1963 | 4333 | 6 | ~229 MHz |
| openCDIV `complex_divider` | `x * conj(h) / (h * conj(h))` | 39 | 1976 | 3598 | 6 | ~308 MHz |

The receiver has four dividers. In the routed WBMC design (build_wbmc.tcl,
same source tree, only the dividers changed):

| build | LUT | FF | BRAM tiles | DSP48E1 | WNS |
|---|---|---|---|---|---|
| with div_gen 5.1 | 37 740 | 35 409 | 50 | 104 | +0.018 ns |
| with openCDIV | 37 318 | 32 831 | 50 | 104 | +0.128 ns |

(-422 LUT, -2 578 FF; the LVPE divider has a constant divisor, which
synthesis folds further than it could inside the IP.)

## Verification

* openCDIV's benches: `signed_divider` every clock against the div_gen
  funcsim netlist (cycle-exact, incl. division by zero - `phase.v` takes
  atan(0/0) of a zero sample and relies on the IP's -1), `complex_divider`
  every clock against the former datapath rebuilt from the cmpy and
  div_gen netlists; further parameter sets against behavioural models.
* openofdm's receiver regression (`make regression`, all 40 reference
  vectors: 802.11a rate ladder, 802.11n MCS ladder, radiated and simulated
  captures) before and after the change: identical FCS verdicts and frame
  counts, and all 280 dump files byte-identical - payload bytes, SIGNAL
  fields and the equalizer output streams (214 068 equalized subcarriers).
* WBMC bitstream built from this tree: timing met (see table).
