# LLM Narrator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An optional LLM gamemaster in the Mac app: milestone narration in a narrator window, ask-the-GM answers grounded in the exported manual, any OpenAI-compatible endpoint, all configured in a settings GUI.

**Architecture:** One additive tap in the Wmac bridge ships every message-pane line and a player-state JSON sample per engine update. A new `NarratorKit` Swift library derives milestones by diffing states, throttles them, builds cache-stable prompts, and streams from the endpoint. The app target adds two windows (narrator pane, settings) and wires the callbacks.

**Tech Stack:** C (bridge), C++ (Wmac.cpp), Swift 5.9 / SwiftPM, SwiftUI in AppKit windows (macOS 14 floor), XCTest, URLSession SSE streaming, Keychain Services.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-08-17-llm-narrator-design.md` (as amended: milestones derived app-side from state diffs, not engine-site hooks).
- Engine changes limited to `src/WmacBridge.h` and `src/Wmac.cpp`. Nothing in shared engine code.
- Engine rebuild: `BACKEND=mac ./build_macos.sh` from repo root. Parity gate: `FULL=yes tools/check_macterm.sh` must pass.
- Swift build: from `macapp/`, `swift build` (needs `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` — see memory note). Tests: `swift test`.
- `NarratorKit` must not import AppKit — Foundation + Security only, so it stays testable.
- The API token lives ONLY in the Keychain. Never in UserDefaults, never logged.
- Request prefix must be byte-stable across calls in a run (asserted by test). JSON bodies are serialized by our own deterministic serializer, not JSONEncoder.
- Every commit message ends with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.
- Milestones: enteredLevel, levelUp, nearDeath (HP ≤ 25% of max, once per crossing), death, artifact (message-pattern-based).
- All new user-facing copy in plain, calm English; errors one line, never modal.

---

### Task 1: Bridge tap — message lines and player-state samples

**Files:**
- Modify: `src/WmacBridge.h` (IncCallbacks struct, ~line 56)
- Modify: `src/Wmac.cpp` (macTerm class ~line 81-151, `Update()` ~line 294)

**Interfaces:**
- Produces (C, consumed by Task 7):
  - `void (*game_message)(void *ctx, const char *line);` — fires on the engine thread for every committed message-pane line, UTF-8/CP437 text, valid only during the call.
  - `void (*player_state)(void *ctx, const char *json);` — fires on the engine thread after an update when the sample changed. JSON shape, single line: `{"name":"Kellin","level":3,"depth":2,"hp":14,"maxhp":22,"turn":8121}`.

- [ ] **Step 1: Add the two callbacks to `IncCallbacks` in `src/WmacBridge.h`**

Append inside the struct, after `fatal_error`:

```c
    /* Narrator tap (optional; null = off). Both fire on the engine thread;
       string arguments are valid only for the duration of the call. */
    void (*game_message)(void *ctx, const char *line); /* message-pane line */
    void (*player_state)(void *ctx, const char *json); /* {"name":...,"level":n,
                              "depth":n,"hp":n,"maxhp":n,"turn":n}, on change */
```

- [ ] **Step 2: Implement the tap in `src/Wmac.cpp`**

In the `macTerm` class body add a member near the other state (`IncCallbacks cb;` block):

```cpp
    char lastStateJson[256];        /* narrator tap: last published sample */
```

Initialize in the constructor: `lastStateJson[0] = 0;`

Add two methods to `macTerm` (declare next to `virtual void Update();`, define near `macTerm::Update`):

```cpp
    virtual void Message(const char *msg);
    void PublishPlayerState();
```

```cpp
/* Narrator tap: every message-pane line, verbatim, before display. */
void macTerm::Message(const char *msg) {
    if (cb.game_message && msg && *msg)
        cb.game_message(cb.ctx, msg);
    TextTerm::Message(msg);
}

static void narratorEscJson(const char *in, char *out, size_t cap) {
    size_t o = 0;
    for (; *in && o + 2 < cap; in++) {
        unsigned char c = (unsigned char)*in;
        if (c == '"' || c == '\\') { out[o++] = '\\'; out[o++] = c; }
        else if (c < 32)           { out[o++] = ' '; }
        else                       { out[o++] = (char)c; }
    }
    out[o] = 0;
}

/* Narrator tap: sample the player after an update; publish on change. */
void macTerm::PublishPlayerState() {
    if (!cb.player_state || !p || !theGame)
        return;
    char nm[64];
    narratorEscJson(p->Name, nm, sizeof(nm));
    char buf[256];
    snprintf(buf, sizeof(buf),
        "{\"name\":\"%s\",\"level\":%d,\"depth\":%d,"
        "\"hp\":%d,\"maxhp\":%d,\"turn\":%u}",
        nm, (int)p->TotalLevel(), (int)(p->m ? p->m->Depth : 0),
        (int)p->cHP, (int)p->mHP, (unsigned)theGame->GetTurn());
    if (strcmp(buf, lastStateJson) == 0)
        return;
    strcpy(lastStateJson, buf);
    cb.player_state(cb.ctx, buf);
}
```

In `macTerm::Update()` (line ~294), immediately BEFORE the existing `frame_ready` firing (`if (cb.frame_ready) ...`, ~line 309), insert:

```cpp
    PublishPlayerState();
```

If the compiler cannot see `p`, `theGame`, `Player`, or `Map`, add the missing engine include at the top of Wmac.cpp next to its existing engine includes (`#include "Incursion.h"` is the umbrella).

- [ ] **Step 3: Rebuild the engine and both variants**

Run from repo root: `BACKEND=mac ./build_macos.sh`
Expected: builds `build/libincursion-mac.a` with no new warnings in Wmac.cpp.

- [ ] **Step 4: Run the parity gate**

Run: `FULL=yes tools/check_macterm.sh`
Expected: all scenarios PASS (the tap is display-neutral; keyscript driver leaves the new callbacks null).

- [ ] **Step 5: Commit**

```bash
git add src/WmacBridge.h src/Wmac.cpp
git commit -m "Give the bridge a narrator tap: messages and player state

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: NarratorKit target, PlayerState, MilestoneDetector

**Files:**
- Modify: `macapp/Package.swift`
- Create: `macapp/Sources/NarratorKit/Milestones.swift`
- Test: `macapp/Tests/NarratorKitTests/MilestoneTests.swift`

**Interfaces:**
- Produces:
  - `public struct PlayerState: Codable, Equatable { public let name: String; public let level: Int; public let depth: Int; public let hp: Int; public let maxhp: Int; public let turn: Int }` (+ `public init(json: Data) throws`)
  - `public enum Milestone: String, CaseIterable, Codable { case enteredLevel, levelUp, nearDeath, death, artifact }` with `public var priority: Int` (death 5 … enteredLevel 1)
  - `public struct MilestoneDetector { public init(); public mutating func ingest(_ s: PlayerState) -> [Milestone] }`

- [ ] **Step 1: Add the library and test targets to `macapp/Package.swift`**

Replace the `targets:` array with:

```swift
    targets: [
        .target(name: "CIncursion"),
        .target(name: "NarratorKit"),
        .executableTarget(
            name: "IncursionApp",
            dependencies: ["CIncursion", "NarratorKit"],
            linkerSettings: [
                .unsafeFlags(["-L../build"]),
                .linkedLibrary(engineLib),
                .linkedLibrary("c++"),
                .linkedLibrary("z"),
            ]
        ),
        .testTarget(name: "NarratorKitTests", dependencies: ["NarratorKit"]),
    ]
```

- [ ] **Step 2: Write the failing tests**

`macapp/Tests/NarratorKitTests/MilestoneTests.swift`:

```swift
import XCTest
@testable import NarratorKit

