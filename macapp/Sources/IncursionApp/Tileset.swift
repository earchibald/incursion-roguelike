// See the Incursion LICENSE file for copyright information.
//
// A tileset is a named partial map from semantic glyph id (256..375,
// inc/Defines.h) to one display character. Ids below 256 are literal CP437
// text shared with menus and messages, so no tileset may touch them; any id
// a set does not map falls back to GlyphMap, which is the Classic look.
//
// Color is deliberately not part of a tileset: the engine's foreground
// color carries game meaning (potion colors, monster tints), and the
// Classic/Soft palette toggle already covers color taste.

import Foundation

struct Tileset: Equatable {
    var name: String
    var glyphs: [UInt32: Character]

    /// Sets compare by what they draw, not what they are called, so the
    /// menu checkmark survives a rename and dies on the first edit.
    static func == (a: Tileset, b: Tileset) -> Bool {
        a.glyphs == b.glyphs
    }

    // MARK: JSON

    /// On-disk form: {"name": "...", "glyphs": {"264": "█", ...}}. String
    /// keys, because Swift encodes non-Int dictionary keys as a flat array.
    private struct DTO: Codable {
        var name: String
        var glyphs: [String: String]
    }

    func jsonData() throws -> Data {
        var out: [String: String] = [:]
        for (id, ch) in glyphs { out[String(id)] = String(ch) }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try enc.encode(DTO(name: name, glyphs: out))
    }

    /// Unknown ids are dropped and long values keep their first character,
    /// so a file from a newer build still loads as much as it can.
    init(jsonData: Data) throws {
        let dto = try JSONDecoder().decode(DTO.self, from: jsonData)
        name = dto.name
        glyphs = [:]
        for (key, value) in dto.glyphs {
            guard let id = UInt32(key), GlyphCatalog.names[id] != nil,
                  let ch = value.first else { continue }
            glyphs[id] = ch
        }
    }

    init(name: String, glyphs: [UInt32: Character]) {
        self.name = name
        self.glyphs = glyphs
    }

    // MARK: built-in sets

    /// The Classic set is GlyphMap itself: no overrides.
    static let classic = Tileset(name: "Classic", glyphs: [:])

    /// Pure printable ASCII in the classic roguelike voice: walls #,
    /// floor ., water ~, trap ^, humanoids @, demons &.
    static let heritage = Tileset(name: "Heritage ASCII", glyphs: [
        256: "@",   // Person
        257: "+",   // Bulk
        258: "~",   // Water
        259: ";",   // Fog
        260: "_",   // Ice
        261: "\"",  // Web
        262: "~",   // Lava
        263: "*",   // Blast
        264: "#",   // Wall
        265: "#",   // Rock
        266: "#",   // Solid
        267: "I",   // Pillar
        268: "o",   // Viewpoint
        269: "+",   // Grave
        270: "=",   // Shelf
        271: "I",   // Broken Pillar
        272: "!",   // Potion
        273: "?",   // Scroll
        275: ")",   // Weapon
        281: "+",   // Book
        283: "[", 284: "[", 285: "[",  // Armour
        287: "[",   // Gauntlets
        288: "[",   // Helmet
        289: "[",   // Headband
        290: "[",   // Boots
        291: "[",   // Bracers
        292: "[",   // Girdle
        293: "[",   // Clothes
        294: "(",   // Container
        296: ",",   // Dust
        297: ",",   // Deck
        298: "=",   // Ring
        299: "\"",  // Amulet
        300: "'",   // Figurine
        302: "\"",  // Eyes
        304: ",",   // Mushroom
        305: "*",   // Gem
        307: "(",   // Tool
        311: "(",   // Chest
        312: "(",   // Cloak
        313: "'",   // Statue
        315: "&",   // Multiple Items
        316: "_",   // Altar
        317: "{",   // Fountain
        318: "\\",  // Throne
        319: "'",   // Symbol
        323: ".",   // Floor
        324: ",",   // Floor (alternate)
        325: "|",   // Door (vertical)
        326: "-",   // Door (horizontal)
        328: "'",   // Broken Door
        330: "O",   // Portal
        331: "$",   // Store
        332: "G",   // Guild
        333: "|",   // Store Wall (vertical)
        334: "-",   // Store Wall (horizontal)
        335: "+",   // Store Corner
        338: "T",   // Tree
        339: "x",   // Check
        340: "\\",  // Furniture
        344: "x",   // Checkmark
        345: "^",   // Trap
        346: "^",   // Disarmed Trap
        347: "^",   // Arrow
        348: "^",   // Arrow Up
        349: "v",   // Arrow Down
        350: ">",   // Arrow Right
        351: "<",   // Arrow Left
        352: "@",   // Guard
        353: "@",   // Townsperson
        354: "@",   // Town Rabble
        356: "&", 357: "&", 358: "&", 359: "&", 360: "&",  // Fiends
        362: "@",   // Human
        363: "@",   // Elf
        364: "@",   // Dwarf
        365: "@",   // Gnome
        366: "@",   // Hobbit
        367: "|",   // Vertical Line
        368: "-",   // Horizontal Line
        369: "/",   // Divider
        370: "~",   // Approximately
        371: "#",   // Black Square
        372: "o",   // Summoning Circle
        373: "<",   // Pointer Left
        374: ">",   // Pointer Right
    ])

