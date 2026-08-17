# Native macOS App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship Incursion as a native macOS app — Swift UI shell, engine untouched behind a new `Term` backend, mouse support, adjustable vector-font text.

**Architecture:** The C++ engine runs on a background thread behind `src/Wmac.cpp` (a `TextTerm` subclass modeled on `Wposix.cpp`). It publishes Glyph-grid snapshots through a C API (`src/WmacBridge.h`) and blocks on an input-event queue. A SwiftPM app (`macapp/`) renders snapshots with CoreText and feeds events. Spec: `docs/superpowers/specs/2026-08-16-native-mac-app-design.md`.

**Tech Stack:** C++17 (engine, backend), Swift 5.9+/SwiftUI/AppKit (app), SwiftPM, shell (build).

## Global Constraints

- **No git commits.** Project profile forbids commits without an explicit ask. Each task ends with a validation checkpoint instead. Report suggested commits at handoff.
- **No game-logic changes.** Only the three mouse-hook files touch existing engine code, exactly as specified in the spec's "Engine hooks" section.
- Engine compile flags must match `build_macos.sh`: `-O2 -w -fpermissive -Wno-narrowing -std=c++17` (`-std=c++14` for `Tokens.cpp`/`Art.cpp`), `-Iinc -Ilib -Icompat`, `.c` files as `-std=gnu89`. Save/module compatibility depends on this.
- Shipping configuration excludes `RComp.cpp Art.cpp yygram.cpp Tokens.cpp cpp1-6.c` (GPL ACCENT — license requirement, `src/Art.cpp:2-7`) and drops `-DDEBUG`.
- Grid minimum 80×48 (`src/TextTerm.cpp:88-89` asserts).
- Glyph grid stores `Glyph` (uint32) verbatim — lossless `AGetChar` (HEADLESS-SPEC traps 1, 7).
- `IncursionDirectory` must be absolute (`src/Wposix.cpp:503-512`).
- Swift builds on this machine need `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` (CLT fails on SwiftUI macros).
- Nothing outward-facing (bundle id, About text, release copy) ships without Brian reading the literal text.
- Track work in beads under epic inc-9df; keep this plan's checkboxes in sync.

## File map

| File | Role |
|---|---|
| `build_macos.sh` (modify) | `BACKEND=mac` → `build/libincursion-mac.a` |
| `src/WmacBridge.h` (create) | C API between engine world and Swift |
| `src/Wmac.cpp` (create) | Backend: grid model, input queue, engine thread entry, Error/Fatal, file I/O |
| `tools/macterm_parity.cpp` (create) | Headless driver: keyscript in, screen dumps out, via the C API |
| `tools/check_macterm.sh` (create) | Parity check vs Wposix dumps |
| `inc/Term.h`, `src/TextTerm.cpp`, `src/Term.cpp` (modify) | KY_MOUSE hooks (Phase 3) |
| `macapp/Package.swift`, `macapp/Sources/…` (create) | Swift app |
| `macapp/build_app.sh` (create) | Assemble + sign `Incursion.app` |
| `tools/check_app.sh` (create) | Bundle correctness check |

---

### Task 1: Engine static library (`BACKEND=mac`)

**Files:**
- Modify: `build_macos.sh` (backend case block :31-37 and :103-120, link step)
- Create: `src/WmacBridge.h`, `src/Wmac.cpp` (compiling stubs only)

**Interfaces produced:** `build/libincursion-mac.a` containing all engine objects + `Wmac.o`; `BACKEND=mac ./build_macos.sh` builds it. `COMPILER=no BACKEND=mac` builds the shipping variant `build/libincursion-mac-ship.a`.