final class MilestoneTests: XCTestCase {
    func state(_ name: String = "Kellin", level: Int = 1, depth: Int = 1,
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
```

- [ ] **Step 3: Run tests to verify they fail**

Run from `macapp/`: `swift test --filter MilestoneTests`
Expected: FAIL — `no such module 'NarratorKit'` / types not defined.

- [ ] **Step 4: Implement `macapp/Sources/NarratorKit/Milestones.swift`**

```swift
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
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter MilestoneTests`
Expected: PASS (7 tests).

- [ ] **Step 6: Commit**

```bash
git add macapp/Package.swift macapp/Sources/NarratorKit/Milestones.swift macapp/Tests/NarratorKitTests/MilestoneTests.swift
git commit -m "Derive narrator milestones by diffing player state

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: Throttle — the restraint rules

**Files:**
- Create: `macapp/Sources/NarratorKit/Throttle.swift`
- Test: `macapp/Tests/NarratorKitTests/ThrottleTests.swift`

**Interfaces:**
- Consumes: `Milestone`, `PlayerState` (Task 2).
- Produces:
  - `public struct ThrottleConfig { public var enabled: Set<Milestone>; public var cooldownTurns: Int; public init(enabled: Set<Milestone>, cooldownTurns: Int) }`
  - `public struct Throttle { public init(); public mutating func permit(_ m: Milestone, state: PlayerState, config: ThrottleConfig) -> Bool; public mutating func reset() }`

- [ ] **Step 1: Write the failing tests**

`macapp/Tests/NarratorKitTests/ThrottleTests.swift`:

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ThrottleTests`
Expected: FAIL — `Throttle` not defined.

- [ ] **Step 3: Implement `macapp/Sources/NarratorKit/Throttle.swift`**

```swift
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ThrottleTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add macapp/Sources/NarratorKit/Throttle.swift macapp/Tests/NarratorKitTests/ThrottleTests.swift
git commit -m "Teach the narrator restraint

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: Prompts and the cache-stable PromptBuilder

**Files:**
- Create: `macapp/Sources/NarratorKit/Prompts.swift`
- Create: `macapp/Sources/NarratorKit/PromptBuilder.swift`
- Test: `macapp/Tests/NarratorKitTests/PromptBuilderTests.swift`

**Interfaces:**
- Produces:
  - `public struct ChatMessage: Equatable { public let role: String; public let content: String; public init(role: String, content: String) }`
  - `public enum PromptKey: String, CaseIterable { case narratorSystem, voiceChronicler, voiceBard, voiceCompanion, askIndex, askAnswer, summarize }` with `public var defaultText: String` and `public var title: String`
  - `public enum NarrationLength: String, CaseIterable { case line, beat, paragraph }` with `public var instruction: String`
  - `public struct PromptBuilder { public init(system: String); public var journalTokenEstimate: Int { get }; public func request(userTurn: String) -> [ChatMessage]; public mutating func record(user: String, assistant: String); public mutating func compact(summary: String) }`
  - `public enum WireJSON { public static func chatBody(model: String, messages: [ChatMessage], temperature: Double, maxTokens: Int, stream: Bool) -> Data }` — deterministic serializer, key order fixed.

- [ ] **Step 1: Write the failing tests**

`macapp/Tests/NarratorKitTests/PromptBuilderTests.swift`:

```swift
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
        XCTAssertTrue(msgs[1].content.contains("the story so far"))
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter PromptBuilderTests`
Expected: FAIL — types not defined.

- [ ] **Step 3: Implement `macapp/Sources/NarratorKit/Prompts.swift`**

```swift
// See the Incursion LICENSE file for copyright information.
//
// Every prompt the narrator uses, with its shipped default. The settings
// window shows these for editing; overrides live in UserDefaults keyed by
// "narrator.prompt.<rawValue>" and fall back to defaultText.
import Foundation

public enum PromptKey: String, CaseIterable {
    case narratorSystem, voiceChronicler, voiceBard, voiceCompanion
    case askIndex, askAnswer, summarize

    public var title: String {
        switch self {
        case .narratorSystem:  return "Narrator system prompt"
        case .voiceChronicler: return "Voice: Dry Chronicler"
        case .voiceBard:       return "Voice: Doomful Bard"
        case .voiceCompanion:  return "Voice: Wry Companion"
        case .askIndex:        return "Ask-the-GM: topic selection"
        case .askAnswer:       return "Ask-the-GM: answer"
        case .summarize:       return "Journal summarization"
        }
    }

    public var defaultText: String {
        switch self {
        case .narratorSystem: return """
You are the narrator of a run of Incursion, a difficult fantasy roguelike. \
You observe milestones of one adventurer's descent and respond with prose. \
Never give tactical advice, never reveal game mechanics or numbers, never \
address the player as "you the player" — narrate the character in the third \
person. Stay grounded in the events you are shown; invent atmosphere, not \
facts. If the events are unclear, be brief rather than wrong.
"""
        case .voiceChronicler: return """
Voice: a dry chronicler writing a terse historical record long after the \
fact. Understatement over drama. No exclamation marks.
"""
        case .voiceBard: return """
Voice: a doomful bard who suspects this tale ends badly and relishes saying \
so. Ominous, musical, a little grand.
"""
        case .voiceCompanion: return """
Voice: a wry companion walking one step behind, fond of the adventurer but \
unable to resist a raised eyebrow. Warm, lightly ironic.
"""
        case .askIndex: return """
You are the gamemaster's librarian for the roguelike Incursion. Below is an \
index of help topics. Given the player's question, reply with ONLY a JSON \
array of the ids of the topics (at most 4) most likely to contain the \
answer, e.g. ["combat","saving-throws"]. No other text.
"""
        case .askAnswer: return """
You are the gamemaster for the roguelike Incursion. Answer the player's \
question using ONLY the reference text provided. Quote rules accurately; \
if the text does not answer the question, say so plainly. End with a line \
"Sources:" listing the topic titles you used. Do not spoil late-game \
content beyond what the question requires.
"""
        case .summarize: return """
Condense the narration journal below into a compact "story so far" of at \
most 150 words, keeping character identity, notable deeds, and tone. \
Reply with the summary only.
"""
        }
    }
}

public enum NarrationLength: String, CaseIterable {
    case line, beat, paragraph

    public var instruction: String {
        switch self {
        case .line:      return "Reply with a single sentence."
        case .beat:      return "Reply with two or three sentences."
        case .paragraph: return "Reply with one short paragraph, five sentences at most."
        }
    }

    public var title: String {
        switch self {
        case .line: return "One line"
        case .beat: return "A beat"
        case .paragraph: return "A paragraph"
        }
    }
}
```

- [ ] **Step 4: Implement `macapp/Sources/NarratorKit/PromptBuilder.swift`**

```swift
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
            ChatMessage(role: "assistant", content: "Understood."),
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
```

Note for the test in Step 1: the serializer puts `messages` LAST so the byte-stable prefix (model, sampling, system, journal) precedes the new user turn. The `testDeterministicSerializerEscapes` expectation string must match this order — it does (`{"model":"m","temperature":0.5,`).

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter PromptBuilderTests`
Expected: PASS (5 tests).

- [ ] **Step 6: Commit**

```bash
git add macapp/Sources/NarratorKit/Prompts.swift macapp/Sources/NarratorKit/PromptBuilder.swift macapp/Tests/NarratorKitTests/PromptBuilderTests.swift
git commit -m "Build narrator prompts on a cache-stable prefix

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: OpenAIClient — model listing and SSE streaming

**Files:**
- Create: `macapp/Sources/NarratorKit/OpenAIClient.swift`
- Test: `macapp/Tests/NarratorKitTests/OpenAIClientTests.swift`

**Interfaces:**
- Consumes: `ChatMessage`, `WireJSON` (Task 4).
- Produces:
  - `public struct EndpointConfig: Equatable { public var baseURL: URL; public var token: String; public var model: String; public init(baseURL: URL, token: String, model: String) }`
  - `public enum OpenAIError: Error, Equatable { case http(Int), badResponse, emptyReply }`
  - `public final class OpenAIClient { public init(config: EndpointConfig, session: URLSession = .shared); public func listModels() async throws -> [String]; public func streamChat(messages: [ChatMessage], temperature: Double, maxTokens: Int, onDelta: @escaping @Sendable (String) -> Void) async throws -> String; public func testConnection() async throws -> TimeInterval }`

- [ ] **Step 1: Write the failing tests (URLProtocol mock, no real network)**

`macapp/Tests/NarratorKitTests/OpenAIClientTests.swift`:

```swift
import XCTest
@testable import NarratorKit

final class MockURLProtocol: URLProtocol {
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

final class OpenAIClientTests: XCTestCase {
    func makeClient() -> OpenAIClient {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [MockURLProtocol.self]
        return OpenAIClient(
            config: EndpointConfig(baseURL: URL(string: "https://mock.test/v1")!,
                                   token: "sk-test", model: "gpt-test"),
            session: URLSession(configuration: cfg))
    }

    func ok(_ body: String, url: URL) -> (HTTPURLResponse, Data) {
        (HTTPURLResponse(url: url, statusCode: 200,
                         httpVersion: nil, headerFields: nil)!, Data(body.utf8))
    }

    func testListModelsParsesAndSorts() async throws {
        MockURLProtocol.handler = { req in
            XCTAssertEqual(req.url?.path, "/v1/models")
            XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
            return self.ok(#"{"data":[{"id":"zeta"},{"id":"alpha"}]}"#, url: req.url!)
        }
        let models = try await makeClient().listModels()
        XCTAssertEqual(models, ["alpha", "zeta"])
    }

    func testStreamChatConcatenatesDeltas() async throws {
        let sse = """
        data: {"choices":[{"delta":{"content":"The "}}]}

        data: {"choices":[{"delta":{"content":"dark."}}]}

        data: [DONE]

        """
        MockURLProtocol.handler = { req in
            XCTAssertEqual(req.url?.path, "/v1/chat/completions")
            return self.ok(sse, url: req.url!)
        }
        var seen: [String] = []
        let lock = NSLock()
        let full = try await makeClient().streamChat(
            messages: [ChatMessage(role: "user", content: "go")],
            temperature: 0.7, maxTokens: 50) { delta in
                lock.lock(); seen.append(delta); lock.unlock()
            }
        XCTAssertEqual(full, "The dark.")
        XCTAssertEqual(seen, ["The ", "dark."])
    }

    func testHTTPErrorSurfacesStatus() async {
        MockURLProtocol.handler = { req in
            (HTTPURLResponse(url: req.url!, statusCode: 401,
                             httpVersion: nil, headerFields: nil)!, Data())
        }
        do {
            _ = try await makeClient().listModels()
            XCTFail("expected throw")
        } catch let e as OpenAIError {
            XCTAssertEqual(e, .http(401))
        } catch { XCTFail("wrong error \(error)") }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter OpenAIClientTests`
Expected: FAIL — `OpenAIClient` not defined.

- [ ] **Step 3: Implement `macapp/Sources/NarratorKit/OpenAIClient.swift`**

```swift
// See the Incursion LICENSE file for copyright information.
//
// A minimal OpenAI-compatible chat client: /v1/models for discovery and
// streaming /v1/chat/completions over SSE. Works against OpenAI, vLLM,
// LM Studio, and Ollama. The token appears only in the Authorization
// header; it is never logged.
import Foundation

public struct EndpointConfig: Equatable {
    public var baseURL: URL
    public var token: String
    public var model: String

    public init(baseURL: URL, token: String, model: String) {
        self.baseURL = baseURL
        self.token = token
        self.model = model
    }
}

public enum OpenAIError: Error, Equatable {
    case http(Int), badResponse, emptyReply
}

public final class OpenAIClient {
    private let config: EndpointConfig
    private let session: URLSession

    public init(config: EndpointConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    private func request(path: String) -> URLRequest {
        var req = URLRequest(url: config.baseURL.appendingPathComponent(path))
        req.setValue("Bearer \(config.token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 60
        return req
    }

    public func listModels() async throws -> [String] {
        struct ModelList: Decodable {
            struct Entry: Decodable { let id: String }
            let data: [Entry]
        }
        let (data, resp) = try await session.data(for: request(path: "models"))
        guard let http = resp as? HTTPURLResponse else { throw OpenAIError.badResponse }
        guard http.statusCode == 200 else { throw OpenAIError.http(http.statusCode) }
        return try JSONDecoder().decode(ModelList.self, from: data)
            .data.map(\.id).sorted()
    }

    public func streamChat(messages: [ChatMessage], temperature: Double,
                           maxTokens: Int,
                           onDelta: @escaping @Sendable (String) -> Void)
                           async throws -> String {
        struct Chunk: Decodable {
            struct Choice: Decodable {
                struct Delta: Decodable { let content: String? }
                let delta: Delta
            }
            let choices: [Choice]
        }
        var req = request(path: "chat/completions")
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = WireJSON.chatBody(model: config.model, messages: messages,
                                         temperature: temperature,
                                         maxTokens: maxTokens, stream: true)
        let (bytes, resp) = try await session.bytes(for: req)
        guard let http = resp as? HTTPURLResponse else { throw OpenAIError.badResponse }
        guard http.statusCode == 200 else { throw OpenAIError.http(http.statusCode) }
        var full = ""
        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))
            if payload == "[DONE]" { break }
            guard let d = payload.data(using: .utf8),
                  let chunk = try? JSONDecoder().decode(Chunk.self, from: d),
                  let delta = chunk.choices.first?.delta.content,
                  !delta.isEmpty else { continue }
            full += delta
            onDelta(delta)
        }
        guard !full.isEmpty else { throw OpenAIError.emptyReply }
        return full
    }

    /// One tiny round trip; returns the latency for the settings window.
    public func testConnection() async throws -> TimeInterval {
        let start = Date()
        _ = try await streamChat(
            messages: [ChatMessage(role: "user", content: "Reply with the single word: ready")],
            temperature: 0, maxTokens: 4, onDelta: { _ in })
        return Date().timeIntervalSince(start)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter OpenAIClientTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add macapp/Sources/NarratorKit/OpenAIClient.swift macapp/Tests/NarratorKitTests/OpenAIClientTests.swift
git commit -m "Speak the OpenAI dialect, streaming, any endpoint

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: Settings model and Keychain store

**Files:**
- Create: `macapp/Sources/NarratorKit/NarratorSettings.swift`
- Test: `macapp/Tests/NarratorKitTests/SettingsTests.swift`

**Interfaces:**
- Consumes: `Milestone`, `NarrationLength`, `PromptKey`.
- Produces:
  - `public enum KeychainStore { public static func saveToken(_ t: String) ; public static func loadToken() -> String?; public static func deleteToken() }` (service `"Incursion Narrator"`, account `"api-token"`)
  - `public final class NarratorSettings: ObservableObject` with `@Published` properties `baseURLString: String` (default `"https://api.openai.com/v1"`), `model: String`, `voice: PromptKey` (default `.voiceChronicler`), `customStyle: String`, `enabledMilestones: Set<Milestone>` (default all), `cooldownTurns: Int` (default 150), `length: NarrationLength` (default `.beat`), `temperature: Double` (default 0.8), `maxTokens: Int` (default 220), `askEnabled: Bool` (default true), `includeWiki: Bool` (default true); methods `public func promptText(_ k: PromptKey) -> String`, `public func setPromptText(_ k: PromptKey, _ text: String)`, `public func isPromptModified(_ k: PromptKey) -> Bool`, `public func restorePromptDefault(_ k: PromptKey)`, `public init(defaults: UserDefaults = .standard)`. Everything persists to the given UserDefaults under keys prefixed `narrator.`.

- [ ] **Step 1: Write the failing tests**

`macapp/Tests/NarratorKitTests/SettingsTests.swift`:

```swift
import XCTest
@testable import NarratorKit

final class SettingsTests: XCTestCase {
    var defaults: UserDefaults!

    override func setUp() {
        defaults = UserDefaults(suiteName: "narrator-tests")!
        defaults.removePersistentDomain(forName: "narrator-tests")
    }

    func testDefaultsAreSane() {
        let s = NarratorSettings(defaults: defaults)
        XCTAssertEqual(s.baseURLString, "https://api.openai.com/v1")
        XCTAssertEqual(s.enabledMilestones, Set(Milestone.allCases))
        XCTAssertEqual(s.cooldownTurns, 150)
        XCTAssertEqual(s.length, .beat)
    }

    func testValuesPersistAcrossInstances() {
        let s1 = NarratorSettings(defaults: defaults)
        s1.model = "llama-3.3-70b"
        s1.cooldownTurns = 400
        s1.enabledMilestones = [.death]
        let s2 = NarratorSettings(defaults: defaults)
        XCTAssertEqual(s2.model, "llama-3.3-70b")
        XCTAssertEqual(s2.cooldownTurns, 400)
        XCTAssertEqual(s2.enabledMilestones, [.death])
    }

    func testPromptOverrideAndRestore() {
        let s = NarratorSettings(defaults: defaults)
        XCTAssertFalse(s.isPromptModified(.narratorSystem))
        XCTAssertEqual(s.promptText(.narratorSystem), PromptKey.narratorSystem.defaultText)
        s.setPromptText(.narratorSystem, "Be terse.")
        XCTAssertTrue(s.isPromptModified(.narratorSystem))
        XCTAssertEqual(s.promptText(.narratorSystem), "Be terse.")
        s.restorePromptDefault(.narratorSystem)
        XCTAssertFalse(s.isPromptModified(.narratorSystem))
        XCTAssertEqual(s.promptText(.narratorSystem), PromptKey.narratorSystem.defaultText)
    }

    func testKeychainRoundTrip() {
        KeychainStore.deleteToken()
        XCTAssertNil(KeychainStore.loadToken())
        KeychainStore.saveToken("sk-abc123")
        XCTAssertEqual(KeychainStore.loadToken(), "sk-abc123")
        KeychainStore.saveToken("sk-updated")
        XCTAssertEqual(KeychainStore.loadToken(), "sk-updated")
        KeychainStore.deleteToken()
        XCTAssertNil(KeychainStore.loadToken())
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter SettingsTests`
Expected: FAIL — types not defined.

- [ ] **Step 3: Implement `macapp/Sources/NarratorKit/NarratorSettings.swift`**

```swift
// See the Incursion LICENSE file for copyright information.
//
// All narrator configuration. Non-secrets in UserDefaults under
// "narrator.*"; the API token only ever touches the Keychain. There are
// no config files anywhere in this feature.
import Foundation
import Security
import Combine

public enum KeychainStore {
    static let service = "Incursion Narrator"
    static let account = "api-token"

    static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    public static func saveToken(_ t: String) {
        deleteToken()
        var q = query
        q[kSecValueData as String] = Data(t.utf8)
        SecItemAdd(q as CFDictionary, nil)
    }

    public static func loadToken() -> String? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func deleteToken() {
        SecItemDelete(query as CFDictionary)
    }
}

public final class NarratorSettings: ObservableObject {
    private let d: UserDefaults

    @Published public var baseURLString: String {
        didSet { d.set(baseURLString, forKey: "narrator.baseURL") }
    }
    @Published public var model: String {
        didSet { d.set(model, forKey: "narrator.model") }
    }
    @Published public var voice: PromptKey {
        didSet { d.set(voice.rawValue, forKey: "narrator.voice") }
    }
    @Published public var customStyle: String {
        didSet { d.set(customStyle, forKey: "narrator.customStyle") }
    }
    @Published public var enabledMilestones: Set<Milestone> {
        didSet { d.set(enabledMilestones.map(\.rawValue).sorted(),
                       forKey: "narrator.milestones") }
    }
    @Published public var cooldownTurns: Int {
        didSet { d.set(cooldownTurns, forKey: "narrator.cooldownTurns") }
    }
    @Published public var length: NarrationLength {
        didSet { d.set(length.rawValue, forKey: "narrator.length") }
    }
    @Published public var temperature: Double {
        didSet { d.set(temperature, forKey: "narrator.temperature") }
    }
    @Published public var maxTokens: Int {
        didSet { d.set(maxTokens, forKey: "narrator.maxTokens") }
    }
    @Published public var askEnabled: Bool {
        didSet { d.set(askEnabled, forKey: "narrator.askEnabled") }
    }
    @Published public var includeWiki: Bool {
        didSet { d.set(includeWiki, forKey: "narrator.includeWiki") }
    }
    /// Bumps whenever a prompt override changes, so SwiftUI refreshes.
    @Published public private(set) var promptEdition = 0

    public init(defaults: UserDefaults = .standard) {
        d = defaults
        baseURLString = d.string(forKey: "narrator.baseURL") ?? "https://api.openai.com/v1"
        model = d.string(forKey: "narrator.model") ?? ""
        voice = PromptKey(rawValue: d.string(forKey: "narrator.voice") ?? "")
            ?? .voiceChronicler
        customStyle = d.string(forKey: "narrator.customStyle") ?? ""
        if let raw = d.stringArray(forKey: "narrator.milestones") {
            enabledMilestones = Set(raw.compactMap(Milestone.init(rawValue:)))
        } else {
            enabledMilestones = Set(Milestone.allCases)
        }
        cooldownTurns = d.object(forKey: "narrator.cooldownTurns") as? Int ?? 150
        length = NarrationLength(rawValue: d.string(forKey: "narrator.length") ?? "")
            ?? .beat
        temperature = d.object(forKey: "narrator.temperature") as? Double ?? 0.8
        maxTokens = d.object(forKey: "narrator.maxTokens") as? Int ?? 220
        askEnabled = d.object(forKey: "narrator.askEnabled") as? Bool ?? true
        includeWiki = d.object(forKey: "narrator.includeWiki") as? Bool ?? true
    }

    // MARK: prompt overrides

    private func promptKey(_ k: PromptKey) -> String { "narrator.prompt." + k.rawValue }

    public func promptText(_ k: PromptKey) -> String {
        d.string(forKey: promptKey(k)) ?? k.defaultText
    }

    public func setPromptText(_ k: PromptKey, _ text: String) {
        if text == k.defaultText {
            d.removeObject(forKey: promptKey(k))
        } else {
            d.set(text, forKey: promptKey(k))
        }
        promptEdition += 1
    }

    public func isPromptModified(_ k: PromptKey) -> Bool {
        d.string(forKey: promptKey(k)) != nil
    }

    public func restorePromptDefault(_ k: PromptKey) {
        d.removeObject(forKey: promptKey(k))
        promptEdition += 1
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter SettingsTests`
Expected: PASS (4 tests). (Keychain access from `swift test` is fine on a local machine; if the environment denies it, mark `testKeychainRoundTrip` with `try XCTSkipIf` on the first failing status and say so in the task report.)

- [ ] **Step 5: Commit**

```bash
git add macapp/Sources/NarratorKit/NarratorSettings.swift macapp/Tests/NarratorKitTests/SettingsTests.swift
git commit -m "Keep narrator settings in defaults and the token in the Keychain

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 7: NarratorEngine — the orchestrator

**Files:**
- Create: `macapp/Sources/NarratorKit/NarratorEngine.swift`
- Test: `macapp/Tests/NarratorKitTests/NarratorEngineTests.swift`

**Interfaces:**
- Consumes: everything from Tasks 2-6.
- Produces:
  - `public struct NarrationEntry: Identifiable, Equatable { public let id: UUID; public let milestone: Milestone?; public var text: String; public let isAnswer: Bool }`
  - `public protocol GroundingSource { func topicIndex(includeWiki: Bool) -> String; func topicText(ids: [String], includeWiki: Bool) -> String; func topicTitles(ids: [String]) -> [String] }`
  - `@MainActor public final class NarratorEngine: ObservableObject` with:
    - `@Published public private(set) var entries: [NarrationEntry]`
    - `@Published public var muted: Bool`
    - `@Published public private(set) var statusLine: String?`
    - `@Published public private(set) var promptTokens: Int` / `completionTokens: Int` (estimates)
    - `public init(settings: NarratorSettings, grounding: GroundingSource?, makeClient: @escaping (EndpointConfig) -> OpenAIClient = { OpenAIClient(config: $0) })`
    - `public func ingestMessage(_ line: String)` — ring buffer (200 lines) + artifact pattern check
    - `public func ingestState(_ json: Data)` — decode, detect, throttle, fire narration
    - `public func ask(_ question: String)` — two-pass ask-the-GM
    - `public var paneOpen: Bool` — when false, no API calls ever
  - Internal but tested: `func artifactMentioned(_ line: String) -> Bool` (case-insensitive contains of "artifact"), `func milestonePrompt(for m: Milestone, state: PlayerState) -> String`.

- [ ] **Step 1: Write the failing tests**

`macapp/Tests/NarratorKitTests/NarratorEngineTests.swift` — test the pure decision paths without network by injecting a client factory that must not be called, plus prompt content:

```swift
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
        })
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter NarratorEngineTests`
Expected: FAIL — `NarratorEngine` not defined.

- [ ] **Step 3: Implement `macapp/Sources/NarratorKit/NarratorEngine.swift`**

```swift
// See the Incursion LICENSE file for copyright information.
//
// The conductor: bridge samples in, throttled milestones out to the LLM,
// prose into `entries` for the pane. Failure is always quiet — one status
// line, never a dialog, and the game never waits on any of this.
import Foundation
import Combine

public struct NarrationEntry: Identifiable, Equatable {
    public let id: UUID
    public let milestone: Milestone?
    public var text: String
    public let isAnswer: Bool

    public init(milestone: Milestone?, text: String, isAnswer: Bool = false) {
        self.id = UUID()
        self.milestone = milestone
        self.text = text
        self.isAnswer = isAnswer
    }
}

/// The app adapts HelpLibrary to this so NarratorKit needs no AppKit.
public protocol GroundingSource {
    func topicIndex(includeWiki: Bool) -> String
    func topicText(ids: [String], includeWiki: Bool) -> String
    func topicTitles(ids: [String]) -> [String]
}

@MainActor
public final class NarratorEngine: ObservableObject {
    @Published public private(set) var entries: [NarrationEntry] = []
    @Published public var muted = false
    @Published public private(set) var statusLine: String?
    @Published public private(set) var promptTokens = 0
    @Published public private(set) var completionTokens = 0
    public var paneOpen = false

    private let settings: NarratorSettings
    private let grounding: GroundingSource?
    private let makeClient: (EndpointConfig) -> OpenAIClient

    private var detector = MilestoneDetector()
    private var throttle = Throttle()
    private var builder: PromptBuilder?
    private var recent: [String] = []       // ring buffer of message lines
    private var lastState: PlayerState?
    private var artifactFlag = false        // set by messages, consumed by state
    private let recentCap = 200

    public init(settings: NarratorSettings, grounding: GroundingSource?,
                makeClient: @escaping (EndpointConfig) -> OpenAIClient
                    = { OpenAIClient(config: $0) }) {
        self.settings = settings
        self.grounding = grounding
        self.makeClient = makeClient
    }

    // MARK: bridge input

    public func ingestMessage(_ line: String) {
        recent.append(line)
        if recent.count > recentCap { recent.removeFirst(recent.count - recentCap) }
        if artifactMentioned(line) { artifactFlag = true }
    }

    public func ingestState(_ json: Data) {
        guard let s = try? PlayerState(json: json) else { return }
        if lastState?.name != s.name {          // new run
            throttle.reset()
            builder = nil
        }
        lastState = s
        var found = detector.ingest(s)
        if artifactFlag { found.append(.artifact); artifactFlag = false }
        guard paneOpen, !muted, !found.isEmpty else { return }
        guard let best = found.max(by: { $0.priority < $1.priority }),
              throttle.permit(best, state: s,
                              config: ThrottleConfig(
                                  enabled: settings.enabledMilestones,
                                  cooldownTurns: settings.cooldownTurns))
        else { return }
        narrate(best, state: s)
    }

    // MARK: narration

    func artifactMentioned(_ line: String) -> Bool {
        line.lowercased().contains("artifact")
    }

    func milestonePrompt(for m: Milestone, state: PlayerState) -> String {
        let what: String
        switch m {
        case .enteredLevel: what = "The adventurer has entered depth \(state.depth)."
        case .levelUp:      what = "The adventurer has grown to level \(state.level)."
        case .nearDeath:    what = "The adventurer is near death (\(state.hp) of \(state.maxhp) HP) at depth \(state.depth)."
        case .death:        what = "The adventurer has died at depth \(state.depth)."
        case .artifact:     what = "The adventurer has come into possession of an artifact at depth \(state.depth)."
        }
        let tail = recent.suffix(20).joined(separator: "\n")
        return what + "\n\nRecent events:\n" + tail + "\n\n"
            + settings.length.instruction
    }

    private func currentSystemPrompt(state: PlayerState) -> String {
        var s = settings.promptText(.narratorSystem)
        s += "\n\n" + settings.promptText(settings.voice)
        if !settings.customStyle.isEmpty { s += "\nStyle notes: " + settings.customStyle }
        s += "\nThe adventurer is named \(state.name)."
        return s
    }

    private func endpoint() -> EndpointConfig? {
        guard let url = URL(string: settings.baseURLString),
              !settings.model.isEmpty,
              let token = KeychainStore.loadToken() else {
            statusLine = "The narrator is not configured yet (see Gamemaster settings)."
            return nil
        }
        return EndpointConfig(baseURL: url, token: token, model: settings.model)
    }

    private func narrate(_ m: Milestone, state: PlayerState) {
        guard let cfg = endpoint() else { return }
        if builder == nil {
            builder = PromptBuilder(system: currentSystemPrompt(state: state))
        }
        let userTurn = milestonePrompt(for: m, state: state)
        let messages = builder!.request(userTurn: userTurn)
        promptTokens += messages.reduce(0) { $0 + $1.content.count } / 4
        var entry = NarrationEntry(milestone: m, text: "")
        entries.append(entry)
        let idx = entries.count - 1
        let client = makeClient(cfg)
        let temperature = settings.temperature
        let maxTokens = settings.maxTokens
        Task { [weak self] in
            do {
                let full = try await client.streamChat(
                    messages: messages, temperature: temperature,
                    maxTokens: maxTokens) { delta in
                        Task { @MainActor [weak self] in
                            guard let self, self.entries.indices.contains(idx) else { return }
                            self.entries[idx].text += delta
                        }
                    }
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.completionTokens += full.count / 4
                    self.builder?.record(user: userTurn, assistant: full)
                    self.statusLine = nil
                    self.compactIfNeeded(m: m, cfg: cfg)
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    if self.entries.indices.contains(idx), self.entries[idx].text.isEmpty {
                        self.entries.remove(at: idx)
                    }
                    self.statusLine = "The narrator could not reach the endpoint. It will try again next time."
                }
            }
            _ = entry // silence unused-variable pedantry across compilers
        }
    }

    /// One deliberate cache break at a depth boundary when the journal is big.
    private func compactIfNeeded(m: Milestone, cfg: EndpointConfig) {
        guard m == .enteredLevel,
              let b = builder, b.journalTokenEstimate > 3000 else { return }
        let client = makeClient(cfg)
        let ask = settings.promptText(.summarize) + "\n\n"
            + entries.filter { !$0.isAnswer }.map(\.text).joined(separator: "\n---\n")
        Task { [weak self] in
            guard let summary = try? await client.streamChat(
                messages: [ChatMessage(role: "user", content: ask)],
                temperature: 0.3, maxTokens: 220, onDelta: { _ in }) else { return }
            await MainActor.run { self?.builder?.compact(summary: summary) }
        }
    }

    // MARK: ask-the-GM

    public func ask(_ question: String) {
        guard settings.askEnabled, let cfg = endpoint(), let g = grounding else { return }
        entries.append(NarrationEntry(milestone: nil,
                                      text: "Q: " + question, isAnswer: true))
        var answer = NarrationEntry(milestone: nil, text: "", isAnswer: true)
        entries.append(answer)
        let idx = entries.count - 1
        let includeWiki = settings.includeWiki
        let pass1 = [
            ChatMessage(role: "system",
                        content: settings.promptText(.askIndex) + "\n\n"
                            + g.topicIndex(includeWiki: includeWiki)),
            ChatMessage(role: "user", content: question),
        ]
        let client = makeClient(cfg)
        let temperature = settings.temperature
        Task { [weak self] in
            do {
                let raw = try await client.streamChat(messages: pass1,
                    temperature: 0, maxTokens: 100, onDelta: { _ in })
                let ids = Self.parseTopicIDs(raw)
                let reference = g.topicText(ids: ids, includeWiki: includeWiki)
                let titles = g.topicTitles(ids: ids)
                let pass2 = [
                    ChatMessage(role: "system", content:
                        (self?.settings.promptText(.askAnswer) ?? "")
                        + "\n\nReference text:\n" + reference
                        + "\n\nTopic titles: " + titles.joined(separator: ", ")),
                    ChatMessage(role: "user", content: question),
                ]
                _ = try await client.streamChat(messages: pass2,
                    temperature: temperature, maxTokens: 600) { delta in
                        Task { @MainActor [weak self] in
                            guard let self, self.entries.indices.contains(idx) else { return }
                            self.entries[idx].text += delta
                        }
                    }
                await MainActor.run { self?.statusLine = nil }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    if self.entries.indices.contains(idx), self.entries[idx].text.isEmpty {
                        self.entries[idx].text = "The gamemaster could not answer (endpoint unreachable)."
                    }
                }
            }
            _ = answer
        }
    }

    /// Accepts `["a","b"]` or the same wrapped in prose or code fences.
    static func parseTopicIDs(_ raw: String) -> [String] {
        guard let start = raw.firstIndex(of: "["),
              let end = raw.lastIndex(of: "]"),
              start < end,
              let data = String(raw[start...end]).data(using: .utf8),
              let ids = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return Array(ids.prefix(4))
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter NarratorEngineTests`
Expected: PASS (5 tests). Then run the whole suite once: `swift test` — all green.

- [ ] **Step 5: Commit**

```bash
git add macapp/Sources/NarratorKit/NarratorEngine.swift macapp/Tests/NarratorKitTests/NarratorEngineTests.swift
git commit -m "Conduct the narrator: milestones in, quiet prose out

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 8: App wiring — EngineHost callbacks, grounding adapter, menu

**Files:**
- Modify: `macapp/Sources/IncursionApp/EngineHost.swift` (`start(...)`, ~line 30-66)
- Create: `macapp/Sources/IncursionApp/NarratorGlue.swift`
- Modify: `macapp/Sources/IncursionApp/main.swift` (menu construction; find the menu-building section near the Help/Tileset menu items around lines 60-80 and 108-141)

**Interfaces:**
- Consumes: `NarratorEngine`, `GroundingSource`, `HelpLibrary` (existing, `HelpContent.swift:146`), `HelpTopic.runs` (`.s` segments), `WikiPage.body`.
- Produces:
  - `EngineHost.onGameMessage: ((String) -> Void)?` and `EngineHost.onPlayerState: ((Data) -> Void)?`, both delivered on the main thread.
  - `enum Narrator { @MainActor static let engine: NarratorEngine }` singleton with `HelpGrounding` adapter.
  - Menu: a "Gamemaster" submenu with "Show Narrator" (⌘⇧N action `showNarrator:`) and "Gamemaster Settings…" (action `showNarratorSettings:`) — the actions themselves land in Tasks 9-10; wire them to `NarratorWindowController.shared.show()` / `NarratorSettingsWindowController.shared.show()`.

- [ ] **Step 1: Extend EngineHost**

In `EngineHost.swift` add next to `onFrame`:

```swift
    /// Narrator taps; called on the main thread. Strings are copied before
    /// the hop because the C buffers die when the callback returns.
    var onGameMessage: ((String) -> Void)?
    var onPlayerState: ((Data) -> Void)?
```

In `start(...)`, after `cfg.cb.engine_waiting = nil`, add:

```swift
        cfg.cb.game_message = { _, cLine in
            guard let cLine else { return }
            let line = String(cString: cLine)
            DispatchQueue.main.async { EngineHost.shared.onGameMessage?(line) }
        }
        cfg.cb.player_state = { _, cJson in
            guard let cJson else { return }
            let json = Data(String(cString: cJson).utf8)
            DispatchQueue.main.async { EngineHost.shared.onPlayerState?(json) }
        }
```

- [ ] **Step 2: Create `macapp/Sources/IncursionApp/NarratorGlue.swift`**

```swift
// See the Incursion LICENSE file for copyright information.
//
// Binds NarratorKit to the app: the HelpLibrary becomes the grounding
// corpus, and the bridge taps feed the engine singleton.
import Foundation
import NarratorKit

struct HelpGrounding: GroundingSource {
    func plainText(of topic: HelpTopic) -> String {
        topic.runs.map(\.s).joined()
    }

    func topicIndex(includeWiki: Bool) -> String {
        var lines: [String] = []
        let lib = HelpLibrary.shared
        for id in lib.topicOrder {
            guard let t = lib.topics[id] else { continue }
            lines.append("\(t.id) — \(t.title) [\(t.section)]")
        }
        if includeWiki {
            for page in lib.pages.values.sorted(by: { $0.title < $1.title }) {
                lines.append("wiki:\(page.slug) — \(page.title) [guide]")
            }
        }
        return lines.joined(separator: "\n")
    }

    func topicText(ids: [String], includeWiki: Bool) -> String {
        let lib = HelpLibrary.shared
        var parts: [String] = []
        for id in ids {
            if id.hasPrefix("wiki:") {
                guard includeWiki,
                      let page = lib.pages[String(id.dropFirst(5))] else { continue }
                parts.append("## \(page.title)\n" + page.body)
            } else if let t = lib.topics[id] {
                parts.append("## \(t.title)\n" + plainText(of: t))
            }
        }
        return parts.joined(separator: "\n\n")
    }

    func topicTitles(ids: [String]) -> [String] {
        let lib = HelpLibrary.shared
        return ids.compactMap { id in
            if id.hasPrefix("wiki:") { return lib.pages[String(id.dropFirst(5))]?.title }
            return lib.topics[id]?.title
        }
    }
}

enum Narrator {
    @MainActor static let settings = NarratorSettings()
    @MainActor static let engine = NarratorEngine(settings: settings,
                                                  grounding: HelpGrounding())

    /// Call once at launch, after EngineHost is configured.
    @MainActor static func attach() {
        EngineHost.shared.onGameMessage = { engine.ingestMessage($0) }
        EngineHost.shared.onPlayerState = { engine.ingestState($0) }
    }
}
```

Note: `WikiPage` needs a `title` and `body` — both exist (`HelpContent.swift:94-109`). If `HelpLibrary.topicOrder`/`topics`/`pages` are `private(set)` they are readable from the same module — this file is in the same target, so plain access works.

- [ ] **Step 3: Wire launch and menu in `main.swift`**

In `applicationDidFinishLaunching`, after `EngineHost.shared.start(...)`, add:

```swift
        Narrator.attach()
```

In the menu-construction code, alongside the existing Help/Tileset items, add a "Gamemaster" menu:

```swift
        let gmMenu = NSMenu(title: "Gamemaster")
        let gmItem = NSMenuItem(title: "Gamemaster", action: nil, keyEquivalent: "")
        gmItem.submenu = gmMenu
        gmMenu.addItem(withTitle: "Show Narrator",
                       action: #selector(showNarrator(_:)),
                       keyEquivalent: "N")
        gmMenu.addItem(withTitle: "Gamemaster Settings…",
                       action: #selector(showNarratorSettings(_:)),
                       keyEquivalent: ",").keyEquivalentModifierMask = [.command, .shift]
        // insert before the Help menu so Help stays last, matching macOS custom
        NSApp.mainMenu?.insertItem(gmItem, at: max(0, (NSApp.mainMenu?.items.count ?? 1) - 1))
```

Match the file's existing menu-building idiom exactly (it may build menus differently — adapt placement, keep titles and selectors). Add the two selector stubs to `AppDelegate`:

```swift
    @objc func showNarrator(_ sender: Any?) {
        NarratorWindowController.shared.show()
    }
    @objc func showNarratorSettings(_ sender: Any?) {
        NarratorSettingsWindowController.shared.show()
    }
```

These reference the Task 9/10 window controllers; to keep this task compiling on its own, create the two minimal placeholder files now (they become real in Tasks 9-10):

`macapp/Sources/IncursionApp/NarratorWindow.swift`:

```swift
// See the Incursion LICENSE file for copyright information.
import AppKit

final class NarratorWindowController: NSObject {
    static let shared = NarratorWindowController()
    func show() {}   // real window arrives with the pane task
}
```

`macapp/Sources/IncursionApp/NarratorSettingsWindow.swift`:

```swift
// See the Incursion LICENSE file for copyright information.
import AppKit

final class NarratorSettingsWindowController: NSObject {
    static let shared = NarratorSettingsWindowController()
    func show() {}   // real window arrives with the settings task
}
```

- [ ] **Step 4: Build the app**

Run from `macapp/`: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`
Expected: builds clean. (Engine library from Task 1 must exist in `../build`.)

- [ ] **Step 5: Commit**

```bash
git add macapp/Sources/IncursionApp/EngineHost.swift macapp/Sources/IncursionApp/NarratorGlue.swift macapp/Sources/IncursionApp/NarratorWindow.swift macapp/Sources/IncursionApp/NarratorSettingsWindow.swift macapp/Sources/IncursionApp/main.swift
git commit -m "Feed the narrator from the bridge and hang it on the menu

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 9: The narrator window

**Files:**
- Modify: `macapp/Sources/IncursionApp/NarratorWindow.swift` (replace placeholder)

**Interfaces:**
- Consumes: `Narrator.engine` (`NarratorEngine`: `entries`, `muted`, `statusLine`, `paneOpen`, `ask(_:)`), `Milestone`.
- Produces: `NarratorWindowController.shared.show()` — a real window. Sets `engine.paneOpen = true` on show, `false` on close (that is the "closed pane = no API calls" contract).

- [ ] **Step 1: Implement the window**

Replace `NarratorWindow.swift` with:

```swift
// See the Incursion LICENSE file for copyright information.
//
// The narrator's own window: prose scrollback, a question field, a mute
// switch. Closing it silences the narrator entirely -- no calls are made
// while it is closed.
import AppKit
import SwiftUI
import NarratorKit

struct NarratorPaneView: View {
    @ObservedObject var engine: NarratorEngine
    @State private var question = ""

    func label(for m: Milestone?) -> String {
        switch m {
        case .enteredLevel: return "A NEW DEPTH"
        case .levelUp:      return "GROWTH"
        case .nearDeath:    return "THE BRINK"
        case .death:        return "THE END"
        case .artifact:     return "A FINDING"
        case nil:           return "THE GAMEMASTER"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(engine.entries) { entry in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(label(for: entry.milestone))
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(entry.text.isEmpty ? "…" : entry.text)
                                    .font(.system(.body, design: .serif))
                                    .textSelection(.enabled)
                            }
                            .id(entry.id)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: engine.entries.last?.text) {
                    if let id = engine.entries.last?.id {
                        proxy.scrollTo(id, anchor: .bottom)
                    }
                }
            }
            if let status = engine.statusLine {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.vertical, 4)
            }
            Divider()
            HStack(spacing: 8) {
                TextField("Ask the gamemaster about the rules…", text: $question)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { submit() }
                Button("Ask") { submit() }
                    .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty)
                Toggle("Mute", isOn: $engine.muted)
                    .toggleStyle(.switch)
                    .help("Silence narration for this session")
            }
            .padding(10)
        }
        .frame(minWidth: 300, minHeight: 380)
    }

    private func submit() {
        let q = question.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        question = ""
        engine.ask(q)
    }
}

final class NarratorWindowController: NSObject, NSWindowDelegate {
    static let shared = NarratorWindowController()
    private var window: NSWindow?

    @MainActor func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 360, height: 520),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered, defer: false)
            w.title = "Narrator"
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.contentView = NSHostingView(
                rootView: NarratorPaneView(engine: Narrator.engine))
            w.setFrameAutosaveName("NarratorWindow")
            window = w
        }
        Narrator.engine.paneOpen = true
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        Task { @MainActor in Narrator.engine.paneOpen = false }
    }
}
```

- [ ] **Step 2: Build**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`
Expected: clean build.

