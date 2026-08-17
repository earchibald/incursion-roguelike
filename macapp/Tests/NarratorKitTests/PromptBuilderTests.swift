import XCTest
@testable import NarratorKit

final class PromptBuilderTests: XCTestCase {
    func testPrefixIsByteStableAcrossCalls() {
        var b = PromptBuilder(system: "You are the narrator.")
        let r1 = WireJSON.chatBody(model: "m", messages: b.request(userTurn: "turn one"),
                                   temperature: 0.8, maxTokens: 200, stream: true)
        b.record(user: "turn one", assistant: "prose one")
        let r2 = WireJSON.chatBody(model: "m", messages: b.request(userTurn: "turn two"),
                                   temperature: 0.8, maxTokens: 200, stream: true)
        // r1 minus its final user turn must be a byte prefix of r2.
        let s1 = String(data: r1, encoding: .utf8)!
        let s2 = String(data: r2, encoding: .utf8)!
        let cut = s1.range(of: #"{"role":"user","content":"turn one"}"#)!.lowerBound
        XCTAssertTrue(s2.hasPrefix(String(s1[s1.startIndex..<cut])),
                      "the serialized prefix must never change between calls")
    }

    func testRecordAppendsToJournal() {
        var b = PromptBuilder(system: "sys")
        b.record(user: "u1", assistant: "a1")
        let msgs = b.request(userTurn: "u2")
        XCTAssertEqual(msgs.map(\.role), ["system", "user", "assistant", "user"])
        XCTAssertEqual(msgs[1].content, "u1")
    }

    func testCompactReplacesJournalWithSummary() {
        var b = PromptBuilder(system: "sys")
        b.record(user: "u1", assistant: "a1")
        b.record(user: "u2", assistant: "a2")
        b.compact(summary: "the story so far")
        let msgs = b.request(userTurn: "u3")
        XCTAssertEqual(msgs.count, 3)
        XCTAssertEqual(msgs[1].role, "assistant")
        XCTAssertTrue(msgs[1].content.contains("the story so far"))
    }

    func testRecordAfterCompactKeepsAppending() {
        var b = PromptBuilder(system: "sys")
        b.record(user: "u1", assistant: "a1")
        b.compact(summary: "recap")
        b.record(user: "u2", assistant: "a2")
        let msgs = b.request(userTurn: "u3")
        XCTAssertEqual(msgs.map(\.role), ["system", "assistant", "user", "assistant", "user"])
    }

    func testDeterministicSerializerEscapes() {
        let body = WireJSON.chatBody(model: "m",
            messages: [ChatMessage(role: "user", content: "say \"hi\"\nplease")],
            temperature: 0.5, maxTokens: 10, stream: false)
        let s = String(data: body, encoding: .utf8)!
        XCTAssertTrue(s.contains(#"say \"hi\"\nplease"#))
        XCTAssertTrue(s.hasPrefix(#"{"model":"m","temperature":0.5,"#))
    }

    func testEveryPromptHasNonEmptyDefault() {
        for key in PromptKey.allCases {
            XCTAssertFalse(key.defaultText.isEmpty, key.rawValue)
            XCTAssertFalse(key.title.isEmpty, key.rawValue)
        }
    }
}
