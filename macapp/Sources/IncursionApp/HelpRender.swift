// See the Incursion LICENSE file for copyright information.
//
// Turning the two kinds of help page into something a Mac window can draw.
//
// The manual is 80-column text with the engine's own markup: a colour index
// per run, links between topics, and anchors -- the {DR} markers that let the
// contents list at the top of a reference page jump to the entry itself. It
// is drawn in a fixed-pitch font at exactly eighty columns, because its boxes
// and tables are aligned with spaces at that width, and the in-game viewer
// wraps its prose to the window.
//
// The wiki pages are Markdown, which is prose, so they ARE re-wrapped and
// drawn in the system font at a comfortable measure.
//
// Both are built as NSAttributedString and drawn by an NSTextView rather than
// a SwiftUI Text. Three reasons, all load-bearing: a reference page is a
// megabyte of text and TextKit is built for that; an anchor needs a character
// range to scroll to, which a SwiftUI Text cannot give; and selection, copy
// and Find come free and behave the way a Mac user expects.
//
// Both are drawn on the game's dark ground with the game's palette, so a
// colour in the manual means here what it means on the map.

import AppKit

/// The one place the help window's colours are decided.
struct HelpTheme {
    var palette: Palette

    var background: NSColor {
        NSColor(srgbRed: 0.043, green: 0.043, blue: 0.06, alpha: 1)
    }
    var body: NSColor { color(7) }        // GREY
    var heading: NSColor { color(14) }    // YELLOW
    var link: NSColor { color(11) }       // SKYBLUE
    var code: NSColor { color(10) }       // EMERALD
    var quiet: NSColor { color(8) }       // SHADOW

    func color(_ index: Int) -> NSColor {
        let i = max(0, min(15, index))
        // BLACK is the background; text stamped with it would be invisible,
        // which is what the manual asks for wherever it paints on a bar.
        return palette.colors[i == 0 ? 7 : i]
    }
}

/// Links inside the window use a private scheme so the text view reports them
/// to us instead of handing them to a browser. Wiki pages keep their http
/// links, which do go to the browser.
enum HelpLink {
    static let scheme = "incursion-help"

    static func topic(_ id: String) -> URL? { make(host: "topic", value: id) }
    static func anchor(_ name: String) -> URL? { make(host: "anchor", value: name) }

    private static func make(host: String, value: String) -> URL? {
        var c = URLComponents()
        c.scheme = scheme
        c.host = host
        c.path = "/" + value
        return c.url
    }

    static func target(of url: URL) -> (kind: String, value: String)? {
        guard url.scheme == scheme, let host = url.host else { return nil }
        let raw = String(url.path.dropFirst())
        return (host, raw.removingPercentEncoding ?? raw)
    }
}

/// A rendered page: the text, where each anchor landed, and how wide to lay
/// it out.
struct HelpDocument {
    var text: NSAttributedString
    /// Anchor name to the character offset a reader should be taken to. The
    /// LAST occurrence wins, which is what the in-game viewer does and what
    /// the pages are written for: the first marker is the contents entry, the
    /// last is the thing itself.
    var anchors: [String: Int]
    var width: CGFloat
}

enum HelpRender {

    /// The width of n characters in the monospaced face the manual is drawn
    /// in. Measured, not guessed: the ratio differs between faces.
    static func columnWidth(_ columns: Int, size: CGFloat) -> CGFloat {
        let font = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        let advance = ("0" as NSString).size(withAttributes: [.font: font]).width
        return ceil(advance * CGFloat(columns)) + 4
    }

    // MARK: the game's manual

