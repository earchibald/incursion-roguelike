// See the Incursion LICENSE file for copyright information.
//
// AppKit lifecycle, chosen over a SwiftUI shell deliberately: the whole UI
// is one custom grid view, and the window must resize in cell increments --
// both are AppKit's home ground. Menus and preferences come later and can
// host SwiftUI where it helps.

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate,
                         NSMenuDelegate {
    var window: NSWindow!
    var gridView: GridView!
    /// The grid last REQUESTED from the engine. Deduping against the last
    /// rendered frame instead would drop a needed resize whenever the
    /// engine is busy and a second resize lands before the first frame.
    var requestedGrid: (w: Int, h: Int)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let dir = AppPaths.resolveGameDirectory()

        gridView = GridView(frame: .zero)
        if UserDefaults.standard.bool(forKey: "softPalette") {
            gridView.setPalette(.soft)
        }
        let cell = gridView.cellSize
        let inset = gridView.contentInset * 2

        // First window: as many cells as comfortably fit, floor 80x48.
        let visible = NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let fitW = Int((visible.width * 0.9 - inset) / cell.width)
        let fitH = Int((visible.height * 0.9 - inset) / cell.height)
        let gridW = max(80, min(fitW, 132))
        let gridH = max(48, min(fitH, 60))
        let content = NSSize(width: CGFloat(gridW) * cell.width + inset,
                             height: CGFloat(gridH) * cell.height + inset)

        window = NSWindow(
            contentRect: NSRect(origin: .zero, size: content),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "Incursion: Halls of the Goblin King"
        window.contentView = gridView
        window.delegate = self
        window.resizeIncrements = NSSize(width: cell.width, height: cell.height)
        window.contentMinSize = NSSize(width: 80 * cell.width + inset,
                                       height: 48 * cell.height + inset)
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(gridView)

        EngineHost.shared.onFrame = { [weak self] in
            self?.gridView.refresh()
        }
        // INCURSION_START_TUTORIAL=1 skips the splash menu into the guided
        // tutorial -- same launch-seam pattern as INCURSION_OPEN_HELP below.
        let wantTutorial = ProcessInfo.processInfo
            .environment["INCURSION_START_TUTORIAL"] == "1"
        EngineHost.shared.start(directory: dir,
                                gridW: Int32(gridW), gridH: Int32(gridH),
                                tutorial: wantTutorial)
        Narrator.attach()

        // Redraw the map whenever the working tileset changes, from the
        // editor or the Tiles menu alike.
        NotificationCenter.default.addObserver(
            forName: TilesetStore.changed, object: nil, queue: .main
        ) { [weak self] _ in self?.gridView.needsDisplay = true }

        // A seam for looking at the help window without driving the menu by
        // hand: INCURSION_OPEN_HELP=<topic|1> opens it at launch. It changes
        // nothing for a player, and it is how the window's appearance is
        // checked (tools/check_help.sh).
        let env = ProcessInfo.processInfo.environment
        if let want = env["INCURSION_OPEN_HELP"], !want.isEmpty {
            HelpWindowController.shared.show(topic: want == "1" ? nil : want,
                                             query: env["INCURSION_HELP_QUERY"])
        }
        // The same seam for the tileset editor.
        if env["INCURSION_OPEN_TILESET_EDITOR"] == "1" {
            TilesetEditorWindowController.shared.show()
        }
    }

    // Closing the window is a request to save and quit; the engine answers
    // through its existing quick-quit path and the app terminates when
    // engine_finished arrives.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        EngineHost.shared.pushQuit()
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication)
        -> NSApplication.TerminateReply {
        if EngineHost.shared.finished {
            return .terminateNow
        }
        EngineHost.shared.pushQuit()
        return .terminateCancel
    }

    // MARK: menu actions

    /// Menu items send raw keys, and only keys that mean the same thing in
    /// both of the game's keysets (Standard and Roguelike) get a menu item.
    @objc func sendEscape(_ sender: Any?) { EngineHost.shared.pushKey(27, mods: 0) }

    /// Starts the guided tutorial by selecting its entry on the engine's
    /// splash menu. The entry's menu letter depends on the keyset option,
    /// so read that from the same Options.Dat the engine reads (byte 202,
    /// OPT_ROGUELIKE; the file is a flat int8[900] indexed by OPT_*).
    /// Mid-game the splash menu does not exist, so ask the player to exit
    /// to it first rather than doing anything destructive on their behalf.
    @objc func startTutorial(_ sender: Any?) {
        let splashMode = 1  // MO_SPLASH, inc/Term.h
        guard EngineHost.shared.currentFrame()?.mode == splashMode else {
            let alert = NSAlert()
            alert.messageText = "Finish this game first"
            alert.informativeText = "The tutorial starts from the opening "
                + "menu. Save and exit your current game (Esc \u{2192} "
                + "Save and Quit), then choose Start Tutorial again."
            alert.runModal()
            return
        }
        var roguelikeKeys = false
        let optPath = AppPaths.resolveGameDirectory() + "/Options.Dat"
        if let opts = FileManager.default.contents(atPath: optPath),
           opts.count > 202 {
            roguelikeKeys = opts[202] != 0
        }
        // "Begin the Tutorial" is the 9th splash entry: letter table
        // "abcdefghi..." standard, "acdefgimo..." roguelike (TextTerm.cpp).
        let letter: UInt8 = roguelikeKeys ? UInt8(ascii: "m")
                                          : UInt8(ascii: "i")
        EngineHost.shared.pushKey(Int32(letter), mods: 0)
    }
    @objc func sendInventory(_ sender: Any?) { EngineHost.shared.pushKey(Int32(UInt8(ascii: "i")), mods: 0) }
    @objc func sendMessages(_ sender: Any?) { EngineHost.shared.pushKey(Int32(UInt8(ascii: "v")), mods: 0) }
    @objc func sendHelp(_ sender: Any?) { EngineHost.shared.pushKey(Int32(UInt8(ascii: "?")), mods: 0) }

    /// The app's own help window. Separate from the in-game help on purpose:
    /// this one does not pause the game, can sit beside it, and carries the
    /// player guides the game itself has none of.
    @objc func showHelpWindow(_ sender: Any?) {
        HelpWindowController.shared.show()
    }

    @objc func showHelpTopic(_ sender: Any?) {
        HelpWindowController.shared.show(
            topic: (sender as? NSMenuItem)?.representedObject as? String)
    }

    // MARK: gamemaster

    @MainActor
    @objc func showNarrator(_ sender: Any?) {
        NarratorWindowController.shared.show()
    }

    @MainActor
    @objc func showNarratorSettings(_ sender: Any?) {
        NarratorSettingsWindowController.shared.show()
    }

    @objc func showLicenses(_ sender: Any?) {
        let bundled = Bundle.main.url(forResource: "LICENSES", withExtension: "md")
        let dev = URL(fileURLWithPath: "macapp/Resources/LICENSES.md")
        if let url = bundled ?? (FileManager.default.fileExists(atPath: dev.path) ? dev : nil) {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: text size and palette

    @objc func biggerText(_ sender: Any?) { adjustFont(by: +1) }
    @objc func smallerText(_ sender: Any?) { adjustFont(by: -1) }

    @objc func chooseFont(_ sender: Any?) {
        guard let item = sender as? NSMenuItem else { return }
        let family = item.representedObject as? String
        gridView.setFontFamily(family)
        item.menu?.items.forEach { $0.state = ($0 == item) ? .on : .off }
        adjustFont(by: 0)  // reapply cell metrics to the window
    }

    // MARK: tiles

    @objc func showTilesetEditor(_ sender: Any?) {
        TilesetEditorWindowController.shared.show()
    }

    @objc func chooseBuiltinTileset(_ sender: Any?) {
        guard let name = (sender as? NSMenuItem)?.representedObject as? String,
              let set = Tileset.builtins.first(where: { $0.name == name })
        else { return }
        TilesetStore.shared.apply(set)
    }

    @objc func chooseSavedTileset(_ sender: Any?) {
        guard let url = (sender as? NSMenuItem)?.representedObject as? URL
        else { return }
        do {
            try TilesetStore.shared.load(from: url)
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Could not load \(url.lastPathComponent)"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    @objc func restoreDefaultTiles(_ sender: Any?) {
        TilesetStore.shared.restoreDefaults()
    }

    /// The Tiles submenu is rebuilt each time it opens: the saved sets on
    /// disk change under the app, and the checkmark tracks the working set.
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu.title == "Tiles" else { return }
        menu.removeAllItems()
        let store = TilesetStore.shared
        for set in Tileset.builtins {
            let title = set.name == "Classic" ? "Classic (Default)" : set.name
            let item = menu.addItem(withTitle: title,
                action: #selector(AppDelegate.chooseBuiltinTileset(_:)),
                keyEquivalent: "")
            item.representedObject = set.name
            item.state = (store.active == set) ? .on : .off
        }
        let saved = store.savedSetURLs()
        if !saved.isEmpty {
            menu.addItem(.separator())
            for url in saved {
                let name = url.deletingPathExtension().lastPathComponent
                let item = menu.addItem(withTitle: name,
                    action: #selector(AppDelegate.chooseSavedTileset(_:)),
                    keyEquivalent: "")
                item.representedObject = url
                if let data = try? Data(contentsOf: url),
                   let set = try? Tileset(jsonData: data) {
                    item.state = (store.active == set) ? .on : .off
                }
            }
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Restore Default Tiles",
            action: #selector(AppDelegate.restoreDefaultTiles(_:)),
            keyEquivalent: "")
        menu.addItem(withTitle: "Edit Tiles…",
            action: #selector(AppDelegate.showTilesetEditor(_:)),
            keyEquivalent: "")
    }

    @objc func togglePalette(_ sender: Any?) {
        let soft = !UserDefaults.standard.bool(forKey: "softPalette")
        UserDefaults.standard.set(soft, forKey: "softPalette")
        gridView.setPalette(soft ? .soft : .classic)
        (sender as? NSMenuItem)?.state = soft ? .on : .off
    }

    private func adjustFont(by delta: CGFloat) {
        let size = max(9, min(32, gridView.font.pointSize + delta))
        gridView.setFont(size: size)
        let cell = gridView.cellSize
        let inset = gridView.contentInset * 2
        window.resizeIncrements = NSSize(width: cell.width, height: cell.height)
        window.contentMinSize = NSSize(width: 80 * cell.width + inset,
                                       height: 48 * cell.height + inset)
        // The window keeps its frame; the grid re-derives from it, so
        // bigger text means fewer, larger cells and vice versa.
        pushGridForCurrentWindow()
        gridView.needsDisplay = true
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        pushGridForCurrentWindow()
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        pushGridForCurrentWindow()
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        pushGridForCurrentWindow()
    }

    private func pushGridForCurrentWindow() {
        let cell = gridView.cellSize
        let size = gridView.bounds.size
        let inset = gridView.contentInset * 2
        let w = max(80, Int((size.width - inset) / cell.width))
        let h = max(48, Int((size.height - inset) / cell.height))
        let current = requestedGrid ?? gridView.gridSize
        if w != current.w || h != current.h {
            requestedGrid = (w, h)
            EngineHost.shared.pushResize(gridW: Int32(w), gridH: Int32(h))
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)

// A minimal main menu so Cmd-Q and Cmd-M work before the real menus land.
let mainMenu = NSMenu()
let appItem = NSMenuItem()
mainMenu.addItem(appItem)
let appMenu = NSMenu()
appMenu.addItem(withTitle: "About Incursion",
                action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                keyEquivalent: "")
appMenu.addItem(withTitle: "Licenses and Notices",
                action: #selector(AppDelegate.showLicenses(_:)), keyEquivalent: "")
appMenu.addItem(.separator())
appMenu.addItem(withTitle: "Hide Incursion",
                action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
appMenu.addItem(.separator())
appMenu.addItem(withTitle: "Quit Incursion",
                action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
appItem.submenu = appMenu

let gameItem = NSMenuItem()
mainMenu.addItem(gameItem)
let gameMenu = NSMenu(title: "Game")
gameMenu.addItem(withTitle: "Start Tutorial",
                 action: #selector(AppDelegate.startTutorial(_:)), keyEquivalent: "")
gameMenu.addItem(withTitle: "Game Menu (Esc)",
                 action: #selector(AppDelegate.sendEscape(_:)), keyEquivalent: "")
gameMenu.addItem(.separator())
gameMenu.addItem(withTitle: "Inventory",
                 action: #selector(AppDelegate.sendInventory(_:)), keyEquivalent: "i")
gameMenu.addItem(withTitle: "Message History",
                 action: #selector(AppDelegate.sendMessages(_:)), keyEquivalent: "")
gameMenu.addItem(withTitle: "Game Help",
                 action: #selector(AppDelegate.sendHelp(_:)), keyEquivalent: "")
gameItem.submenu = gameMenu

let viewItem = NSMenuItem()
mainMenu.addItem(viewItem)
let viewMenu = NSMenu(title: "View")
viewMenu.addItem(withTitle: "Bigger Text",
                 action: #selector(AppDelegate.biggerText(_:)), keyEquivalent: "=")
viewMenu.addItem(withTitle: "Smaller Text",
                 action: #selector(AppDelegate.smallerText(_:)), keyEquivalent: "-")
viewMenu.addItem(.separator())

// Every installed fixed-pitch family, System Monospace first. The engine
// draws per-cell, so any of them stays grid-aligned.
let fontItem = NSMenuItem(title: "Font", action: nil, keyEquivalent: "")
let fontMenu = NSMenu(title: "Font")
let currentFamily = UserDefaults.standard.string(forKey: "fontFamily")
let systemItem = fontMenu.addItem(withTitle: "System Monospace",
    action: #selector(AppDelegate.chooseFont(_:)), keyEquivalent: "")
systemItem.state = currentFamily == nil ? .on : .off
fontMenu.addItem(.separator())
let families = NSFontManager.shared.availableFontFamilies.filter { family in
    guard let f = NSFont(name: family, size: 13) else { return false }
    return f.isFixedPitch
}.sorted()
for family in families {
    let item = fontMenu.addItem(withTitle: family,
        action: #selector(AppDelegate.chooseFont(_:)), keyEquivalent: "")
    item.representedObject = family
    item.state = (family == currentFamily) ? .on : .off
}
fontItem.submenu = fontMenu
viewMenu.addItem(fontItem)

viewMenu.addItem(.separator())
let softItem = viewMenu.addItem(withTitle: "Soft Palette",
                 action: #selector(AppDelegate.togglePalette(_:)), keyEquivalent: "")
softItem.state = UserDefaults.standard.bool(forKey: "softPalette") ? .on : .off

// The Tiles submenu: built-in and saved tilesets plus the editor. Its
// items are rebuilt on open (menuNeedsUpdate), because saved sets live on
// disk and the checkmark follows the working set.
viewMenu.addItem(.separator())
let tilesItem = NSMenuItem(title: "Tiles", action: nil, keyEquivalent: "")
let tilesMenu = NSMenu(title: "Tiles")
tilesMenu.delegate = delegate
tilesItem.submenu = tilesMenu
viewMenu.addItem(tilesItem)
viewItem.submenu = viewMenu

// The Gamemaster menu: the narrator pane and its settings. Sits before Help
// so Help stays the last menu, matching the standard Mac layout.
let gmItem = NSMenuItem()
mainMenu.addItem(gmItem)
let gmMenu = NSMenu(title: "Gamemaster")
let gmShowItem = gmMenu.addItem(withTitle: "Show Narrator",
    action: #selector(AppDelegate.showNarrator(_:)), keyEquivalent: "N")
gmShowItem.keyEquivalentModifierMask = [.command, .shift]
let gmSettingsItem = gmMenu.addItem(withTitle: "Gamemaster Settings…",
    action: #selector(AppDelegate.showNarratorSettings(_:)), keyEquivalent: ",")
gmSettingsItem.keyEquivalentModifierMask = [.command, .shift]
gmItem.submenu = gmMenu

// The Help menu. macOS puts a search field at the top of whatever menu is
// named "Help", which searches menu items -- harmless, and the standard
// place a Mac user looks.
let helpItem = NSMenuItem()
mainMenu.addItem(helpItem)
let helpMenu = NSMenu(title: "Help")
helpMenu.addItem(withTitle: "Incursion Help",
                 action: #selector(AppDelegate.showHelpWindow(_:)), keyEquivalent: "?")
helpMenu.addItem(.separator())
for (title, topic) in [("Getting Started", "intro"),
                       ("Command Listing", "commands"),
                       ("Character Generation", "chargen"),
                       ("Combat", "combat"),
                       ("Magic and Spellcasting", "magic")] {
    let item = helpMenu.addItem(withTitle: title,
        action: #selector(AppDelegate.showHelpTopic(_:)), keyEquivalent: "")
    item.representedObject = topic
}
helpMenu.addItem(.separator())
helpMenu.addItem(withTitle: "In-Game Help (?)",
                 action: #selector(AppDelegate.sendHelp(_:)), keyEquivalent: "")
helpItem.submenu = helpMenu
app.helpMenu = helpMenu

app.mainMenu = mainMenu

app.activate(ignoringOtherApps: true)
app.run()
