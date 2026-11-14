import AppKit

// Draws Vigil's app icon (a watchful eye on a night-sky tile) into an .iconset folder.
// usage: swift script/create_icon.swift <output.iconset>
let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

func drawIcon(pixels: Int) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB,
                                  bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current?.imageInterpolation = .high
    let size = CGFloat(pixels)
    // macOS icon grid: the tile sits inside a ~10% margin.
    let inset = size * 0.1
    let tile = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let path = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225)
    NSGradient(colors: [NSColor(red: 0.07, green: 0.09, blue: 0.22, alpha: 1),
                        NSColor(red: 0.18, green: 0.13, blue: 0.40, alpha: 1)])!
        .draw(in: path, angle: 90)

    // A few stars.
    NSColor(white: 1, alpha: 0.75).setFill()
    for (x, y, r) in [(0.27, 0.74, 0.012), (0.70, 0.78, 0.009), (0.78, 0.66, 0.014), (0.33, 0.30, 0.008)] {
        NSBezierPath(ovalIn: NSRect(x: size * x, y: size * y, width: size * r * 2, height: size * r * 2)).fill()
    }

    // The eye.
    let configuration = NSImage.SymbolConfiguration(pointSize: size * 0.34, weight: .semibold)
        .applying(.init(paletteColors: [NSColor(red: 1.0, green: 0.78, blue: 0.35, alpha: 1)]))
    if let eye = NSImage(systemSymbolName: "eye.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(configuration) {
        let width = size * 0.56
        let height = width * eye.size.height / eye.size.width
        eye.draw(in: NSRect(x: (size - width) / 2, y: (size - height) / 2 - size * 0.02, width: width, height: height))
    }
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
    try drawIcon(pixels: size).write(to: directory.appendingPathComponent("icon_\(size)x\(size).png"))
    try drawIcon(pixels: size * 2).write(to: directory.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
