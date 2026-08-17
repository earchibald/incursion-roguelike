// See the Incursion LICENSE file for copyright information.
//
// The working tileset: the one the game window draws with, the one the
// editor edits. It persists to UserDefaults on every change, so a
// mixed-and-matched set survives relaunch without ever being saved to a
// named file. Named files are for keeping more than one.
//
// Main-thread only, like the rest of the UI layer: GridView draws on the
// main thread and the editor mutates from SwiftUI actions.

import AppKit

final class TilesetStore {
    static let shared = TilesetStore()

    /// Posted after any change to the working set. The app delegate redraws
    /// the game window; the editor refreshes its rows.
    static let changed = Notification.Name("IncursionTilesetChanged")

    private static let defaultsKey = "tileset.active"

    private(set) var active: Tileset

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let saved = try? Tileset(jsonData: data) {
            active = saved
        } else {
            active = .classic
        }
    }

    /// What the game draws for an id: the working set's choice, else the
    /// Classic look. GridView calls this per cell.
    func character(for id: UInt32) -> Character {
        active.glyphs[id] ?? GlyphMap.character(for: id)
    }

    // MARK: mutation

    func set(glyph: Character?, for id: UInt32) {
        guard GlyphCatalog.names[id] != nil else { return }
        if let glyph {
            active.glyphs[id] = glyph
        } else {
            active.glyphs.removeValue(forKey: id)
        }
        // An edit makes the set the player's own: a built-in's name is
        // dropped the moment the glyphs stop matching it. A name from the
        // player's own file is kept -- it is still their set, edited.
        if Tileset.builtins.contains(where: { $0.name == active.name }),
           !Tileset.builtins.contains(active) {
            active.name = "Custom"
        }
        didChange()
    }

    func apply(_ set: Tileset) {
        active = set
        didChange()
    }

    func restoreDefaults() {
        active = .classic
        didChange()
    }

    private func didChange() {
        if let data = try? active.jsonData() {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
        NotificationCenter.default.post(name: Self.changed, object: self)
    }

    // MARK: named files

    /// Where saved tilesets live. Beside the game's own data on purpose:
    /// the whole Incursion folder is the thing a player backs up.
    var setsDirectory: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Incursion", isDirectory: true)
            .appendingPathComponent("Tilesets", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: base, withIntermediateDirectories: true)
        return base
    }

    /// Every saved set, for the menu and the editor. Sorted by file name so
    /// the menu order is stable.
    func savedSetURLs() -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: setsDirectory, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func load(from url: URL) throws {
        let data = try Data(contentsOf: url)
        apply(try Tileset(jsonData: data))
    }

    func save(to url: URL) throws {
        var named = active
        named.name = url.deletingPathExtension().lastPathComponent
        try named.jsonData().write(to: url)
        active.name = named.name
        didChange()
    }
}
