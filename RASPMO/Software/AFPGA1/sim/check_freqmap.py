#!/usr/bin/env python3
"""Check freqmap against an independent model of the ramp it is supposed to be.

The model is the obvious one - five anchors, evenly spaced, linear in between:

    0 blue -> 64 green -> 128 yellow -> 192 red -> 255 violet

and every code is compared against it, not just the anchors. Three things are
checked, in increasing order of what they would actually cost on screen:

  anchors    exact at 0/64/128/192/255. A wrong anchor is a wrong colour scheme.
  continuity no channel may jump by more than one step between adjacent codes.
             A seam at a segment boundary is a visible band edge in the middle
             of a smooth ramp, and it is the classic failure of a hand-written
             piecewise map.
  monotonic  within a segment each channel moves one way only. Catches a
             sign/complement error that still happens to hit both anchors.
"""
import sys

ANCHORS = [(0,   (0x00, 0x00, 0xFF)),   # blue
           (64,  (0x00, 0xFF, 0x00)),   # green
           (128, (0xFF, 0xFF, 0x00)),   # yellow
           (192, (0xFF, 0x00, 0x00)),   # red
           (255, (0xFF, 0x00, 0xFF))]   # violet

got = {}
for line in open(sys.argv[1]):
    if line.startswith("FM"):
        _, c, r, g, b = line.split()
        got[int(c)] = (int(r), int(g), int(b))

bad = []
if len(got) != 256:
    bad.append("expected 256 codes, got %d" % len(got))

for code, want in ANCHORS:
    if got.get(code) != want:
        bad.append("anchor %d: got %s, expected %s" % (code, got.get(code), want))

# continuity: the ramp covers 255 counts over 64 codes, so ~4 per step; allow 5
STEP_MAX = 5
for c in range(1, 256):
    if c not in got or c - 1 not in got:
        continue
    for ch, name in enumerate("rgb"):
        d = abs(got[c][ch] - got[c - 1][ch])
        if d > STEP_MAX:
            bad.append("seam at code %d in %s: %d -> %d (jump %d)"
                       % (c, name, got[c - 1][ch], got[c][ch], d))

# monotonic within each segment
for lo, hi in [(0, 63), (64, 127), (128, 191), (192, 255)]:
    for ch, name in enumerate("rgb"):
        seq = [got[c][ch] for c in range(lo, hi + 1) if c in got]
        up = all(x <= y for x, y in zip(seq, seq[1:]))
        dn = all(x >= y for x, y in zip(seq, seq[1:]))
        if not (up or dn):
            bad.append("segment %d..%d not monotonic in %s" % (lo, hi, name))

for b in bad:
    print("  FAIL", b)
print("%s freqmap (%d codes, anchors exact, max step %d)"
      % ("PASS" if not bad else "FAIL", len(got),
         max((abs(got[c][ch] - got[c-1][ch])
              for c in range(1, 256) for ch in range(3)
              if c in got and c-1 in got), default=0)))
sys.exit(1 if bad else 0)
