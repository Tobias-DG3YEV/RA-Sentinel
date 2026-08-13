#!/usr/bin/env python3
"""Stimulus for tb_cordic_vec: full angle sweeps at several magnitudes, the
axis/full-scale corner cases, and 300 fixed-seed random vectors.

The small-magnitude sweeps are the point of this file, not filler: without
guard bits the CORDIC's per-stage right shifts truncate to -1 and the
iteration diverges, which is invisible at large |v| and catastrophic at small
|v| - exactly where the renderer (pixel offsets) and the DF engine (dB
differences) actually operate."""
import math, random, sys

out = sys.argv[1] if len(sys.argv) > 1 else "vectors.hex"
random.seed(7)
vecs = []
for mag in (1000, 32000, 37, 5):
    for adeg in range(0, 360, 3):
        a = math.radians(adeg)
        vecs.append((round(mag * math.cos(a)), round(mag * math.sin(a))))
vecs += [(0, 0), (1, 0), (0, 1), (-1, 0), (0, -1), (32767, 0), (-32768, 0),
         (0, 32767), (0, -32768), (32767, 32767), (-32768, -32768), (32767, -32768)]
for _ in range(300):
    vecs.append((random.randint(-32768, 32767), random.randint(-32768, 32767)))

with open(out, "w") as f:
    for x, y in vecs:
        f.write("%04x%04x\n" % (x & 0xFFFF, y & 0xFFFF))
print("wrote %d vectors to %s (set NVEC=%d in tb_cordic_vec.v)" % (len(vecs), out, len(vecs)))
