// See the Incursion LICENSE file for copyright information.
//
// The conductor: bridge samples in, throttled milestones out to the LLM,
// prose into `entries` for the pane. Failure is always quiet — one status
// line, never a dialog, and the game never waits on any of this.
import Foundation
import Combine

public struct NarrationEntry: Identifiable, Equatable {
    public let id: UUID
    public let milestone: Milestone?
    public var text: String
    public let isAnswer: Bool

    public init(milestone: Milestone?, text: String, isAnswer: Bool = false) {
        self.id = UUID()
        self.milestone = milestone
        self.text = text
        self.isAnswer = isAnswer
    }
}

/// The app adapts HelpLibrary to this so NarratorKit needs no AppKit.
public protocol GroundingSource {
    func topicIndex(includeWiki: Bool) -> String
    func topicText(ids: [String], includeWiki: Bool) -> String
    func topicTitles(ids: [String]) -> [String]
}

@MainActor
public final class NarratorEngine: ObservableObject {
    @Published public private(set) var entries: [NarrationEntry] = []
    @Published public var muted = false
    @Published public private(set) var statusLine: String?
    @Published public private(set) var promptTokens = 0
    @Published public private(set) var completionTokens = 0
    public var paneOpen = false

    private let settings: NarratorSettings
    private let grounding: GroundingSource?
    private let makeClient: (EndpointConfig) -> OpenAIClient
    private let tokenProvider: () -> String?

    private var detector = MilestoneDetector()
    private var throttle = Throttle()
    private var builder: PromptBuilder?
    private var recent: [String] = []       // ring buffer of message lines
    private var lastState: PlayerState?
    private var artifactFlag = false        // set by messages, consumed by state
    private let recentCap = 200

    public init(settings: NarratorSettings, grounding: GroundingSource?,
                makeClient: @escaping (EndpointConfig) -> OpenAIClient
                    = { OpenAIClient(config: $0) },
                tokenProvider: @escaping () -> String? = { KeychainStore.loadToken() }) {
        self.settings = settings
        self.grounding = grounding
        self.makeClient = makeClient
        self.tokenProvider = tokenProvider
    }

    // MARK: bridge input

    public func ingestMessage(_ line: String) {
        recent.append(line)
        if recent.count > recentCap { recent.removeFirst(recent.count - recentCap) }
        if artifactMentioned(line) { artifactFlag = true }
    }

    public func ingestState(_ json: Data) {
        guard let s = try? PlayerState(json: json) else { return }
        if lastState?.name != s.name {          // new run
            throttle.reset()
            builder = nil
        }
        lastState = s
        var found = detector.ingest(s)
        if artifactFlag { found.append(.artifact); artifactFlag = false }
        guard paneOpen, !muted, !found.isEmpty else { return }
        guard let best = found.max(by: { $0.priority < $1.priority }),
              throttle.permit(best, state: s,
                              config: ThrottleConfig(
                                  enabled: settings.enabledMilestones,
                                  cooldownTurns: settings.cooldownTurns))
        else { return }
        narrate(best, state: s)
    }

    // MARK: narration

    func artifactMentioned(_ line: String) -> Bool {
        line.lowercased().contains("artifact")
    }

    func milestonePrompt(for m: Milestone, state: PlayerState) -> String {
        let what: String
        switch m {
        case .enteredLevel: what = "The adventurer has entered depth \(state.depth)."
        case .levelUp:      what = "The adventurer has grown to level \(state.level)."
        case .nearDeath:    what = "The adventurer is near death (\(state.hp) of \(state.maxhp) HP) at depth \(state.depth)."
        case .death:        what = "The adventurer has died at depth \(state.depth)."
        case .artifact:     what = "The adventurer has come into possession of an artifact at depth \(state.depth)."
        }
        let tail = recent.suffix(20).joined(separator: "\n")
        return what + "\n\nRecent events:\n" + tail + "\n\n"
            + settings.length.instruction
    }

    private func currentSystemPrompt(state: PlayerState) -> String {
        var s = settings.promptText(.narratorSystem)
        s += "\n\n" + settings.promptText(settings.voice)
        if !settings.customStyle.isEmpty { s += "\nStyle notes: " + settings.customStyle }
        s += "\nThe adventurer is named \(state.name)."
        return s
    }

    private func endpoint() -> EndpointConfig? {
        guard let url = URL(string: settings.baseURLString),
              !settings.model.isEmpty,
              let token = tokenProvider() else {
            statusLine = "The narrator is not configured yet (see Gamemaster settings)."
            return nil
        }
        return EndpointConfig(baseURL: url, token: token, model: settings.model)
    }

