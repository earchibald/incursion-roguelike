// See the Incursion LICENSE file for copyright information.
//
// The request layout is a byte-stable prefix plus an append-only journal,
// so OpenAI-compatible servers hit their prefix caches on every call.
// WireJSON serializes with fixed key order because JSONEncoder's output
// ordering is not guaranteed.
import Foundation

public struct ChatMessage: Equatable {
    public let role: String
    public let content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

public struct PromptBuilder {
    private let system: String
    private var journal: [ChatMessage] = []

    public init(system: String) {
        self.system = system
    }

    /// Rough size gauge for deciding when to compact (4 chars ≈ 1 token).
    public var journalTokenEstimate: Int {
        journal.reduce(0) { $0 + $1.content.count } / 4
    }

    public func request(userTurn: String) -> [ChatMessage] {
        [ChatMessage(role: "system", content: system)]
            + journal
            + [ChatMessage(role: "user", content: userTurn)]
    }

    public mutating func record(user: String, assistant: String) {
        journal.append(ChatMessage(role: "user", content: user))
        journal.append(ChatMessage(role: "assistant", content: assistant))
    }

    /// One deliberate cache break: the journal becomes a single summary
    /// turn. Call only at a depth boundary.
    public mutating func compact(summary: String) {
        journal = [
            ChatMessage(role: "user", content: "The story so far: " + summary),
        ]
    }
}

public enum WireJSON {
    static func escape(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count + 8)
        for u in s.unicodeScalars {
            switch u {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if u.value < 0x20 {
                    out += String(format: "\\u%04x", u.value)
                } else {
                    out.unicodeScalars.append(u)
                }
            }
        }
        return out
    }

    /// Deterministic chat-completions body: fixed key order, no dictionary
    /// traversal, so equal inputs give byte-equal output.
    public static func chatBody(model: String, messages: [ChatMessage],
                                temperature: Double, maxTokens: Int,
                                stream: Bool) -> Data {
        var s = "{\"model\":\"\(escape(model))\""
        s += ",\"temperature\":\(temperature)"
        s += ",\"max_tokens\":\(maxTokens)"
        s += ",\"stream\":\(stream)"
        s += ",\"messages\":["
        s += messages.map {
            "{\"role\":\"\(escape($0.role))\",\"content\":\"\(escape($0.content))\"}"
        }.joined(separator: ",")
        s += "]}"
        return Data(s.utf8)
    }
}
