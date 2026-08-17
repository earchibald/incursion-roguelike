// See the Incursion LICENSE file for copyright information.
//
// The tileset editor: a window of the app's own, on the help window's
// pattern -- created once, raised on demand, independent of the game
// window. Every change applies to the game immediately; there is no
// Apply/Cancel, and Restore Default Tiles is the way back.
//
// Mix and match is the row itself: each row shows what every built-in set
// would draw for that glyph, one click adopts it, and the text field takes
// any character the built-ins do not offer.

import AppKit
import SwiftUI
import UniformTypeIdentifiers

final class TilesetEditorModel: ObservableObject {
    @Published var search = ""
    /// Bumped on every store change so rows re-read the working set.
    @Published var revision = 0

    let store = TilesetStore.shared
    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: TilesetStore.changed, object: nil, queue: .main
        ) { [weak self] _ in self?.revision += 1 }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    var filtered: [(GlyphCatalog.Category, [GlyphCatalog.Entry])] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return GlyphCatalog.Category.allCases.compactMap { category in
            let entries = GlyphCatalog.entries(in: category).filter {
                q.isEmpty || $0.name.lowercased().contains(q)
            }
            return entries.isEmpty ? nil : (category, entries)
        }
    }

    // MARK: actions

    func adopt(_ set: Tileset, for id: UInt32) {
        // Adopting a built-in's glyph means "draw what that set draws",
        // including its fallback to Classic.
        let ch = set.glyphs[id] ?? GlyphMap.character(for: id)
        store.set(glyph: ch == GlyphMap.character(for: id) ? nil : ch, for: id)
    }

    func setCustom(_ text: String, for id: UInt32) {
        guard let ch = text.last else { return }
        store.set(glyph: ch == GlyphMap.character(for: id) ? nil : ch, for: id)
    }

    func loadPanel() {
        let panel = NSOpenPanel()
        panel.directoryURL = store.setsDirectory
        panel.allowedContentTypes = [.json]
        panel.message = "Choose a tileset file"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.load(from: url)
        } catch {
            alert("Could not load \(url.lastPathComponent)",
                  error.localizedDescription)
        }
    }

    func savePanel() {
        let panel = NSSavePanel()
        panel.directoryURL = store.setsDirectory
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue =
            store.active.name == "Classic" || store.active.name == "Custom"
            ? "My Tiles" : store.active.name
        panel.message = "Save the current tiles as a set"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.save(to: url)
        } catch {
            alert("Could not save \(url.lastPathComponent)",
                  error.localizedDescription)
        }
    }

    private func alert(_ message: String, _ detail: String) {
        let a = NSAlert()
        a.alertStyle = .warning
        a.messageText = message
        a.informativeText = detail
        a.runModal()
    }
}

struct TilesetEditorView: View {
    @ObservedObject var model: TilesetEditorModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            columnCaptions
            Divider()
            list
        }
        .frame(minWidth: 620, minHeight: 420)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Menu("Start From") {
                ForEach(Tileset.builtins, id: \.name) { set in
                    Button(set.name) { model.store.apply(set) }
                }
            }
            .fixedSize()
            .help("Replace the working set with a built-in set")

            Button("Restore Default Tiles") { model.store.restoreDefaults() }
                .help("Back to the Classic look")

            Spacer()

            Text("Editing: \(activeName)")
                .foregroundStyle(.secondary)

            Button("Load…") { model.loadPanel() }
            Button("Save As…") { model.savePanel() }
        }
        .padding(10)
    }

    private var activeName: String {
        _ = model.revision
        return model.store.active.name
    }

    /// One caption per swatch column, so the mix-and-match buttons read as
    /// "what each set would draw here" and not as decoration.
    private var columnCaptions: some View {
        HStack(spacing: 8) {
            Text("Glyph").frame(width: 190, alignment: .leading)
            Text("Now").frame(width: 44)
            ForEach(Tileset.builtins, id: \.name) { set in
                Text(shortName(set.name)).frame(width: 44)
            }
            Text("Custom").frame(width: 60)
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private func shortName(_ name: String) -> String {
        name == "Heritage ASCII" ? "ASCII" : name
    }

    private var list: some View {
        List {
            ForEach(model.filtered, id: \.0) { category, entries in
                Section(category.rawValue) {
                    ForEach(entries) { entry in
                        TileRow(model: model, entry: entry)
                    }
                }
            }
        }
        .listStyle(.inset)
        .searchable(text: $model.search, prompt: "Find a glyph by name")
        .overlay {
            if model.filtered.isEmpty {
                ContentUnavailableView("No matches",
                                       systemImage: "magnifyingglass")
            }
        }
    }
}

struct TileRow: View {
    @ObservedObject var model: TilesetEditorModel
    let entry: GlyphCatalog.Entry
    @State private var custom = ""

    var body: some View {
        // Reading revision here re-renders the row after every store change.
        let _ = model.revision
        let current = model.store.character(for: entry.id)

        HStack(spacing: 8) {
            Text(entry.name)
                .frame(width: 190, alignment: .leading)

            swatch(String(current), highlighted: true)
                .help("What the game draws now")

            ForEach(Tileset.builtins, id: \.name) { set in
                let ch = set.glyphs[entry.id] ?? GlyphMap.character(for: entry.id)
                Button {
                    model.adopt(set, for: entry.id)
                } label: {
                    swatch(String(ch), highlighted: ch == current)
                }
                .buttonStyle(.plain)
                .help("Use \(set.name)'s \(entry.name.lowercased())")
            }

            TextField("…", text: $custom)
                .textFieldStyle(.roundedBorder)
                .frame(width: 60)
                .multilineTextAlignment(.center)
                .onSubmit {
                    model.setCustom(custom, for: entry.id)
                    custom = ""
                }
                .onChange(of: custom) { _, value in
                    // Apply as soon as a character lands; keep the field
                    // one character so typing replaces, not appends.
                    guard !value.isEmpty else { return }
                    model.setCustom(value, for: entry.id)
                    custom = String(value.suffix(1))
                }

            Spacer()
        }
        .padding(.vertical, 1)
    }

    /// A game-true preview cell: the glyph in a monospaced font, light on
    /// dark, the way the map shows it.
    private func swatch(_ text: String, highlighted: Bool) -> some View {
        Text(text)
            .font(.system(size: 15, design: .monospaced))
            .frame(width: 40, height: 26)
            .foregroundStyle(.white)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(highlighted ? Color.accentColor
                                              : Color.gray.opacity(0.4),
                                  lineWidth: highlighted ? 2 : 1)
            )
    }
}

/// One window, reused, exactly as the help window is.
final class TilesetEditorWindowController: NSWindowController {
    static let shared = TilesetEditorWindowController()
    private let model = TilesetEditorModel()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "Incursion Tiles"
        window.setFrameAutosaveName("IncursionTilesetEditor")
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.contentView = NSHostingView(
            rootView: TilesetEditorView(model: model))
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not from a nib") }

    func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
