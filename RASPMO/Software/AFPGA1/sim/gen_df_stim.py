#!/usr/bin/env python3
"""Stimulus for tb_df_amp: four channel amplitudes for a source at each test
bearing, in the stored log-count domain (0.376dB per count).

Pattern model G = 1 + a*cos(delta) is the one the four-beam DFT is exact for,
so any bearing error the check reports is the implementation's, not the
model's. Bearing 0 is repeated last: it is also the first test, and the first
sweep after reset once silently produced nothing (an RMW read-timing bug), so
running it twice distinguishes an init artifact from a real bearing bug."""
import math, sys

out = sys.argv[1] if len(sys.argv) > 1 else "stim.hex"
BORE = [0, 90, 180, 270]      # ch0=E, ch1=N, ch2=W, ch3=S as the TB instantiates them
A = 0.8
tests = list(range(0, 360, 15)) + [0]
with open(out, "w") as f:
    for th in tests:
        amps = [max(0, min(255, round(200 + 10 * math.log10(1.0 + A * math.cos(
                math.radians(th - psi))) / 0.376))) for psi in BORE]
        f.write("%02x%02x%02x%02x\n" % tuple(amps))
with open("df_truth.txt", "w") as f:
    f.write("\n".join(str(t) for t in tests))
print("wrote %d tests to %s (set NTEST=%d in tb_df_amp.v)" % (len(tests), out, len(tests)))
