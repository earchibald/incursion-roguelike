#!/bin/bash
# Is the app's help window fit to ship?
#
# Four things can go wrong with it, and each fails silently in the app -- a
# blank page, a dead link, a guide with no credit on it -- so each is checked
# here instead of being noticed by a player.
#
#   1  THE MANUAL IS THERE AND WHOLE. macapp/Resources/Help/manual.json is
#      generated from the compiled module by `incursion -exporthelp`. Every
#      topic must have text; an empty one means a help resource went missing
#      from the ruleset and nobody saw.
#   2  EVERY LINK LANDS. A topic link must name an exported topic and an
#      anchor link must name an anchor on the page it is on. Three targets
#      are known dead in the base data itself and are listed below; a fourth
#      is a regression.
#   3  EVERY VENDORED PAGE CARRIES ITS LICENCE. CC BY-SA 3.0 requires the
#      title, the author, the licence and a statement of changes. The help
#      window prints them from the file's front matter, so a file missing a
#      field ships a page with no credit on it.
#   4  THE BUNDLE ACTUALLY CONTAINS THEM. dist/Incursion.app is assembled by
#      copying; a mistyped path there leaves the window empty in the shipped
#      app while every check above still passes.
#
# LIVE=yes adds a fifth: launch the app, open the help window, and confirm it
# appears. That needs a display, so it is off by default.
#
# PASS is exit 0 and the word PASS on the last line.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

MANUAL="$ROOT/macapp/Resources/Help/manual.json"
WIKI="$ROOT/macapp/Resources/Help/wiki"
APP="$ROOT/dist/Incursion.app"

FAILED=0
fail() { echo "FAIL: $*"; FAILED=1; }

# --- 1 and 2: the manual ----------------------------------------------------
if [ ! -f "$MANUAL" ]; then
    echo "FAIL: $MANUAL is not built."
    echo "      Run: ./incursion -exporthelp \"$MANUAL\""
    echo "      (macapp/build_app.sh does this as part of a build.)"
    echo "FAIL"
    exit 1
fi

python3 - "$MANUAL" <<'PY'
import json, sys

# Links the base data itself points at and never defines. "custom" is My
# Character, which describes a live character and cannot be exported; the
# other two are written into the powers page and exist nowhere. Anything
# outside this set is a regression in the export or in lib/help.irh.
KNOWN_DEAD = {"custom", "poisons", "psionics"}
MIN_TOPICS = 20

data = json.load(open(sys.argv[1]))
topics = {t["id"]: t for t in data["topics"]}
problems = []

if len(topics) < MIN_TOPICS:
    problems.append(f"only {len(topics)} topics exported, expected at least {MIN_TOPICS}")

for tid, t in topics.items():
    text = "".join(r["s"] for r in t["runs"])
    if len(text.strip()) < 40:
        problems.append(f"topic '{tid}' is empty or near-empty ({len(text)} chars)")
    if not t["title"].strip():
        problems.append(f"topic '{tid}' has no title")
    if t["section"] not in ("manual", "reference", "legal"):
        problems.append(f"topic '{tid}' has an unknown section '{t['section']}'")

    anchors = {r["anchor"] for r in t["runs"] if "anchor" in r}
    for r in t["runs"]:
        if "to" in r and r["to"] not in topics and r["to"] not in KNOWN_DEAD:
            problems.append(f"topic '{tid}' links to '{r['to']}', which was not exported")

contents = [t for t in topics.values() if t["contents"]]
if len(contents) < 15:
    problems.append(f"only {len(contents)} topics are in the contents list")

if problems:
    for p in problems:
        print("FAIL: " + p)
    sys.exit(1)

chars = sum(len(r["s"]) for t in topics.values() for r in t["runs"])
print(f"PASS: manual has {len(topics)} topics, {chars:,} characters, every link lands")
PY
[ $? -eq 0 ] || FAILED=1

# --- 3: the vendored guides -------------------------------------------------
python3 - "$WIKI" <<'PY'
import os, sys

REQUIRED = ["title", "slug", "order", "source", "attribution",
            "license", "license_url", "retrieved", "modifications"]
LICENSE = "CC BY-SA 3.0"
LICENSE_URL = "https://creativecommons.org/licenses/by-sa/3.0/"