    static func manual(_ topic: HelpTopic, theme: HelpTheme, size: CGFloat,
                       known: (String) -> Bool) -> HelpDocument {
        let out = NSMutableAttributedString()
        let font = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        var anchors: [String: Int] = [:]

        func append(_ s: String, _ attrs: [NSAttributedString.Key: Any]) {
            out.append(NSAttributedString(string: s, attributes: attrs))
        }
        func linked(_ s: String, _ url: URL?) {
            guard let url else {
                append("[\(s)]", [.font: font, .foregroundColor: theme.quiet])
                return
            }
            append("[\(s)]", [.font: font,
                              .foregroundColor: theme.link,
                              .underlineStyle: NSUnderlineStyle.single.rawValue,
                              .link: url])
        }

        // An anchor that appears once is a pure destination -- the manual
        // marks every command in the command listing so a key press can jump
        // there -- and drawing it would put "[A]" in the middle of a sentence
        // for no gain. An anchor that appears twice is a contents entry and
        // the entry it points at, and THAT is worth a link.
        var occurrences: [String: Int] = [:]
        for run in topic.runs {
            if let name = run.anchor { occurrences[name, default: 0] += 1 }
        }

        for run in topic.runs {
            if let name = run.anchor {
                anchors[name] = out.length
                if occurrences[name, default: 0] > 1 {
                    linked(run.s, HelpLink.anchor(name))
                }
                continue
            }
            if let to = run.to {
                // A link whose target was not exported -- "My Character",
                // which needs a live character, and two targets the base data
                // points at without ever defining -- is drawn as plain text.
                // A link that goes nowhere is worse than no link.
                linked(run.s, known(to) ? HelpLink.topic(to) : nil)
                continue
            }
            append(run.s, [.font: font, .foregroundColor: theme.color(run.c)])
        }

        return HelpDocument(text: out, anchors: anchors,
                            width: columnWidth(80, size: size))
    }

    // MARK: vendored wiki pages

    static func markdown(_ text: String, theme: HelpTheme,
                         size: CGFloat) -> HelpDocument {
        let out = NSMutableAttributedString()
        var inCode = false
        var codeBuffer: [String] = []

        let bodyStyle = NSMutableParagraphStyle()
        bodyStyle.paragraphSpacing = size * 0.7
        bodyStyle.lineSpacing = 2
        let headStyle = NSMutableParagraphStyle()
        headStyle.paragraphSpacingBefore = size * 1.2
        headStyle.paragraphSpacing = size * 0.3

        func block(_ s: NSAttributedString, style: NSParagraphStyle) {
            let m = NSMutableAttributedString(attributedString: s)
            m.addAttribute(.paragraphStyle, value: style,
                           range: NSRange(location: 0, length: m.length))
            if out.length > 0 { out.append(NSAttributedString(string: "\n")) }
            out.append(m)
        }

        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("```") {
                if inCode {
                    block(NSAttributedString(
                        string: codeBuffer.joined(separator: "\n"),
                        attributes: [
                            .font: NSFont.monospacedSystemFont(ofSize: size - 1,
                                                               weight: .regular),
                            .foregroundColor: theme.code,
                        ]), style: bodyStyle)
                    codeBuffer = []
                }
                inCode.toggle()
                continue
            }
            if inCode { codeBuffer.append(line); continue }

            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            if trimmed == "---" || trimmed == "***" {
                block(NSAttributedString(
                    string: String(repeating: "─", count: 28),
                    attributes: [
                        .font: NSFont.monospacedSystemFont(ofSize: size,
                                                           weight: .regular),
                        .foregroundColor: theme.quiet,
                    ]), style: bodyStyle)
                continue
            }

            // A pipe table row, kept monospaced so its columns line up. The
            // alignment row under a header means nothing outside Markdown
            // source and is dropped.
            if trimmed.hasPrefix("|") {
                let cells = trimmed.split(separator: "|",
                                          omittingEmptySubsequences: false)
                if cells.allSatisfy({
                    $0.trimmingCharacters(in: CharacterSet(charactersIn: " -:")).isEmpty
                }) { continue }
                let mono = NSFont.monospacedSystemFont(ofSize: size - 1, weight: .regular)
                let tight = NSMutableParagraphStyle()
                tight.lineSpacing = 1
                block(inline(trimmed, theme: theme, size: size - 1,
                             font: mono, color: theme.body), style: tight)
                continue
            }

            if let level = headingLevel(trimmed) {
                let body = String(trimmed.drop(while: { $0 == "#" }))
                    .trimmingCharacters(in: .whitespaces)
                let bump: CGFloat = level == 1 ? 8 : level == 2 ? 5 : 2
                block(inline(body, theme: theme, size: size + bump,
                             font: .systemFont(ofSize: size + bump, weight: .bold),
                             color: theme.heading), style: headStyle)
                continue
            }

            if trimmed.hasPrefix("> ") {
                let style = NSMutableParagraphStyle()
                style.firstLineHeadIndent = size * 1.5
                style.headIndent = size * 1.5
                style.paragraphSpacing = size * 0.5
                block(inline(String(trimmed.dropFirst(2)), theme: theme, size: size,
                             font: .systemFont(ofSize: size),
                             color: theme.quiet), style: style)
                continue
            }

            // A list item keeps its indent, which is what shows nesting.
            let indent = line.prefix(while: { $0 == " " }).count / 2
            if let marker = listMarker(trimmed) {
                let rest = String(trimmed.dropFirst(marker.count))
                    .trimmingCharacters(in: .whitespaces)
                let item = NSMutableAttributedString(
                    string: (marker.hasSuffix(".") ? marker + " " : "•  "),
                    attributes: [.font: NSFont.systemFont(ofSize: size),
                                 .foregroundColor: theme.quiet])
                item.append(inline(rest, theme: theme, size: size,
                                   font: .systemFont(ofSize: size), color: theme.body))
                let style = NSMutableParagraphStyle()
                style.paragraphSpacing = size * 0.25
                style.lineSpacing = 2
                style.firstLineHeadIndent = CGFloat(indent) * size * 1.6
                style.headIndent = CGFloat(indent) * size * 1.6 + size * 1.2
                block(item, style: style)
                continue
            }

            block(inline(trimmed, theme: theme, size: size,
                         font: .systemFont(ofSize: size), color: theme.body),
                  style: bodyStyle)
        }

