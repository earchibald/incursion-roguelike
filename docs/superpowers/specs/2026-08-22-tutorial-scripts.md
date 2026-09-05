# Tutorial Scripts, Arcs 2-6

Reviewed narration for the unimplemented arcs, written through the
cycle in `2026-08-22-tutorial-voice.md` (draft → tell-scan → voice →
truth → independent review). Implementation is transcription: each
beat names its slug, trigger, and text. Arc 1's script lives in the
engine itself (`lib/tutorial.irh`, `src/Main.cpp`), narrator Hadric.

Cycle state: pass-1 drafts reviewed once by an independent reader;
every key cited was verified against the standard keyset
(`src/Tables.cpp:4586+`) and every mechanical claim against the
vendored wiki. A final truth pass runs at implementation, when each
trigger is wired and observable.

## Implementation notes (2026-09-05)

All five arcs are implemented in `lib/tutorial.irh` (effects "Tutorial
Guide II" through "VI") over the arc infrastructure in `src/Main.cpp`
(TutorialArcs table) and `src/Create.cpp` (TutorialSpecs presets).
Where the engine survey contradicted a trigger named below, the
implementation differs; the implemented trigger is authoritative:

| Beat | Trigger as implemented |
|---|---|
| 2/tHearth | `META(POST(EV_ACTIVATE))` guarded on `EItem->ieID` -- item use throws EV_ACTIVATE, not EV_INVOKE |
| 2/tTrap | `META(POST(EV_EFFECT))` guarded on `EItem->isType(T_TRAP)` -- trap squares surface only as their effect |
| 2/tLock | `META(EV_PICKLOCK)` -- the event existed upstream (Knock spell only); port-addition throws added at the manual pick sites (`src/Inv.cpp`, `src/Feature.cpp`) |
| 5/tUneasy | `META(EV_TURN)` poll of `getGodAnger()` -- "uneasy" is a message, not a stati |
| 5/tGuilty, 6/tConduct | `META(EV_GUILT)` -- a port-addition event (`inc/Defines.h:193`) thrown from `Character::AlignedAct` when guilt or foolishness is recorded |
| 5/tCleric | poll also requires `HasMFlag(M_CASTER)` -- god alone matched ordinary worshippers |
| 5/tAltar, 6/tForge | `META(EV_TURN)` poll of `FFeatureAt` under the player -- EV_ENTER is portal-only |
| 6/tFountain | `META(EV_TURN)` poll for a `T_FOUNTAIN` item within one square |
| 6/tMulti | `META(EV_TURN)` poll of `TotalLevel() >= 8` -- level-up events bypass the trap dispatcher |
| 6/tLast | `META(POST(EV_DESCEND))` guarded on `EMap->Depth >= 4` |
| 3/tMiss | guarded on the event weapon being a bow or missile |
| 3/tKite | poll compares `mID->Mov` of a visible hostile against the player's |
| 3/tCompanion | rest beat fires only if a creature on the map has the player as leader |

---

## Arc 2 — Eyes Open (Perrin Underbough, halfling rogue)

### Welcome box

> Two thousand came down these stairs before you. Some of them are
> still listening.
>
> <13>Perrin:<7> Perrin Underbough, late of the Underboughs of
> Greenhollow, later still of this floor. I slept in the wrong
> corridor once. Once was the whole lesson.
>
> <13>Perrin:<7> Folk up top will tell you this business below is
> fighting. It is not. It is the art of not being caught -- by eyes,
> or by a lock you rattled instead of listened at, or worst of all by
> your own sleep.
>
> <13>Perrin:<7> Your errand is the goblin king, down at the bottom of
> these caves. Mine is to walk you across this first floor with your
> pockets full and your blood inside you. We had a saying: a door you
> listened at is a door that owes you.
>
> <13>Perrin:<7> Check those pockets, by the way. Halflings are born
> carrying more than luck.

### Beats

**tLook** — `META(POST(EV_STRIKE))`, fire-once
> <13>Perrin:<7> Before your next swing, press <9>[l]<7> and read what
> you are swinging at. Some things down here drain the strength from
> your arms; some carry disease in their teeth. The monster you read
> is half fought -- another of our sayings, and truer than most.

**tHide** — poll stealth stati from `META(EV_TURN)`, fire-once
> <13>Perrin:<7> Press <9>[h]<7> and the caves forget you are in them.
> Hiding works with any amount of skill, though skill keeps it
> working. A thing that has not seen you takes your first blow
> flat-footed, and flat-footed is how I liked them.

**tTrap** — `META(POST(EV_WALKON))` on a trap square, fire-once
> <13>Perrin:<7> That was a trap, and you found it the expensive way.
> Press <9>[s]<7> to search the ground ahead when a floor looks too
> clean. And if you smell kobolds -- their warrens are floored with
> traps wall to wall. Stay out until your Search skill is worth the
> rent.

**tLock** — lock-pick success (needs hook; see arcs doc), fire-once
> <13>Perrin:<7> A hundred XP for a lock that never swung at you.
> Picks and disarmed traps can carry you a level, and a second, and a
> third, while the brave are still bleeding for theirs. My uncle
> Tobbin called it burglar's rent, paid out by the door.

**tUnknown** — inventory scan from `META(EV_TURN)` for the first
unidentified item, fire-once
> <13>Perrin:<7> You are carrying something you cannot name. Appraise
> before you spend, my mother said. When one kind of scroll stacks
> four or five deep, it is near-certain to be Identify; press
> <9>[r]<7> and read one over the rest. Even clumsy eyes manage that
> read half the time.

**tEscape** — `META(EVICTIM(POST(EV_DAMAGE)))` when `cHP*3 < mHP`,
fire-once
> <13>Perrin:<7> <4>You are near the floor.<7> Healing swallowed
> mid-fight buys you a round; a potion of dimension door buys you a
> different room. At the brink, drink the door. Three of them were
> laid around the chamber where you started.

**tRest** — `META(POST(EV_REST))`, fire-once
> <13>Perrin:<7> Sleep is where this floor eats people. I know. Rest
> with your back to a cleared corner, never in a corridor, and if an
> ally or a beast walks with you, they will stand watches over your
> sleep. A neutral, asked kindly, might too.

**tHearth** — `META(POST(EV_INVOKE))` on a Hearthstone of Onanda,
fire-once
> <13>Perrin:<7> A Hearthstone of Onanda -- a night's worth of home,
> we call them. Crumble one and nothing touches you before morning.
> Halflings begin with a pocketful and no more come after, so break
> them on the nights that matter.

**tInn** — `META(POST(EV_ASCEND))`, fire-once
> <13>Perrin:<7> Past the top of these stairs stands the inn, and an
> inn bed is as safe as sleep gets in this country. When your
> hearthstones run thin and the floor below has been unkind, climb up
> and take the night. The dungeon keeps.

**tFarewell** — `META(POST(EV_DESCEND))`, fire-once
> <13>Perrin:<7> The stairs are as far as I go; the corridor that kept
> me is on this floor, and I mind it still. Walk soft, and count your
> stones before you sleep. If we never meet again, that means it
> worked.

---

## Arc 3 — At Range (Sylvassi, elf archery ranger)

### Welcome box

> One of the dead has been waiting a long time, and is good at it.
>
> <13>Sylvassi:<7> Sylvassi. I was owed three centuries and spent them
> here instead.
>
> <13>Sylvassi:<7> You carry a bow. Then the ground between you and a
> thing is yours, and you will keep it. Everything I have to teach is
> a distance.
>
> <13>Sylvassi:<7> Twelve paces is a friend. I will speak when there
> is something to say.

### Beats

**tSlots** — `META(EV_TURN)`, once, early
> <13>Sylvassi:<7> Open your pack with <9>[I]<7>. Set the bow with
> <9>[R]<7>, arrows with <9>[A]<7>, a blade with <9>[M]<7>, shield or
> second blade with <9>[O]<7>. A slot takes nothing that stays in the
> pack. What is slotted answers the hand; the rest is baggage.

**tFire** — `META(EV_TURN)`, once, after tSlots
> <13>Sylvassi:<7> Hold Shift and press a direction: the bow speaks
> down that line. For a moving mark, press <9>[f]<7> and choose it.

**tShot** — `META(POST(EV_RATTACK))`, fire-once
> <13>Sylvassi:<7> Loosed. Now step back and loose again. The bow's
> whole argument is the ground between you.

**tMiss** — `META(POST(EV_MISS))` on a ranged attack, fire-once
> <13>Sylvassi:<7> A miss spends the arrow all the same. Count what
> rides in your quiver before you pick a quarrel at forty paces.

**tAmmoLow** — quiver poll from `META(EV_TURN)`, fire-once
> <13>Sylvassi:<7> Your quiver runs light. Gather every arrow the
> floor offers, and walk wide of trouble until it fills.

**tSwapMelee** — `META(POST(EV_STRIKE))`, fire-once
> <13>Sylvassi:<7> So you let the argument get close. Press <9>[-]<7>
> to trade the bow for the blade, and press it again once you have
> made room to shoot.

**tKite** — `META(EV_TURN)` poll: slow hostile in view, fire-once
> <13>Sylvassi:<7> That one is slower than you. Walk back one pace,
> loose, walk back again. It will die without once arriving.

**tSpecial** — `META(EVICTIM(POST(EV_DAMAGE)))`, fire-once
> <13>Sylvassi:<7> It touched you. Press <9>[l]<7> before you close
> with anything new; some of what walks here drains and sickens at
> arm's length. Arm's length is the one range I refused them --
> except once.

**tCompanion** — `META(POST(EV_REST))` with companion present,
fire-once
> <13>Sylvassi:<7> The beast beside you keeps watch while you sleep;
> that is worth more than its teeth. Press <9>[t]<7> to speak with it
> -- it will follow you, or take a mark.

**tFarewell** — `META(POST(EV_DESCEND))`, fire-once
> <13>Sylvassi:<7> I stop here. Below, the corridors shorten and the
> dark stands closer; hold your twelve paces where the map allows
> fewer. Waste nothing.

---

## Arc 4 — First Spells (Maro Venn, human mage)

### Welcome box

> Among the corpses strewn about the entry stair, one sits apart,
> propped against the wall with a book still open on its knees.
>
> <13>Maro Venn:<7> Maro Venn, mage -- late mage, in both senses. I
> died on this floor with three -- no, two and a half -- spells left
> unlearned in the book I was reading. Your craft is the economy of
> mana, and I will teach it as nobody taught me. Press <9>[m]<7> for
> your spell list: every spell you know, its mana price, its odds of
> success. Learn the prices before you spend.

### Beats

**tCast** — `META(POST(EV_CAST))`, first cast
> <13>Maro Venn:<7> That casting was paid for in mana. Watch the
> meter: green mana returns when you rest; brown is pledged to a
> spell that persists, and stays pledged until you drop the working.
> A mage's ledger has two columns. Mine balanced one day too late.

**tHotkey** — `META(POST(EV_CAST))`, second cast
> <13>Maro Venn:<7> Twice now you have walked the whole menu. In the
> spell list, press <9>[0]<7> through <9>[9]<7> on a spell to bind
> it; the digit alone then casts it, with no menu between you and the
> foe. Ten keys -- nine, if a use-verb has claimed one. They share
> the pool.

**tBuffMark** — `META(POST(EV_CAST))`, first persistent buff
> <13>Maro Venn:<7> A persistent spell wants recasting every morning,
> and mornings multiply. In the spell list, press <9>[F5]<7> on each
> buff to mark it; outside the list, <9>[F5]<7> casts the whole
> marked slate at once. I marked mine the week I died -- the week
> before. The habit outlived me.

**tMacro** — `META(POST(EV_MACRO))`, F5 pressed
> <13>Maro Venn:<7> The slate is cast. Do this after every rest, once
> your spells have lapsed. An unbuffed mage is a scribe in a
> knife-fight, and the dungeon does not read.

**tMeleeCast** — `META(POST(EV_CAST))` with a foe adjacent
> <13>Maro Venn:<7> Step back before you shape the next one. Every
> enemy in reach taxes the casting through your Concentration skill;
> fail that check and the mana is spent on nothing. The step costs
> you nothing. The spell costs mana either way.

**tHurt** — `META(EVICTIM(POST(EV_DAMAGE)))`
> <13>Maro Venn:<7> Wounds break spells the same way blades do --
> damage forces a Concentration check on anything you are casting.
> Put ranks in that skill and keep it high. Your hide is thin vellum;
> write on it as little as possible.

**tLowMana** — poll from `META(EV_TURN)`: mana below a third
> <13>Maro Venn:<7> <4>Your mana runs low.<7> Stop spending. An empty
> mage is prey, and prey that glows. I counted four points left --
> three, in truth -- and priced my last spell wrong. Withdraw and
> rest, or drink a potion of mana if your kit holds one.

**tRest** — `META(POST(EV_REST))`
> <13>Maro Venn:<7> Rest is repayment. Sleep restores green mana in
> full and renews your lapsed spells for the day. It repays nothing
> in the brown column -- press <9>[x]<7> to drop a persistent working
> first, if you want that mana back before you lie down.

**tBook** — `META(POST(EV_PICKUP))`, item is a spellbook
> <13>Maro Venn:<7> A spellbook. The better part of a mage's craft is
> found, not granted, and the finding of books is your true career --
> Luck the finder's fee. Read it with <9>[r]<7>, and read it to the
> end. The answer to my death was three pages past my bookmark.

**tStairs** — `META(POST(EV_DESCEND))`
> <13>Maro Venn:<7> The stair. I go no further; my binding is exact,
> even where my counting was not. Below, spend mana like the miser it
> deserves, and keep a reserve of four points at all times. Five.
> Always five.

---

## Arc 5 — Faith and Favor (Sister Ilsabet, human priest)

### Welcome box

> By the entry stair a shade kneels among the dead as if in vigil,
> hands folded over a chained holy symbol long since rusted through.
>
> <13>Sister Ilsabet:<7> I am Ilsabet, once a sister of the cloth. I
> called upon my god at the end, and the ledger said no. You already
> serve a power; mind the terms of service. Favor is an account --
> deeds that please your god are paid in, aid you ask for is drawn
> out, and nothing is forgiven that was not first recorded. Press
> <9>[p]<7> when you would pray.

### Beats

**tPray** — `META(POST(EV_PRAY))`
> <13>Sister Ilsabet:<7> You have prayed. Prayer is a withdrawal:
> aid, insight, blessing, each drawn against your favor. Petition
> when the need is real. A god dunned daily grows deaf -- mine did,
> though the fault in the account was my own.

**tSac** — `META(POST(EV_SACRIFICE))`
> <13>Sister Ilsabet:<7> An offering, and the ledger moves. Sacrifice
> upon your god's altar pays favor in -- corpses, treasure, whatever
> that god prizes. Feed the account before the day you must draw on
> it. So it is written, and so I learned.

**tUneasy** — poll uneasy stati from `META(EV_TURN)`
> <13>Sister Ilsabet:<7> <4>You feel uneasy.<7> That is your god's
> displeasure being entered against you: some act of yours broke the
> terms of service, and the hint beside the feeling names the deed.
> Mark it. Atonement is sacrifice, and works the god loves.

**tGuilty** — poll guilty stati from `META(EV_TURN)`
> <13>Sister Ilsabet:<7> <4>You feel guilty.<7> This debt is not your
> god's; it is your own. You have acted against your stated
> alignment, and the alignment is shifting under you. Conduct is a
> vow. Keep it, or choose from the character screen a creed you can
> keep.

**tCleric** — poll from `META(EV_TURN)`: priest NPC in view
> <13>Sister Ilsabet:<7> A cleric of the dungeon stands in view. Any
> priest sells service spells -- healing, cure disease, remove curse
> -- for coin, where Charisma or the Diplomacy skill opens the trade.
> My order sold the same mercies, at the same counter.

**tCurse** — poll from `META(EV_TURN)`: cursed item known in pack
> <13>Sister Ilsabet:<7> The thing is cursed. Carry it to an altar of
> your own god: laid there unequipped, prayer will have it blessed
> clean. A spell, scroll or potion of Remove Curse serves as well,
> and some gods lift curses outright for the faithful whose account
> stands high.

**tAltar** — `META(POST(EV_ENTER))`, altar feature
> <13>Sister Ilsabet:<7> An altar, and its sign tells you whose. On
> your own god's stone you may sacrifice and be heard; on a
> stranger's, conduct yourself as a guest. Every altar is a
> counting-house, and every house keeps a different book.

**tInsight** — `META(POST(EV_INSIGHT))`
> <13>Sister Ilsabet:<7> You sought insight -- the cheapest line of
> the litany. The god will speak to your standing, or lay open the
> nature of a thing you carry, as Xavias does for those he favors.
> Ask often. Knowledge is drawn at a discount.

**tAid** — `META(EVICTIM(POST(EV_DAMAGE)))`, HP below a third
> <13>Sister Ilsabet:<7> <4>You are failing.<7> Now, if the account
> is full, press <9>[p]<7> and pray for aid: a pleased god mends
> flesh and strikes at besiegers. If the account is empty, the answer
> is silence. I have heard that silence. Arrange never to hear it.

**tStairs** — `META(POST(EV_DESCEND))`
> <13>Sister Ilsabet:<7> Here I stop; the stair is the edge of my
> parish. Below, keep the vow, feed the altar, and draw no more than
> you deposit. The god remembers all of it, item by item. So it is
> written, and so I learned.

---

## Arc 6 — The Deep Game (the Margins)

### Foreword (box)

> A second hand keeps the margins of this journal -- small, exact,
> browned with age. It belonged to a scholar who mapped the game
> above the game: conduct, parley, water, coin. The entries run to
> the deepest page and stop. The hand did not stop because it ran
> out of things to say.

### Beats

**tSelf** — early poll from `META(EV_TURN)`
> <13>Margins:<7> First entry, underlined twice: know the creature
> one already is. Race and class carry abilities that die unused --
> the kobold with Flawless Dodge who never dodged lies buried by the
> stair. The dungeon waits while a page is read. It always waits.

**tConduct** — poll guilty stati from `META(EV_TURN)`
> <13>Margins:<7> Alignment is not a label; it is a record of
> conduct. Each act against the creed shifts the needle, and the
> needle stays honest when the adventurer does not. Those who find
> the accounting tiresome play neutral evil, and answer only to the
> dungeon.

**tTerms** — parley with a fleeing foe
> <13>Margins:<7> A fleeing foe that can speak can surrender: press
> <9>[t]<7> and offer terms, and the fight closes without stain. What
> cannot speak cannot yield -- cut it down in flight and the guilt is
> entered all the same.

**tTalk** — first talk
> <13>Margins:<7> The scholar rated <9>[t]<7> above the sword.
> Neutrals trade for coin, allies take orders, summoned things are
> commanded by it, and a strong voice demoralizes what a strong arm
> cannot reach. Most of the dungeon has ears.

**tTerrain** — terrain `META(EV_SPECIAL)` / hazard square entered
> <13>Margins:<7> Terrain kills the incurious. The mark <9>[l]<7>
> laid upon any square tells what it costs to stand there, and hazard
> ground bills once for the move and again for every turn spent upon
> it. The floor was read, or the floor was paid.

**tFountain** — `META(POST(EV_ENTER))`, fountain square
> <13>Margins:<7> A fountain wagers on Luck: one d20 and the
> drinker's modifier. High water heals poison, disease, even curses;
> drinking is a fair bet for the fortunate. Dipping an item is
> another matter -- <4>a roll of 1 or 2 raises a wastrilith,<7> a
> water demon of the tenth rank. The scholar's rule: no dipping under
> Luck +2, and a potion of dimension door in hand regardless.

**tForge** — `META(POST(EV_ENTER))`, forge feature
> <13>Margins:<7> A forge is the only ground where metal is made or
> mended: stand upon it and work the Craft skill. The scholar noted
> that smiths outlive swordsmen, and then went below without a
> hammer.

**tCoin** — `META(POST(EV_PICKUP))`, coinage
> <13>Margins:<7> Coin is heavy and the store is dear, yet the
> scholar carried gold. Crafting, alchemy, scribing and brewing all
> consume it; neutral denizens sell for it; a priest's mercy carries
> a price in it. Money buys what looting cannot schedule.

**tMulti** — poll from `META(EV_TURN)`: mid-game level reached
> <13>Margins:<7> On multiclassing the margin is firm. A class is a
> trade, and a second trade is taken late: a level or two of rogue or
> monk near the tenth season buys evasion, saves, and skills. Before
> then, depth in one craft over breadth in two.

**tLast** — `META(POST(EV_DESCEND))`, deep stair
> <13>Margins:<7> The last note in the book, deepest page, smallest
> hand: "Below this line the maps disagree." Nothing follows it.
> Margins are written for whoever comes after. So was this one.