d = sys.argv[1]
files = sorted(f for f in os.listdir(d) if f.endswith(".md")) if os.path.isdir(d) else []
if not files:
    print(f"FAIL: no vendored guides in {d}")
    sys.exit(1)

problems = []
for name in files:
    text = open(os.path.join(d, name), encoding="utf-8").read()
    if not text.startswith("---\n"):
        problems.append(f"{name} has no front matter")
        continue
    front, _, body = text[4:].partition("\n---\n")
    fields = {}
    for line in front.split("\n"):
        if ": " in line:
            k, v = line.split(": ", 1)
            fields[k] = v.strip()
    for key in REQUIRED:
        if not fields.get(key):
            problems.append(f"{name} is missing '{key}' -- the licence requires it")
    if fields.get("license") != LICENSE:
        problems.append(f"{name} says licence '{fields.get('license')}', expected {LICENSE}")
    if fields.get("license_url") != LICENSE_URL:
        problems.append(f"{name} has the wrong licence URL")
    if not fields.get("source", "").startswith("http://incursion.wikidot.com/"):
        problems.append(f"{name} does not name a wiki page as its source")
    if len(body.strip()) < 300:
        problems.append(f"{name} has almost no text ({len(body.strip())} chars) -- "
                        "the site's markup probably changed")

if problems:
    for p in problems:
        print("FAIL: " + p)
    sys.exit(1)
print(f"PASS: {len(files)} vendored guides, each with its source, licence and changes")
PY
[ $? -eq 0 ] || FAILED=1

# The bundled licence document must name the licence too: the per-page credit
# is the notice a reader sees, this is the one that travels with the bundle.
if ! grep -q "CC BY-SA 3.0" "$ROOT/macapp/Resources/LICENSES.md" 2>/dev/null; then
    fail "macapp/Resources/LICENSES.md does not mention CC BY-SA 3.0"
else
    echo "PASS: the bundled licence document names CC BY-SA 3.0"
fi

# --- 4: the bundle ----------------------------------------------------------
if [ -d "$APP" ]; then
    n_wiki="$(ls "$APP/Contents/Resources/Help/wiki"/*.md 2>/dev/null | wc -l | tr -d ' ')"
    if [ ! -f "$APP/Contents/Resources/Help/manual.json" ]; then
        fail "the bundle has no Help/manual.json -- the help window would be empty"
    elif [ "$n_wiki" -lt 1 ]; then
        fail "the bundle has no Help/wiki pages"
    else
        echo "PASS: the bundle carries the manual and $n_wiki guides"
    fi
else
    echo "note: dist/Incursion.app is not built, so the bundle was not checked"
fi

# --- 5: the window opens (optional) ----------------------------------------
if [ "${LIVE:-no}" = yes ]; then
    BIN="$ROOT/macapp/.build/debug/IncursionApp"
    [ -x "$BIN" ] || BIN="$APP/Contents/MacOS/Incursion"
    if [ ! -x "$BIN" ]; then
        fail "LIVE=yes but no app binary to run"
    else
        WORK="$(mktemp -d "${TMPDIR:-/tmp}/incursion-help.XXXXXX")"
        mkdir -p "$WORK/save" "$WORK/logs"
        ln -sfn "$ROOT/mod" "$WORK/mod"; ln -sfn "$ROOT/lib" "$WORK/lib"
        cp "$ROOT/tools/gates/Options.Dat" "$WORK/Options.Dat" 2>/dev/null || true
        INCURSIONPATH="$WORK/" INCURSION_OPEN_HELP=races "$BIN" >/dev/null 2>&1 &
        pid=$!
        sleep 6
        titles="$(osascript -e 'tell application "System Events" to get name of every window of (first process whose name contains "Incursion")' 2>/dev/null)"
        kill "$pid" 2>/dev/null
        rm -rf "$WORK"
        case "$titles" in
            *"Races and Subraces"*) echo "PASS: the help window opened on the topic it was asked for" ;;
            *) fail "the help window did not open (windows: ${titles:-none})" ;;
        esac
    fi
fi

echo
if [ "$FAILED" -eq 0 ]; then
    echo "PASS"
    exit 0
fi
echo "FAIL"
exit 1
