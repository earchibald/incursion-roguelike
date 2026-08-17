// See the Incursion LICENSE file for copyright information.
//
// Glyph id -> Unicode. The game's cells carry either a literal CP437 code
// (ids below 256) or a semantic GLYPH_* id (256..375, inc/Defines.h). The
// SDL build drew both through a CP437-layout PNG font; this table renders
// the same visual language with real vector glyphs. The GLYPH_* -> CP437
// choices are transcribed from glyphchar_to_char (src/Wlibtcod.cpp:518),
// so the native app looks like the game always looked, only crisp.
//
// The four CUSTOM face graphics in the old PNG (ids 131-133 in the font)
// have no Unicode form and were of dubious provenance anyway
// (docs/reference.md:8); those races draw the standard CP437 accented
// letters instead, which is the same language the townsfolk and demons
// already speak (i-umlaut, u-grave and friends).

enum GlyphMap {

    // Standard CP437 -> Unicode, all 256 cells.
    private static let cp437: [Character] = [
        " ", "☺", "☻", "♥", "♦", "♣", "♠", "•", "◘", "○", "◙", "♂", "♀", "♪", "♫", "☼",
        "►", "◄", "↕", "‼", "¶", "§", "▬", "↨", "↑", "↓", "→", "←", "∟", "↔", "▲", "▼",
        " ", "!", "\"", "#", "$", "%", "&", "'", "(", ")", "*", "+", ",", "-", ".", "/",
        "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", ":", ";", "<", "=", ">", "?",
        "@", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O",
        "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "[", "\\", "]", "^", "_",
        "`", "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o",
        "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z", "{", "|", "}", "~", "⌂",
        "Ç", "ü", "é", "â", "ä", "à", "å", "ç", "ê", "ë", "è", "ï", "î", "ì", "Ä", "Å",
        "É", "æ", "Æ", "ô", "ö", "ò", "û", "ù", "ÿ", "Ö", "Ü", "¢", "£", "¥", "₧", "ƒ",
        "á", "í", "ó", "ú", "ñ", "Ñ", "ª", "º", "¿", "⌐", "¬", "½", "¼", "¡", "«", "»",
        "░", "▒", "▓", "│", "┤", "╡", "╢", "╖", "╕", "╣", "║", "╗", "╝", "╜", "╛", "┐",
        "└", "┴", "┬", "├", "─", "┼", "╞", "╟", "╚", "╔", "╩", "╦", "╠", "═", "╬", "╧",
        "╨", "╤", "╥", "╙", "╘", "╒", "╓", "╫", "╪", "┘", "┌", "█", "▄", "▌", "▐", "▀",
        "α", "ß", "Γ", "π", "Σ", "σ", "µ", "τ", "Φ", "Θ", "Ω", "δ", "∞", "φ", "ε", "∩",
        "≡", "±", "≥", "≤", "⌠", "⌡", "÷", "≈", "°", "∙", "·", "√", "ⁿ", "²", "■", " ",
    ]

