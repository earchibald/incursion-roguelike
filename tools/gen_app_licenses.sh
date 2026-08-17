#!/bin/bash
# Assemble the license document the Mac app ships (macapp/Resources/LICENSES.md)
# from the canonical texts in this repo, so the shipped copy can never drift
# from LICENSE, docs/reference.md, or the Mersenne notice in src/Base.cpp.
#
# What ships and why (see the design spec's licensing section):
#   MIT (Richard Tew)      LICENSE 1 -- required, the port layer is his work
#   Mensch grant           LICENSE 2 -- required; the Expat license is elected
#   OGL v1.0a, full text   LICENSE 3 -- required by OGL section 10
#   OGC designation        required by OGL section 8
#   Mersenne Twister       its clause 2 requires this notice beside binaries
#   CC BY-SA 3.0           the wiki guides in the help window are under it,
#                          and it requires the licence to be named wherever
#                          the work is conveyed. The per-page credit in the
#                          help window is the primary notice; this is the
#                          copy that travels with the bundle.
#
# What does NOT ship, deliberately: libtcod, SDL2, Breakpad, font PNGs --
# the native app contains nothing of theirs, and LICENSE scopes each of those
# blocks "only applies if in use".
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/macapp/Resources/LICENSES.md}"
mkdir -p "$(dirname "$OUT")"

extract() { # start-marker end-marker file -> lines between them, exclusive
    local text
    text="$(awk -v s="$1" -v e="$2" '
        index($0, s) { grab = 1; next }
        index($0, e) { grab = 0 }
        grab { print }
    ' "$3")"
    # A reworded or renumbered marker must fail the build, not silently ship
    # a license document with a required section missing.
    if [ -z "$(echo "$text" | tr -d '[:space:]')" ]; then
        echo "gen_app_licenses: nothing found between '$1' and '$2' in $3" >&2
        exit 1
    fi
    printf '%s\n' "$text"
}

{
    cat <<'HEADER'
# Incursion — Licenses and Notices

Incursion: Halls of the Goblin King.
By Julian Mensch, with additional concepts and material by Westley Weimer.
Copyright 1999-2007 Julian Mensch, 2014 Richard Tew, 2026 Brian Hill.

This application contains no code or assets from libtcod, SDL2, or Google
Breakpad; their licenses, which cover other builds of Incursion, therefore
do not apply to it and are not reproduced here. The full license file for
the source tree is `LICENSE` in the repository.

## Incursion engine — Julian Mensch's grant

HEADER
    extract "-- LICENSE 2:" "-- LICENSE 3:" "$ROOT/LICENSE"
    cat <<'ELECTION'

For this application, the Expat License is elected from the grant above.
Credit as: Copyright (c) 1999-2008 Julian Mensch. The full announcement is
preserved in `docs/reference.md` in the source repository.

## Port and later changes — MIT License (Richard Tew)

ELECTION
    extract "-- LICENSE 1:" "-- LICENSE 2:" "$ROOT/LICENSE"
    cat <<'OGLHEAD'

## Open Game License v1.0a

OGLHEAD
    extract "-- LICENSE 3:" "-- LICENSE 4:" "$ROOT/LICENSE"
    cat <<'DESIGNATION'

### Designation of Open Game Content

All of the game mechanics used in Incursion, along with the names of
monsters, items and spells, are designated as open game content. The
setting, plot and flavour text, as well as the computer code used to
interpret and apply the game mechanics, are considered to be Product
Identity of Incursion and are not released under the OGL.

All Incursion Product Identity may be freely distributed provided that it
is unaltered, but is otherwise in the majority copyright 1999-2007 Julian
Mensch, with some portions copyright 1999-2003 Westley Weimer.

(Julian Mensch's later license announcement, preserved in
`docs/reference.md`, redefines Incursion's own Product Identity to nothing;
the paragraph above is retained as the OGL section 8 designation as it
appears in the game's help.)

## Mersenne Twister random number generator

DESIGNATION
    MT_TEXT="$(awk '/A C-program for MT19937/{grab=1} grab{print}
         /email: m-mat/{exit}' "$ROOT/src/Base.cpp")"
    if [ -z "$(echo "$MT_TEXT" | tr -d '[:space:]')" ]; then
        echo "gen_app_licenses: Mersenne notice not found in src/Base.cpp" >&2
        exit 1
    fi
    printf '%s\n' "$MT_TEXT"
    cat <<'FOOTER'

## Player guides in the help window — CC BY-SA 3.0

The Help window's "Getting Started" pages are copied from the Incursion Wiki
(http://incursion.wikidot.com/), whose content is licensed under the Creative
Commons Attribution-ShareAlike 3.0 Unported licence:

    https://creativecommons.org/licenses/by-sa/3.0/

Each page keeps that licence, names its own source page, its authors as
"Incursion Wiki contributors", the date it was retrieved and the only change
made to it -- the conversion from the site's HTML to Markdown. The pages are
separate documents displayed by this application, not part of its code, and
they may be redistributed under CC BY-SA 3.0 like any other copy. The
vendored files and the tool that produced them are
`macapp/Resources/Help/wiki/` and `tools/fetch_wiki_help.py` in the source
repository.

## Other acknowledgements

Incursion was created using the ACCENT Compiler-Compiler system and
incorporates the source code of the Decus CPP public-domain C preprocessor.
Neither ships in this application: the resource compiler that uses them is
excluded from distributed builds. Full credits are in the game's help
(Help -> Credits), including the many Open Gaming License contributors.
FOOTER
} > "$OUT"

echo "Wrote $OUT ($(wc -l < "$OUT" | tr -d ' ') lines)"