- [ ] **Step 1: Add the `mac` backend case.** In the `case "$BACKEND"` blocks: `mac)` sets `DEFS=-DMAC_TERM`, skips `Wlibtcod Wcurses Wposix` from the source list but includes `Wmac`, and instead of linking a binary runs `ar rcs "$LIBOUT" "$OBJ"/*.o` where `LIBOUT=build/libincursion-mac.a` (default) or `build/libincursion-mac-ship.a` when `COMPILER=no`. No SDL/libtcod/ncurses linkage. Object dir follows the existing rule (`build/obj-libmac`, `build/obj-libmac-ship`).
- [ ] **Step 2: Stub the two new files** so the archive links-checks. `src/WmacBridge.h`: the full header from Task 2 (write it now, it is the contract). `src/Wmac.cpp`: `#ifdef MAC_TERM` wrapper, `#include "WmacBridge.h"`, and `extern "C" int incursion_engine_main(const IncEngineConfig*){ return 0; }` plus empty `Term *T1 = NULL;` — enough to compile, not to run.
- [ ] **Step 3: Verify.** Run: `BACKEND=mac ./build_macos.sh` → expect `Built: build/libincursion-mac.a`; `ar t build/libincursion-mac.a | grep -c '\.o'` ≥ 50; `nm build/libincursion-mac.a | grep incursion_engine_main` shows a `T`. Then `COMPILER=no BACKEND=mac ./build_macos.sh` → archive exists and `nm … | grep -i accent` and `ar t … | grep -E 'Art|yygram|Tokens|RComp'` are empty.
- [ ] **Checkpoint:** default `./build_macos.sh` still builds `./incursion` unchanged (run it; binary links).

### Task 2: The C API — `src/WmacBridge.h`

**Files:** Create: `src/WmacBridge.h` (finalize the Task-1 stub).

**Interfaces produced (consumed by Tasks 3, 4, 6):**

```c
#ifndef WMAC_BRIDGE_H
#define WMAC_BRIDGE_H
#include <stdint.h>
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif

/* Cells are the engine's Glyph verbatim: bits 0-11 glyph id (CP437 <256,
   GLYPH_* semantic ids 256..375), 12-15 fg palette index, 16-19 bg. */
typedef uint32_t IncCell;

typedef struct IncSnapshot {
    int32_t  sizeX, sizeY;      /* grid dimensions */
    int32_t  cursorX, cursorY;  /* absolute cell; -1,-1 = hidden */
    uint64_t seq;               /* increments per Update() */
    const IncCell *cells;       /* sizeX*sizeY, row-major; valid until next
                                   inc_snapshot_release */
} IncSnapshot;

typedef enum IncEventKind {
    INC_EV_KEY = 1,        /* ch = KY_* raw code, mods = SHIFT|CONTROL|ALT bits */
    INC_EV_MOUSE_DOWN = 2, /* x,y = cell */
    INC_EV_WHEEL = 3,      /* delta = +up / -down lines */
    INC_EV_RESIZE = 4,     /* x,y = new grid size (>=80x48) */
    INC_EV_QUIT = 5        /* window close: engine saves and finishes */
} IncEventKind;

typedef struct IncEvent {
    int32_t kind;   /* IncEventKind */
    int32_t ch;     /* KEY: raw KY_* code (inc/Term.h) */
    int32_t mods;   /* KEY: bit1 SHIFT, bit2 CONTROL, bit4 ALT (inc/Term.h:56-58) */
    int32_t x, y;   /* MOUSE: cell; RESIZE: new sizeX,sizeY */
    int32_t delta;  /* WHEEL: signed lines */
} IncEvent;

typedef struct IncCallbacks {
    void *ctx;
    void (*frame_ready)(void *ctx);            /* snapshot seq advanced        */
    void (*engine_waiting)(void *ctx);         /* about to block for input     */
    void (*engine_finished)(void *ctx, int rc);/* StartMenu returned / parked  */
    void (*fatal_error)(void *ctx, const char *msg); /* before parking         */
} IncCallbacks;

typedef struct IncEngineConfig {
    const char *incursion_dir; /* ABSOLUTE writable root (save/ logs/ mod/) */
    int32_t sizeX, sizeY;      /* initial grid, floor 80x48 */
    IncCallbacks cb;
} IncEngineConfig;

/* Runs the whole game (Wlibtcod main() equivalent). Call on a dedicated
   thread; blocks until quit. Returns the game's retval. */
int  incursion_engine_main(const IncEngineConfig *cfg);

/* UI side, any thread: */
void inc_push_event(const IncEvent *ev);
/* Copies the latest published frame reference; call release when done. */
int  inc_snapshot_acquire(IncSnapshot *out);
void inc_snapshot_release(const IncSnapshot *snap);
uint64_t inc_snapshot_seq(void);

#ifdef __cplusplus
}
#endif
#endif
```

