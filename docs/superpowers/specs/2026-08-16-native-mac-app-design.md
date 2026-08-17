# Native macOS App for Incursion — Design

Date: 2026-08-16. Status: designed autonomously under a session goal; Brian has
not reviewed this. Nothing here is outward-facing.

## Summary

| Decision | Choice |
|---|---|
| Architecture | Native Swift app embeds the C++ engine. Engine runs on a background thread behind a new `Term` backend. |
| New backend | `src/Wmac.cpp` — subclasses `TextTerm`, owns a lossless Glyph grid and an input queue, modeled on `Wposix.cpp`. |
| UI shell | SwiftUI app + AppKit `NSView` grid renderer (CoreText). Native menu bar, preferences, About box. |
| Text | Real vector fonts (SF Mono default), any size, Retina-crisp. CP437/GLYPH_* ids map to Unicode. No font PNGs ship. |
| Mouse | ~30 lines of engine hooks (`KY_MOUSE`) + bridge synthesis. Menus, targeting, map moves, scroll wheel. |
| Grid size | Variable, derived from window ÷ cell size, floor 80×48 (engine minimum). Live resize supported. |
| File layout | `IncursionDirectory` = `~/Library/Application Support/Incursion/`. Module copied from bundle Resources on first launch or version change. Engine path logic unchanged. |
| Game logic changes | None. Content, rules, saves, chargen, help — all untouched. |
| Licensing | libtcod/SDL2/Breakpad notices drop out (nothing of theirs ships). MIT (Tew), Mensch grant (elect Expat), full OGL + notices, Mersenne Twister notice ship in-app and as a bundled document. |
| Build | `build_macos.sh BACKEND=mac` produces `build/libincursion-mac.a`; `macapp/` holds the SwiftPM package and bundle assembly. |
| Verification | Bridge accepts the same `-keys` scripts and emits the same `@dump` format as `Wposix`; screen dumps diff cell-identical. Plus the existing `tools/check_*.sh` suite. |

Evidence for every claim below is in the recon reports of 2026-08-16 (cited
file:line throughout). Load-bearing sources: `inc/Term.h`, `src/Wposix.cpp`,
`src/Wlibtcod.cpp`, `src/TextTerm.cpp`, `src/Term.cpp`, `tools/package_macos.sh`,
`docs/HEADLESS-SPEC.md`, `LICENSE`, `docs/reference.md`.

## Why this approach

The seam already exists. `TextTerm` implements every game-facing UI behavior
(windows, menus, prompts, map drawing) on top of a small pure-virtual platform
layer (`inc/Term.h:719-785`). Backends are one translation unit each. `Wposix.cpp`
proves the display is fully replaceable: it satisfies the whole contract with a
`Glyph scr[48][80]` array and no window.

The engine is strictly single-threaded and event-loop-free. All input funnels
through `GetCharCmd` (51 call sites); all output goes through Term virtuals.
`GetCharCmd` already blocks for minutes inside the backend. A backend that blocks
on a queue instead of an SDL poll is behaviorally identical from the engine's
side.

Approaches rejected:

- **Modernize the SDL/libtcod frontend** (HiDPI, bigger bitmap fonts). Less
  work, but it can never be a first-class Mac app: no native menus or dialogs,
  no real text rendering, bitmap fonts with dubious glyph provenance
  (`docs/reference.md:8`), and mouse support would still need the same engine
  hooks. Fails the goal.
- **Terminal-emulator wrapper** (ncurses in a native terminal view). Text stays
  terminal-grade, mouse support is poor, and the app would be a shell around a
  shell. Fails the goal.
- **Reimplement the UI natively** (native menu widgets replacing LMenu etc.).
  Violates "keep all logic": TextTerm's menus, prompts and chargen recording are
  game logic. Rejected outright.

## Components

### 1. Engine static library

`build_macos.sh` gains `BACKEND=mac`: compile the engine sources with the same
flags as today (same compiler, `-O2`, same std versions) into
`build/libincursion-mac.a`, with `-DMAC_TERM` selecting no other backend TU.
Two configurations, matching the existing COMPILER switch:

