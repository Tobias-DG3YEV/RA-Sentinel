#!/usr/bin/env python3
"""Check tb_cordic_vec output against exact atan2/hypot.

o_mag carries the CORDIC processing gain K on purpose (see cordic_vec.v), so
the reference is K*hypot, not hypot."""
import math, sys

K = 1.6467602578654548
LIMITS = [(100, 0.05, 0.10), (16, 0.05, 1.00), (4, 0.05, 6.00)]  # |v|, deg, mag%

rows = []
for line in open(sys.argv[1]):
    if line.startswith("RES"):
        _, x, y, m, a = line.split()
        rows.append((int(x), int(y), int(m), int(a)))
if not rows:
    print("FAIL cordic: no RES lines"); sys.exit(1)

bad = 0
for thr, dlim, mlim in LIMITS:
    wa = wm = 0.0
    for x, y, m, a in rows:
        d = math.hypot(x, y)
        if d < thr:
            continue
        ta = (math.degrees(math.atan2(y, x)) % 360) / 360 * 65536
        wa = max(wa, abs((a - ta + 32768) % 65536 - 32768) * 360 / 65536)
        wm = max(wm, abs(m - d * K) / (d * K) * 100)
    ok = (wa <= dlim) and (wm <= mlim)
    bad += 0 if ok else 1
    print("%-4s cordic |v|>=%-5d angle %.4f deg (<=%.2f)  mag %.2f%% (<=%.2f)" %
          ("ok" if ok else "FAIL", thr, wa, dlim, wm, mlim))
print("%s cordic (%d vectors)" % ("PASS" if not bad else "FAIL", len(rows)))
sys.exit(1 if bad else 0)
