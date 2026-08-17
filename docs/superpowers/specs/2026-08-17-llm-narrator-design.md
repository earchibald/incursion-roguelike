# LLM Narrator for the Incursion Mac App — Design

Date: 2026-08-17
Status: approved in discussion; spec pending user review
Tier: Narrator (first of Narrator → Author → Director; see wishlist bead for Author ideas)

## Goal

Add an optional LLM "gamemaster" voice to the native Mac app. It narrates
milestones of a run in its own narrator window and answers rules/lore questions grounded
in the game's own manual and wiki pages. It must feel additive, never
overbearing, and never touch game mechanics. All configuration lives in a
settings GUI — no config files.

## Non-goals

- No engine-side content generation (that is the Author tier).
- No mid-run intervention in game state (Director tier).
- No narration into the engine's own message pane (the narrator window only, for now).
- No Anthropic-specific API features; the client speaks the OpenAI
  chat-completions dialect only.

## Architecture

Three layers:

1. **Engine tap** — one additive extension to `src/WmacBridge.h` /
   `src/Wmac.cpp`. No behavior change; parity oracle unaffected.
2. **Swift Narrator subsystem** — controller, LLM client, grounding store,
   narrator window, settings window. Split between `macapp/Sources/
   NarratorKit/` (engine-independent logic: milestone detection, throttle,
   prompt building, client) and `macapp/Sources/IncursionApp/` (the two
   AppKit/SwiftUI windows and the Gamemaster menu).
3. **LLM endpoint** — any OpenAI-compatible server the user configures
   (OpenAI, vLLM, LM Studio, Ollama, etc.).

### 1. Engine tap

Two new optional callbacks in `IncCallbacks`, both in `src/WmacBridge.h` /
`src/Wmac.cpp` only:

```c
void (*game_message)(void *ctx, const char *line); /* message-pane line */
void (*player_state)(void *ctx, const char *json);  /* {"name":...,"level":n,
                          "depth":n,"hp":n,"maxhp":n,"turn":n}, on change */
```

- `game_message` fires once per line the engine commits to the message pane.
- `player_state` fires a compact state sample after each `Update()`, but only
  when the sample differs from the last one published — no milestone
  vocabulary or event classification lives in the engine.
- Milestones are derived app-side, in NarratorKit, not by the engine:
  `MilestoneDetector` (`macapp/Sources/NarratorKit/Milestones.swift`) diffs
  consecutive `PlayerState` samples — depth change → `enteredLevel`, a level
  increase → `levelUp`, HP crossing at or below 25% of max (once per
  crossing) → `nearDeath`, HP reaching zero → `death` — while `artifact` is
  detected separately from a `game_message` text pattern
  (`NarratorEngine.artifactMentioned`). When one state update yields several
  milestones, `Milestone.priority` picks the one narrated (death highest,
  entered-level lowest). `Throttle` (`Throttle.swift`) then applies the
  cadence rules: per-type enable, a cooldown measured in game turns taken
  from the sample's `turn` field, and once-per-depth dedupe, with death
  bypassing the cooldown.
- Threading follows the existing bridge contract: callbacks fire on the
  engine thread; the Swift side hops to the main queue immediately.
- Null callbacks are legal; the tap costs nothing when unset. Wposix builds
  do not compile it, so `tools/check_macterm.sh` is unaffected.
- Why derive milestones app-side rather than add engine callback sites: it
  keeps every engine change confined to `Wmac.cpp`, and it makes the
  milestone rules (what counts, how eager, how quiet) tunable in Swift
  without an engine rebuild.

### 2. NarratorController

Owns cadence and restraint. Responsibilities:

- Rolling buffer of recent `game_message` lines (~200, ring buffer).
- On each `player_state` sample: run it through `MilestoneDetector`, then
  `Throttle`; a permitted milestone bundles a short state description plus
  the last ~20 message lines into a user-turn, sends async, and streams
  prose into the narrator window.
- Throttles ("not overbearing" is enforced here, in Swift, tunable without
  an engine rebuild):
  - per-milestone-type enable (from settings)
  - global cooldown: no narration within N game turns of the previous one,
    measured off the `turn` field in the state sample; death bypasses it
  - dedupe: the same milestone type on the same dungeon level narrates once
  - closed/muted narrator window ⇒ zero API calls
- Narration NEVER blocks input. Requests are fire-and-forget; text streams
  into the narrator window whenever it arrives.
- Each streaming entry is tracked by a stable identity (`NarrationEntry.id`),
  not by array position, so two narrations in flight at once cannot
  overwrite or interleave into each other's text.

### 3. LLM client and cache management

Plain `URLSession` against `{base}/v1/chat/completions` with `stream: true`.

**Prefix-cache discipline (hard requirements):**

- The request message array is a **byte-stable prefix** followed by an
  **append-only journal**.
- Prefix = system prompt (voice preset + custom style + character intro +
  rules of engagement + ask-the-GM topic index), frozen at run start.
