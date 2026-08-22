# Tutorial Voice: Style and Narrative Guides

Style and narrative guides for every tutorial game type, and the
review/rewrite cycle that enforces them. The goal: guide text that
sounds like Incursion, not like an assistant — deeper, stranger, and
more worth reading.

## Part I — The house voice, from the source

Incursion already has a voice. It was written in the 2000s by one
author with strong habits, and the tutorial must sound like it grew in
the same soil. Exemplars, and what each one teaches:

| Exemplar | Where | What it teaches |
|---|---|---|
| The Forsaken intro | `lib/help.irh:42` ("primordial mage-lords who made pacts with beings beyond the edge of creation... a crimson fire rains from the sky for three days and three nights over the town of Akrenstone") | Lore arrives as *fact*, dense with proper nouns, never explained twice. Stakes are stated flatly: "Fail, and they will spread despair and destruction." |
| Aiswin | `lib/religion.irh:10` ("Aiswin the Whisperer lurks in the hearts of all men and women... A common cliche states that Aiswin has dominion over everyone who has nobody else.") | Long declarative sentences that turn at a semicolon or dash. Moral texture over neatness — the god is sympathetic *and* poisonous in the same paragraph. |
| Entry Chamber | `lib/dungeon.irh` region desc ("this room is a mass grave, the floor splattered with blood and the corpses of your fellow adventurers laying strewn around the stairs") | The game opens on your predecessors' corpses. Death is scenery. The tutorial's narrator lives here. |
| Cave exit | `lib/dungeon.irh:212` ("where you left it as a novice, you re-emerge into it as a hero, having taken the first steps toward becoming like the great adventurer-lords of old") | Second person, elevated but concrete; the sentence earns its length. |
| Warrior class | `lib/classes.irh:2748` ("The peasantry respects a lord who is willing to take up arms to defend them rather than letting others die in his name") | Even a stat-block description carries social worldbuilding and opinion. |
| Wiki survival tips | `macapp/Resources/Help/wiki/general-tips-for-survival.md` ("Don't be too resource conscious or you will end up in the grave with them!") | The community's table-talk register: blunt, wry, numerate, unafraid of death jokes. |

**House rules distilled:**

1. **Fact, not framing.** State the world; never announce that you are
   about to explain it. No "let's", no "note that", no "remember".
2. **Diction has dirt on it.** Period-flavored words used naturally:
   succor, wherein, boiling forth, protectorate. Never a modern
   corporate or therapeutic word.
3. **Mechanics mid-prose, unashamed.** "3d6 Hearthstones", "1,000 XP",
   "[Z]" sit inside sentences the way the manual writes them.
4. **Opinion is allowed.** The source text editorializes constantly.
   A guide who has died here has *views*.
5. **Sentences turn.** The signature move is a long declarative that
   pivots at a dash or semicolon into consequence or irony — not a
   balanced antithesis, a *turn*.
6. **Death is weather.** Wry fatalism, never grimdark posturing and
   never reassurance.

## Part II — The Claude-tell blacklist

Tells found in the current arc-1 text (and to be hunted in all drafts):

- **Praise-bot openers**: "Good — that is how you move." A dead
  mercenary does not award participation credit.
- **Tidy summarizing triads**: "explore, fight, take, rest, descend."
  The house voice never recaps; it moves on.
- **Balanced antithesis as wit**: "fleeing beats dying", "a death
  sentence, not a payday". One per arc at most; the source's humor is
  crooked, not symmetrical.
- **Metronome structure**: every beat shaped observation → rule → tip.
  Vary the entry point: some beats start mid-thought, some with a
  memory, some with an order.
- **Hedged imperatives**: "is always a fair tactic", "whenever you
  need". The house voice commands or states.
- **The colon-title reflex** and **em-dash pairs balancing clauses of
  equal weight** — allowed only where the pivot earns it (rule I.5).
- **Universal second-person present**: the personas below get pasts,
  and their sentences sometimes live there.

## Part III — Narrative frame: the dead of the Entry Chamber