    // GLYPH_* id -> the CP437 cell the SDL build drew it with.
    // Ids and choices from inc/Defines.h:4194-4330 and src/Wlibtcod.cpp:518.
    private static let semantic: [UInt32: Int] = [
        256: 6,    // PERSON
        257: 197,  // BULK
        258: 247,  // WATER
        259: 126,  // FOG '~'
        260: 254,  // ICE
        261: 35,   // WEB '#'
        262: 247,  // LAVA
        263: 15,   // BLAST
        264: 177,  // WALL
        265: 176,  // ROCK
        266: 219,  // SOLID
        267: 9,    // PILLAR1
        268: 9,    // VIEWPOINT
        269: 239,  // GRAVE
        270: 216,  // SHELF
        271: 15,   // PILLAR2
        272: 173,  // POTION
        273: 168,  // SCROLL
        275: 251,  // WEAPON
        276: 124,  // ROD '|'
        277: 47,   // STAFF '/'
        278: 45,   // WAND '-'
        279: 37,   // FOOD '%'
        280: 37,   // CORPSE '%'
        281: 254,  // BOOK
        282: 125,  // TORCH '}'
        283: 228,  // LARMOUR
        284: 228,  // MARMOUR
        285: 228,  // HARMOUR
        286: 93,   // SHIELD ']'
        287: 229,  // GAUNTLETS
        288: 155,  // HELMET
        289: 155,  // HEADBAND
        290: 224,  // BOOTS
        291: 224,  // BRACERS
        292: 226,  // GIRDLE
        293: 20,   // CLOTHES
        294: 127,  // CONTAIN
        295: 94,   // CROWN '^'
        296: 240,  // DUST
        297: 240,  // DECK
        298: 235,  // RING
        299: 11,   // AMULET
        300: 156,  // FIGURE
        301: 38,   // HORN '&'
        302: 236,  // EYES
        303: 34,   // HERB '"'
        304: 227,  // MUSH
        305: 4,    // GEM
        306: 36,   // COIN '$'
        307: 234,  // TOOL
        308: 40,   // SWORD '('
        309: 41,   // BOW ')'
        310: 38,   // JUNK '&'
        311: 127,  // CHEST
        312: 6,    // CLOAK
        313: 5,    // STATUE
        314: 42,   // PILE '*'
        315: 146,  // MULTI
        316: 56,   // ALTAR '8'
        317: 244,  // FOUNTAIN
        318: 190,  // THRONE
        319: 237,  // SYMBOL
        320: 34,   // HEDGE '"'
        321: 58,   // RUBBLE ':'
        322: 61,   // BRIDGE '='
        323: 250,  // FLOOR
        324: 249,  // FLOOR2
        325: 179,  // VDOOR
        326: 196,  // HDOOR
        327: 43,   // ODOOR '+'
        328: 241,  // BDOOR
        329: 48,   // PIT '0'
        330: 240,  // PORTAL
        331: 21,   // STORE
        332: 20,   // GUILD
        333: 186,  // STORE_VWALL
        334: 205,  // STORE_HWALL
        335: 219,  // STORE_CORNER
        336: 60,   // USTAIRS '<'
        337: 62,   // DSTAIRS '>'
        338: 157,  // TREE
        339: 251,  // CHECK
        340: 254,  // FURNATURE
        341: 63,   // UNKNOWN '?'
        342: 38,   // TRASH '&'
        343: 38,   // BONES '&'
        344: 251,  // CHECKMARK
        345: 232,  // TRAP
        346: 246,  // DISARMED
        347: 24,   // ARROW
        348: 24,   // ARROW_UP
        349: 25,   // ARROW_DOWN
        350: 26,   // ARROW_RIGHT
        351: 27,   // ARROW_LEFT
        352: 140,  // GUARD
        353: 139,  // TOWNIE
        354: 141,  // TOWNSCUM
        355: 105,  // TOWN_NPC 'i'
        356: 151,  // LDEMON
        357: 154,  // GDEMON
        358: 148,  // LDEVIL
        359: 153,  // GDEVIL
        360: 152,  // FIEND
        361: 64,   // PLAYER '@'
        362: 1,    // HUMAN
        363: 132,  // ELF (custom face in the PNG; a-umlaut here)
        364: 131,  // DWARF (custom face; a-circumflex here)
        365: 133,  // GNOME (custom face; a-grave here)
        366: 133,  // HOBBIT (custom face; a-grave here)
        367: 179,  // VLINE
        368: 196,  // HLINE
        369: 246,  // DIVIDE
        370: 247,  // APPROXIMATELY
        371: 254,  // BLACK_SQUARE
        372: 233,  // SUMMONING_CIRCLE
        373: 17,   // POINTER_LEFT
        374: 16,   // POINTER_RIGHT
        375: 32,   // UNSEEN ' '
    ]

    static func character(for id: UInt32) -> Character {
        if id < 256 {
            return cp437[Int(id)]
        }
        if let cp = semantic[id] {
            return cp437[cp]
        }
        return "?"
    }
}
