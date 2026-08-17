// See the Incursion LICENSE file for copyright information.
//
// Milestone derivation for the narrator: the bridge sends flat player-state
// samples; diffing consecutive samples yields the moments worth narrating.
import Foundation

public struct PlayerState: Codable, Equatable {
    public let name: String
    public let level: Int
    public let depth: Int
    public let hp: Int
    public let maxhp: Int
    public let turn: Int

    public init(name: String, level: Int, depth: Int,
                hp: Int, maxhp: Int, turn: Int) {
        self.name = name; self.level = level; self.depth = depth
        self.hp = hp; self.maxhp = maxhp; self.turn = turn
    }

    public init(json: Data) throws {
        self = try JSONDecoder().decode(PlayerState.self, from: json)
    }
}

public enum Milestone: String, CaseIterable, Codable {
    case enteredLevel, levelUp, nearDeath, death, artifact

    /// Higher wins when one update yields several milestones.
    public var priority: Int {
        switch self {
        case .death:        return 5
        case .nearDeath:    return 4
        case .artifact:     return 3
        case .levelUp:      return 2
        case .enteredLevel: return 1
        }
    }
}

public struct MilestoneDetector {
    private var last: PlayerState?

    public init() {}

    public mutating func ingest(_ s: PlayerState) -> [Milestone] {
        defer { last = s }
        guard let p = last, p.name == s.name else { return [] }
        var out: [Milestone] = []
        if s.depth != p.depth { out.append(.enteredLevel) }
        if s.level > p.level  { out.append(.levelUp) }
        let wasFrac = Double(p.hp) / Double(max(1, p.maxhp))
        let nowFrac = Double(s.hp) / Double(max(1, s.maxhp))
        if s.hp > 0 && nowFrac <= 0.25 && wasFrac > 0.25 { out.append(.nearDeath) }
        if s.hp <= 0 && p.hp > 0 { out.append(.death) }
        return out
    }
}
