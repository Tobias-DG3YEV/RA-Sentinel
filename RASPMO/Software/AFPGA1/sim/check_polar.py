#!/usr/bin/env python3
"""Check tb_polar_view geometry.

Frame 2 - uniform table: the lit pixels must form a disc of the commanded
radius, and its area must match pi*r^2. Area is the real test: it catches a
wrong CORDIC magnitude or a broken K compensation, which a radius check alone
would not.
Frame 3 - table populated only near 90deg: the ray must point UP the screen,
which is what pins down the angle convention end to end.
All frames - o_active is the alpha mask for the blend over the spectra, so it
must be high ONLY on drawn pixels. A claimed black pixel would punch a black
hole in a spectrum, so any is a failure.
Frame 2 - o_shade, the disc the spectra are darkened under, must be a disc of
R_MAX (area again, not just radius) and must cover every drawn pixel: a drawn
pixel outside it would be blended over an unveiled background.
Frames 2/3 - ray colour comes from the FREQUENCY code, not the amplitude, so
every ray pixel in a frame must carry the one colour that frame's code maps to.
The two frames drive the two ends of the ramp."""
import math, sys
from collections import defaultdict

GRAT = (48, 48, 48)
# freqmap(code) at the two codes the testbench drives, per frame
FRQ_COLOUR = {2: (0, 0, 255), 3: (255, 0, 255)}   # blue at 0, violet at 255
CX = CY = 64          # region is 128x128 in the testbench
RMAX = 48             # ...with R_MAX 48
px = defaultdict(list)
shade = set()
for line in open(sys.argv[1]):
    if line.startswith("PX"):
        _, f, x, y, r, g, b = line.split()
        px[int(f)].append((int(x), int(y), (int(r), int(g), int(b))))
    elif line.startswith("SH"):
        _, x, y = line.split()
        shade.add((int(x), int(y)))

bad = []
# all frames: nothing claimed that is not drawn (the transparency contract)
blank = [(f, x, y) for f, pl in px.items() for x, y, c in pl if c == (0, 0, 0)]
if blank:
    f, x, y = blank[0]
    bad.append("o_active claims %d undrawn (black) pixel(s), e.g. frame %d (%d,%d)"
               " - the pane would not be transparent there" % (len(blank), f, x, y))
print("  mask: %d claimed pixels, %d of them black" %
      (sum(len(v) for v in px.values()), len(blank)))

# frame 2: the shade disc, and it must cover everything drawn
if not shade:
    bad.append("shade: no shaded pixels")
else:
    rad = [math.hypot(x - CX, CY - y) for x, y in shade]
    maxr, area = max(rad), len(shade)
    ideal = math.pi * maxr ** 2
    if abs(maxr - RMAX) > 1.5:
        bad.append("shade radius %.1f, expected ~%d" % (maxr, RMAX))
    if abs(area - ideal) / ideal > 0.02:
        bad.append("shade area %d vs pi*r^2 %.0f (>2%%)" % (area, ideal))
    loose = [(x, y) for x, y, _ in px.get(2, []) if (x, y) not in shade]
    if loose:
        bad.append("%d drawn pixel(s) outside the shade disc, e.g. %s - would"
                   " blend over an unveiled background" % (len(loose), loose[0]))
    print("  shade: radius %.1f, area %d vs pi*r^2 %.0f, %d drawn pixel(s) uncovered"
          % (maxr, area, ideal, len(loose)))

# frame 2: disc, commanded length 24
ray = [p for p in px.get(2, []) if p[2] != GRAT]
if not ray:
    bad.append("disc: no ray pixels")
else:
    rad = [math.hypot(x - CX, CY - y) for x, y, _ in ray]
    maxr, area = max(rad), len(ray)
    ideal = math.pi * maxr ** 2
    if abs(maxr - 24) > 1.5:
        bad.append("disc radius %.1f, expected ~24" % maxr)
    if abs(area - ideal) / ideal > 0.02:
        bad.append("disc area %d vs pi*r^2 %.0f (>2%%)" % (area, ideal))
    print("  disc: radius %.1f, area %d vs pi*r^2 %.0f" % (maxr, area, ideal))

# frame 3: ray near 90deg must point up
ray = [p for p in px.get(3, []) if p[2] != GRAT]
if not ray:
    bad.append("ray: no ray pixels")
else:
    a = [math.degrees(math.atan2(CY - y, x - CX)) % 360 for x, y, _ in ray if (x, y) != (CX, CY)]
    if not (88.0 <= min(a) and max(a) <= 93.0):
        bad.append("ray bearing %.1f..%.1f, expected within 88..93 (up)" % (min(a), max(a)))
    print("  ray: bearing %.1f..%.1f deg" % (min(a), max(a)))

# frames 2/3: every ray pixel carries that frame's frequency colour
for f, want in sorted(FRQ_COLOUR.items()):
    ray = [p for p in px.get(f, []) if p[2] != GRAT]
    wrong = [p for p in ray if p[2] != want]
    if not ray:
        bad.append("colour: frame %d has no ray pixels" % f)
    elif wrong:
        bad.append("colour: frame %d has %d ray pixel(s) not %s, e.g. (%d,%d)=%s"
                   % (f, len(wrong), want, wrong[0][0], wrong[0][1], wrong[0][2]))
    else:
        print("  colour: frame %d all %d ray pixels %s" % (f, len(ray), want))

for b in bad:
    print("  FAIL", b)
print("%s polar_view" % ("PASS" if not bad else "FAIL"))
sys.exit(1 if bad else 0)