- Journal = alternating milestone/narration turns, only ever appended.
- Nothing before the append point is ever edited mid-run. This gives
  automatic prefix-cache hits on OpenAI, vLLM, LM Studio, and Ollama.
- When the journal exceeds a token budget, summarize-and-restart it at a
  dungeon-level boundary only: one deliberate cache break, not churn.
  Compaction asks the model to condense the builder's own journal
  transcript, and the resulting recap is stored back as a single assistant
  turn — the journal shrinks without losing its role in the conversation.
- A unit test asserts the serialized prefix is byte-identical across
  consecutive requests in a run.

**Model discovery:** `GET {base}/v1/models` populates a picker; a manual
text field covers endpoints that do not implement it. Both paths set the
same stored model id.

### 4. Ask-the-GM

A question field in the narrator window. Grounding corpus is already in the
app: `Resources/Help/manual.json` topics plus bundled wiki pages. A question
is gated by the same rules as milestone narration — the window must be open
and the session must not be muted — so ask-the-GM never calls out while the
narrator is closed or silenced.

Two-pass flow (no tool-calling required, so any endpoint works):

1. Pass 1: send the compact topic index (titles + sections; part of the
   stable prefix) and the question. The model names the topics it needs.
2. Pass 2: send those topics' full text; the model answers and cites topic
   titles. Citations are tappable and open the help window at that topic.

### 5. Narrator window

The narrator lives in its own window, not a pane docked to the game grid,
following the app's window-per-feature pattern already used for the Help
and Tileset windows (`NarratorWindowController`, `macapp/Sources/
IncursionApp/NarratorWindow.swift`). It is opened from the Gamemaster menu
(`Show Narrator`, ⌘⇧N) alongside `Gamemaster Settings…`. Contents:

- scrollback of narrations, each tagged with its milestone
- streaming text as it arrives
- ask-the-GM input field
- mute toggle (session-scoped quick kill, independent of settings)
- one quiet status line for errors

Closing the window sets `paneOpen = false` synchronously on the main actor
(`NSWindowDelegate.windowWillClose`), so a closed narrator window is fully
idle — no milestone narration and no ask-the-GM call fires while it is
closed, matching the "closed/muted narrator window ⇒ zero API calls" rule in §2.

### 6. Settings GUI

A Gamemaster preferences window (standard ⌘, menu item, AppKit lifecycle
like the existing Help and Tileset windows). Secrets go to the Keychain;
everything else to `UserDefaults`. The user never touches a file.

| Group | Controls |
|---|---|
| Connection | Base URL (default `https://api.openai.com/v1`); API token (secure field → Keychain, never plain text on disk — the Keychain entry's account name is parameterizable, so tests run against an isolated account rather than the user's real token); Test Connection button (one-token round trip; shows status + latency); Detect Models button → picker from `/v1/models`; manual model text field fallback |
| Voice | Preset popup: Dry Chronicler, Doomful Bard, Wry Companion; free-text style box appended to the preset |
| Prompts | Every core prompt is exposed as an editable text view: narrator system prompt template, each voice preset body, ask-the-GM pass-1 prompt, ask-the-GM pass-2 prompt, journal-summarization prompt. Each editor has a per-prompt **Restore Default** button and a visible "modified" badge. Defaults ship in code; edits persist in `UserDefaults`. Prompt edits apply immediately, at the cost of one prefix-cache break; the editor notes this. |
| Cadence | Checkbox per milestone type; cooldown as a Stepper in game turns (from the `player_state` sample's `turn` field, not wall-clock time); length picker: one line / a beat / a paragraph |
| Sampling | Temperature slider; response token cap |
| Ask-the-GM | Enable toggle; include-wiki-pages toggle |
| Status | Session token usage (prompt/completion); last error in plain words |

### 7. Failure behavior

- Endpoint unreachable or token rejected: one quiet status line in the
  narrator window; the narrator sleeps; the game never notices. No modals, no
  repeated error spam.
- Malformed model responses degrade to "no narration this time."
- The API token is redacted from all logs and diagnostics.

### 8. Privacy note

Milestone narration sends recent game text to whatever endpoint the user
configured. The settings window states this plainly next to the Base URL
field. Nothing is sent until an endpoint and token are entered and a
narration trigger fires with the narrator window open.

## Testing

- **Unit:** prompt-builder prefix byte-stability (the caching guarantee);
  model-list JSON parsing; throttle rules (cooldown, dedupe, per-type
  enable); Keychain wrapper.
- **Integration:** a local mock OpenAI server drives the closed loop:
  milestone in → request shape asserted → canned stream out → window state.
- **Engine:** `FULL=yes tools/check_macterm.sh` re-run to prove the tap
  changed nothing rendered. The tap is additive and off when callbacks are
  null.

## Work tracking

- Implementation epic and tasks in beads under the Mac-app epic family.
- A dedicated **Author-tier wishlist bead** collects ideas that surface
  while tuning the Narrator (e.g. GM-authored quest skeletons, new NPCs,
  themed encounter lists via the vestigial module system and `TQuest`).
