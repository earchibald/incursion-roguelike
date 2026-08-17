# LLM Narrator for the Incursion Mac App — Design

Date: 2026-08-17
Status: approved in discussion; spec pending user review
Tier: Narrator (first of Narrator → Author → Director; see wishlist bead for Author ideas)

## Goal

Add an optional LLM "gamemaster" voice to the native Mac app. It narrates
milestones of a run in a side pane and answers rules/lore questions grounded
in the game's own manual and wiki pages. It must feel additive, never
overbearing, and never touch game mechanics. All configuration lives in a
settings GUI — no config files.

## Non-goals

- No engine-side content generation (that is the Author tier).
- No mid-run intervention in game state (Director tier).
- No narration into the engine's own message pane (side pane only, for now).
- No Anthropic-specific API features; the client speaks the OpenAI
  chat-completions dialect only.

## Architecture

Three layers:

1. **Engine tap** — one additive extension to `src/WmacBridge.h` /
   `src/Wmac.cpp`. No behavior change; parity oracle unaffected.
2. **Swift Narrator subsystem** — controller, LLM client, grounding store,
   side pane, settings window. Lives in `macapp/Sources/IncursionApp/`.
3. **LLM endpoint** — any OpenAI-compatible server the user configures
   (OpenAI, vLLM, LM Studio, Ollama, etc.).

### 1. Engine tap

Two new optional callbacks in `IncCallbacks`:

```c
void (*game_message)(void *ctx, const char *line);   /* message-pane line   */
void (*milestone)(void *ctx, const char *json);      /* structured event    */
```

- `game_message` fires where the engine commits a line to the message pane.
- `milestone` fires at five unambiguous engine sites:
  1. entered dungeon level (with depth)
  2. character level-up
  3. near-death (HP falls to 25% of maximum or below, once per crossing)
  4. artifact acquired
  5. player death
- Each milestone carries a compact JSON state block: character name,
  race/class, level, depth, HP/max, milestone-specific fields.
- Threading follows the existing bridge contract: callbacks fire on the
  engine thread; the Swift side hops to the main queue immediately.
- Null callbacks are legal; the tap costs nothing when unset. Wposix builds
  do not compile it, so `tools/check_macterm.sh` is unaffected.

### 2. NarratorController

Owns cadence and restraint. Responsibilities:

- Rolling buffer of recent `game_message` lines (~200, ring buffer).
- On milestone: bundle the milestone JSON plus the last ~20 message lines
  into a user-turn, send async, stream prose into the side pane.
- Throttles ("not overbearing" is enforced here, in Swift, tunable without
  an engine rebuild):
  - per-milestone-type enable (from settings)
  - global cooldown: no narration within N game turns of the previous one
  - dedupe: the same milestone type on the same dungeon level narrates once
  - closed/muted pane ⇒ zero API calls
- Narration NEVER blocks input. Requests are fire-and-forget; text streams
  into the pane whenever it arrives.

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
- A unit test asserts the serialized prefix is byte-identical across
  consecutive requests in a run.

**Model discovery:** `GET {base}/v1/models` populates a picker; a manual
text field covers endpoints that do not implement it. Both paths set the
same stored model id.

### 4. Ask-the-GM

A question field in the side pane. Grounding corpus is already in the app:
`Resources/Help/manual.json` topics plus bundled wiki pages.

Two-pass flow (no tool-calling required, so any endpoint works):

1. Pass 1: send the compact topic index (titles + sections; part of the
   stable prefix) and the question. The model names the topics it needs.
2. Pass 2: send those topics' full text; the model answers and cites topic
   titles. Citations are tappable and open the help window at that topic.

### 5. Side pane

Collapsible panel beside the game grid:

- scrollback of narrations, each tagged with its milestone
- streaming text as it arrives
- ask-the-GM input field
- mute button (session-scoped quick kill, independent of settings)
- one quiet status line for errors; collapsed pane means the narrator is
  fully idle

### 6. Settings GUI

A Gamemaster preferences window (standard ⌘, menu item, AppKit lifecycle
like the existing Help and Tileset windows). Secrets go to the Keychain;
everything else to `UserDefaults`. The user never touches a file.

| Group | Controls |
|---|---|
| Connection | Base URL (default `https://api.openai.com/v1`); API token (secure field → Keychain, never plain text on disk); Test Connection button (one-token round trip; shows status + latency); Detect Models button → picker from `/v1/models`; manual model text field fallback |
| Voice | Preset popup: Dry Chronicler, Doomful Bard, Wry Companion; free-text style box appended to the preset |
| Prompts | Every core prompt is exposed as an editable text view: narrator system prompt template, each voice preset body, ask-the-GM pass-1 prompt, ask-the-GM pass-2 prompt, journal-summarization prompt. Each editor has a per-prompt **Restore Default** button and a visible "modified" badge. Defaults ship in code; edits persist in `UserDefaults`. Prompt edits apply immediately, at the cost of one prefix-cache break; the editor notes this. |
| Cadence | Checkbox per milestone type; global cooldown slider (game turns); length picker: one line / a beat / a paragraph |
| Sampling | Temperature slider; response token cap |
| Ask-the-GM | Enable toggle; include-wiki-pages toggle |
| Status | Session token usage (prompt/completion); last error in plain words |

### 7. Failure behavior

- Endpoint unreachable or token rejected: one quiet status line in the
  pane; the narrator sleeps; the game never notices. No modals, no
  repeated error spam.
- Malformed model responses degrade to "no narration this time."
- The API token is redacted from all logs and diagnostics.

### 8. Privacy note

Milestone narration sends recent game text to whatever endpoint the user
configured. The settings window states this plainly next to the Base URL
field. Nothing is sent until an endpoint and token are entered and a
narration trigger fires with the pane open.

## Testing

- **Unit:** prompt-builder prefix byte-stability (the caching guarantee);
  model-list JSON parsing; throttle rules (cooldown, dedupe, per-type
  enable); Keychain wrapper.
- **Integration:** a local mock OpenAI server drives the closed loop:
  milestone in → request shape asserted → canned stream out → pane state.
- **Engine:** `FULL=yes tools/check_macterm.sh` re-run to prove the tap
  changed nothing rendered. The tap is additive and off when callbacks are
  null.

## Work tracking

- Implementation epic and tasks in beads under the Mac-app epic family.
- A dedicated **Author-tier wishlist bead** collects ideas that surface
  while tuning the Narrator (e.g. GM-authored quest skeletons, new NPCs,
  themed encounter lists via the vestigial module system and `TQuest`).
