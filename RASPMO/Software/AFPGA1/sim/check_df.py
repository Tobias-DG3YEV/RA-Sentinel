#!/usr/bin/env python3
"""Check tb_df_amp: every test bearing must produce exactly one angle-table
entry, at the right bearing. A MISSING entry is as much a failure as a wrong
one - that is how the first-sweep-after-reset bug showed up.

Each entry also carries the frequency code of the bin that won that bearing,
which polar_view colours the ray with. The stimulus only ever populates SIGBIN,
so every entry must report SIGBIN's code - anything else means the code and the
amplitude came out of the pipeline out of step, which on screen is a ray of the
wrong colour rather than a missing one, and is invisible without this check."""
import sys
from collections import defaultdict

TOL_DEG = 1.5
SIGBIN, FRQSHIFT = 100, 2      # tb_df_amp's signal bin, and FFTLEN-FRQBITS
WANT_FRQ = SIGBIN >> FRQSHIFT
log, truth = sys.argv[1], sys.argv[2]
tests = [int(l) for l in open(truth) if l.strip()]

res = defaultdict(list)
for line in open(log):
    if line.startswith("TBL"):
        _, t, i, v, f = line.split()
        res[int(t)].append((int(i), int(v), int(f)))

bad = []
worst = 0.0
for t, th in enumerate(tests):
    e = res.get(t, [])
    if not e:
        bad.append("bearing %d: NO RAY" % th); continue
    idx, _, _ = max(e, key=lambda p: p[1])
    wrong_frq = [(i, f) for i, _, f in e if f != WANT_FRQ]
    if wrong_frq:
        bad.append("bearing %d: %d entry/entries with frequency code %d, expected"
                   " %d (bin %d)" % (th, len(wrong_frq), wrong_frq[0][1],
                                     WANT_FRQ, SIGBIN))
    rec = idx * 360.0 / 512
    err = (rec - th + 180) % 360 - 180
    worst = max(worst, abs(err))
    if abs(err) > TOL_DEG:
        bad.append("bearing %d: got %.1f (err %+.1f)" % (th, rec, err))
for b in bad:
    print("  FAIL", b)
print("%s df: %d/%d bearings, worst error %.1f deg (tol %.1f), all frequency"
      " codes %d" % ("PASS" if not bad else "FAIL", len(tests) - len(bad),
                     len(tests), worst, TOL_DEG, WANT_FRQ))
sys.exit(1 if bad else 0)