- [ ] **Step 3: Commit**

```bash
git add macapp/Sources/IncursionApp/NarratorWindow.swift
git commit -m "Give the narrator a window of its own

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 10: The Gamemaster settings window

**Files:**
- Modify: `macapp/Sources/IncursionApp/NarratorSettingsWindow.swift` (replace placeholder)

**Interfaces:**
- Consumes: `Narrator.settings` (`NarratorSettings`), `KeychainStore`, `OpenAIClient` (`listModels`, `testConnection`), `PromptKey`, `NarrationLength`, `Milestone`, `Narrator.engine` (`promptTokens`, `completionTokens`).
- Produces: `NarratorSettingsWindowController.shared.show()` — the full settings GUI.

- [ ] **Step 1: Implement the settings window**

Replace `NarratorSettingsWindow.swift` with:

```swift
// See the Incursion LICENSE file for copyright information.
//
// Every knob the narrator has, in one window. The token goes straight to
// the Keychain; nothing here writes a file. The privacy line by the URL
// says plainly where game text will be sent.
import AppKit
import SwiftUI
import NarratorKit

struct NarratorSettingsView: View {
    @ObservedObject var settings: NarratorSettings
    @ObservedObject var engine: NarratorEngine

    @State private var token: String = KeychainStore.loadToken() ?? ""
    @State private var models: [String] = []
    @State private var testResult: String?
    @State private var busy = false
    @State private var editingPrompt: PromptKey?
    @State private var draft = ""