- Developer: all sources, `-DDEBUG`. Used for parity testing and module builds.
- Shipping: `COMPILER=no` file set — 45 `.cpp` + `lz.c` + `rle.c`, no ACCENT/GPL
  code (`build_macos.sh:100`, license requirement per `src/Art.cpp:2-7`).

`mod/Incursion.Mod` is still compiled by the classic developer binary
(`./incursion -compile main.irc`); the app ships that module. This pairing is
already proven by `tools/package_macos.sh:52-62`.

### 2. Bridge backend — `src/Wmac.cpp` (+ `src/WmacBridge.h` C API)

A `TextTerm` subclass plus a small extern-C API. No `main()`; instead
`incursion_engine_main(config)` reproduces `Wlibtcod.cpp:416-502`'s sequence
(Game before Term, `SetIncursionDirectory` before `Initialize`,
`RunOnCommandLine` before UI — `src/Wlibtcod.cpp` ordering quirks section).
Also defines `Error()`, `Fatal()`, `T1` (`inc/Globals.h:9-10,279`).

**Screen model.** `Glyph*` grid sized `sizeX × sizeY`, stored verbatim like
Wposix (`src/Wposix.cpp:635-666`) — lossless `AGetChar`, which three engine
call sites require (`docs/HEADLESS-SPEC.md:43-50`). Colorless glyphs take the
current pen in `APutChar` (`src/Wposix.cpp:642-647`). One-deep `Save`/`Restore`
snapshot buffer. Scroll plane: heap `Glyph[MAX_SCROLL_LINES × SCROLL_WIDTH]`
exactly as `src/Wposix.cpp:698-739`.

**Presentation.** `Update()` copies the grid into a double-buffered snapshot
(cells + cursor state + seq counter) under a lock and signals the UI (callback,
dispatched to main). The UI never reads engine memory, only snapshots.

**Input.** A thread-safe queue of events: key (raw code + modifier byte), mouse
(kind, cell x/y, wheel delta), resize (new grid size), quit. `GetCharCmd`:

1. Honor `QueuedChar` first (`src/Wposix.cpp:1238-1242`).
2. Reproduce the frame pump: RefreshMap/ShowTraits/ShowStatus on dirty flags,
   message auto-clear, autosave counting, then `Update()` before blocking
   (`src/Wlibtcod.cpp:1441-1469`).
3. Block on the queue (condition variable; no polling, no idle-repaint
   workaround — that was SDL archaeology, `src/Wlibtcod.cpp:1475-1487`).
4. Translate through the keysets with exact modifier matching — SHIFT is
   semantic (`src/Tables.cpp:4558`, `docs/HEADLESS-SPEC.md:79-85`); rebuild
   `ControlKeys` per event (`src/Wlibtcod.cpp:1555-1561`).
5. Mouse events become synthesized keys or `KY_MOUSE` (below). Resize events
   rebuild the grid + `InitWindows()` and return `KY_REDRAW`, the same recovery
   path as Alt+Enter fullscreen today (`src/Wlibtcod.cpp:1563-1569`).
6. `CheckEscape`/`ClearKeyBuff` get real implementations (scan/drain queue);
   the Wposix no-op stubs are a headless-only exception
   (`src/Wposix.cpp:190-195`).

**Lifecycle.** Engine thread runs `incursion_engine_main`. Clean StartMenu quit
returns normally → notify UI "engine finished" → UI terminates the app.
`ShutDown()` from save-quit paths notifies the UI and parks the engine thread;
the UI terminates the process, so `exit(0)` never races AppKit. `Fatal()` logs
(shared `LogError`, `src/ErrorLog.cpp:112`), snapshots the message to the UI for
a native alert, then parks. Window close → UI enqueues quit → existing
`KY_CMD_QUICK_QUIT` path saves and exits cleanly
(`src/Wlibtcod.cpp:1489-1501`, `src/Player.cpp:729-732`).

**File I/O.** POSIX implementations copied from Wposix (stdio + dirent/fnmatch;
`FirstFile` leaves the match open — module loader contract,
`src/Wposix.cpp:1578-1590`). `ChangeDirectory` keeps real `chdir` semantics:
the engine owns the process CWD, the Swift side never relies on CWD. This
preserves the raw-`fopen` stragglers (`src/Main.cpp:2360`,
`src/Registry.cpp:813-833`) without touching them.

