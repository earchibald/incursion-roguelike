---
title: Known Issues and Workarounds
slug: known-issues-and-workarounds
order: 40
source: http://incursion.wikidot.com/known-issues-and-workarounds
attribution: Incursion Wiki contributors
license: CC BY-SA 3.0
license_url: https://creativecommons.org/licenses/by-sa/3.0/
retrieved: 2026-08-17
modifications: converted from the page's HTML to Markdown; text unchanged
---
# Linux

**Issue**: When using the windowed (non-fullscreen) mode and switching from the Incursion window to another and then back again, the game will sometimes act like you're holding down the Alt key, and pressing Esc won't bring up the system menu.

**Workaround**: Press and release the Alt key and things should return to normal.

# User Interface

**Issue**: If you target the "talk" command at a square with two or more monsters and then accidentally select an object (including things like stairs or a tree) then the game will crash.

**Workaround**: None - Be very careful to only select a monster to talk to.

---

**Issue**: Turning on the Roguelike-keyset option changes the keys used for things besides movement.

**Workaround**:

- To learn spells from the Display Character screen, use Ctrl-L instead of 'l'.
- To display the list of known items from the Display Character screen, use 'i' or Ctrl-K instead of 'k'.
- To switch to select-a-location targeting/looking mode use Ctrl-L instead of 'l'.

---

**Issue**: The auto-loot macro (F8 key) doesn't work on chests.

**Workaround**:

- Set the "Auto-open Chest" option to YES (found under Input Options). Be warned that this dumps all of the chest items onto the floor.
- Attempt to pick up the chest ('g'), answer 'y' to "Open a container?", transfer items from the chest to your belt or shoulders slots, exit the chest using ESC, and then transfer the items to your pack. Be warned that monsters can act and attack you while you're taking items out of the chest.

---

**Issue**: The "automatically use a Wand of Opening on locked chests" option doesn't work.

**Workaround**: Manually zap the wand while standing next to the chest and aim at the chest. Note that the wand's beam angers neutral monsters even though it's harmless. (More than one chest can be opened with a single wand charge this way if you line them up in a row or put them all on the same square)

---

**Issue**: Holy symbols and shields with holy symbols will be automatically picked up.

**Workaround**: None.

# Alignment issues

**Issue**: Attacking a frightened hostile sapient monster which can't speak is an evil act even though it's impossible to offer it terms. This includes:

- Druids, mages and lycanthropes which have polymorphed into an animal.
- Elementals.
- 'K' monsters (dust devils, vampiric mists, etc), except for azers and azerkins.
- Blazing terrors. ('c')
- Cave lions. ('c')
- Kreshnar. ('c')
- Spectral panthers. ('c')
- Tabaxi. ('c')
- Centaurs. ('q')
- Nightmares. ('q')
- Ettercaps. ('s')
- Gricks. ('w')
- Myconids. ('F')
- Cedar wretch ('P')
- Dark tree ('P')
- Tendriculous ('P')
- Winged snakes. ('R')

**Workaround**: A Knowledge (Nature) skill of 10 or more will let you talk to 'F' and 'P' sapient monsters (except for cedar wretches), but otherwise there are no workarounds.

---

**Issue**: Clockwork unicorns are hostile, yet killing them is an evil act.

**Workaround**: None.

---

