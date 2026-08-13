#!/usr/bin/env bash
# Regression for the direction-finder RTL: builds stimulus, runs the three
# testbenches under xsim, and checks each against an independent reference
# model. Exits non-zero if any check fails, so it can gate a build.
#
#   ./sim/run_sims.sh            run everything
#   ./sim/run_sims.sh cordic     run one (cordic | freqmap | polar | df)
#
# Everything happens under sim/work/, which is gitignored.
set -u

SIM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(dirname "$SIM_DIR")"
SRC="$PROJ/rtl/sources"
TB="$PROJ/rtl/sim"
WORK="$SIM_DIR/work"

command -v xvlog >/dev/null || { echo "xvlog not on PATH - source the Vivado settings first"; exit 2; }

mkdir -p "$WORK"; cd "$WORK" || exit 2
WHICH="${1:-all}"
FAILED=0

run_one() {
    local name="$1"; shift
    local top="$1"; shift
    echo "=== $name ==="
    rm -rf xsim.dir *.pb *.jou *.wdb 2>/dev/null
    xvlog "$@" "$TB/tb_${top}.v" > xvlog.out 2>&1 || { echo "  FAIL compile"; sed -n '1,20p' xvlog.out; FAILED=1; return; }
    xelab -debug typical "tb_${top}" -s simx > xelab.out 2>&1 || { echo "  FAIL elaborate"; grep -i error xelab.out | head; FAILED=1; return; }
    xsim simx -R > "${top}.log" 2>&1 || { echo "  FAIL simulate"; FAILED=1; return; }
}

if [ "$WHICH" = all ] || [ "$WHICH" = cordic ]; then
    python3 "$SIM_DIR/gen_cordic_vectors.py" vectors.hex >/dev/null
    run_one "cordic_vec" cordic_vec "$SRC/cordic_vec.v"
    python3 "$SIM_DIR/check_cordic.py" cordic_vec.log || FAILED=1
fi

if [ "$WHICH" = all ] || [ "$WHICH" = freqmap ]; then
    run_one "freqmap" freqmap "$SRC/freqmap.v"
    python3 "$SIM_DIR/check_freqmap.py" freqmap.log || FAILED=1
fi

if [ "$WHICH" = all ] || [ "$WHICH" = polar ]; then
    run_one "polar_view" polar_view "$SRC/cordic_vec.v" "$SRC/freqmap.v" "$SRC/polar_view.v"
    python3 "$SIM_DIR/check_polar.py" polar_view.log || FAILED=1
fi

if [ "$WHICH" = all ] || [ "$WHICH" = df ]; then
    python3 "$SIM_DIR/gen_df_stim.py" stim.hex >/dev/null
    run_one "df_amp" df_amp "$SRC/cordic_vec.v" "$SRC/dp_ram.v" "$SRC/df_amp.v"
    python3 "$SIM_DIR/check_df.py" df_amp.log df_truth.txt || FAILED=1
fi

echo
[ "$FAILED" -eq 0 ] && echo "ALL CHECKS PASSED" || echo "SOME CHECKS FAILED"
exit $FAILED
