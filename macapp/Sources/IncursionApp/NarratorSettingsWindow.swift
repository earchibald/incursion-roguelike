// See the Incursion LICENSE file for copyright information.
//
// Every knob the narrator has, in one window. The token goes straight to
// the Keychain; nothing here writes a file. The privacy line by the URL
// says plainly where game text will be sent.
import AppKit
import SwiftUI
import NarratorKit

struct NarratorSettingsView: View {
    @ObservedObject var settings: NarratorSettings
    @ObservedObject var engine: NarratorEngine

    @State private var token: String = KeychainStore.loadToken() ?? ""
    @State private var models: [String] = []
    @State private var testResult: String?
    @State private var busy = false
    @State private var editingPrompt: PromptKey?

    private func client() -> OpenAIClient? {
        guard let url = URL(string: settings.baseURLString) else {
            testResult = "The endpoint URL is not valid."
            return nil
        }
        guard !settings.model.isEmpty else {
            testResult = "Choose or enter a model first."
            return nil
        }
        return OpenAIClient(config: EndpointConfig(
            baseURL: url, token: token, model: settings.model))
    }

    var body: some View {
        Form {
            Section("Connection") {
                TextField("Endpoint", text: $settings.baseURLString,
                          prompt: Text("https://api.openai.com/v1"))
                Text("Milestone text from your game is sent to this endpoint.")
                    .font(.caption).foregroundStyle(.secondary)
                SecureField("API token", text: $token)
                    .onChange(of: token) {
                        token.isEmpty ? KeychainStore.deleteToken()
                                      : KeychainStore.saveToken(token)
                    }
                HStack {
                    if models.isEmpty {
                        TextField("Model", text: $settings.model,
                                  prompt: Text("model id"))
                    } else {
                        Picker("Model", selection: $settings.model) {
                            ForEach(models, id: \.self, content: Text.init)
                            if !settings.model.isEmpty && !models.contains(settings.model) {
                                Text(settings.model).tag(settings.model)
                            }
                        }
                    }
                    Button("Detect Models") { detectModels() }.disabled(busy)
                }
                HStack {
                    Button("Test Connection") { testConnection() }.disabled(busy)
                    if busy { ProgressView().controlSize(.small) }
                    if let r = testResult {
                        Text(r).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section("Voice") {
                Picker("Preset", selection: $settings.voice) {
                    Text("Dry Chronicler").tag(PromptKey.voiceChronicler)
                    Text("Doomful Bard").tag(PromptKey.voiceBard)
                    Text("Wry Companion").tag(PromptKey.voiceCompanion)
                }
                TextField("Extra style notes", text: $settings.customStyle,
                          axis: .vertical)
                    .lineLimit(2...4)
            }
            Section("Prompts") {
                ForEach(PromptKey.allCases, id: \.self) { key in
                    HStack {
                        Text(key.title)
                        if settings.isPromptModified(key) {
                            Text("modified").font(.caption2)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(.quaternary, in: Capsule())
                        }
                        Spacer()
                        Button("Edit…") { editingPrompt = key }
                        Button("Restore Default") { settings.restorePromptDefault(key) }
                            .disabled(!settings.isPromptModified(key))
                    }
                }
                Text("Edited prompts apply at the next narration, at the cost of one prompt-cache break.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Cadence") {
                ForEach(Milestone.allCases, id: \.self) { m in
                    Toggle(cadenceTitle(m), isOn: Binding(
                        get: { settings.enabledMilestones.contains(m) },
                        set: { on in
                            if on { settings.enabledMilestones.insert(m) }
                            else  { settings.enabledMilestones.remove(m) }
                        }))
                }
                Stepper("Cooldown: \(settings.cooldownTurns) game turns",
                        value: $settings.cooldownTurns, in: 0...2000, step: 50)
                Picker("Length", selection: $settings.length) {
                    ForEach(NarrationLength.allCases, id: \.self) {
                        Text($0.title).tag($0)
                    }
                }
            }
            Section("Sampling") {
                Slider(value: $settings.temperature, in: 0...1.5) {
                    Text("Temperature \(settings.temperature, specifier: "%.2f")")
                }
                Stepper("Response cap: \(settings.maxTokens) tokens",
                        value: $settings.maxTokens, in: 60...1000, step: 20)
            }
            Section("Ask the GM") {
                Toggle("Enable rules & lore questions", isOn: $settings.askEnabled)
                Toggle("Include wiki pages in grounding", isOn: $settings.includeWiki)
            }
            Section("Status") {
                Text("This session: ~\(engine.promptTokens) prompt / ~\(engine.completionTokens) completion tokens")
                    .font(.caption).foregroundStyle(.secondary)
                if let status = engine.statusLine {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 460, minHeight: 560)
        .sheet(item: $editingPrompt) { key in
            // A child view that owns its text state: the parent's @State is
            // not reliably applied to a sheet presented in the same update,
            // which left the editor empty (bead inc-fun).
            PromptEditorSheet(key: key,
                              initialText: settings.promptText(key)) { text in
                settings.setPromptText(key, text)
            }
        }
    }

    private func cadenceTitle(_ m: Milestone) -> String {
        switch m {
        case .enteredLevel: return "Entering a new depth"
        case .levelUp:      return "Gaining a level"
        case .nearDeath:    return "Falling near death"
        case .death:        return "Death"
        case .artifact:     return "Finding an artifact"
        }
    }

    @MainActor private func detectModels() {
        guard let c = client() else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                models = try await c.listModels()
                testResult = "\(models.count) models found."
            } catch {
                models = []
                testResult = "Model listing failed — enter the model id by hand."
            }
        }
    }

    @MainActor private func testConnection() {
        guard let c = client() else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                let dt = try await c.testConnection()
                testResult = String(format: "Connected — %.1f s round trip.", dt)
            } catch OpenAIError.http(let code) {
                testResult = "The endpoint answered with HTTP \(code)."
            } catch {
                testResult = "The endpoint could not be reached."
            }
        }
    }
}

extension PromptKey: Identifiable {
    public var id: String { rawValue }
}

/// The prompt editor. It owns the draft text, seeded from the current prompt
/// at init, so the sheet never presents empty.
private struct PromptEditorSheet: View {
    let key: PromptKey
    let onSave: (String) -> Void
    @State private var draft: String
    @Environment(\.dismiss) private var dismiss

    init(key: PromptKey, initialText: String, onSave: @escaping (String) -> Void) {
        self.key = key
        self.onSave = onSave
        _draft = State(initialValue: initialText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(key.title).font(.headline)
            TextEditor(text: $draft)
                .font(.system(.body, design: .monospaced))
                .frame(minWidth: 480, minHeight: 260)
            HStack {
                Button("Restore Default") { draft = key.defaultText }
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    onSave(draft)
                    dismiss()
                }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
    }
}

final class NarratorSettingsWindowController: NSObject {
    static let shared = NarratorSettingsWindowController()
    private var window: NSWindow?

    @MainActor func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 600),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered, defer: false)
            w.title = "Gamemaster"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: NarratorSettingsView(
                settings: Narrator.settings, engine: Narrator.engine))
            w.setFrameAutosaveName("NarratorSettingsWindow")
            window = w
        }
        window?.makeKeyAndOrderFront(nil)
    }
}
