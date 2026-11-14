// Draws a soft pastel folder (tab, peeking sheet, gradient front) with a brand logo tile,
// and sets it as the Finder icon of each folder given.
//
//   folder-icon --logo logos/acme.png --color "#0E5A47" <folder>...
//   folder-icon --symbol book.fill --color "#5B5BD6" <folder>...         (SF Symbol on a colour tile)
//   folder-icon --mark logos/leaf.png --tile "#FFFCE9" --color "#75BA4B" <folder>...  (small logo on a tile)
//   folder-icon --logo logos/acme.png --color "#0E5A47" --preview out.png
//   folder-icon --reset <folder>...
import AppKit

var logoPath: String?
var markPath: String?
var symbol: String?
var tileHex: String?
var hex = "#D4AF37"
var reset = false
var preview: String?
var folders: [String] = []

var args = CommandLine.arguments.dropFirst().makeIterator()
while let a = args.next() {
    switch a {
    case "--logo": logoPath = args.next()
    case "--mark": markPath = args.next()
    case "--symbol": symbol = args.next()
    case "--tile": tileHex = args.next()
    case "--color": hex = args.next() ?? hex
    case "--preview": preview = args.next()
    case "--reset": reset = true
    default: folders.append(a)
    }
}
guard !folders.isEmpty || preview != nil else {
    print("usage: folder-icon (--logo <png> | --mark <png> | --symbol <sf-name>) --color <#hex> [--tile <#hex>] [--preview out.png] [--reset] <folder>...")
    exit(1)
}

func color(_ hex: String) -> NSColor {
    let v = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0xD4AF37
    return NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
                   green: CGFloat((v >> 8) & 0xFF) / 255,
                   blue: CGFloat(v & 0xFF) / 255, alpha: 1)
}

extension NSColor {
    /// Mix toward white by `t` (0 = this colour, 1 = white).
    func pastel(_ t: CGFloat) -> NSColor { blended(withFraction: t, of: .white)! }
}

func withShadow(blur: CGFloat, y: CGFloat, alpha: CGFloat, _ draw: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let s = NSShadow()
    s.shadowBlurRadius = blur
    s.shadowOffset = NSSize(width: 0, height: y)
    s.shadowColor = NSColor.black.withAlphaComponent(alpha)
    s.set()
    draw()
    NSGraphicsContext.restoreGraphicsState()
}

// Geometry on a 1024 canvas, origin bottom-left. Folder icons sit wider than tall.
let L: CGFloat = 96, R: CGFloat = 928, B: CGFloat = 184
let backTop: CGFloat = 790, tabTop: CGFloat = 852, tabEnd: CGFloat = 372
let frontTop: CGFloat = 724, radius: CGFloat = 72

func backPath() -> NSBezierPath {
    let p = NSBezierPath()
    p.move(to: NSPoint(x: L + radius, y: B))
    p.appendArc(from: NSPoint(x: R, y: B), to: NSPoint(x: R, y: backTop), radius: radius)
    p.appendArc(from: NSPoint(x: R, y: backTop), to: NSPoint(x: tabEnd, y: backTop), radius: radius)
    p.line(to: NSPoint(x: tabEnd + 76, y: backTop))
    // Soft S-curve up into the tab, like a real folder tab.
    p.curve(to: NSPoint(x: tabEnd, y: tabTop),
            controlPoint1: NSPoint(x: tabEnd + 38, y: backTop),
            controlPoint2: NSPoint(x: tabEnd + 38, y: tabTop))
    p.appendArc(from: NSPoint(x: L, y: tabTop), to: NSPoint(x: L, y: B), radius: 48)
    p.appendArc(from: NSPoint(x: L, y: B), to: NSPoint(x: R, y: B), radius: radius)
    p.close()
    return p
}

enum TileContent {
    case logo(NSImage)                      // full-bleed brand tile, aspect-filled
    case glyph(NSImage, background: NSColor) // centred on a gradient tile
}

/// Draws an image scaled to fit `rect` at `fraction` of its size, centred.
func drawContained(_ img: NSImage, in rect: NSRect, fraction: CGFloat) {
    let s = min(rect.width / img.size.width, rect.height / img.size.height) * fraction
    let w = img.size.width * s, h = img.size.height * s
    img.draw(in: NSRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h))
}

