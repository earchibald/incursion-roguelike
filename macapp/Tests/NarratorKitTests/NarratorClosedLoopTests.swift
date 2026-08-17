// See the Incursion LICENSE file for copyright information.
//
// End-to-end tests that drive the real pipeline: NarratorEngine, feeding
// through the actual PromptBuilder and OpenAIClient, over a mocked
// URLSession. Duplicates the small MockURLProtocol from
// OpenAIClientTests.swift (under its own name) so this file has no
// cross-file test coupling.
import XCTest
@testable import NarratorKit

final class ClosedLoopMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else { return }
        do {
            let (resp, data) = try handler(request)
            client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

/// `session.bytes(for:)` uploads the body as a stream rather than leaving
/// it on `httpBody`, so the mock has to read `httpBodyStream` instead.
func closedLoopBodyString(_ req: URLRequest) -> String {
    if let d = req.httpBody { return String(data: d, encoding: .utf8) ?? "" }
    guard let stream = req.httpBodyStream else { return "" }
    stream.open()
    defer { stream.close() }
    var data = Data()
    let bufferSize = 4096
    var buffer = [UInt8](repeating: 0, count: bufferSize)
    while stream.hasBytesAvailable {
        let read = stream.read(&buffer, maxLength: bufferSize)
        if read <= 0 { break }
        data.append(buffer, count: read)
    }
    return String(data: data, encoding: .utf8) ?? ""
}

/// A tiny synchronized box. Its methods are plain (non-async) functions, so
/// calling them from an `async` test body doesn't trip the "lock/unlock
/// unavailable from async contexts" diagnostic that a bare NSLock would.
final class LockedBox<T> {
    private var value: T
    private let lock = NSLock()
    init(_ v: T) { value = v }
    func mutate(_ f: (inout T) -> Void) { lock.lock(); defer { lock.unlock() }; f(&value) }
    func get() -> T { lock.lock(); defer { lock.unlock() }; return value }
}

@MainActor
final class NarratorClosedLoopTests: XCTestCase {
    func state(name: String = "K", level: Int = 1, depth: Int, turn: Int, hp: Int = 10) -> Data {
        Data(#"{"name":"\#(name)","level":\#(level),"depth":\#(depth),"hp":\#(hp),"maxhp":10,"turn":\#(turn)}"#.utf8)
    }

    func ok(_ body: String, url: URL) -> (HTTPURLResponse, Data) {
        (HTTPURLResponse(url: url, statusCode: 200,
                         httpVersion: nil, headerFields: nil)!, Data(body.utf8))
    }

    func makeEngine(suite: String, settings out: ((NarratorSettings) -> Void)? = nil) -> NarratorEngine {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = NarratorSettings(defaults: defaults)
        settings.model = "test-model"
        settings.cooldownTurns = 0
        out?(settings)
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [ClosedLoopMockURLProtocol.self]
        let mockSession = URLSession(configuration: cfg)
        let engine = NarratorEngine(settings: settings, grounding: nil,
                                    makeClient: { OpenAIClient(config: $0, session: mockSession) },
                                    tokenProvider: { "sk-test" })
        engine.paneOpen = true
        return engine
    }

    func waitForEntryText(_ engine: NarratorEngine, contains fragment: String,
                          timeout: TimeInterval = 2) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if engine.entries.last?.text.contains(fragment) == true { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return false
    }

    /// The full loop: a milestone reaches the real client, the mock asserts
    /// what went over the wire, and the streamed prose lands in `entries`.
    func testEnteredLevelStreamsOverRealPipeline() async {
        let engine = makeEngine(suite: "closed-loop-entered-level")
        let bodyExp = expectation(description: "request received")
        ClosedLoopMockURLProtocol.handler = { req in
            XCTAssertEqual(req.url?.path, "/v1/chat/completions")
            bodyExp.fulfill()
            let sse = """
            data: {"choices":[{"delta":{"content":"The gate "}}]}

            data: {"choices":[{"delta":{"content":"gives way."}}]}

            data: [DONE]

            """
            return self.ok(sse, url: req.url!)
        }
        engine.ingestState(state(depth: 1, turn: 1))     // baseline, no milestone
        engine.ingestState(state(depth: 2, turn: 2))     // enteredLevel
        await fulfillment(of: [bodyExp], timeout: 2)
        let streamed = await waitForEntryText(engine, contains: "The gate gives way.")
        XCTAssertTrue(streamed)
    }

    /// The request body actually carries the model id and the milestone text.
    func testRequestBodyCarriesModelAndMilestoneText() async {
        let engine = makeEngine(suite: "closed-loop-body-assert")
        let bodyExp = expectation(description: "request received")
        ClosedLoopMockURLProtocol.handler = { req in
            let body = closedLoopBodyString(req)
            XCTAssertTrue(body.contains(#""model":"test-model""#))
            XCTAssertTrue(body.contains("entered depth 2"))
            bodyExp.fulfill()
            let sse = """
            data: {"choices":[{"delta":{"content":"Prose."}}]}

            data: [DONE]

            """
            return self.ok(sse, url: req.url!)
        }
        engine.ingestState(state(depth: 1, turn: 1))
        engine.ingestState(state(depth: 2, turn: 2))
        await fulfillment(of: [bodyExp], timeout: 2)
        _ = await waitForEntryText(engine, contains: "Prose.")
    }

    /// A depth *decrease* is a new depth just as much as an increase is --
    /// this closes a gap the milestone-priority tests never exercised.
    func testDepthDecreaseTriggersEnteredLevel() async {
        let engine = makeEngine(suite: "closed-loop-depth-decrease")
        let seen = LockedBox<[String]>([])
        let count = LockedBox<Int>(0)
        let firstExp = expectation(description: "first narration")
        let secondExp = expectation(description: "second narration")
        ClosedLoopMockURLProtocol.handler = { req in
            var n = 0
            count.mutate { $0 += 1; n = $0 }
            let body = closedLoopBodyString(req)
            seen.mutate { $0.append(body) }
            let sse = "data: {\"choices\":[{\"delta\":{\"content\":\"Beat \(n).\"}}]}\n\ndata: [DONE]\n\n"
            if n == 1 { firstExp.fulfill() } else { secondExp.fulfill() }
            return self.ok(sse, url: req.url!)
        }
        engine.ingestState(state(depth: 3, turn: 1))     // baseline
        engine.ingestState(state(depth: 5, turn: 2))     // enteredLevel: 3 -> 5
        await fulfillment(of: [firstExp], timeout: 2)
        _ = await waitForEntryText(engine, contains: "Beat 1.")
        engine.ingestState(state(depth: 2, turn: 3))     // enteredLevel: 5 -> 2 (a decrease)
        await fulfillment(of: [secondExp], timeout: 2)
        _ = await waitForEntryText(engine, contains: "Beat 2.")
        let bodies = seen.get()
        XCTAssertEqual(bodies.count, 2)
        XCTAssertTrue(bodies[0].contains("entered depth 5"))
        XCTAssertTrue(bodies[1].contains("entered depth 2"))
    }

    /// A prompt/voice/style edit lands between two narrations of the same
    /// run: the second request's system message must reflect it, while the
    /// journal from the first exchange survives -- one deliberate cache
    /// break, not a fresh conversation.
    func testPromptEditAppliesAtNextNarrationOnly() async {
        var settingsRef: NarratorSettings!
        let engine = makeEngine(suite: "closed-loop-cache-break") { settingsRef = $0 }
        let settings = settingsRef!

        let seen = LockedBox<[String]>([])
        let count = LockedBox<Int>(0)
        let firstExp = expectation(description: "first narration")
        let secondExp = expectation(description: "second narration")
        ClosedLoopMockURLProtocol.handler = { req in
            var n = 0
            count.mutate { $0 += 1; n = $0 }
            seen.mutate { $0.append(closedLoopBodyString(req)) }
            let sse = "data: {\"choices\":[{\"delta\":{\"content\":\"Beat \(n).\"}}]}\n\ndata: [DONE]\n\n"
            if n == 1 { firstExp.fulfill() } else { secondExp.fulfill() }
            return self.ok(sse, url: req.url!)
        }

        engine.ingestState(state(depth: 1, turn: 1))          // baseline
        engine.ingestState(state(depth: 2, turn: 2))           // enteredLevel #1
        await fulfillment(of: [firstExp], timeout: 2)
        _ = await waitForEntryText(engine, contains: "Beat 1.")

        // Edit the style mid-run: this must apply at the *next* narration.
        settings.customStyle = "UNIQUE_STYLE_MARKER_42"

        engine.ingestState(state(level: 2, depth: 2, turn: 3)) // levelUp -> second narration
        await fulfillment(of: [secondExp], timeout: 2)
        _ = await waitForEntryText(engine, contains: "Beat 2.")

        let bodies = seen.get()
        XCTAssertEqual(bodies.count, 2)
        XCTAssertFalse(bodies[0].contains("UNIQUE_STYLE_MARKER_42"),
                       "the edit must not retroactively touch the first request")
        XCTAssertTrue(bodies[1].contains("UNIQUE_STYLE_MARKER_42"),
                      "the edit must apply at the next narration")
        // The journal from the first exchange survives the system swap.
        XCTAssertTrue(bodies[1].contains("entered depth 2"))
    }
}