    /// Clean geometric Unicode: heavy walls, fine dots, open shapes.
    static let crisp = Tileset(name: "Crisp", glyphs: [
        256: "☺",   // Person
        259: "░",   // Fog
        260: "▪",   // Ice
        261: "╳",   // Web
        263: "✶",   // Blast
        264: "█",   // Wall
        265: "▓",   // Rock
        267: "●",   // Pillar
        271: "○",   // Broken Pillar
        275: "†",   // Weapon
        281: "▤",   // Book
        298: "∘",   // Ring
        329: "○",   // Pit
        330: "◎",   // Portal
        338: "♣",   // Tree
        340: "▬",   // Furniture
        345: "▲",   // Trap
        346: "△",   // Disarmed Trap
        362: "☺",   // Human
        372: "⊕",   // Summoning Circle
    ])

    /// Decorative Unicode where it reads well; chess royalty for the
    /// regalia, quilted walls, a starburst for ice.
    static let ornate = Tileset(name: "Ornate", glyphs: [
        256: "☻",   // Person
        258: "≋",   // Water
        260: "✻",   // Ice
        261: "✳",   // Web
        263: "✺",   // Blast
        264: "▦",   // Wall
        265: "▨",   // Rock
        267: "◉",   // Pillar
        269: "⊓",   // Grave
        271: "☉",   // Broken Pillar
        275: "‡",   // Weapon
        281: "≣",   // Book
        295: "♚",   // Crown
        298: "◦",   // Ring
        305: "❖",   // Gem
        313: "♜",   // Statue
        318: "♛",   // Throne
        324: "∘",   // Floor (alternate)
        330: "◈",   // Portal
        338: "♠",   // Tree
        362: "☻",   // Human
        372: "⊛",   // Summoning Circle
    ])

    static let builtins: [Tileset] = [classic, heritage, crisp, ornate]
}

/// The editor's vocabulary: a name and a grouping for every editable id.
/// Names follow inc/Defines.h GLYPH_* with spelling a player can read.
enum GlyphCatalog {

    enum Category: String, CaseIterable {
        case terrain = "Terrain"
        case dungeon = "Dungeon Features"
        case items = "Items"
        case creatures = "Creatures"
        case interface = "Interface and Effects"
    }

    struct Entry: Identifiable {
        let id: UInt32
        let name: String
        let category: Category
    }