    private func narrate(_ m: Milestone, state: PlayerState) {
        guard let cfg = endpoint() else { return }
        if builder == nil {
            builder = PromptBuilder(system: currentSystemPrompt(state: state))
        }
        let userTurn = milestonePrompt(for: m, state: state)
        let messages = builder!.request(userTurn: userTurn)
        promptTokens += messages.reduce(0) { $0 + $1.content.count } / 4
        let entry = NarrationEntry(milestone: m, text: "")
        entries.append(entry)
        let entryID = entry.id
        let client = makeClient(cfg)
        let temperature = settings.temperature
        let maxTokens = settings.maxTokens
        Task { [weak self] in
            do {
                let full = try await client.streamChat(
                    messages: messages, temperature: temperature,
                    maxTokens: maxTokens) { delta in
                        Task { @MainActor [weak self] in
                            guard let self,
                                  let idx = self.entries.firstIndex(where: { $0.id == entryID })
                            else { return }
                            self.entries[idx].text += delta
                        }
                    }
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.completionTokens += full.count / 4
                    self.builder?.record(user: userTurn, assistant: full)
                    // Scalar overwrite by design: only the latest status
                    // survives, so a burst of failures doesn't spam the pane.
                    self.statusLine = nil
                    self.compactIfNeeded(m: m, cfg: cfg)
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    if let idx = self.entries.firstIndex(where: { $0.id == entryID }),
                       self.entries[idx].text.isEmpty {
                        self.entries.remove(at: idx)
                    }
                    self.statusLine = "The narrator could not reach the endpoint. It will try again next time."
                }
            }
        }
    }

    /// One deliberate cache break at a depth boundary when the journal is big.
    private func compactIfNeeded(m: Milestone, cfg: EndpointConfig) {
        guard m == .enteredLevel,
              let b = builder, b.journalTokenEstimate > 3000 else { return }
        let client = makeClient(cfg)
        let ask = settings.promptText(.summarize) + "\n\n" + b.journalTranscript
        Task { [weak self] in
            guard let summary = try? await client.streamChat(
                messages: [ChatMessage(role: "user", content: ask)],
                temperature: 0.3, maxTokens: 220, onDelta: { _ in }) else { return }
            await MainActor.run { self?.builder?.compact(summary: summary) }
        }
    }

    // MARK: ask-the-GM

    public func ask(_ question: String) {
        guard paneOpen, !muted,
              settings.askEnabled, let cfg = endpoint(), let g = grounding else { return }
        entries.append(NarrationEntry(milestone: nil,
                                      text: "Q: " + question, isAnswer: true))
        let answer = NarrationEntry(milestone: nil, text: "", isAnswer: true)
        entries.append(answer)
        let entryID = answer.id
        let includeWiki = settings.includeWiki
        let pass1 = [
            ChatMessage(role: "system",
                        content: settings.promptText(.askIndex) + "\n\n"
                            + g.topicIndex(includeWiki: includeWiki)),
            ChatMessage(role: "user", content: question),
        ]
        let client = makeClient(cfg)
        let temperature = settings.temperature
        Task { [weak self] in
            do {
                let raw = try await client.streamChat(messages: pass1,
                    temperature: 0, maxTokens: 100, onDelta: { _ in })
                let ids = Self.parseTopicIDs(raw)
                let reference = g.topicText(ids: ids, includeWiki: includeWiki)
                let titles = g.topicTitles(ids: ids)
                let pass2 = [
                    ChatMessage(role: "system", content:
                        (self?.settings.promptText(.askAnswer) ?? "")
                        + "\n\nReference text:\n" + reference
                        + "\n\nTopic titles: " + titles.joined(separator: ", ")),
                    ChatMessage(role: "user", content: question),
                ]
                _ = try await client.streamChat(messages: pass2,
                    temperature: temperature, maxTokens: 600) { delta in
                        Task { @MainActor [weak self] in
                            guard let self,
                                  let idx = self.entries.firstIndex(where: { $0.id == entryID })
                            else { return }
                            self.entries[idx].text += delta
                        }
                    }
                await MainActor.run { self?.statusLine = nil }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    if let idx = self.entries.firstIndex(where: { $0.id == entryID }),
                       self.entries[idx].text.isEmpty {
                        self.entries.remove(at: idx)
                    }
                    self.statusLine = "The narrator could not reach the endpoint. It will try again next time."
                }
            }
        }
    }

    /// Accepts `["a","b"]` or the same wrapped in prose or code fences.
    static func parseTopicIDs(_ raw: String) -> [String] {
        guard let start = raw.firstIndex(of: "["),
              let end = raw.lastIndex(of: "]"),
              start < end,
              let data = String(raw[start...end]).data(using: .utf8),
              let ids = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return Array(ids.prefix(4))
    }
}
