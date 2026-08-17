import XCTest
@testable import NarratorKit

final class MilestoneTests: XCTestCase {
    func state(name: String = "Kellin", level: Int = 1, depth: Int = 1,
               hp: Int = 10, maxhp: Int = 10, turn: Int = 0) -> PlayerState {
        PlayerState(name: name, level: level, depth: depth,
                    hp: hp, maxhp: maxhp, turn: turn)
    }

    func testDecodesBridgeJSON() throws {
        let json = #"{"name":"Kellin","level":3,"depth":2,"hp":14,"maxhp":22,"turn":8121}"#
        let s = try PlayerState(json: Data(json.utf8))
        XCTAssertEqual(s.depth, 2)
        XCTAssertEqual(s.maxhp, 22)
    }

    func testFirstSampleIsBaselineOnly() {
        var d = MilestoneDetector()
        XCTAssertEqual(d.ingest(state()), [])
    }

    func testDepthChangeIsEnteredLevel() {
        var d = MilestoneDetector()
        _ = d.ingest(state())
        XCTAssertEqual(d.ingest(state(depth: 2)), [.enteredLevel])
    }

    func testLevelUp() {
        var d = MilestoneDetector()
        _ = d.ingest(state())
        XCTAssertEqual(d.ingest(state(level: 2)), [.levelUp])
    }

    func testNearDeathFiresOnceAtQuarterHP() {
        var d = MilestoneDetector()
        _ = d.ingest(state(hp: 10, maxhp: 40))   // baseline already at 25%
        XCTAssertEqual(d.ingest(state(hp: 8, maxhp: 40)), [],
                       "no re-fire while already under the line")
        _ = d.ingest(state(hp: 30, maxhp: 40))   // healed
        XCTAssertEqual(d.ingest(state(hp: 9, maxhp: 40)), [.nearDeath])
    }

    func testDeath() {
        var d = MilestoneDetector()
        _ = d.ingest(state())
        XCTAssertEqual(d.ingest(state(hp: 0)), [.death])
    }

    func testNewCharacterNameResetsBaseline() {
        var d = MilestoneDetector()
        _ = d.ingest(state(name: "Kellin", depth: 5))
        XCTAssertEqual(d.ingest(state(name: "Borund", depth: 1)), [],
                       "a new run must not narrate a phantom level change")
    }
}
