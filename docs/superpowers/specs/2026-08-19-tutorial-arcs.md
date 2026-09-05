# Tutorial Arcs

A ladder of guided tutorials, from first keystrokes to the deep game.
Arc 1 shipped with commit 84277ff; arcs 2-6 are implemented (guide
effects in `lib/tutorial.irh`, presets in the `TutorialSpecs` table in
`src/Create.cpp`, arc menu in `src/Main.cpp`, Mac submenu in
`macapp/Sources/IncursionApp/main.swift`). Trigger deltas found at
implementation are recorded in `2026-08-22-tutorial-scripts.md`.

Sources: the vendored Incursion Wiki guides (`macapp/Resources/Help/wiki/`,
CC BY-SA 3.0), chiefly *General Tips for Survival* and the *FAQ*. Where an
arc leans on a wiki claim, the anchor column names it.

## The arc ladder

| # | Arc | Preset character | Teaches | Wiki anchor |
|---|-----|------------------|---------|-------------|
| 1 | First Steps *(shipped)* | Human Warrior | move, attack, loot, inventory, rest, descend, XP, entry-chamber potions | Survival: "Early Game Tips", "Starting Potions", "Pace Yourself" |
| 2 | Eyes Open | Halfling Rogue | look before fighting, stealth toggle, Search and traps, lockpicking as safe XP, identifying items, escape potions, safe sleep (hearthstones, the inn, watches) | Survival: "Stealth is Your Friend", "Know your enemy"; FAQ: "How can I identify my stuff?", "How can I safely sleep?" |
| 3 | At Range | Elf Archery Ranger | ranged slots (M/O/R/A), quick-swap `-`, Shift-direction fire, ammo economy, kiting slow monsters, animal companion and watches | FAQ: "What race and class combinations are good?", "I keep dying to zombies and blobs" |
| 4 | First Spells | Human Mage | spell menu, spell hotkeys 0-9, autobuff F5, mana economy, Concentration, rest renews spells, spellbooks | Survival: "User Interface Tips"; Arcane Spell Guide |
| 5 | Faith and Favor | Human Priest | choosing a god, prayer, favor and sacrifice, transgressions ("uneasy"), service spells, curses and altars | FAQ: "What gods are good?", "Why do I sometimes feel guilty or uneasy?", "How do I get rid of a curse?" |
| 6 | The Deep Game | player's own character | alignment as conduct, talking (terms, trade, demoralize), terrain hazards, fountains and dipping, forges and money, multiclassing | FAQ: "How does alignment work?", "What are fountains for?", "What good is money?" |

The order is deliberate. Arcs 1-3 teach with systems that cannot be
misconfigured (no god, no spells). Arc 4 adds resource management, arc 5
adds the first conduct system, arc 6 assumes the player can already
survive and only narrates the strategic layer.

Arc 2's halfling is chosen for sleep safety: halflings begin play with
3d6 Hearthstones of Onanda (lib/races.irh:1602), one-use items that
guarantee a safe rest. New players die in their sleep; arc 2 hands them
the tool and a beat that teaches it, early in the ladder. The halfling
birth script grants only a proficiency, so the preset path stays
prompt-free.

Every tutorial preset also writes the wiki's recommended beginner
options into the character (Beginner's Kit ON, maximum hit points and
mana, out-of-depth monsters OFF, plus transgression hints). The options
array is a Player field, so the tutorial save keeps these settings for
its whole life without touching Options.Dat or other characters.

## Mechanism (built, reused by every arc)

One arc = one preset + one guide effect. Both halves shipped with arc 1:

- **Preset**: `InTutorial` branches in `Player::Create` make every
  chargen choice. Arc 2+ generalizes these branches into a
  `TutorialSpec` table (race, class, gender, attributes, feats with
  params, skills, god) indexed by arc number, so a new arc adds a table
  row, not new control flow.
- **Guide**: an Effect in `lib/tutorial.irh` whose resource variables
  hold stage state (saved in the module data segment) and whose
  `META(POST(EV_*))` handlers are the beats. `InstallTutorialGuide()`
  (src/Main.cpp) discovers the handlers from the effect's annotations
  and installs matching `TRAP_EVENT` stati; a new beat is one
  `On Event` block. Handlers observe only: every one returns `NOTHING`.
- **Entry**: splash option val 10 → with more than one arc, an LMenu of
  arcs replaces the direct start. `IncEngineConfig.tutorial` becomes the
  arc number (0 = off, 1 = arc 1, ...). The Mac Game menu grows a
  submenu when arc 2 lands.

## Trigger inventory per arc

Events already thrown by the engine cover most beats. Gaps are listed
so nobody rediscovers them.

| Arc | Beats with existing events | Gaps (need a new hook or a workaround) |
|---|---|---|
| 2 | `EV_PICKUP`, `EV_WALKON` (traps), `EV_ASCEND` (inn), `EV_DEATH`, `EV_INVOKE` (crumbling a hearthstone) | hide toggle has no event (poll a stati from `META(EV_TURN)`); lock-pick success has no event (hook the XP gain or add a `Throw` in src/Inv.cpp); "first unidentified item" needs an inventory scan from `META(EV_TURN)` |
| 3 | `EV_RATTACK`, `EV_STRIKE`, `EV_HIT`, `EV_MISS` | out-of-ammo moment (poll quiver from `META(EV_TURN)`); companion beats can hook `GODWATCH`-visible rest events |
| 4 | `EV_CAST`, `EV_INVOKE`, `EV_MACRO` (F-keys) | "opened the spell menu" has no event (teach it from the welcome text instead); mana-low nudge polls from `META(EV_TURN)` |
| 5 | `EV_PRAY`, `EV_SACRIFICE`, `EV_CONVERT`, `EV_INSIGHT` | transgression moment: watch the guilty/uneasy stati from `META(EV_TURN)` |
| 6 | `EV_ENTER` (features), terrain `EV_SPECIAL`, `EV_TALK`-family if thrown | fountain/forge use goes through `y`use verbs — survey `docs/YUSE-VERBS.md` before writing beats |

A standing limitation, inherited from the engine: UI commands (opening
inventory, the spell manager, the journal) throw no events. Beats teach
those keys in prose, or a C++ `Throw` is added at the command site — a
one-line change, but it must be marked as a port addition, not smuggled
in as upstream behavior.

## What "done" means per arc

Each arc closes when: (a) the preset creates with zero prompts under
`tools/headless.sh`-style sandbox runs, (b) every beat with a reachable
trigger has been observed once in a scripted or hand session, (c) the
arc's text fits the message window or reads acceptably as a box in
80 columns, and (d) `check_macterm.sh` parity still passes.

## Standing cautions

- Recompiling `mod/Incursion.Mod` shifts rIDs and breaks existing
  saves. Land arc content in batches, at release points (inc-pw1.2.4).
- Guide text over two message-window lines becomes a modal box in
  80-column terminals but flows inline in the wide Mac window. Write
  beats so either rendering reads well.
- Never test against the repo's `save/` or a live app-support
  directory; sandbox with `INCURSIONPATH`.
