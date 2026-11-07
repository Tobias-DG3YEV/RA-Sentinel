# openFFT versus Xilinx xfft 9.1 in the RA-Sentinel receiver

openofdm's 64-point FFT (`sync_long.v`) comes from openFFT now. The AMD/Xilinx
Fast Fourier Transform 9.1 core is no longer part of any build; after
openViterbi, openCMUL and openCDIV it was the last Xilinx core in the
receiver, so `[openofdm::ip]` is an empty list and the receiver is plain
Verilog from the ADC samples to the decoded bytes. The board design keeps
one Xilinx IP, the `Video_clk` MMCM of the HDMI output.

## What the receiver asks of the FFT

`sync_long.v` feeds each OFDM symbol as a burst of 64 samples in 64
consecutive clocks (16-bit I and Q), with the 20 MHz sample stream arriving
in the background, and takes the 23-bit unscaled result in natural order,
of which it keeps bits 22:7. Symbols are 80 samples = 400 clocks apart at
100 MHz. The IP was configured as *pipelined streaming I/O*, unscaled,
truncation, natural order, non-realtime throttle; its first result arrived
212 clocks after the first sample.

`fft_axis` has the IP's AXI4-Stream ports, data layout and configuration
word, so `sync_long.v` only changed the module name and added the
parameters:

```
fft_axis #(.LOG2_N(6), .DATA_WIDTH(16), .TWIDDLE_WIDTH(16), .ARCH(1),
           .SCALING(0), .ROUND_MODE(0), .OUTPUT_ORDER(1), .LATENCY(212)) dft_inst (...)
```

`ARCH = 1` is the pipelined streaming engine (radix-2^2 single-path delay
feedback, one sample per clock). `LATENCY = 212` pads the engine's natural
141 clocks to the IP's latency, see below.

## Measured comparison

Same conditions for all rows: xc7a100tcsg324-2, Vivado 2025.2
out-of-context synthesis + opt_design, Fmax estimated from the worst slack
against a 5 ns clock. The receiver runs at 100 MHz. BRAM counts RAMB18 and
RAMB36 alike.

| core | configuration | latency | LUT | FF | BRAM | DSP48E1 | Fmax est. |
|---|---|---|---|---|---|---|---|
| Xilinx xfft 9.1 | pipelined streaming, unscaled, natural order | 212 | 1403 | 2609 | 2 | 6 | ~348 MHz |
| openFFT `fft_axis` | streaming, `LATENCY=212` (as instantiated) | 212 | 1344 | 800 | 1 | 8 | ~225 MHz |
| openFFT `fft_axis` | streaming, natural latency | 141 | 1173 | 635 | 1 | 8 | ~225 MHz |
| openFFT `fft_axis` | streaming, `OPTIMIZE_GOAL=0` (three multipliers per complex one) | 143 | 1268 | 943 | 1 | 6 | ~225 MHz |
| openFFT `fft_axis` | burst (`ARCH=0`), one butterfly | 295 | 850 | 446 | 0 | 4 | ~201 MHz |

The whole receiver (`dot11`, out of context, same part and flow):

| | LUT | FF | BRAM | DSP48E1 |
|---|---|---|---|---|
| with xfft 9.1 | 23 917 | 16 266 | 18 | 69 |
| with openFFT | 23 705 | 14 343 | 17 | 71 |

## Verification

* openFFT's bench drives the core and the IP's own simulation netlist
  (`ip_repo/xfft_v9`, written by openofdm's `make refnetlists`) with the
  same 14 400 result samples - random data, tones, impulses, samples at the
  rails, with idle clocks and back pressure: 91 % of the 23-bit results are
  bit-identical, 99.92 % identical in bits 22:7 (what `sync_long.v` keeps),
  no result differs by more than 2 LSB (RMS 0.25 LSB), and both cores show
  the same error against a double precision transform (max 21.8 LSB, RMS
  2.33 LSB). The latency of both is 212 clocks. Seven further configurations
  (burst engine, scaled, bit reversed, 8 .. 256 points, LUT multipliers,
  block RAM) are checked bit for bit against a model of the arithmetic.
* openofdm's `make regression` (31 reference vectors, 802.11a/g rate ladder,
  802.11n MCS 0-7, simulated frames, side-channel and noise captures): every
  vector gives the same verdict, frame count and payload bytes as with the
  IP.
* Hardware, 2026-10-01: the WBMC build with openFFT (`build_wbmc.tcl` and
  the Vivado project alike) meets timing (WNS +0.177 ns) and, loaded over
  JTAG after a power-cycle, shows the usual frame log and decodes on air.

## The latency

With the engine's natural 141 clocks, 30 of the 31 vectors decoded exactly
as before, but the 65 Mbps conducted capture (MCS 7, a weak capture that
yields 3 of 9 frames with the IP) lost those three frames. Delaying the FFT
output by the missing 71 clocks in an experiment restored them, with
identical decode timestamps. The cause is in `dot11.v`, not in the FFT:
after decoding HT-SIG it decides by `num_ofdm_symbol == 5` (sync_long's
count of loaded symbols at that moment) whether the HT-STS symbol has to be
skipped to keep the equalizer aligned - a documented "quick fix" that ties
the control flow to the moment the FFT results come out. The IP's 212
clocks were part of that tuning, so openFFT is instantiated with
`LATENCY = 212` (an SRL delay line, 171 LUT / 165 FF). The proper fix is a
feedback from the decoder to the symbol handling in `dot11.v`; until then
the latency parameter must move together with that logic.

## Building

Nothing to configure when `openFFT` is cloned next to `openofdm` (or
`$OPENFFT` points at it): `tools/openofdm_sources.tcl` returns its
`rtl/*.v` with the receiver sources, `build_wbmc.tcl`, `build_rasbb.tcl`
and the simulation scripts pick them up, and `owifi.xpr` lists them
instead of the `xfft_v9` fileset. No IP is generated for the receiver any
more, so a bitstream build needs no IP catalog and no licence.
