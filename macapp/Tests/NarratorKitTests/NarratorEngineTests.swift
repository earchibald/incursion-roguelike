import XCTest
@testable import NarratorKit

@MainActor
final class NarratorEngineTests: XCTestCase {
    func makeEngine(paneOpen: Bool = true,
                    clientCalls: XCTestExpectation? = nil) -> NarratorEngine {
        let defaults = UserDefaults(suiteName: "narrator-engine-tests")!
        defaults.removePersistentDomain(forName: "narrator-engine-tests")
        let settings = NarratorSettings(defaults: defaults)
        settings.model = "test-model"
        let engine = NarratorEngine(settings: settings, grounding: nil,
                                    makeClient: { cfg in
            clientCalls?.fulfill()
            return OpenAIClient(config: cfg)
        }, tokenProvider: { "sk-test" })
        engine.paneOpen = paneOpen
        return engine
    }

    func stateJSON(depth: Int, turn: Int, hp: Int = 10) -> Data {
        Data(#"{"name":"K","level":1,"depth":\#(depth),"hp":\#(hp),"maxhp":10,"turn":\#(turn)}"#.utf8)
    }

    func testClosedPaneMakesNoClient() {
        let exp = expectation(description: "no client")
        exp.isInverted = true
        let e = makeEngine(paneOpen: false, clientCalls: exp)
        e.ingestState(stateJSON(depth: 1, turn: 1))
        e.ingestState(stateJSON(depth: 2, turn: 2))
        wait(for: [exp], timeout: 0.2)
    }

    func testClosedPaneAskMakesNoClient() {
        let exp = expectation(description: "no client")
        exp.isInverted = true
        let e = makeEngine(paneOpen: false, clientCalls: exp)
        e.ask("What is a kobold?")
        wait(for: [exp], timeout: 0.2)
    }

    func testMutedMakesNoClient() {
        let exp = expectation(description: "no client")
        exp.isInverted = true
        let e = makeEngine(clientCalls: exp)
        e.muted = true
        e.ingestState(stateJSON(depth: 1, turn: 1))
        e.ingestState(stateJSON(depth: 2, turn: 2))
        wait(for: [exp], timeout: 0.2)
    }

    func testMilestonePromptCarriesStateAndRecentMessages() {
        let e = makeEngine()
        e.ingestMessage("The kobold hits you.")
        e.ingestMessage("You feel a strange resonance.")
        let s = PlayerState(name: "K", level: 3, depth: 4, hp: 5, maxhp: 20, turn: 900)
        let prompt = e.milestonePrompt(for: .nearDeath, state: s)
        XCTAssertTrue(prompt.contains("kobold"))
        XCTAssertTrue(prompt.contains("depth 4"))
        XCTAssertTrue(prompt.contains("near death"))
    }

    func testArtifactPattern() {
        let e = makeEngine()
        XCTAssertTrue(e.artifactMentioned("You now hold the ARTIFACT blade!"))
        XCTAssertFalse(e.artifactMentioned("You pick up a longsword."))
    }

    func testRingBufferCaps() {
        let e = makeEngine()
        for i in 0..<300 { e.ingestMessage("line \(i)") }
        let s = PlayerState(name: "K", level: 1, depth: 1, hp: 10, maxhp: 10, turn: 1)
        let prompt = e.milestonePrompt(for: .enteredLevel, state: s)
        XCTAssertFalse(prompt.contains("line 0"))
        XCTAssertTrue(prompt.contains("line 299"))
    }
}