    private func client() -> OpenAIClient? {
        guard let url = URL(string: settings.baseURLString) else { return nil }
        return OpenAIClient(config: EndpointConfig(
            baseURL: url, token: token,
            model: settings.model.isEmpty ? "unset" : settings.model))
    }

    var body: some View {
        Form {
            Section("Connection") {
                TextField("Endpoint", text: $settings.baseURLString,
                          prompt: Text("https://api.openai.com/v1"))
                Text("Milestone text from your game is sent to this endpoint.")
                    .font(.caption).foregroundStyle(.secondary)
                SecureField("API token", text: $token)
                    .onChange(of: token) {
                        token.isEmpty ? KeychainStore.deleteToken()
                                      : KeychainStore.saveToken(token)
                    }
                HStack {
                    if models.isEmpty {
                        TextField("Model", text: $settings.model,
                                  prompt: Text("model id"))
                    } else {
                        Picker("Model", selection: $settings.model) {
                            ForEach(models, id: \.self, content: Text.init)
                            if !settings.model.isEmpty && !models.contains(settings.model) {
                                Text(settings.model).tag(settings.model)
                            }
                        }
                    }
                    Button("Detect Models") { detectModels() }.disabled(busy)
                }
                HStack {
                    Button("Test Connection") { testConnection() }.disabled(busy)
                    if busy { ProgressView().controlSize(.small) }
                    if let r = testResult {
                        Text(r).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section("Voice") {
                Picker("Preset", selection: $settings.voice) {
                    Text("Dry Chronicler").tag(PromptKey.voiceChronicler)
                    Text("Doomful Bard").tag(PromptKey.voiceBard)
                    Text("Wry Companion").tag(PromptKey.voiceCompanion)
                }
                TextField("Extra style notes", text: $settings.customStyle,
                          axis: .vertical)
                    .lineLimit(2...4)
            }
            Section("Prompts") {
                ForEach(PromptKey.allCases, id: \.self) { key in
                    HStack {
                        Text(key.title)
                        if settings.isPromptModified(key) {
                            Text("modified").font(.caption2)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(.quaternary, in: Capsule())
                        }
                        Spacer()
                        Button("Edit…") { draft = settings.promptText(key)
                                          editingPrompt = key }
                        Button("Restore Default") { settings.restorePromptDefault(key) }
                            .disabled(!settings.isPromptModified(key))
                    }
                }
                Text("Edited prompts apply at the next narration, at the cost of one prompt-cache break.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Cadence") {
                ForEach(Milestone.allCases, id: \.self) { m in
                    Toggle(cadenceTitle(m), isOn: Binding(
                        get: { settings.enabledMilestones.contains(m) },
                        set: { on in
                            if on { settings.enabledMilestones.insert(m) }
                            else  { settings.enabledMilestones.remove(m) }
                        }))
                }
                Stepper("Cooldown: \(settings.cooldownTurns) game turns",
                        value: $settings.cooldownTurns, in: 0...2000, step: 50)
                Picker("Length", selection: $settings.length) {
                    ForEach(NarrationLength.allCases, id: \.self) {
                        Text($0.title).tag($0)
                    }
                }
            }
            Section("Sampling") {
                Slider(value: $settings.temperature, in: 0...1.5) {
                    Text("Temperature \(settings.temperature, specifier: "%.2f")")
                }
                Stepper("Response cap: \(settings.maxTokens) tokens",
                        value: $settings.maxTokens, in: 60...1000, step: 20)
            }
            Section("Ask the GM") {
                Toggle("Enable rules & lore questions", isOn: $settings.askEnabled)
                Toggle("Include wiki pages in grounding", isOn: $settings.includeWiki)
            }
            Section("Status") {
                Text("This session: ~\(engine.promptTokens) prompt / ~\(engine.completionTokens) completion tokens")
                    .font(.caption).foregroundStyle(.secondary)
                if let status = engine.statusLine {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 460, minHeight: 560)
        .sheet(item: $editingPrompt) { key in
            VStack(alignment: .leading, spacing: 10) {
                Text(key.title).font(.headline)
                TextEditor(text: $draft)
                    .font(.system(.body, design: .monospaced))
                    .frame(minWidth: 480, minHeight: 260)
                HStack {
                    Button("Restore Default") { draft = key.defaultText }
                    Spacer()
                    Button("Cancel") { editingPrompt = nil }
                    Button("Save") {
                        settings.setPromptText(key, draft)
                        editingPrompt = nil
                    }.keyboardShortcut(.defaultAction)
                }
            }
            .padding(16)
        }
    }

    private func cadenceTitle(_ m: Milestone) -> String {
        switch m {
        case .enteredLevel: return "Entering a new depth"
        case .levelUp:      return "Gaining a level"
        case .nearDeath:    return "Falling near death"
        case .death:        return "Death"
        case .artifact:     return "Finding an artifact"
        }
    }

    private func detectModels() {
        guard let c = client() else { testResult = "The endpoint URL is not valid."; return }
        busy = true
        Task {
            defer { busy = false }
            do {
                models = try await c.listModels()
                testResult = "\(models.count) models found."
            } catch {
                models = []
                testResult = "Model listing failed — enter the model id by hand."
            }
        }
    }

    private func testConnection() {
        guard let c = client() else { testResult = "The endpoint URL is not valid."; return }
        busy = true
        Task {
            defer { busy = false }
            do {
                let dt = try await c.testConnection()
                testResult = String(format: "Connected — %.1f s round trip.", dt)
            } catch OpenAIError.http(let code) {
                testResult = "The endpoint answered with HTTP \(code)."
            } catch {
                testResult = "The endpoint could not be reached."
            }
        }
    }
}

extension PromptKey: Identifiable {
    public var id: String { rawValue }
}

final class NarratorSettingsWindowController: NSObject {
    static let shared = NarratorSettingsWindowController()
    private var window: NSWindow?

    @MainActor func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 600),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered, defer: false)
            w.title = "Gamemaster"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: NarratorSettingsView(
                settings: Narrator.settings, engine: Narrator.engine))
            w.setFrameAutosaveName("NarratorSettingsWindow")
            window = w
        }
        window?.makeKeyAndOrderFront(nil)
    }
}
```

- [ ] **Step 2: Build**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`
Expected: clean build.

- [ ] **Step 3: Commit**

```bash
git add macapp/Sources/IncursionApp/NarratorSettingsWindow.swift
git commit -m "Put every gamemaster knob in one settings window

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 11: Amend the spec, verify everything, close out

**Files:**
- Modify: `docs/superpowers/specs/2026-08-17-llm-narrator-design.md` (section "1. Engine tap")

- [ ] **Step 1: Amend the spec's engine-tap section**

Replace the milestone-callback description (the `milestone(ctx, json)` bullet and the five-sites list) with the implemented design: the bridge ships `game_message` lines plus `player_state` JSON samples on change; milestones are derived app-side by `MilestoneDetector` (state diffs) and an artifact message pattern; cooldown is measured in game turns from the `turn` field. Note WHY: engine changes stay confined to Wmac.cpp, milestone rules become tunable without engine rebuilds. Also update section 5 ("Side pane") to say the narrator lives in its own window following the app's window-per-feature pattern, and the cooldown wording in section 6 to "game turns (Stepper)".

- [ ] **Step 2: Full verification pass**

Run each, expect success:

```bash
BACKEND=mac ./build_macos.sh                 # engine still builds
FULL=yes tools/check_macterm.sh              # parity: all scenarios PASS
cd macapp && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test   # all NarratorKit suites PASS
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build               # app builds
```

- [ ] **Step 3: Smoke run (manual, sandboxed)**

Launch the app against a scratch directory (never the repo's real `save/`; use `INCURSIONPATH` per the machine notes). Open Gamemaster Settings, confirm the window renders all sections. Open the Narrator window, confirm the status line reports "not configured yet" until an endpoint is set. Do NOT capture the full screen — capture by window id if a screenshot is wanted.

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/specs/2026-08-17-llm-narrator-design.md
git commit -m "Record the narrator tap as built: state diffs, not engine hooks

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```