**Issue**: Normally evil monsters (like goblins) which get the paladin template are still hostile to good characters, yet killing them is an evil act. (They are both evil and good at the same time, plus lawful and chaotic at the same time if they're normally chaotic)

**Workaround**: None.

---

**Issue**: Spells which affect an area (/Fireball/, /Faerie Fire/, /Dispel Magic/, etc) which don't travel with the player (like /Spook/, /Globe of Shadow/, etc) will desecrate graves. This doesn't include the various wall spells like /Wall of Fog/.

**Workaround**: None, besides not using those spells around graves.

---

**Issue**: Triggering an area affect trap desecrate graves and counts against you as an evil act.

**Workaround**: None.

# Dungeon

**Issue**: The very tough monsters in vaults aren't generated in stasis and can thus exit the vault and come after you.

**Workaround**: Stay away from the area around the vault, if possible. If you have the /Wizard Lock/ spell then casting that on the vault doors can help.

---

**Issue**: The first level can be generated with damaging terrain that blocks off all paths to the second level.

**Workaround**: Try using the three guaranteed Dimension Door potions to get around it. Failing that, just trying bulling your way through the damaging terrain, and if that kills you reincarnate.

---

**Issue**: The bottom level can be generated with chasms, and falling into one crashes the game.

**Workaround**: Stay away from the chasms on the bottom level.

# Monsters

**Issue**: After killing a hostile monster nearby neutrals will sweep in and start picking up your loot. The same thing happens if you drop an item because of hitting a shrinking trap, if you drop an item on an altar to be blessed, or if you drop your pack to switch from one backpack to another.

**Workaround**:

- For monsters picking up your loot, you can usually buy it back from them by bartering with them ('t'alk and then 'B'arter).
- When switching backpacks, make sure that no monster, hostile *or* neutral, are nearby.
- In all cases you can attack and kill a neutral monster without it being an evil act so long as the monster isn't of good alignment and you give it a chance to surrender first; if it surrenders you can attack it again without having to offer it terms a second time. Note that some gods will have other restrictions on who you can't attack.

---

**Issue**: Neutral monster will often be riding hostile mounts which will kick you whenever you step next to them.

**Workaround**: Either avoid that monster or kill it (see note above on killing neutrals not usually being an evil act).

# Items

**Issue**: Divine aid uncursing an item you're carrying will crash the game.

**Workaround**: Try not to keep cursed (or possibly cursed) items in your inventory if you're going to be asking for divine aid. You can get your god to get rid an item's cursed status by dropping the item on an altar to that god, praying, and selecting 'bless item'.

---

**Issue**: Identifying one amulet, bracer, magical staff or pair of lenses won't identify the rest of the same kind, and they won't show up in the known items list.

**Workaround**: Manually keep track of those types of items in a text file.

---

**Issue**: Some potions are simply shown as "a potion" when unidentified rather than having a colour or description. After identifying them potions of the same type will still be shown as "a potion", and they won't be listed among the known items.

**Workaround**: None.

---

**Issue**: Backpacks will sometimes not hold as much weight or as many items as their descriptions say they will.

**Workaround**: Get another backpack of the same type and switch your items to the new pack.

---

**Issue**: A wand which is identified via praying to a god won't show the number of charges it has, and normal identification won't let you re-identify it to find that out.

**Workaround**: Read a Scroll of *Identify* while the wand is in your inventory.

---

**Issue**: Special items like quickblades are mildly damaged but can't be repaired or fixed.

**Workaround**: They aren't actually damaged; examining them in detail will show that they actually have more than their maximum hit points.

---

**Issue**: Items that are bought/bartered from a monster won't stack with other items of the same type.

**Workaround**: Drop and pick back up the bartered item.

# Spells

**Issue**: All area-affect spells (/Fireball/, /Dispel Magic/, etc) which don't travel with the player (/Globe of Shadow/, /Spook/, etc) anger neutral monsters and desecrate graves.

**Workaround**: Don't use them where this might be a problem.

---

**Issue**: If you gain a spell via /Steal Magic/ then the game will freeze the next time you rest for the night.

**Workaround**: None.

---

**Issue**: If a volumetric blast spell (including /Fireball/, /Spirit Net/, and /Force Shapechange/) don't have enough room to expand completely the game will freeze.

**Workaround**: Don't use them where this might be a problem.

---

**Issue**: Casting /Fireball/ or /Ice Storm/ on mud which has been created by the /Transmute Rock to Mud/ spell will crash the game.

**Workaround**: Don't cast those spells on magically created mud.

---

**Issue**: The /Magic Missile/ spell won't work on huge monsters (monsters occupying more than one square).

**Workaround**: Use some other attack spell on them.

---

**Issue**: /Chromatic Orb/ doesn't work on huge monsters (monsters occupying more than one square) if the monster was targeted.

**Workaround**: Fire the spell in a compass direction rather than targeting the monster.

---

**Issue**: The /Wall of Doors/ spell produces broken doors.

**Workaround**: None.

---

**Issue**: Using /Gaze Reflection/ against a bodak's death gaze crashes the game.

**Workaround**: None.

# Combat

**Issue**: If you use trip with a reach weapon (like whip) and succeed at tripping the creature, you automatically make an attack of opportunity to both that creature, and yourself.

**Workaround**: Keep your health at high level , don't use trip on reach weapons, keep your defence high.

# Feats and Special Abilities

**Issue**: If you get to choose a feat from gaining a level, you'll be unable to choose any feat that is granted to you through an equipped item.

**Workaround**: Remove any such items before gaining a level.

---

**Issue**: If you read a Libram of Hidden Secrets while wearing an item which grants the perception special ability the Libram would have granted grant, the Libram will skip that ability and move onto the next one.

**Workaround**: Remove any such items before reading the Libram.

---

**Issue**: Holy Summonings by a Priest/Alienist (alienist level >=2) do not get the Pseudonatural template, unlike in the description of the Alienist prestige class.

**Workaround**: Probably as designed. Holy Summonings conjure Outsiders: it doesn't make sense for outsiders from the higher or lower planes to be pseudonatural. Druid/Alienist combos are semi-viable since Summon Nature's Ally produces psuedonaturals as described, but alienist levels do not improve your Wild shape or animal companion.
