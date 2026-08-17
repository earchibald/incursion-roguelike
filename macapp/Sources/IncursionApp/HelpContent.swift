// See the Incursion LICENSE file for copyright information.
//
// What the help window reads, and where it comes from.
//
//   Resources/Help/manual.json   the game's own manual, produced at build
//                                time by `incursion -exporthelp`. Half of it
//                                is written by hand in lib/help.irh and half
//                                is generated from the loaded module, so it
//                                always describes the ruleset that shipped
//                                with this binary. Never edited by hand.
//   Resources/Help/wiki/*.md     guide pages vendored from the Incursion
//                                wiki by tools/fetch_wiki_help.py, under
//                                CC BY-SA 3.0. Each file carries the
//                                attribution the licence requires, and the
//                                window shows it with the page.
//
// Nothing here reaches the network. A help window that needs the internet is
// useless in the one place it is most wanted, which is mid-game on a laptop.

import Foundation

// MARK: - the game's manual

/// One coloured stretch of manual text. `to` is set when the run is a link
/// to another topic; `anchor` when it marks a place within this one.
struct HelpRun: Decodable {
    let c: Int
    let s: String
    let to: String?
    let anchor: String?
}

struct HelpTopic: Decodable {
    let id: String
    let title: String
    let section: String
    let contents: Bool
    let runs: [HelpRun]

    /// The topic as plain text, for searching and for the copy command.
    var plainText: String {
        runs.map(\.s).joined()
    }
}

private struct HelpManual: Decodable {
    let topics: [HelpTopic]
}

// MARK: - vendored wiki pages

struct WikiPage {
    var title: String
    var slug: String
    var order: Int
    var source: String
    var attribution: String
    var license: String
    var licenseURL: String
    var retrieved: String
    var modifications: String
    var body: String

    /// The line the licence asks for, in the form a reader can act on.
    var credit: String {
        "“\(title)” by \(attribution), from the Incursion Wiki. "
        + "Licensed \(license). Retrieved \(retrieved). "
        + "Changes: \(modifications)."
    }

