#!/bin/bash
# Does a mouse click do exactly what its keystroke does?
#
# Runs tools/keys/mouse-smoke.keys (clicks) through the mac backend's parity
# driver, and tools/keys/mouse-smoke-kb.keys (the same session by keyboard)
# through the PROVEN posix backend, same seed, same pinned options. Then
# diffs every dumped screen body. Identical bodies prove the whole chain --
# mouse event -> Wmac queue -> KY_MOUSE -> LMenu/EffectPrompt hit-testing --
# lands in the very accept paths the keyboard uses, across two backends.
#
# Headers are stripped before the diff: click tokens and keystrokes are
# counted differently, so the "key N" figures legitimately disagree.
#
# PASS is exit 0 and the word PASS on the last line.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

POSIX_BIN=./incursion-headless
MAC_BIN=./build/macterm-parity
[ -x "$POSIX_BIN" ] || { echo "$POSIX_BIN not built. Run: BACKEND=posix ./build_macos.sh"; exit 2; }
[ -x "$MAC_BIN" ]   || { echo "$MAC_BIN not built. Run: PARITY=yes BACKEND=mac ./build_macos.sh"; exit 2; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/incursion-macmouse.XXXXXX")"
# Evidence survives a failure; success cleans up.
cleanup() {
    if [ "${FAILED:-1}" -eq 0 ]; then
        rm -rf "$WORK"
    else
        KEEP="$ROOT/logs/runs/macmouse-fail-$(date +%Y%m%d-%H%M%S)"
        mkdir -p "$ROOT/logs/runs"
        mv "$WORK" "$KEEP" 2>/dev/null && echo "evidence kept: $KEEP"
    fi
}
trap cleanup EXIT

INCURSION_BIN="$MAC_BIN" \
INCURSION_RUN_DIR="$WORK/mouse" \
INCURSION_OPTIONS="$ROOT/tools/gates/Options.Dat" \
INCURSION_DUMP_COLOR=1 \
    tools/headless.sh tools/keys/mouse-smoke.keys 1 > "$WORK/mouse.out" 2>&1
MS=$?

INCURSION_BIN="$POSIX_BIN" \
INCURSION_RUN_DIR="$WORK/kb" \
INCURSION_OPTIONS="$ROOT/tools/gates/Options.Dat" \
INCURSION_DUMP_COLOR=1 \
    tools/headless.sh tools/keys/mouse-smoke-kb.keys 1 > "$WORK/kb.out" 2>&1
KS=$?

FAILED=0
if [ "$MS" != 0 ] || [ "$KS" != 0 ]; then
    echo "FAIL: sessions did not end cleanly (mouse $MS, keyboard $KS)"
    tail -12 "$WORK/mouse.out" | sed 's/^/  mouse: /'
    tail -12 "$WORK/kb.out" | sed 's/^/  kb:    /'
    echo "FAIL"
    exit 1
fi

for m in "$WORK/mouse/logs/screens/"*.txt; do
    name="$(basename "$m")"
    k="$WORK/kb/logs/screens/$name"
    if [ ! -f "$k" ]; then
        echo "FAIL: keyboard run has no screen $name"
        FAILED=1
        continue
    fi
    # Only the key-count figure may differ (clicks and keystrokes are
    # counted differently); the mode field still has to match.
    if ! diff <(sed -E '1s/ key [0-9]+//' "$m") <(sed -E '1s/ key [0-9]+//' "$k") \
            > "$WORK/$name.diff" 2>&1; then
        echo "FAIL: $name differs between click and keystroke --"
        head -12 "$WORK/$name.diff" | sed 's/^/  /'
        FAILED=1
    else
        echo "ok:   $name identical by click and by keystroke"
    fi
done

if [ "$FAILED" -ne 0 ]; then
    echo "FAIL"
    exit 1
fi
echo "PASS"