- [ ] **Step 1:** Write the header exactly as above.
- [ ] **Step 2: Verify** it is C-clean: `clang -x c -fsyntax-only src/WmacBridge.h` → no output.

### Task 3: The backend — `src/Wmac.cpp`

**Files:** Create: `src/Wmac.cpp` (~1,400 lines, adapted). Reference sources are cited per section; copy then adjust, do not reinvent.

**Consumes:** Task 2 API. **Produces:** a working engine inside `libincursion-mac.a`; every symbol the linker needs from a backend TU: `T1`, `Error`, `Fatal`, `incursion_engine_main` (no `main`).

Structure `src/Wmac.cpp` in this order:

- [ ] **Step 1: Class + globals.** `class macTerm : public TextTerm` declaring the pure-virtual set exactly as `src/Wposix.cpp:119-282` does (drop script-runner members). Members: `Glyph *scr, *scrSave; int32 gridX, gridY;` scroll plane `Glyph *scroll`; snapshot double buffer + `std::mutex` + `seq`; input `std::deque<IncEvent>` + mutex + condvar; `IncCallbacks cb;` `bool parked`. Globals: `Term *T1; static macTerm *MT;`
- [ ] **Step 2: Grid + scroll + Save/Restore.** Adapt `src/Wposix.cpp:623-739` (APutChar pen rule :642-647, verbatim AGetChar :662-666, bounds-checked scroll :698-739). `Save()/Restore()` memcpy `scr`↔`scrSave`, each ending in `Update()` like `src/Wlibtcod.cpp:753-761`. Grid allocation helper `AllocGrid(x,y)` used by Initialize and resize.
- [ ] **Step 3: Update/snapshot.** `Update()`: lock, memcpy grid into the back snapshot buffer, fill cursor fields (`showCursor ? cx,cy : -1`), `seq++`, swap, unlock, `cb.frame_ready(ctx)`, `updated = true`. Implement the four C functions over these members (acquire returns the front buffer under refcount or simply copies — copying 128×96×4 B ≈ 48 KB is fine; copy).
- [ ] **Step 4: Timing.** `GetElapsedMilli` via `clock_gettime(CLOCK_MONOTONIC)` (`src/Wposix.cpp:687-691`); `StopWatch` honors `OPT_ANIMATION` like `src/Wlibtcod.cpp:835-841` using `usleep`.
- [ ] **Step 5: File I/O + directories.** Copy `src/Wposix.cpp:1471-1614` (stdio + dirent/fnmatch; `FirstFile` leaves file open) and `:222-259` (SubDir strings, `LibraryPath` with `INCURSIONLIBPATH`, chdir-based `ChangeDirectory`). `SetIncursionDirectory` mkdirs `mod/ logs/ save/` (`src/Wposix.cpp:1454-1464`).
- [ ] **Step 6: Input.** `GetCharCmd(KeyCmdMode)` adapted from `src/Wposix.cpp:1229-1336`, with the read step replaced by: pop queue under lock; if empty → `cb.engine_waiting(ctx)` then condvar wait. Handle kinds: KEY → `(ch,mods)` sets `ControlKeys`, falls into the existing keyset-translation tail (exact-modifier matching, normal mode scans backward — copy the loop). MOUSE_DOWN → Task 8 (until then: ignore). WHEEL → synthesize raw `KY_UP`/`KY_DOWN` × |delta|. RESIZE → `AllocGrid`, `sizeX=x; sizeY=y; InitWindows();` redraw dirty flags, return `KY_REDRAW`. QUIT → in-play: `p->SetQuitFlag(); return KY_CMD_QUICK_QUIT;` pre-game: notify finished + park (mirror `src/Wlibtcod.cpp:1489-1501`). Reproduce the frame pump before blocking (`QueuedChar` first, RefreshMap/ShowTraits/ShowStatus, `Update()`), per `src/Wposix.cpp:1238-1315`. `GetCharRaw()`/`GetCharCmd()` wrappers as `src/Wposix.cpp`. `CheckEscape`: scan queue for ESC key, drop it, return true. `ClearKeyBuff`: drain queue of KEY events. `PrePrompt {}`.
- [ ] **Step 7: Lifecycle.** `Initialize()` = Wposix's field-reset list `src/Wposix.cpp:1394-1446` (alloc grid+scroll, `InitWindows(); SetWin(WIN_SCREEN); Clear(); Color(YELLOW);` `initialised=true`). `ShutDown()`: notify `engine_finished`, then `Park()` (condvar wait forever) — the UI terminates the process; EXCEPT when StartMenu returned normally (flag), then just return. `Reset() {}`, `hideOption(opt)`: return true for `OPT_WIND_RES, OPT_FULL_RES, OPT_WIND_FONT, OPT_FULL_FONT` (find ids in `inc/Defines.h`), else false. `ConvertChar { return 0; }` (Wposix precedent).
- [ ] **Step 8: Error/Fatal + engine main.** `LogGameError` wrapper (10 lines, `src/Wposix.cpp:1345-1355`, banner word "mac"). `Fatal`: log; if `initialised` → `cb.fatal_error(msg)` then `Park()`; else stderr + return code path. `Error`: log-and-return (`src/Wposix.cpp:1375-1391`). `incursion_engine_main(cfg)`: validate `cfg->incursion_dir` absolute; `theGame = new Game(); MT = new macTerm(cfg); T1 = MT;` `SetIncursionDirectory(dir)`; NO RunOnCommandLine (no argv in app context — skip; `-compile` stays with the classic binary); `Initialize(); theGame->StartMenu(); ShutDown-normal-return; delete theGame; engine_finished(rc); return rc;` Ordering per `src/Wlibtcod.cpp:416-502` (Game before Term; quirks section).
- [ ] **Step 9: Verify compile.** `BACKEND=mac ./build_macos.sh` → archive builds with no warnings beyond the suppressed set. `nm build/libincursion-mac.a | grep -E 'T _?(Error|Fatal)'` present; `grep ' U _?main$'` absent.

