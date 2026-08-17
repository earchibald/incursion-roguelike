#!/bin/bash
# Does the native-app backend play the same game as the proven headless one?
#
# Runs the same key scripts with the same seeds and the same pinned options
# through BOTH backends -- src/Wposix.cpp via ./incursion-headless, and
# src/Wmac.cpp via ./build/macterm-parity -- and diffs every screen dump.
# The Wmac backend feeds the same engine through a different door (an event
# queue and published snapshots instead of a script reader and a live
# buffer), so identical screens mean the door changes nothing: input
# translation, the GetCharCmd frame pump, the glyph grid, save and load.
#
# Options are pinned to tools/gates/Options.Dat, never the live file: the
# live file changes whenever Brian plays, and settings change the game
# (2026-08-15, same binary and seed, different screens across a rewrite).
#
# PASS is exit 0 and the word PASS on the last line. Each script must also
# END CLEANLY in both backends -- two runs that both died identically would
# otherwise count as agreement.
#
# FULL=yes adds the longer scripts (dive12, marathon, the class variants).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

POSIX_BIN=./incursion-headless
MAC_BIN=./build/macterm-parity

[ -x "$POSIX_BIN" ] || { echo "$POSIX_BIN not built. Run: BACKEND=posix ./build_macos.sh"; exit 2; }
[ -x "$MAC_BIN" ]   || { echo "$MAC_BIN not built. Run: PARITY=yes BACKEND=mac ./build_macos.sh"; exit 2; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/incursion-macterm.XXXXXX")"
# Evidence survives a failure: a deleted workdir has already cost one
# debugging round-trip (2026-08-16). Success cleans up.
cleanup() {
    if [ "${FAILED:-1}" -eq 0 ]; then
        rm -rf "$WORK"
    else
        KEEP="$ROOT/logs/runs/macterm-fail-$(date +%Y%m%d-%H%M%S)"
        mkdir -p "$ROOT/logs/runs"
        mv "$WORK" "$KEEP" 2>/dev/null && echo "evidence kept: $KEEP"
    fi
}
trap cleanup EXIT

# script : seed : expected exit. The chargen-only scripts end without ever
# entering a map, so headless.sh promotes their clean exit to 5 by design.
PAIRS="smoke.keys:1:0 chargen-mage.keys:1:5 explore.keys:3:0 dive.keys:2:0"
if [ "${FULL:-no}" = yes ]; then
    # marathon.keys is deliberately absent: at ~40 minutes per side it
    # belongs to soak runs, not a check.
    PAIRS="$PAIRS chargen-priest.keys:1:5 chargen-rogue.keys:1:5 explore-mage.keys:4:0 explore-priest.keys:4:0 explore-rogue.keys:4:0 dive12.keys:5:0"
fi

FAILED=0
for pair in $PAIRS; do
    keys="tools/keys/${pair%%:*}"
    rest="${pair#*:}"
    seed="${rest%%:*}"
    want="${rest##*:}"
    name="$(basename "$keys" .keys)-s$seed"

    for side in posix mac; do
        if [ "$side" = posix ]; then bin="$POSIX_BIN"; else bin="$MAC_BIN"; fi
        INCURSION_BIN="$bin" \
        INCURSION_RUN_DIR="$WORK/$name-$side" \
        INCURSION_OPTIONS="$ROOT/tools/gates/Options.Dat" \
        INCURSION_DUMP_COLOR=1 \
            tools/headless.sh "$keys" "$seed" > "$WORK/$name-$side.out" 2>&1
        echo "$?" > "$WORK/$name-$side.status"
    done

    ps="$(cat "$WORK/$name-posix.status")"
    ms="$(cat "$WORK/$name-mac.status")"

    if [ "$ps" != "$ms" ]; then
        echo "FAIL: $name exit codes differ: posix $ps, mac $ms"
        FAILED=1
        continue
    fi
    if [ "$ps" != "$want" ]; then
        echo "FAIL: $name exited $ps on both sides, wanted $want; fix the"
        echo "      script or seed before reading anything into agreement"
        FAILED=1
        continue
    fi
    if ! diff -r "$WORK/$name-posix/logs/screens" "$WORK/$name-mac/logs/screens" \
            > "$WORK/$name.diff" 2>&1; then
        echo "FAIL: $name screens differ --"
        head -20 "$WORK/$name.diff" | sed 's/^/  /'
        FAILED=1
        continue
    fi
    n="$(ls "$WORK/$name-posix/logs/screens" | wc -l | tr -d ' ')"
    if [ "$n" = 0 ]; then
        echo "FAIL: $name produced no screens at all; agreement about"
        echo "      nothing is not evidence"
        FAILED=1
        continue
    fi
    echo "ok:   $name ($n screens identical, both exited $ps)"
done

if [ "$FAILED" -ne 0 ]; then
    echo "FAIL"
    exit 1
fi
echo "PASS"
