// See the Incursion LICENSE file for copyright information.
//
// The one view: draws the engine's latest frame as a character grid and
// turns AppKit events into engine events. Every character is drawn at its
// own computed cell origin -- never as a laid-out string -- so symbol
// glyphs with odd advances can never shear the grid.

import AppKit

final class GridView: NSView {
    private var frame_: Frame?
    private var palette = Palette.classic

    private(set) var font: NSFont
    private(set) var cellSize: CGSize = .zero

    /// Margin between the window edge and the outermost cells. The window's
    /// rounded corners clip anything drawn flush against the edge (bead
    /// inc-d8s), so the grid is drawn inset and the margin shows background.
    let contentInset: CGFloat = 6

    // KY_* codes, computed as inc/Term.h computes them (200 + Dir).
    private static let kyUp: Int32 = 200, kyDown: Int32 = 201
    private static let kyRight: Int32 = 202, kyLeft: Int32 = 203
    private static let kyPgUp: Int32 = 204, kyHome: Int32 = 205
    private static let kyPgDn: Int32 = 206, kyEnd: Int32 = 207
    private static let kyBackspace: Int32 = 213, kyF1: Int32 = 214
    private static let modShift: Int32 = 1, modControl: Int32 = 2
    private static let modAlt: Int32 = 4

    static func preferredFont() -> NSFont {
        let d = UserDefaults.standard
        let size = d.double(forKey: "fontSize")
        let pt = size > 0 ? size : 14
        if let family = d.string(forKey: "fontFamily"),
           let f = NSFont(name: family, size: pt), f.isFixedPitch {
            return f
        }
        return NSFont.monospacedSystemFont(ofSize: pt, weight: .regular)
    }

    override init(frame frameRect: NSRect) {
        font = GridView.preferredFont()
        super.init(frame: frameRect)
        recomputeCellSize()
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    var gridSize: (w: Int, h: Int) {
        guard let f = frame_ else { return (80, 48) }
        return (f.width, f.height)
    }

    func setFont(size: CGFloat) {
        UserDefaults.standard.set(size, forKey: "fontSize")
        font = GridView.preferredFont()
        recomputeCellSize()
        needsDisplay = true
    }

    func setFontFamily(_ family: String?) {
        if let family {
            UserDefaults.standard.set(family, forKey: "fontFamily")
        } else {
            UserDefaults.standard.removeObject(forKey: "fontFamily")
        }
        font = GridView.preferredFont()
        recomputeCellSize()
        needsDisplay = true
    }

    func setPalette(_ p: Palette) {
        palette = p
        needsDisplay = true
    }

    private func recomputeCellSize() {
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let advance = ("M" as NSString).size(withAttributes: attrs).width
        let height = ceil(font.ascender - font.descender + font.leading)
        cellSize = CGSize(width: ceil(advance), height: height)
    }

    func refresh() {
        frame_ = EngineHost.shared.currentFrame()
        needsDisplay = true
    }

    // MARK: drawing

    override func draw(_ dirtyRect: NSRect) {
        palette.colors[0].setFill()
        bounds.fill()

        guard let f = frame_ else { return }
        let cw = cellSize.width, ch = cellSize.height
        NSGraphicsContext.current?.cgContext
            .translateBy(x: contentInset, y: contentInset)

        // Backgrounds first, in runs of equal colour per row.
        for y in 0..<f.height {
            var x = 0
            while x < f.width {
                let bg = Int((f.cells[y * f.width + x] >> 16) & 0xF)
                var x2 = x + 1
                while x2 < f.width,
                      Int((f.cells[y * f.width + x2] >> 16) & 0xF) == bg {
                    x2 += 1
                }
                if bg != 0 {
                    palette.colors[bg].setFill()
                    NSRect(x: CGFloat(x) * cw, y: CGFloat(y) * ch,
                           width: CGFloat(x2 - x) * cw, height: ch).fill()
                }
                x = x2
            }
        }

        // Characters, one draw per non-blank cell at its exact origin.
        for y in 0..<f.height {
            for x in 0..<f.width {
                let cell = f.cells[y * f.width + x]
                let id = cell & 0xFFF
                let c = TilesetStore.shared.character(for: id)
                if c == " " { continue }
                let fg = Int((cell >> 12) & 0xF)
                let s = String(c) as NSString
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: palette.colors[fg],
                ]
                let w = s.size(withAttributes: attrs).width
                let origin = NSPoint(
                    x: CGFloat(x) * cw + (cw - w) / 2,
                    y: CGFloat(y) * ch)
                s.draw(at: origin, withAttributes: attrs)
            }
        }

        if f.cursorX >= 0, f.cursorY >= 0,
           f.cursorX < f.width, f.cursorY < f.height {
            palette.colors[15].withAlphaComponent(0.35).setFill()
            NSRect(x: CGFloat(f.cursorX) * cw, y: CGFloat(f.cursorY) * ch,
                   width: cw, height: ch).fill()
        }
    }

