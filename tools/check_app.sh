#!/bin/bash
# Is dist/Incursion.app fit to hand to a person?
#
# The checks mirror tools/check_package.sh for the folder release, adapted
# to a bundle:
#   1  the GPLv2 ACCENT runtime must not be in the binary (yyparse and
#      friends are every function src/Art.cpp defines; 'accent' appears in
#      no symbol, so do not grep for it)
#   2  no SDL and no libtcod -- the native app links neither
#   3  the data module and the license document are in Resources
#   4  the code signature verifies
#   5  the binary is arm64 and claims macOS 14 minimum
#
# PASS is exit 0 and the word PASS on the last line.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/Incursion.app"
BIN="$APP/Contents/MacOS/Incursion"

FAILED=0
fail() { echo "FAIL: $*"; FAILED=1; }

[ -d "$APP" ] || { echo "FAIL: $APP not built. Run: macapp/build_app.sh"; echo "FAIL"; exit 1; }
[ -x "$BIN" ] || fail "no executable at $BIN"

if [ -x "$BIN" ]; then
    n="$(nm "$BIN" 2>/dev/null | grep -c 'yyparse\|yyselect\|yymallocerror')"
    [ "$n" = 0 ] || fail "binary contains $n ACCENT (GPLv2) symbols"

    if otool -L "$BIN" | grep -qiE 'SDL|tcod'; then
        fail "binary links SDL or libtcod"
    fi

    info="$(otool -l "$BIN" | grep -A4 'LC_BUILD_VERSION' | grep minos | head -1)"
    case "$info" in
        *14.0*) : ;;
        *) fail "minimum OS is not 14.0: ${info:-none found}" ;;
    esac

    arch="$(lipo -archs "$BIN" 2>/dev/null)"
    case "$arch" in
        *arm64*) : ;;
        *) fail "no arm64 slice (got: $arch)" ;;
    esac
fi

[ -f "$APP/Contents/Resources/Incursion.Mod" ] || fail "Incursion.Mod missing from Resources"
[ -f "$APP/Contents/Resources/LICENSES.md" ]   || fail "LICENSES.md missing from Resources"
for needle in "OPEN GAME LICENSE" "Matsumoto" "Richard Tew" "Julian Mensch" \
              "Expat"; do
    grep -q "$needle" "$APP/Contents/Resources/LICENSES.md" 2>/dev/null \
        || fail "LICENSES.md lacks required text: $needle"
done

# The app must carry nothing outside the system: a stray Homebrew dylib
# reference means it runs on this machine only (the folder release had
# exactly this bug once; see inc-9df.6).
if otool -L "$BIN" 2>/dev/null | grep -vE "^\S|/usr/lib/|/System/" | grep -q .; then
    fail "binary references a non-system dylib: $(otool -L "$BIN" | grep -vE '^\S|/usr/lib/|/System/' | head -2 | tr -d '\t')"
fi

codesign -v "$APP" 2>/dev/null || fail "code signature does not verify"

if [ "$FAILED" -ne 0 ]; then
    echo "FAIL"
    exit 1
fi
echo "PASS"
