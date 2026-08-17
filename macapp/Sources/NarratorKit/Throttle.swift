// See the Incursion LICENSE file for copyright information.
//
// "Not overbearing" is enforced here: per-type enables, a global cooldown
// in game turns, once-per-depth dedupe. Death always speaks.
import Foundation

public struct ThrottleConfig {
    public var enabled: Set<Milestone>
    public var cooldownTurns: Int

    public init(enabled: Set<Milestone>, cooldownTurns: Int) {
        self.enabled = enabled
        self.cooldownTurns = cooldownTurns
    }
}

public struct Throttle {
    private var lastNarrationTurn: Int?
    private var seen: Set<String> = []

    public init() {}

    public mutating func permit(_ m: Milestone, state: PlayerState,
                                config: ThrottleConfig) -> Bool {
        guard config.enabled.contains(m) else { return false }
        let key = "\(m.rawValue):\(state.depth)"
        guard !seen.contains(key) else { return false }
        if m != .death, let lastTurn = lastNarrationTurn,
           state.turn - lastTurn <= config.cooldownTurns {
            return false
        }
        seen.insert(key)
        lastNarrationTurn = state.turn
        return true
    }

    /// A new run starts clean.
    public mutating func reset() {
        lastNarrationTurn = nil
        seen.removeAll()
    }
}