    // MARK: input

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags
        var mods: Int32 = 0
        if flags.contains(.option) { mods |= Self.modAlt }
        if flags.contains(.control) { mods |= Self.modControl }

        if let special = event.specialKey {
            var ch: Int32? = nil
            switch special {
            case .upArrow: ch = Self.kyUp
            case .downArrow: ch = Self.kyDown
            case .leftArrow: ch = Self.kyLeft
            case .rightArrow: ch = Self.kyRight
            case .pageUp: ch = Self.kyPgUp
            case .pageDown: ch = Self.kyPgDn
            case .home: ch = Self.kyHome
            case .end: ch = Self.kyEnd
            case .delete, .backspace, .deleteForward: ch = Self.kyBackspace
            case .carriageReturn, .enter: ch = 13
            case .tab: ch = 9
            default:
                if let n = special.functionKeyN {
                    ch = Self.kyF1 + Int32(n - 1)
                }
            }
            if let ch {
                // Modifiers pass through unchanged: the keysets carry real
                // SHIFT+arrow and ALT+arrow bindings (look and map-pan),
                // and no keyset has a CONTROL+arrow entry, so inventing one
                // would fall through to raw codes that alias KY_CMD_ESCAPE
                // and friends. Ctrl+direction (move without attacking)
                // stays keyboard-unreachable on macOS -- bead inc-9df.1.
                if flags.contains(.shift) { mods |= Self.modShift }
                EngineHost.shared.pushKey(ch, mods: mods)
                return
            }
        }

        guard let chars = event.charactersIgnoringModifiers,
              let scalar = chars.unicodeScalars.first else { return }

        if scalar.value == 27 {
            EngineHost.shared.pushKey(27, mods: mods)
            return
        }
        if scalar.value == 13 || scalar.value == 3 {
            EngineHost.shared.pushKey(13, mods: mods)
            return
        }
        if scalar.value == 9 {
            EngineHost.shared.pushKey(9, mods: mods)
            return
        }
        if scalar.value == 127 || scalar.value == 8 {
            EngineHost.shared.pushKey(Self.kyBackspace, mods: mods)
            return
        }
        guard scalar.isASCII else { return }
        var ch = Int32(scalar.value)

        // Control keys arrive as codes 1-26; hand the engine the letter with
        // the CONTROL flag, the shape every backend produces.
        if ch >= 1 && ch <= 26 && flags.contains(.control) {
            ch = Int32(UInt8(ascii: "a")) + ch - 1
            mods |= Self.modControl
        }
        // SHIFT is semantic for letters only: the keysets match toupper(ch)
        // plus exact flags, and punctuation entries ignore modifiers.
        if scalar.properties.isUppercase {
            mods |= Self.modShift
        }
        EngineHost.shared.pushKey(ch, mods: mods)
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let x = Int32(max(0, p.x - contentInset) / cellSize.width)
        let y = Int32(max(0, p.y - contentInset) / cellSize.height)
        EngineHost.shared.pushMouseDown(cellX: x, cellY: y)
    }

    /// Accumulated precise scroll, drained one line per threshold. Trackpads
    /// deliver dozens of small point-valued events per flick; without the
    /// accumulator every one of them became at least a full line.
    private var wheelAccumulator: CGFloat = 0

    override func scrollWheel(with event: NSEvent) {
        if event.hasPreciseScrollingDeltas {
            wheelAccumulator += event.scrollingDeltaY
            let threshold: CGFloat = 24  // points per line
            let lines = Int32((wheelAccumulator / threshold).rounded(.towardZero))
            if lines != 0 {
                wheelAccumulator -= CGFloat(lines) * threshold
                EngineHost.shared.pushWheel(lines: lines)
            }
        } else {
            // Line-based devices already report whole lines.
            let dy = event.scrollingDeltaY
            if abs(dy) < 0.5 { return }
            EngineHost.shared.pushWheel(lines: Int32(dy.rounded(.awayFromZero)))
        }
    }
}

private extension NSEvent.SpecialKey {
    /// 1 for F1 ... 12 for F12, nil otherwise.
    var functionKeyN: Int? {
        let base = NSEvent.SpecialKey.f1.rawValue
        let n = rawValue - base + 1
        return (1...12).contains(n) ? n : nil
    }
}
