// See the Incursion LICENSE file for copyright information.
//
// Draws the app icon: the player's '@' in the palette's YELLOW on a dark
// rounded square, echoing the game's own look. Run by build_app.sh:
//
//   swift macapp/gen_icon.swift <out.iconset>
//
// then iconutil turns the iconset into the .icns. No asset files, so the
// icon can never carry a provenance question the way fonts/*.png did.

import AppKit

let args = CommandLine.arguments
guard args.count == 2 else {
    FileHandle.standardError.write("usage: gen_icon.swift <out.iconset>\n".data(using: .utf8)!)
    exit(2)
}
let outDir = URL(fileURLWithPath: args[1], isDirectory: true)
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func drawIcon(pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels,
        pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let s = CGFloat(pixels)
    // macOS icon grid: content square inset ~10%, continuous-corner radius ~22.5%.
    let inset = s * 0.10
    let box = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let path = NSBezierPath(roundedRect: box, xRadius: box.width * 0.225,
                            yRadius: box.width * 0.225)
    NSColor(srgbRed: 0.075, green: 0.075, blue: 0.09, alpha: 1).setFill()
    path.fill()
    NSColor(srgbRed: 0.25, green: 0.25, blue: 0.30, alpha: 1).setStroke()
    path.lineWidth = max(1, s * 0.008)
    path.stroke()

    let font = NSFont.monospacedSystemFont(ofSize: s * 0.62, weight: .medium)
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor(srgbRed: 1, green: 1, blue: 0, alpha: 1),
    ]
    let glyph = "@" as NSString
    let size = glyph.size(withAttributes: attrs)
    glyph.draw(at: NSPoint(x: (s - size.width) / 2, y: (s - size.height) / 2),
               withAttributes: attrs)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

for (name, px) in [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
] {
    let rep = drawIcon(pixels: px)
    let png = rep.representation(using: .png, properties: [:])!
    try png.write(to: outDir.appendingPathComponent("\(name).png"))
}
print("iconset written to \(outDir.path)")