    static let entries: [Entry] = [
        // Terrain
        Entry(id: 258, name: "Water", category: .terrain),
        Entry(id: 259, name: "Fog", category: .terrain),
        Entry(id: 260, name: "Ice", category: .terrain),
        Entry(id: 262, name: "Lava", category: .terrain),
        Entry(id: 261, name: "Web", category: .terrain),
        Entry(id: 264, name: "Wall", category: .terrain),
        Entry(id: 265, name: "Rock", category: .terrain),
        Entry(id: 266, name: "Solid Rock", category: .terrain),
        Entry(id: 323, name: "Floor", category: .terrain),
        Entry(id: 324, name: "Floor (alternate)", category: .terrain),
        Entry(id: 338, name: "Tree", category: .terrain),
        Entry(id: 320, name: "Hedge", category: .terrain),
        Entry(id: 321, name: "Rubble", category: .terrain),
        Entry(id: 322, name: "Bridge", category: .terrain),
        // Dungeon features
        Entry(id: 267, name: "Pillar", category: .dungeon),
        Entry(id: 271, name: "Broken Pillar", category: .dungeon),
        Entry(id: 268, name: "Viewpoint", category: .dungeon),
        Entry(id: 269, name: "Grave", category: .dungeon),
        Entry(id: 270, name: "Shelf", category: .dungeon),
        Entry(id: 313, name: "Statue", category: .dungeon),
        Entry(id: 316, name: "Altar", category: .dungeon),
        Entry(id: 317, name: "Fountain", category: .dungeon),
        Entry(id: 318, name: "Throne", category: .dungeon),
        Entry(id: 319, name: "Symbol", category: .dungeon),
        Entry(id: 340, name: "Furniture", category: .dungeon),
        Entry(id: 325, name: "Door (vertical)", category: .dungeon),
        Entry(id: 326, name: "Door (horizontal)", category: .dungeon),
        Entry(id: 327, name: "Open Door", category: .dungeon),
        Entry(id: 328, name: "Broken Door", category: .dungeon),
        Entry(id: 329, name: "Pit", category: .dungeon),
        Entry(id: 330, name: "Portal", category: .dungeon),
        Entry(id: 336, name: "Stairs Up", category: .dungeon),
        Entry(id: 337, name: "Stairs Down", category: .dungeon),
        Entry(id: 331, name: "Store", category: .dungeon),
        Entry(id: 332, name: "Guild", category: .dungeon),
        Entry(id: 333, name: "Store Wall (vertical)", category: .dungeon),
        Entry(id: 334, name: "Store Wall (horizontal)", category: .dungeon),
        Entry(id: 335, name: "Store Corner", category: .dungeon),
        Entry(id: 345, name: "Trap", category: .dungeon),
        Entry(id: 346, name: "Disarmed Trap", category: .dungeon),
        Entry(id: 372, name: "Summoning Circle", category: .dungeon),
        // Items
        Entry(id: 272, name: "Potion", category: .items),
        Entry(id: 273, name: "Scroll", category: .items),
        Entry(id: 281, name: "Book", category: .items),
        Entry(id: 275, name: "Weapon", category: .items),
        Entry(id: 308, name: "Sword", category: .items),
        Entry(id: 309, name: "Bow", category: .items),
        Entry(id: 276, name: "Rod", category: .items),
        Entry(id: 277, name: "Staff", category: .items),
        Entry(id: 278, name: "Wand", category: .items),
        Entry(id: 279, name: "Food", category: .items),
        Entry(id: 280, name: "Corpse", category: .items),
        Entry(id: 282, name: "Torch", category: .items),
        Entry(id: 283, name: "Light Armour", category: .items),
        Entry(id: 284, name: "Medium Armour", category: .items),
        Entry(id: 285, name: "Heavy Armour", category: .items),
        Entry(id: 286, name: "Shield", category: .items),
        Entry(id: 287, name: "Gauntlets", category: .items),
        Entry(id: 288, name: "Helmet", category: .items),
        Entry(id: 289, name: "Headband", category: .items),
        Entry(id: 290, name: "Boots", category: .items),
        Entry(id: 291, name: "Bracers", category: .items),
        Entry(id: 292, name: "Girdle", category: .items),
        Entry(id: 293, name: "Clothes", category: .items),
        Entry(id: 312, name: "Cloak", category: .items),
        Entry(id: 295, name: "Crown", category: .items),
        Entry(id: 298, name: "Ring", category: .items),
        Entry(id: 299, name: "Amulet", category: .items),
        Entry(id: 305, name: "Gem", category: .items),
        Entry(id: 306, name: "Coin", category: .items),
        Entry(id: 294, name: "Container", category: .items),
        Entry(id: 311, name: "Chest", category: .items),
        Entry(id: 296, name: "Dust", category: .items),
        Entry(id: 297, name: "Deck", category: .items),
        Entry(id: 300, name: "Figurine", category: .items),
        Entry(id: 301, name: "Horn", category: .items),
        Entry(id: 302, name: "Eyes", category: .items),
        Entry(id: 303, name: "Herb", category: .items),
        Entry(id: 304, name: "Mushroom", category: .items),
        Entry(id: 307, name: "Tool", category: .items),
        Entry(id: 310, name: "Junk", category: .items),
        Entry(id: 342, name: "Trash", category: .items),
        Entry(id: 343, name: "Bones", category: .items),
        Entry(id: 314, name: "Pile", category: .items),
        Entry(id: 315, name: "Multiple Items", category: .items),
        // Creatures
        Entry(id: 361, name: "Player", category: .creatures),
        Entry(id: 256, name: "Person", category: .creatures),
        Entry(id: 362, name: "Human", category: .creatures),
        Entry(id: 363, name: "Elf", category: .creatures),
        Entry(id: 364, name: "Dwarf", category: .creatures),
        Entry(id: 365, name: "Gnome", category: .creatures),
        Entry(id: 366, name: "Hobbit", category: .creatures),
        Entry(id: 352, name: "Guard", category: .creatures),
        Entry(id: 353, name: "Townsperson", category: .creatures),
        Entry(id: 354, name: "Town Rabble", category: .creatures),
        Entry(id: 355, name: "Town NPC", category: .creatures),
        Entry(id: 356, name: "Lesser Demon", category: .creatures),
        Entry(id: 357, name: "Greater Demon", category: .creatures),
        Entry(id: 358, name: "Lesser Devil", category: .creatures),
        Entry(id: 359, name: "Greater Devil", category: .creatures),
        Entry(id: 360, name: "Fiend", category: .creatures),
        // Interface and effects
        Entry(id: 257, name: "Bulk", category: .interface),
        Entry(id: 263, name: "Blast", category: .interface),
        Entry(id: 339, name: "Check", category: .interface),
        Entry(id: 344, name: "Checkmark", category: .interface),
        Entry(id: 341, name: "Unknown", category: .interface),
        Entry(id: 347, name: "Arrow", category: .interface),
        Entry(id: 348, name: "Arrow Up", category: .interface),
        Entry(id: 349, name: "Arrow Down", category: .interface),
        Entry(id: 350, name: "Arrow Right", category: .interface),
        Entry(id: 351, name: "Arrow Left", category: .interface),
        Entry(id: 373, name: "Pointer Left", category: .interface),
        Entry(id: 374, name: "Pointer Right", category: .interface),
        Entry(id: 367, name: "Vertical Line", category: .interface),
        Entry(id: 368, name: "Horizontal Line", category: .interface),
        Entry(id: 369, name: "Divider", category: .interface),
        Entry(id: 370, name: "Approximately", category: .interface),
        Entry(id: 371, name: "Black Square", category: .interface),
        Entry(id: 375, name: "Unseen", category: .interface),
    ]

    static let names: [UInt32: String] =
        Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0.name) })

    static func entries(in category: Category) -> [Entry] {
        entries.filter { $0.category == category }
    }
}
