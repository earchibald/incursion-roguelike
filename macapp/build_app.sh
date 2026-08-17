#!/bin/bash
# Build dist/Incursion.app -- the native macOS application.
#
#   macapp/build_app.sh              ad-hoc signed, runs on this machine
#   SIGN_ID=auto macapp/build_app.sh sign with the Developer ID certificate
#                                    if the keychain has one (none on this
#                                    machine today; see bead inc-9df.7)
#
# What goes in and why:
#   engine     build/libincursion-mac-ship.a -- the COMPILER=no library:
#              no resource compiler, no GPLv2 ACCENT code (src/Art.cpp:2-7)
#   module     mod/Incursion.Mod, recompiled every time by the classic
#              developer binary. Registry writes raw struct bytes, so the
#              module must come from a developer build of the SAME source
#              (tools/package_macos.sh:54-59 does the identical dance).
#   LICENSES   regenerated from the canonical texts by
#              tools/gen_app_licenses.sh.
#
# The app keeps its writable state in ~/Library/Application Support/Incursion
# (or $INCURSIONPATH), so the bundle stays signed and read-only -- the split
# that bead inc-9df.8 names as what a real .app needs.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP="$ROOT/dist/Incursion.app"
SWIFT_ENV=()
# SwiftUI-era toolchains fail under bare CommandLineTools on this machine;
# use the full Xcode when it is present. See docs/PORT-STATUS.md.
if [ -d /Applications/Xcode.app ] && ! xcodebuild -version >/dev/null 2>&1; then
    SWIFT_ENV=(env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer)
fi

echo "--- engine library (shipping) ---"
COMPILER=no BACKEND=mac ./build_macos.sh > /dev/null
echo "build/libincursion-mac-ship.a"

echo "--- game data module (developer binary, fresh) ---"
# Rebuild the developer binary unconditionally, with its variant pinned
# against whatever COMPILER/OUT/BACKEND the caller's environment carries: a
# stale or wrong-variant ./incursion would stamp the module with a layout
# the freshly built engine library does not have, and nothing would notice
# (tools/package_macos.sh rebuilds for the same reason).
COMPILER=yes BACKEND=libtcod OUT=incursion EXTRA_CXXFLAGS= ./build_macos.sh > /dev/null
"$ROOT/incursion" -compile main.irc > /dev/null
echo "mod/Incursion.Mod"

echo "--- license document ---"
tools/gen_app_licenses.sh "$ROOT/macapp/Resources/LICENSES.md"

echo "--- icon ---"
ICONSET="$ROOT/build/Incursion.iconset"
rm -rf "$ICONSET"
"${SWIFT_ENV[@]}" swift macapp/gen_icon.swift "$ICONSET" > /dev/null
iconutil -c icns "$ICONSET" -o "$ROOT/build/Incursion.icns"
echo "build/Incursion.icns"

echo "--- app binary ---"
BIN="$ROOT/macapp/.build/release/IncursionApp"
# Remove the previous product first: a failed compile would otherwise leave
# it in place and this script would package a stale binary as fresh.
rm -f "$BIN"
SWIFT_LOG="$(mktemp)"
if ! (cd macapp && "${SWIFT_ENV[@]}" \
        INCURSION_ENGINE_LIB=incursion-mac-ship \
        swift build -c release > "$SWIFT_LOG" 2>&1); then
    grep -vE "was built for newer" "$SWIFT_LOG" | tail -40
    rm -f "$SWIFT_LOG"
    echo "swift build failed"
    exit 1
fi
rm -f "$SWIFT_LOG"
[ -x "$BIN" ] || { echo "swift build produced no binary"; exit 1; }

echo "--- assembling $APP ---"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Incursion"
cp "$ROOT/macapp/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/mod/Incursion.Mod" "$APP/Contents/Resources/Incursion.Mod"
cp "$ROOT/macapp/Resources/LICENSES.md" "$APP/Contents/Resources/LICENSES.md"
cp "$ROOT/build/Incursion.icns" "$APP/Contents/Resources/Incursion.icns"

echo "--- signing ---"
IDENTITY=""
if [ "${SIGN_ID:-}" = auto ]; then
    IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null |
        awk -F'"' '/Developer ID Application/ { print $2; exit }')"
fi
if [ -n "$IDENTITY" ]; then
    codesign --force --deep --timestamp --options runtime \
        --sign "$IDENTITY" "$APP"
    echo "signed: $IDENTITY"
else
    codesign --force --deep --sign - "$APP"
    echo "signed: ad-hoc (no Developer ID; see bead inc-9df.7)"
fi

codesign -v "$APP"
echo
echo "Built: $APP"
echo "Verify: tools/check_app.sh"
