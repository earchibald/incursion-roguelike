# Tileset Editor for the Native Mac App — Design

Bead: inc-9df.9.11. Parent epic: inc-9df.9 (native Mac app).
Written 2026-08-17 in an autonomous session; the design decisions below were
made without user review because the goal directive forbade blocking on
questions. Each decision states its reason so it can be revisited cheaply.

## Summary

| Piece | Decision |
|---|---|
| What a tileset is | A named partial map: semantic glyph id (256–375) → one display character |
| What it is not | No remapping of ids < 256; no color overrides |
| Built-in sets | Classic CP437 (default, full), Heritage ASCII, Crisp, Ornate (partial) |
| Fallback | Any unmapped id falls back to Classic (GlyphMap) |
| Editor | Own window, Help-window pattern (SwiftUI in a shared NSWindowController) |
| Mix and match | Per-row swatch buttons, one per built-in set, plus a custom character field |
| Apply | Live: every edit redraws the game window immediately |
| Persistence | Working set in UserDefaults; named sets as JSON in App Support/Incursion/Tilesets |
| Menus | View ▸ Tiles: built-ins, saved sets, Restore Default Tiles, Edit Tiles… |
| Test seam | `INCURSION_OPEN_TILESET_EDITOR=1` opens the editor at launch |

## Scope of a tile

The engine's cells carry a 12-bit glyph id, 4-bit fg, 4-bit bg
(`GridView.draw`). Ids below 256 are literal CP437 codes and are shared by
menus, messages and prompts; remapping them would corrupt on-screen text.
Ids 256–375 are the semantic `GLYPH_*` vocabulary (inc/Defines.h) the map
draws with. The editor therefore edits exactly ids 256–375.

Color is not part of a tileset. The engine's fg color carries game meaning
(potion colors, monster tints, status highlights); a tileset that overrides
it would fight the game. The existing Classic/Soft palette toggle already
covers color taste.

## Model

`Tileset`: `name: String`, `glyphs: [UInt32: String]`, Codable. Each value
is one character (grapheme cluster); longer strings are truncated to their
first character on load. A set may be partial: lookup falls back to
`GlyphMap.character(for:)`, which is the Classic set.

`GlyphCatalog`: the display table for the editor — for each id: name
("Wall", "Potion", …) and a category (Terrain, Dungeon Features, Items,
Creatures, Interface). Transcribed from inc/Defines.h names.

`TilesetStore` (singleton):
- `active: Tileset` — the working set the game draws with.
- `character(for id: UInt32) -> Character` — active override, else GlyphMap.
- Persists `active` to UserDefaults (`tileset.active`, JSON) on every
  change, so mix-and-match state survives relaunch without an explicit save.
- `setsDirectory` — `Application Support/Incursion/Tilesets/`, scanned for
  `*.json` to build the menu and the editor's Load list.
- Posts `.tilesetChanged`; the app delegate observes it and redraws the
  grid view and refreshes menu checkmarks.

## Built-in sets

Classic is the current GlyphMap and is not a data file; it is the floor
every lookup lands on. The three new sets are partial override tables in
code (Tileset.swift), immutable, and chosen to stay inside characters that
common monospaced fonts carry at text presentation (no emoji: color glyphs
ignore fg tint and break the grid's look):

- **Heritage ASCII** — every override is printable ASCII, in the classic
  roguelike voice: walls `#`, floor `.`, water `~`, trap `^`, humanoids `@`,
  demons `&`, arrows `^ v < >`.
- **Crisp** — clean geometric Unicode: walls `█`, floor `·`, water `≈`,
  gem `♦`, tree `♣`, pillar `●`.
- **Ornate** — decorative Unicode where it reads well: wall `▦`, ice `✻`,
  gem `❖`, grave `⊓`, portal `◈`.

## Editor window

One shared `TilesetEditorWindowController` (the HelpWindowController
pattern: created once, `isReleasedWhenClosed = false`, `show()` raises).
Content is SwiftUI.

Layout: a toolbar row, then a searchable list grouped by category. Each row:

- glyph name,
- live preview drawn white-on-black in a monospaced font,
- one swatch button per built-in set showing that set's character for the
  id — clicking adopts it (this is mix and match),
- a one-character text field for a custom character.

Toolbar / controls:
- **Base set** popup: apply a whole built-in set as the working set.
- **Restore Default Tiles**: working set becomes Classic (empty overrides).
- **Load…** / **Save As…**: NSOpenPanel/NSSavePanel on the Tilesets
  directory, JSON.

Every change applies immediately: the store persists and notifies, the game
window redraws. There is no separate Apply/Cancel; Restore Default Tiles is
the escape hatch.

## Menus

View ▸ Tiles submenu:
- Classic (Default), Heritage ASCII, Crisp, Ornate — radio checkmarks; the
  check shows when the working set equals that built-in exactly, so a
  mixed set shows no check.
- Saved sets found in the Tilesets directory, rebuilt when the menu opens.
- Restore Default Tiles.
- Edit Tiles… — opens the editor window.

## Error handling

- Unreadable or malformed JSON on load: NSAlert with the file name and the
  decode error; working set unchanged.
- Save failure: NSAlert; nothing else changes.
- Unknown ids in a loaded file are ignored; unknown keys likewise (forward
  compatibility).
- Multi-character custom input keeps the first grapheme.

## Verification

- `swift build` in macapp (DEVELOPER_DIR at Xcode per the toolchain memory).
- `INCURSION_OPEN_TILESET_EDITOR=1` opens the editor at launch, the same
  seam INCURSION_OPEN_HELP established; screenshots are taken by window id,
  never full screen, with INCURSIONPATH pointed at a scratch directory.

## Files

| File | Role |
|---|---|
| `macapp/Sources/IncursionApp/Tileset.swift` | Model, catalog, built-in sets, JSON codec |
| `macapp/Sources/IncursionApp/TilesetStore.swift` | Working set, persistence, directory, notification |
| `macapp/Sources/IncursionApp/TilesetEditorWindow.swift` | Editor UI and window controller |
| `macapp/Sources/IncursionApp/GridView.swift` | Draw through `TilesetStore.character(for:)` |
| `macapp/Sources/IncursionApp/main.swift` | View ▸ Tiles menu, env seam |