### Task 4: Parity driver + check

**Files:** Create: `tools/macterm_parity.cpp`, `tools/check_macterm.sh`. Modify: `build_macos.sh` (a `PARITY=yes BACKEND=mac` extra link step producing `build/macterm-parity`).

**Consumes:** the C API only. **Produces:** `build/macterm-parity -keys FILE -seed N -dir DIR` → `logs/screens/NNNN[-label].txt` dumps in Wposix's format (`src/Wposix.cpp:749-779`: one text line per row, `|`-framed, trailing color plane omitted exactly as Wposix omits it).

- [ ] **Step 1: Driver.** Single C++ file: parse the keyscript token language by adapting `src/Wposix.cpp:925-1099` (chars, `"strings"`, named keys incl. arrows/F-keys, `^X` control chars, `TOK*N` repeats, `@dump[:label]`, `@quit`, `@include`, `@while "text" KEYS` / `@until` bounded at 200). Run `incursion_engine_main` on a `std::thread` with `sizeX=80,sizeY=48`. In `engine_waiting`: if next token is `@dump`, snapshot-acquire and write the dump (render cells via the same CP437-to-ASCII fold Wposix uses, `src/Wposix.cpp:755-779`); `@while/@until` test `ScreenShows`-equivalent row matching (`src/Wposix.cpp:781-805`) against the snapshot; then push the next key event. `INCURSION_SEED` passes through the environment (`src/Main.cpp:47-49`). Key budget guard: 20000 events → exit 3.
- [ ] **Step 2: check script.** `tools/check_macterm.sh`: sandbox a temp dir like `tools/headless.sh` does (symlink `lib/`+`mod/`, never the real `save/` — HEADLESS-SPEC trap 11); run `tools/keys/smoke.keys` (then `chargen1.keys`, `dive.keys`) with the same seed through `incursion-headless` and `macterm-parity`; `diff -u` each dump pair; exit 0 only if all identical.
- [ ] **Step 3: Verify.** `BACKEND=posix ./build_macos.sh && BACKEND=mac PARITY=yes ./build_macos.sh && tools/check_macterm.sh` → PASS. Investigate any cell diff to root cause (expected classes: pen-rule misses, keyset translation, dump timing).

### Task 5: Swift package + engine-in-app boot

