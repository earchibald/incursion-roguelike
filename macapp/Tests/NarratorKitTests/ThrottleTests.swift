import XCTest
@testable import NarratorKit

final class ThrottleTests: XCTestCase {
    func state(depth: Int = 1, turn: Int) -> PlayerState {
        PlayerState(name: "K", level: 1, depth: depth, hp: 10, maxhp: 10, turn: turn)
    }
    let all = ThrottleConfig(enabled: Set(Milestone.allCases), cooldownTurns: 50)

    func testDisabledTypeNeverPermits() {
        var t = Throttle()
        let cfg = ThrottleConfig(enabled: [.death], cooldownTurns: 0)
        XCTAssertFalse(t.permit(.levelUp, state: state(turn: 1), config: cfg))
        XCTAssertTrue(t.permit(.death, state: state(turn: 2), config: cfg))
    }

    func testCooldownBlocksThenExpires() {
        var t = Throttle()
        XCTAssertTrue(t.permit(.enteredLevel, state: state(depth: 2, turn: 100), config: all))
        XCTAssertFalse(t.permit(.levelUp, state: state(depth: 2, turn: 120), config: all))
        XCTAssertTrue(t.permit(.levelUp, state: state(depth: 2, turn: 151), config: all))
    }

    func testDeathIgnoresCooldown() {
        var t = Throttle()
        XCTAssertTrue(t.permit(.enteredLevel, state: state(depth: 2, turn: 100), config: all))
        XCTAssertTrue(t.permit(.death, state: state(depth: 2, turn: 101), config: all))
    }

    func testSameMilestoneSameDepthNarratesOnce() {
        var t = Throttle()
        let cfg = ThrottleConfig(enabled: Set(Milestone.allCases), cooldownTurns: 0)
        XCTAssertTrue(t.permit(.enteredLevel, state: state(depth: 3, turn: 1), config: cfg))
        XCTAssertFalse(t.permit(.enteredLevel, state: state(depth: 3, turn: 900), config: cfg))
        XCTAssertTrue(t.permit(.enteredLevel, state: state(depth: 4, turn: 901), config: cfg))
    }

    func testResetClearsHistory() {
        var t = Throttle()
        let cfg = ThrottleConfig(enabled: Set(Milestone.allCases), cooldownTurns: 0)
        _ = t.permit(.enteredLevel, state: state(depth: 3, turn: 1), config: cfg)
        t.reset()
        XCTAssertTrue(t.permit(.enteredLevel, state: state(depth: 3, turn: 2), config: cfg))
    }
}
