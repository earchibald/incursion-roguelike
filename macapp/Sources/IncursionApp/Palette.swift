// See the Incursion LICENSE file for copyright information.
//
// The game's sixteen colours, in the engine's index order (BLACK..WHITE,
// inc/Defines.h). Both palettes are transcribed from src/Wlibtcod.cpp:128-165;
// "classic" is RGBValues, "soft" is RGBSofter, and the game's own
// OPT_SOFT_PALETTE option picked between them.

import AppKit

struct Palette {
    let name: String
    let colors: [NSColor]

    private static func rgb(_ r: Int, _ g: Int, _ b: Int) -> NSColor {
        NSColor(srgbRed: CGFloat(r) / 255.0,
                green: CGFloat(g) / 255.0,
                blue: CGFloat(b) / 255.0,
                alpha: 1.0)
    }

    static let classic = Palette(name: "Classic", colors: [
        rgb(0, 0, 0),        // BLACK
        rgb(0, 0, 192),      // BLUE
        rgb(0, 128, 0),      // GREEN
        rgb(0, 128, 128),    // CYAN
        rgb(128, 0, 0),      // RED
        rgb(128, 0, 128),    // PURPLE
        rgb(128, 128, 0),    // BROWN
        rgb(192, 192, 192),  // GREY
        rgb(128, 128, 128),  // SHADOW
        rgb(64, 64, 255),    // AZURE
        rgb(0, 255, 0),      // EMERALD
        rgb(0, 255, 255),    // SKYBLUE
        rgb(255, 0, 0),      // PINK
        rgb(255, 0, 255),    // MAGENTA
        rgb(255, 255, 0),    // YELLOW
        rgb(255, 255, 255),  // WHITE
    ])

    static let soft = Palette(name: "Soft", colors: [
        rgb(0, 0, 0),        // BLACK
        rgb(64, 64, 187),    // BLUE
        rgb(0, 128, 0),      // GREEN
        rgb(0, 128, 128),    // CYAN
        rgb(192, 64, 48),    // RED
        rgb(128, 0, 128),    // PURPLE
        rgb(128, 128, 0),    // BROWN
        rgb(192, 192, 192),  // GREY
        rgb(128, 128, 128),  // SHADOW
        rgb(85, 85, 230),    // AZURE
        rgb(0, 230, 0),      // EMERALD
        rgb(0, 230, 230),    // SKYBLUE
        rgb(230, 0, 0),      // PINK
        rgb(230, 0, 230),    // MAGENTA
        rgb(230, 230, 0),    // YELLOW
        rgb(230, 230, 230),  // WHITE
    ])
}
