// See the Incursion LICENSE file for copyright information.
//
// Binds NarratorKit to the app: the HelpLibrary becomes the grounding
// corpus, and the bridge taps feed the engine singleton.
import Foundation
import NarratorKit

struct HelpGrounding: GroundingSource {
    func plainText(of topic: HelpTopic) -> String {
        topic.runs.map(\.s).joined()
    }

    func topicIndex(includeWiki: Bool) -> String {
        var lines: [String] = []
        let lib = HelpLibrary.shared
        for id in lib.topicOrder {
            guard let t = lib.topics[id] else { continue }
            lines.append("\(t.id) — \(t.title) [\(t.section)]")
        }
        if includeWiki {
            for page in lib.pages.values.sorted(by: { $0.title < $1.title }) {
                lines.append("wiki:\(page.slug) — \(page.title) [guide]")
            }
        }
        return lines.joined(separator: "\n")
    }

    func topicText(ids: [String], includeWiki: Bool) -> String {
        let lib = HelpLibrary.shared
        var parts: [String] = []
        for id in ids {
            if id.hasPrefix("wiki:") {
                guard includeWiki,
                      let page = lib.pages[String(id.dropFirst(5))] else { continue }
                parts.append("## \(page.title)\n" + page.body)
            } else if let t = lib.topics[id] {
                parts.append("## \(t.title)\n" + plainText(of: t))
            }
        }
        return parts.joined(separator: "\n\n")
    }

    func topicTitles(ids: [String]) -> [String] {
        let lib = HelpLibrary.shared
        return ids.compactMap { id in
            if id.hasPrefix("wiki:") { return lib.pages[String(id.dropFirst(5))]?.title }
            return lib.topics[id]?.title
        }
    }
}

enum Narrator {
    @MainActor static let settings = NarratorSettings()
    @MainActor static let engine = NarratorEngine(settings: settings,
                                                  grounding: HelpGrounding())

    /// Call once at launch, after EngineHost is configured.
    @MainActor static func attach() {
        EngineHost.shared.onGameMessage = { engine.ingestMessage($0) }
        EngineHost.shared.onPlayerState = { engine.ingestState($0) }
    }
}