The Entry Chamber is canonically a mass grave of failed adventurers.
Every tutorial guide is one of them: a shade bound to the caves,
speaking to the newest arrival. This is diegetic (the corpses are
literally in the room description), it explains why the voice knows
what kills beginners (it killed *them*), and it gives each game type a
distinct narrator with a distinct death.

Frame rules: the shade speaks in the message pane with a name prefix,
`<13>Name:<7>`. It never breaks frame to discuss "the game" as
software; keys are spoken as marks or signs ("press <9>[Z]<7>") without
apology, exactly as the manual does. It does not follow below the
first level willingly — its last beat is delivered at the stairs, which
gives every arc a natural ending and a reason the hints stop.

## Part IV — Persona sheets, one per game type

### Arc 1, First Steps — **Hadric** (human warrior)
Caravan guard out of Mohandi; died on this floor with his shield still
on his back, which is the detail he cannot forgive himself. Blunt,
soldierly, economical; counts things (paces, potions, hit points);
gallows humor delivered deadpan. Sentence shape: short order, then a
longer sentence that explains the order by way of how he died ignoring
it. Never praises. Signature: calls the player "recruit".

### Arc 2, Eyes Open — **Perrin Underbough** (halfling rogue)
Halfling burglar; slept in the wrong corridor once, and once was
enough. Talkative, proverb-making, warm in a way Hadric is not;
treats stealth, locks and sleep as one subject — *not being caught*.
Quotes invented halfling sayings ("a door you listened at is a door
that owes you"). Signature: calls hearthstones "a night's worth of
home". Teaches identification as a burglar's appraisal habit.

### Arc 3, At Range — **Sylvassi** (elf archer)
Elf; patient in the way of something that expected to live centuries
and is still surprised it did not. Terse. Speaks in distances,
angles, wind; describes melee as "letting the argument get close".
Longest silences of any guide — beats are two sentences where Hadric's
are four. Signature: never names the monster, names the range.

### Arc 4, First Spells — **Maro Venn** (human mage)
Died mana-dry with the answer three pages further into a spellbook he
had not finished reading. Pedantic, precise, faintly contemptuous of
his own corpse; loves the economy of mana the way misers love coin.
Explains casting as debt and rest as repayment. Signature: corrects
himself mid-sentence for precision ("four — no, five, if you count the
reserve").

### Arc 5, Faith and Favor — **Sister Ilsabet** (human priest)
Priest whose god did not answer, for reasons she has had a long time
to consider. Liturgical cadence without piety; speaks of favor as a
ledger and transgression as a debt one signs unknowingly. The only
guide who talks about the *why* of conduct. Signature: ends hard
lessons with "so it is written, and so I learned".

### Arc 6, The Deep Game — **the Margins**
No shade. The player's journal carries annotations in a dead
scholar's hand — the margin-notes voice of someone who mapped the
strategic layer (alignment, parley, fountains, coin) and went too deep
anyway. Dry, third-person, aphoristic; the only voice allowed
maxim-shaped sentences, because maxims are what margins are for.

## Part V — The review/rewrite cycle

Every arc's text goes through this cycle before it lands, and again
whenever it is edited. Reviews are performed against this document.

1. **Draft** in the persona, from the arc's beat list.
2. **Tell-scan**: sweep against Part II, line by line. Every hit is
   rewritten, not patched.
3. **Voice pass**: read each beat against the persona sheet — would
   *this* dead adventurer say *this* sentence? Check sentence-shape
   signatures, not just diction.
4. **Truth pass**: every mechanical claim checked against code or the
   vendored wiki (a guide that lies about keys is worse than a bland
   one). Keys verified against the standard keyset in `src/Tables.cpp`.
5. **Fit pass**: render check in 80 columns (box) and the wide Mac
   message pane; a beat must read well as both. Length budget: 2-5
   message lines; the welcome box alone may run long.
6. An **independent reviewer** (not the drafter) runs passes 2-4 and
   files specific line objections; the drafter rewrites and the cycle
   repeats until the reviewer has no Part-II hits left.

Cycle state per arc is tracked in the arc's bead. Arc scripts that are
not yet implementable (arcs 2-6) still go through the cycle and live in
`2026-08-22-tutorial-scripts.md` beside this file, so implementation
becomes transcription.