    /// Front matter is `key: value` lines between two `---` fences. Written
    /// by tools/fetch_wiki_help.py and by nothing else, so a strict parser
    /// is right: a file that does not match is a bug to see, not to absorb.
    static func parse(_ text: String, slug: String) -> WikiPage? {
        var fields: [String: String] = [:]
        var lines = text.components(separatedBy: "\n")
        guard lines.first == "---" else { return nil }
        lines.removeFirst()
        var body: [String] = []
        var inFront = true
        for line in lines {
            if inFront {
                if line == "---" { inFront = false; continue }
                guard let colon = line.firstIndex(of: ":") else { continue }
                let key = String(line[line.startIndex..<colon])
                let value = line[line.index(after: colon)...]
                    .trimmingCharacters(in: .whitespaces)
                fields[key] = value
            } else {
                body.append(line)
            }
        }
        guard !inFront,
              let title = fields["title"],
              let source = fields["source"],
              let license = fields["license"] else { return nil }
        return WikiPage(
            title: title,
            slug: fields["slug"] ?? slug,
            order: Int(fields["order"] ?? "") ?? 999,
            source: source,
            attribution: fields["attribution"] ?? "Incursion Wiki contributors",
            license: license,
            licenseURL: fields["license_url"]
                ?? "https://creativecommons.org/licenses/by-sa/3.0/",
            retrieved: fields["retrieved"] ?? "unknown",
            modifications: fields["modifications"] ?? "none stated",
            body: body.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

// MARK: - what the sidebar shows

enum HelpItem: Identifiable, Hashable {
    case topic(String)     // manual topic id
    case wiki(String)      // wiki slug
    case about             // the hand-written page about this window

    var id: String {
        switch self {
        case .topic(let t): return "topic:" + t
        case .wiki(let s):  return "wiki:" + s
        case .about:        return "about"
        }
    }
}

struct HelpSection: Identifiable {
    let id: String
    let title: String
    let items: [HelpItem]
}

struct HelpHit: Identifiable {
    let id: String
    let item: HelpItem
    let title: String
    let snippet: String
    let count: Int
}

/// Everything the window knows. Loaded once, on the main thread, from the
/// bundle -- or from the repository when running the binary straight out of
/// `swift build`, which is how the window gets worked on.
final class HelpLibrary {
    static let shared = HelpLibrary()

    private(set) var topics: [String: HelpTopic] = [:]
    private(set) var topicOrder: [String] = []
    private(set) var pages: [String: WikiPage] = [:]
    private(set) var sections: [HelpSection] = []
    /// Set when the manual is missing, so the window can say so plainly
    /// instead of showing an empty sidebar.
    private(set) var loadProblem: String?

    private init() {
        load()
        buildSections()
    }

    private static func resourceDirectory() -> URL? {
        if let url = Bundle.main.url(forResource: "Help", withExtension: nil) {
            return url
        }
        // Running from `swift build` inside the checkout.
        for candidate in ["macapp/Resources/Help", "Resources/Help", "../Resources/Help"] {
            let url = URL(fileURLWithPath: candidate)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    private func load() {
        guard let dir = Self.resourceDirectory() else {
            loadProblem = "The Help folder is not in this build."
            return
        }
        let manualURL = dir.appendingPathComponent("manual.json")
        do {
            let data = try Data(contentsOf: manualURL)
            let manual = try JSONDecoder().decode(HelpManual.self, from: data)
            for t in manual.topics {
                topics[t.id] = t
                topicOrder.append(t.id)
            }
        } catch {
            loadProblem = "The manual could not be read (\(manualURL.lastPathComponent)): "
                + error.localizedDescription
        }

        let wikiDir = dir.appendingPathComponent("wiki")
        let files = (try? FileManager.default.contentsOfDirectory(
            at: wikiDir, includingPropertiesForKeys: nil)) ?? []
        for url in files where url.pathExtension == "md" {
            guard let text = try? String(contentsOf: url, encoding: .utf8),
                  let page = WikiPage.parse(text,
                                            slug: url.deletingPathExtension().lastPathComponent)
            else { continue }
            pages[page.slug] = page
        }
    }

    private func buildSections() {
        var built: [HelpSection] = []
        let guides = pages.values.sorted { ($0.order, $0.title) < ($1.order, $1.title) }
        if !guides.isEmpty {
            built.append(HelpSection(id: "guides", title: "Getting Started",
                                     items: guides.map { .wiki($0.slug) }))
        }
        // The manual keeps the order the engine exported: chapters as the
        // manual itself lists them, then the generated reference.
        for (id, title) in [("manual", "The Manual"),
                            ("reference", "Reference"),
                            ("legal", "Licences")] {
            let items = topicOrder
                .compactMap { topics[$0] }
                .filter { $0.section == id && $0.contents }
                .map { HelpItem.topic($0.id) }
            if !items.isEmpty {
                built.append(HelpSection(id: id, title: title, items: items))
            }
        }
        built.append(HelpSection(id: "about", title: "About", items: [.about]))
        sections = built
    }

    // MARK: lookup

    func title(for item: HelpItem) -> String {
        switch item {
        case .topic(let id): return topics[id]?.title ?? id
        case .wiki(let slug): return pages[slug]?.title ?? slug
        case .about: return "About This Help"
        }
    }

    func firstItem() -> HelpItem {
        if pages["general-tips-for-survival"] != nil {
            return .wiki("general-tips-for-survival")
        }
        if topics["mainmenu"] != nil { return .topic("mainmenu") }
        return .about
    }

    /// Case-insensitive substring search over every page. Deliberately not
    /// fuzzy: a reader searching "cursed" wants the word, and a ranked guess
    /// over a two-megabyte manual is slower and harder to trust.
    func search(_ query: String) -> [HelpHit] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard needle.count >= 2 else { return [] }
        var hits: [HelpHit] = []

        func hit(_ item: HelpItem, _ title: String, _ text: String) {
            let hay = text.lowercased()
            var count = 0
            var index = hay.startIndex
            var firstRange: Range<String.Index>?
            while let r = hay.range(of: needle, range: index..<hay.endIndex) {
                if firstRange == nil { firstRange = r }
                count += 1
                index = r.upperBound
                if count > 999 { break }
            }
            let inTitle = title.lowercased().contains(needle)
            guard count > 0 || inTitle else { return }
            var snippet = ""
            if let r = firstRange {
                let start = hay.index(r.lowerBound,
                                      offsetBy: -60,
                                      limitedBy: hay.startIndex) ?? hay.startIndex
                let end = hay.index(r.upperBound,
                                    offsetBy: 90,
                                    limitedBy: hay.endIndex) ?? hay.endIndex
                snippet = String(text[start..<end])
                    .replacingOccurrences(of: "\n", with: " ")
                snippet = snippet.split(separator: " ").joined(separator: " ")
            }
            hits.append(HelpHit(id: item.id, item: item, title: title,
                                snippet: snippet, count: count))
        }

        for page in pages.values.sorted(by: { $0.order < $1.order }) {
            hit(.wiki(page.slug), page.title, page.body)
        }
        for id in topicOrder {
            guard let t = topics[id] else { continue }
            hit(.topic(id), t.title, t.plainText)
        }
        // Title matches first, then by how often the word appears.
        return hits.sorted {
            let a = $0.title.lowercased().contains(needle)
            let b = $1.title.lowercased().contains(needle)
            if a != b { return a }
            return $0.count > $1.count
        }
    }
}