        return HelpDocument(text: out, anchors: [:], width: 720)
    }

    private static func headingLevel(_ line: String) -> Int? {
        let hashes = line.prefix(while: { $0 == "#" }).count
        guard hashes > 0, hashes <= 6, line.dropFirst(hashes).hasPrefix(" ")
        else { return nil }
        return hashes
    }

    private static func listMarker(_ line: String) -> String? {
        if line.hasPrefix("- ") || line.hasPrefix("* ") { return String(line.prefix(1)) }
        let digits = line.prefix(while: { $0.isNumber })
        if !digits.isEmpty, line.dropFirst(digits.count).hasPrefix(". ") {
            return digits + "."
        }
        return nil
    }

    /// Inline Markdown: **bold**, *italic*, `code`, [text](url). Hand-rolled
    /// because the system parser throws away the block structure around it
    /// and cannot be told which font to use.
    private static func inline(_ text: String, theme: HelpTheme, size: CGFloat,
                               font: NSFont, color: NSColor) -> NSAttributedString {
        let out = NSMutableAttributedString()
        var plain = ""
        let chars = Array(text)
        var i = 0

        func flush() {
            guard !plain.isEmpty else { return }
            out.append(NSAttributedString(string: plain,
                                          attributes: [.font: font,
                                                       .foregroundColor: color]))
            plain = ""
        }

        while i < chars.count {
            let c = chars[i]
            if c == "\\", i + 1 < chars.count {
                plain.append(chars[i + 1]); i += 2; continue
            }
            if c == "*" || c == "`" {
                let isDouble = c == "*" && i + 1 < chars.count && chars[i + 1] == "*"
                let marker = isDouble ? "**" : String(c)
                if let close = find(chars, marker, from: i + marker.count),
                   close > i + marker.count {
                    flush()
                    let inner = String(chars[(i + marker.count)..<close])
                    if c == "`" {
                        out.append(NSAttributedString(string: inner, attributes: [
                            .font: NSFont.monospacedSystemFont(ofSize: size - 1,
                                                               weight: .regular),
                            .foregroundColor: theme.code,
                        ]))
                    } else {
                        let traits: NSFontDescriptor.SymbolicTraits =
                            isDouble ? .bold : .italic
                        let f = NSFont(descriptor:
                                        font.fontDescriptor.withSymbolicTraits(traits),
                                       size: font.pointSize) ?? font
                        out.append(NSAttributedString(string: inner,
                                                      attributes: [.font: f,
                                                                   .foregroundColor: color]))
                    }
                    i = close + marker.count
                    continue
                }
            }
            if c == "[", let close = find(chars, "]", from: i + 1),
               close + 1 < chars.count, chars[close + 1] == "(",
               let paren = find(chars, ")", from: close + 2) {
                flush()
                let label = String(chars[(i + 1)..<close])
                let href = String(chars[(close + 2)..<paren])
                var attrs: [NSAttributedString.Key: Any] = [
                    .font: font, .foregroundColor: theme.link,
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                ]
                if let url = URL(string: href) { attrs[.link] = url }
                out.append(NSAttributedString(string: label, attributes: attrs))
                i = paren + 1
                continue
            }
            plain.append(c)
            i += 1
        }
        flush()
        return out
    }

    private static func find(_ chars: [Character], _ needle: String, from: Int) -> Int? {
        let n = Array(needle)
        guard from >= 0, !n.isEmpty else { return nil }
        var i = from
        while i + n.count <= chars.count {
            if Array(chars[i..<(i + n.count)]) == n { return i }
            i += 1
        }
        return nil
    }
}
