// See the Incursion LICENSE file for copyright information.
//
// The narrator's own window: prose scrollback, a question field, a mute
// switch. Closing it silences the narrator entirely -- no calls are made
// while it is closed.
import AppKit
import SwiftUI
import NarratorKit

struct NarratorPaneView: View {
    @ObservedObject var engine: NarratorEngine
    @State private var question = ""

    func label(for m: Milestone?) -> String {
        switch m {
        case .enteredLevel: return "A NEW DEPTH"
        case .levelUp:      return "GROWTH"
        case .nearDeath:    return "THE BRINK"
        case .death:        return "THE END"
        case .artifact:     return "A FINDING"
        case nil:           return "THE GAMEMASTER"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(engine.entries) { entry in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(label(for: entry.milestone))
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(entry.text.isEmpty ? "…" : entry.text)
                                    .font(.system(.body, design: .serif))
                                    .textSelection(.enabled)
                            }
                            .id(entry.id)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: engine.entries.last?.text) {
                    if let id = engine.entries.last?.id {
                        proxy.scrollTo(id, anchor: .bottom)
                    }
                }
            }
            if let status = engine.statusLine {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.vertical, 4)
            }
            Divider()
            HStack(spacing: 8) {
                TextField("Ask the gamemaster about the rules…", text: $question)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { submit() }
                Button("Ask") { submit() }
                    .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty)
                Toggle("Mute", isOn: $engine.muted)
                    .toggleStyle(.switch)
                    .help("Silence narration for this session")
            }
            .padding(10)
        }
        .frame(minWidth: 300, minHeight: 380)
    }

    private func submit() {
        let q = question.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        question = ""
        engine.ask(q)
    }
}

final class NarratorWindowController: NSObject, NSWindowDelegate {
    static let shared = NarratorWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 360, height: 520),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered, defer: false)
            w.title = "Narrator"
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.contentView = NSHostingView(
                rootView: NarratorPaneView(engine: Narrator.engine))
            w.setFrameAutosaveName("NarratorWindow")
            window = w
        }
        Task { @MainActor in Narrator.engine.paneOpen = true }
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        Task { @MainActor in Narrator.engine.paneOpen = false }
    }
}
