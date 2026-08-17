// See the Incursion LICENSE file for copyright information.
//
// AppKit lifecycle, chosen over a SwiftUI shell deliberately: the whole UI
// is one custom grid view, and the window must resize in cell increments --
// both are AppKit's home ground. Menus and preferences come later and can
// host SwiftUI where it helps.

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
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

        // First window: as many cells as comfortably fit, floor 80x48.
        let visible = NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let fitW = Int((visible.width * 0.9) / cell.width)
        let fitH = Int((visible.height * 0.9) / cell.height)
        let gridW = max(80, min(fitW, 132))
        let gridH = max(48, min(fitH, 60))
        let content = NSSize(width: CGFloat(gridW) * cell.width,
                             height: CGFloat(gridH) * cell.height)

        window = NSWindow(
            contentRect: NSRect(origin: .zero, size: content),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "Incursion: Halls of the Goblin King"
        window.contentView = gridView
        window.delegate = self
        window.resizeIncrements = NSSize(width: cell.width, height: cell.height)
        window.contentMinSize = NSSize(width: 80 * cell.width,
                                       height: 48 * cell.height)
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(gridView)

        EngineHost.shared.onFrame = { [weak self] in
            self?.gridView.refresh()
        }
        EngineHost.shared.start(directory: dir,
                                gridW: Int32(gridW), gridH: Int32(gridH))
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
    @objc func sendInventory(_ sender: Any?) { EngineHost.shared.pushKey(Int32(UInt8(ascii: "i")), mods: 0) }
    @objc func sendMessages(_ sender: Any?) { EngineHost.shared.pushKey(Int32(UInt8(ascii: "v")), mods: 0) }
    @objc func sendHelp(_ sender: Any?) { EngineHost.shared.pushKey(Int32(UInt8(ascii: "?")), mods: 0) }

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
        window.resizeIncrements = NSSize(width: cell.width, height: cell.height)
        window.contentMinSize = NSSize(width: 80 * cell.width,
                                       height: 48 * cell.height)
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
        let w = max(80, Int(size.width / cell.width))
        let h = max(48, Int(size.height / cell.height))
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
gameMenu.addItem(withTitle: "Game Menu (Esc)",
                 action: #selector(AppDelegate.sendEscape(_:)), keyEquivalent: "")
gameMenu.addItem(.separator())
gameMenu.addItem(withTitle: "Inventory",
                 action: #selector(AppDelegate.sendInventory(_:)), keyEquivalent: "i")
gameMenu.addItem(withTitle: "Message History",
                 action: #selector(AppDelegate.sendMessages(_:)), keyEquivalent: "")
gameMenu.addItem(withTitle: "Game Help",
                 action: #selector(AppDelegate.sendHelp(_:)), keyEquivalent: "?")
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
viewItem.submenu = viewMenu

app.mainMenu = mainMenu

app.activate(ignoringOtherApps: true)
app.run()