func makeIcon(base: NSColor, tileContent: TileContent?) -> NSBitmapImageRep {
    let side = 1024
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high

    // Back panel with tab.
    withShadow(blur: 24, y: -8, alpha: 0.10) {
        NSGradient(starting: base.pastel(0.50), ending: base.pastel(0.62))!.draw(in: backPath(), angle: -90)
    }

    // Sheet of paper peeking out between back and front.
    let paper = NSBezierPath(roundedRect: NSRect(x: L + 56, y: B + 120, width: R - L - 112, height: backTop - 30 - (B + 120)),
                             xRadius: 36, yRadius: 36)
    withShadow(blur: 10, y: -2, alpha: 0.08) {
        NSColor.white.withAlphaComponent(0.95).setFill()
        paper.fill()
    }

    // Front panel: light gradient, soft shadow cast upward onto the paper, inner highlight.
    let frontRect = NSRect(x: L, y: B, width: R - L, height: frontTop - B)
    let front = NSBezierPath(roundedRect: frontRect, xRadius: radius, yRadius: radius)
    withShadow(blur: 28, y: 6, alpha: 0.14) {
        NSGradient(starting: base.pastel(0.86), ending: base.pastel(0.70))!.draw(in: front, angle: -90)
    }
    let rim = NSBezierPath(roundedRect: frontRect.insetBy(dx: 5, dy: 5), xRadius: radius - 5, yRadius: radius - 5)
    rim.lineWidth = 6
    NSColor.white.withAlphaComponent(0.55).setStroke()
    rim.stroke()

    // Brand logo tile, centred on the front.
    if let tileContent {
        let tileSide: CGFloat = 510
        let tile = NSRect(x: (CGFloat(side) - tileSide) / 2, y: frontRect.midY - tileSide / 2 - 6,
                          width: tileSide, height: tileSide)
        let tilePath = NSBezierPath(roundedRect: tile, xRadius: 116, yRadius: 116)
        withShadow(blur: 30, y: -12, alpha: 0.22) {
            NSColor.white.setFill()
            tilePath.fill()
        }
        NSGraphicsContext.saveGraphicsState()
        tilePath.addClip()
        switch tileContent {
        case .logo(let logo):
            // Aspect-fill the tile.
            let s = max(tileSide / logo.size.width, tileSide / logo.size.height)
            let w = logo.size.width * s, h = logo.size.height * s
            logo.draw(in: NSRect(x: tile.midX - w / 2, y: tile.midY - h / 2, width: w, height: h))
        case .glyph(let glyph, let bg):
            NSGradient(starting: bg.pastel(0.18), ending: bg)!.draw(in: tile, angle: -90)
            drawContained(glyph, in: tile, fraction: 0.64)
        }
        NSGraphicsContext.restoreGraphicsState()
        NSColor.white.withAlphaComponent(0.6).setStroke()
        tilePath.lineWidth = 4
        tilePath.stroke()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func load(_ path: String) -> NSImage {
    guard let img = NSImage(contentsOfFile: (path as NSString).expandingTildeInPath) else {
        print("✗ could not read \(path)"); exit(1)
    }
    return img
}

var content: TileContent?
if let logoPath {
    content = .logo(load(logoPath))
} else if let markPath {
    content = .glyph(load(markPath), background: color(tileHex ?? "#FFFFFF"))
} else if let symbol {
    // White SF Symbol, drawn large so it stays crisp when scaled onto the tile.
    let config = NSImage.SymbolConfiguration(pointSize: 220, weight: .semibold)
        .applying(.init(paletteColors: [.white]))
    guard let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config) else {
        print("✗ unknown SF Symbol \(symbol)"); exit(1)
    }
    content = .glyph(img, background: color(tileHex ?? hex))
}

let rep = reset ? nil : makeIcon(base: color(hex), tileContent: content)

if let preview, let rep {
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: preview))
}

let icon: NSImage? = rep.map { r in
    let img = NSImage(size: NSSize(width: r.pixelsWide, height: r.pixelsHigh))
    img.addRepresentation(r)
    return img
}

for path in folders {
    let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    let ok = NSWorkspace.shared.setIcon(icon, forFile: url.path, options: [])
    print("\(ok ? "✓" : "✗") \(url.lastPathComponent)")

    // Finder stores the icon in a hidden "Icon\r" file; keep it out of git status.
    // (Git strips a trailing \r from patterns, so it has to go in brackets.)
    let exclude = url.appendingPathComponent(".git/info/exclude")
    if !reset, let current = try? String(contentsOf: exclude, encoding: .utf8), !current.contains("Icon[\r]") {
        try? (current + (current.hasSuffix("\n") ? "" : "\n") + "Icon[\r]\n").write(to: exclude, atomically: true, encoding: .utf8)
    }
}