**Files:** Create: `macapp/Package.swift`, `macapp/Sources/CIncursion/module.modulemap` (+ empty `shim.h` including `../../src/WmacBridge.h`), `macapp/Sources/IncursionApp/IncursionApp.swift`, `EngineHost.swift`.

**Produces:** `EngineHost` (Swift): `start(dir: URL, gridW: Int, gridH: Int)`, `push(_ ev: IncEvent)`, `latestSnapshot() -> Snapshot?` (Swift struct: `cells: [UInt32], w: Int, h: Int, cursor: (Int,Int)?, seq: UInt64`), Combine/`@Observable` `frameSeq` the view observes; callbacks trampoline C→Swift via `Unmanaged<EngineHost>`.

- [ ] **Step 1: Package.** Executable target `IncursionApp` depending on system-library-style target `CIncursion` (`module.modulemap` exporting the header); `linkerSettings: .unsafeFlags(["-L../build", "-lincursion-mac", "-lz"])` plus `.linkedLibrary("c++")` (engine is C++; the archive needs libc++). Platform `.macOS(.v14)`.
- [ ] **Step 2: EngineHost** spawns `Thread { incursion_engine_main(&cfg) }` with callbacks; `engine_finished` → `DispatchQueue.main` → `NSApp.terminate`. `fatal_error` → main-thread `NSAlert` then terminate.
- [ ] **Step 3: Boot proof.** Temporary: on `frame_ready`, print seq to stderr. Run the executable with a scratch dir; expect frames advancing (title screen draws) and a live process. Kill it.
- [ ] **Step 4: Verify** `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build` in `macapp/` → `Build complete`.

### Task 6: GridView rendering + keyboard + window

**Files:** Create: `macapp/Sources/IncursionApp/GridView.swift`, `GlyphMap.swift`, `Palette.swift`, `KeyTranslation.swift`, `GameWindow.swift`.

**Produces:** playable app: text renders, keys work, resize works.