**Directories.** `IncursionDirectory` = `~/Library/Application Support/Incursion/`
(absolute — hard invariant, `src/Wposix.cpp:503-512`), created on launch with
`save/`, `logs/`, `mod/`. The app copies `Incursion.Mod` from bundle Resources
into `mod/` when missing or when the bundled version stamp differs. Existing
folder-layout users migrate by copying `save/` and `Options.Dat`; the
`INCURSIONPATH` override still works for a portable layout.

**Timing.** `GetElapsedMilli` via `CLOCK_MONOTONIC` (`src/Wposix.cpp:687-691`);
`StopWatch` sleeps per the animation option (`src/Wlibtcod.cpp:835-841`).

**Headless parity mode.** The bridge accepts `-keys FILE` and `@dump`, emitting
Wposix's screen-dump format, so `diff logs/screens/` between backends is the
correctness oracle for the whole port (`docs/HEADLESS-SPEC.md`,
`src/Wposix.cpp:925-1099`).

### 3. Engine hooks for the mouse (the only engine edits)

All are port work, not upstream fixes; none change existing behavior.

1. `inc/Term.h`: `#define KY_MOUSE 251` beside `KY_REDRAW`; protected members
   `mouseCX, mouseCY` and the menu-layout stash
   (`menuMWin, menuVStart, menuVRows, menuSzCol, menuDY`).
2. `src/TextTerm.cpp`: LMenu/LMultiSelect stash their layout at each redraw
   (beside lines 1061/1373); one `case KY_MOUSE:` per switch inverts the layout
   formula — `col = wx/szCol; i = vStart + col*vRows + (wy-DY)` — highlights or
   selects (LMenu) / toggles (LMultiSelect). Mind the WIN_INPUT/WIN_MESSAGE
   mode aliasing (`src/TextTerm.cpp:118-128`).
3. `src/Term.cpp` EffectPrompt: one `else if (ch == KY_MOUSE)` sets the local
   cursor from the clicked map square and falls into the existing confirm path,
   so all validation runs unchanged (~6 lines, near line 2074).

Bridge-side synthesis needs no hooks: clicked menu letters (Tier 0), map-square
inverse transform `mx = cx − Windows[WIN_MAP].Left + XOff`
(`src/Term.cpp:1230-1231`), adjacent-square clicks → arrow commands in MO_PLAY
(the bridge is the Term subclass; it reads `p->x/y`, `XOff/YOff`, `Mode`
directly), wheel → raw `KY_UP`/`KY_DOWN` which every scroll loop understands
(`src/TextTerm.cpp:394-410`). Mouse-synthesized keys record and replay in
chargen exactly like keystrokes (`src/Term.cpp:2930-2934`).

Because clicks arrive as keys, prompts driven by `yn`/`ChoicePrompt` accept
clicks on their rendered choice letters later with zero further engine work.

### 4. Swift app — `macapp/`

SwiftPM executable target + thin C interop target for `WmacBridge.h`.
Structure:

- **GridView** (`NSView`): draws the snapshot with CoreText — per-row
  attributed strings, background rects from the 16-color palette, block cursor.
  16 palette slots; classic and soft palettes ship
  (`src/Wlibtcod.cpp:128-165`), themes later. CP437→Unicode and
  GLYPH_*→Unicode mapping table (the Unicode list already exists per bead
  inc-9df.2).
- **Input**: `keyDown`/`flagsChanged` → raw KY_* + modifier byte (arrows →
  KY_UP…, F-keys, Ctrl chars 1-26 with CONTROL flag reconstructed,
  `docs/HEADLESS-SPEC.md` trap 4). Mouse/scroll events → cell coordinates.
  Option+arrows deliver the Ctrl+direction semantics macOS steals (bead
  inc-9df.1) via a preference.
- **Window**: content size = grid × cell size; live resize recomputes the grid
  (floor 80×48) and enqueues a resize event. Native fullscreen. Font family
  (monospaced) and size in Preferences; size changes re-derive the grid.
  `hideOption()` returns true for the now-meaningless resolution/font options
  (`src/Wlibtcod.cpp:267` precedent).
- **Menu bar**: standard app menu plus game commands that enqueue their keys
  (Save, Character Sheet, Inventory, Help…). About box carries the attribution
  block (below).
- **Bundle assembly**: `macapp/build_app.sh` — `swift build` (needs
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` on this machine),
  assemble `Incursion.app/Contents/{MacOS,Resources}`, copy `Incursion.Mod`,
  license documents, Info.plist, icon; ad-hoc sign. Developer ID signing and
  notarization reuse the `package_macos.sh` steps when the certificate exists
  (bead inc-9df.7 tracks its absence).

### 5. Licensing and attribution

Ships nothing from libtcod, SDL2, Breakpad, or `fonts/*.png` — those notices
drop out (`LICENSE:8-10`), and the Microsoft-screencap glyph question
(`docs/reference.md:8`) becomes moot. The app must carry:

- Bundled license document (Resources + reachable from About): MIT (Tew,
  `LICENSE:12-34`); Mensch grant with Expat elected, credit
  "Copyright (c) 1999-2008 Julian Mensch" (`docs/reference.md:9`); full OGL
  v1.0a with the §15 COPYRIGHT NOTICE (`LICENSE:162-167`) and the OGC
  designation (`lib/help.irh:4976-4984`); Mersenne Twister notice
  (`lib/help.irh:4986-4988`).
- About box: "Incursion: Halls of the Goblin King", fork identity
  (`inc/Defines.h:33-37`), "By Julian Mensch, with additional concepts and
  material by Westley Weimer", "Copyright 1999-2007 Julian Mensch, 2014
  Richard Tew, 2026 Brian Hill" (`src/Term.cpp:2984-2987`).
- In-game: title screen, help::OGL, and CREDITS all survive automatically
  because the backend routes through TextTerm.
- No D&D/WotC trademarks in app metadata (OGL §7).

Gate: the About box, license document, and any release copy are outward-facing.
Brian reads the literal text before anything ships (CLAUDE.md rule 1).

## Error handling

- `Error()` keeps the log-and-continue policy (`logs/errors.log` under
  Application Support). `INCURSION_ERROR_PROMPT` is honored via a native alert.
- `Fatal()` → native alert with the message, then the app terminates; the log
  entry is written first, exactly as today.
- Engine-thread crash: out of scope v1 (matches today's behavior; macOS writes
  the DiagnosticReports entry).

## Testing

1. **Screen parity**: run `tools/keys/*.keys` scripts with fixed seeds through
   `incursion-headless` and through the bridge's headless mode; diff the
   `@dump` output cell-by-cell. This exercises the entire engine + bridge
   input/translation/render-model path with the existing corpus (smoke,
   chargen×4, dive, explore×4, marathon).
2. **Existing regression suite**: `check_abi.sh`, `check_abs_path.sh`,
   `check_headless.sh`, `check_layout.sh` unchanged; a `check_app.sh` variant
   of `check_package.sh` for the bundle (no GPL symbols, data files present,
   signature valid).
3. **Interactive**: Brian plays. Screen capture + scripted keystroke driving
   for unattended sanity checks (docs/PORT-STATUS.md "Claude can now see and
   drive the game").

## Phases

| Phase | Deliverable | Proof |
|---|---|---|
| 1 | `BACKEND=mac` engine library + `Wmac.cpp` with headless parity mode | keyscript screen dumps diff clean vs Wposix |
| 2 | Swift app: window, GridView, keyboard → playable | chargen → play → save → load in the app |
| 3 | Mouse: engine hooks + bridge synthesis + wheel | menus, targeting, map moves by mouse |
| 4 | First-class polish: menus, Preferences, About, .app assembly, App Support layout | `check_app.sh` passes; drag-install works |
| 5 | Docs, beads closed, handoff | this table all green |

## Open questions (do not block phases 1-3)

- Bundle identifier and app display name — outward-facing, Brian decides.
- Distribution: DMG with the .app vs folder-with-app; Developer ID signing
  waits on inc-9df.7.
- Whether the portable-folder release remains a parallel artifact (README
  promises it today; suggest keeping both).