- [ ] **Step 1: GlyphMap.** `func scalar(for id: UInt32) -> Unicode.Scalar` — ids <256 through a CP437→Unicode table (public domain mapping, 256 entries, include inline); ids 256…375: map each `GLYPH_*` in `inc/Defines.h:4194-4330` to a Unicode equivalent (wall/floor/door/player-race glyphs; start from the list bead inc-9df.2 references in `src/Wposix.cpp`'s ASCII fold and upgrade to box-drawing/symbols where obvious; unknown → the CP437 fallback the id would render as under `glyphchar_to_char`, `src/Wlibtcod.cpp:518-687`).
- [ ] **Step 2: Palette.** 16 `NSColor`s from `RGBValues` and `RGBSofter` (`src/Wlibtcod.cpp:128-165`), selectable.
- [ ] **Step 3: GridView** (`NSView`, `isFlipped`, layer-backed): on draw, for each row build one `CFAttributedString` per run of equal (fg) using the selected monospaced font; fill bg rects per run of equal (bg); draw with CoreText; block cursor = inverted cell. Cell size = font advance width × line height (`ceil`). Redraw on `frameSeq` change (setNeedsDisplay). 60fps not required; frames arrive ~2/s.
- [ ] **Step 4: Keys.** `keyDown` → `IncEvent`: letters/digits/punct from `charactersIgnoringModifiers` (keep case; SHIFT bit from modifierFlags — semantic, Tables.cpp:4558), arrows → `KY_UP/DOWN/LEFT/RIGHT` (206,201,203,202 — compute from `inc/Term.h:7-14`: 200+Dir), PgUp/PgDn/Home/End → the diagonal KY codes, F1-F12 → 214-225, Esc 27, Return 13, Tab 9, Backspace 213, Ctrl+letter → code 1-26 with CONTROL bit (HEADLESS-SPEC trap 4). Option+arrow → same arrow + CONTROL bit (the Ctrl+direction fix for bead inc-9df.1, preference-gated later).
- [ ] **Step 5: Window.** SwiftUI `Window` hosting `GridView` via `NSViewRepresentable`; initial content size = 100×54 × cell size (or last saved); on `windowDidEndLiveResize` compute grid = size ÷ cell, clamp ≥80×48, push `INC_EV_RESIZE`; on close push `INC_EV_QUIT` (engine saves; `engine_finished` terminates).
- [ ] **Step 6: Verify by play.** Launch; create a character (or load), walk, save, quit via ESC menu. Confirm `save/*.sav` appears under the scratch dir. Screenshot for the record: `screencapture -R…`.

### Task 7: App Support layout + bundle assembly

**Files:** Create: `macapp/build_app.sh`, `macapp/Resources/Info.plist`, `macapp/Sources/IncursionApp/AppPaths.swift`. Modify: `EngineHost` boot to use AppPaths.

- [ ] **Step 1: AppPaths.** Resolve `~/Library/Application Support/Incursion/` (FileManager, create dirs `save logs mod`); if `INCURSIONPATH` env set, use it instead (portable mode). Copy `Incursion.Mod` from `Bundle.main` Resources into `mod/` when absent or when `Bundle` version stamp ≠ stored stamp file `mod/.module-version`.
- [ ] **Step 2: build_app.sh.** Build ship engine lib (`COMPILER=no BACKEND=mac ./build_macos.sh`), module via classic developer binary (reuse `tools/package_macos.sh:52-59` logic), `swift build -c release`, assemble `dist/Incursion.app/Contents/{MacOS/IncursionApp,Resources/{Incursion.Mod,LICENSES.md,AppIcon.icns},Info.plist}`, `codesign --force --sign -` (ad-hoc; Developer ID path mirrors `package_macos.sh:111-137` when the identity exists). Info.plist: bundle id placeholder `local.incursion.dev` (**flagged: Brian must choose the real one**), `LSMinimumSystemVersion 14.0`, `NSHighResolutionCapable`.
- [ ] **Step 3: Verify.** `open dist/Incursion.app` from a path outside the repo → app launches, plays, writes to Application Support, quits cleanly. `codesign -v` passes.

### Task 8: Mouse — engine hooks

**Files:** Modify: `inc/Term.h` (~+8 lines), `src/TextTerm.cpp` (~+30), `src/Term.cpp` (~+8), `src/Wmac.cpp` (mouse branch).

- [ ] **Step 1: Term.h.** After `#define KY_REDRAW 250` (inc/Term.h:31): `#define KY_MOUSE 251`. In `Term`'s protected block add `int16 mouseCX, mouseCY; int16 menuMWin, menuVStart, menuVRows, menuSzCol, menuDY;`.
- [ ] **Step 2: TextTerm.cpp stash.** In `LMenu` beside the layout math (~:1061) and `LMultiSelect` (~:1373): `menuMWin=MWin; menuVStart=vStart; menuVRows=vRows; menuSzCol=szCol; menuDY=DY;` (match local names at the site).
- [ ] **Step 3: TextTerm.cpp cases.** In LMenu's key switch add:
  ```cpp
  case KY_MOUSE: {
      int16 wx = mouseCX - Windows[menuMWin].Left,
            wy = mouseCY - Windows[menuMWin].Top;
      int16 row = wy - menuDY, col = wx / menuSzCol;
      int32 i = menuVStart + col * menuVRows + row;
      if (row < 0 || row >= menuVRows || i < 0 || i >= OptionCount) break;
      c = (int16)i;
      goto /* the existing KY_ENTER accept path label; introduce one if absent */;
      }
  ```
  LMultiSelect: same math, then fall into the KY_SPACE toggle. Respect the `SetWin` aliasing (`src/TextTerm.cpp:118-128`) by stashing the ALIASED window id (stash inside LMenu after SetWin ran, so `menuMWin` is already the real one).
- [ ] **Step 4: Term.cpp EffectPrompt.** In the key handling (~:2074 area): `else if (ch == KY_MOUSE) { int16 mx = mouseCX - Windows[WIN_MAP].Left + XOff, my = mouseCY - Windows[WIN_MAP].Top + YOff; if (m->InBounds(mx,my)) { tx = mx; ty = my; /* fall into the KY_CMD_ENTER confirm branch */ } }` — reuse the existing validation; a second click confirms if a direct fall-through is awkward.
- [ ] **Step 5: Wmac.cpp mouse branch.** On `INC_EV_MOUSE_DOWN`: set `mouseCX/mouseCY`; if `Mode == MO_PLAY` and the cell is in WIN_MAP: if the square is adjacent to `p->x,p->y` (or equal), synthesize the matching `KY_CMD_*` direction (or `KY_CMD_REST` for self); else return `KY_MOUSE` only when a prompt is listening (`Mode == MO_DIALOG`) — otherwise ignore. In MO_DIALOG return `KY_MOUSE`.
- [ ] **Step 6: Verify.** Rebuild everything incl. `./incursion` (hooks must not disturb libtcod build: `KY_MOUSE` never arrives there). Parity check still green (`tools/check_macterm.sh` — mouse adds no keyscript tokens). In-app: click menu options in StartMenu and chargen; click targets in an `x`amine prompt; click-move one square; wheel-scroll message history.

### Task 9: Menu bar, Preferences, About

**Files:** Create: `macapp/Sources/IncursionApp/Preferences.swift`, `AboutView.swift`, `Menus.swift`. Modify: `IncursionApp.swift`.

- [ ] **Step 1: Menus.** Commands enqueue keys: Game (Save `KY_CMD…` via raw 'S'? — use the keyset's raw keys: Save and Continue lives in the ESC menu, so send ESC-menu sequences only where a single key exists; otherwise omit the item v1): v1 items — Character Sheet (`d` raw? no: send raw `'d'` only in Standard keyset context; safer: send `KY_CMD_CHAR_SHEET`? engine expects raw keys — send the raw key for the ACTIVE keyset read from `OPT_ROGUELIKE`… v1 simplification: menu items send raw keys per the Standard keyset and are disabled when OPT_ROGUELIKE is on), Inventory `i`, Help `?`, Messages `v`, Fullscreen (native). **Keep this honest and small: only keys that are identical in both keysets (`i`, `?`, `v`, ESC) ship v1.**
- [ ] **Step 2: Preferences.** Font family picker (monospaced fonts via `NSFontManager`… filter fixed-pitch), size stepper 9-32, palette classic/soft. Persist in `UserDefaults`; changes re-derive cell size → resize event; palette redraws.
- [ ] **Step 3: About.** Text per spec §5 (Mensch/Weimer/Tew/Hill lines, fork identity, license button opening `LICENSES.md`). Content copied verbatim from `src/Term.cpp:2984-3013`. **Flag: outward-facing text; Brian reads before any release.**
- [ ] **Step 4: Verify.** Build, click every menu item and preference; font size change reflows the window; About shows.

### Task 10: LICENSES.md + check_app.sh + docs

**Files:** Create: `macapp/Resources/LICENSES.md`, `tools/check_app.sh`. Modify: `docs/PORT-STATUS.md` (new section), `README.md` (dev-notes pointer only, no release promises).

- [ ] **Step 1: LICENSES.md** assembled per spec §5 checklist: MIT(Tew) verbatim `LICENSE:12-34`; Mensch grant + Expat election + credit line; OGL v1.0a full text verbatim `LICENSE:52-167`; OGC designation from `lib/help.irh:4976-4984`; Mersenne notice `lib/help.irh:4986-4988`. NO libtcod/SDL2/Breakpad blocks.
- [ ] **Step 2: check_app.sh**: bundle exists; `nm` of the binary has no ACCENT symbols (`Art|yygram|accent` — mirror `tools/check_package.sh`); `Incursion.Mod` + `LICENSES.md` present in Resources; `codesign -v` passes; app binary links no SDL (`otool -L` clean).
- [ ] **Step 3: Docs.** PORT-STATUS gains a "Native app" section: what exists, how to build (`macapp/build_app.sh`), parity harness, open items (bundle id, Developer ID). README: one line under development pointing at the doc.
- [ ] **Step 4: Verify.** `tools/check_app.sh` exits 0. `tools/check_upstream_marks.sh` still passes (no upstream marks added — none of this is upstream's code).

## Self-review notes

- Spec coverage: components 1-5 map to Tasks 1-10; spec's testing section → Tasks 4, 6, 8, 10. Open questions stay open (bundle id, distribution).
- Type consistency: `IncEvent`/`IncSnapshot` names used identically in Tasks 2/3/4/5/6/8.
- The KY_MOUSE menu-accept "goto" is site-dependent; the implementer reads the LMenu switch and reuses its accept code path — the plan names the invariant (all validation runs unchanged), not a fictional label.
