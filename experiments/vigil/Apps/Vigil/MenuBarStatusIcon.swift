import AppKit

/// A template eye that follows the menu-bar appearance, with a green
/// activity dot while any feature is active.
@MainActor enum MenuBarStatusIcon {
    static func make(active: Bool) -> NSImage {
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        let symbol = NSImage(systemSymbolName: active ? "eye.fill" : "eye", accessibilityDescription: "Vigil")?
            .withSymbolConfiguration(configuration) ?? NSImage()
        guard active else {
            symbol.isTemplate = true
            return symbol
        }
        // A colored dot cannot be part of a template image, so draw the eye
        // in the label color and add the dot.
        let size = NSSize(width: symbol.size.width + 8, height: max(symbol.size.height, 14))
        let image = NSImage(size: size, flipped: false) { _ in
            let tinted = symbol.copy() as! NSImage
            tinted.lockFocus()
            NSColor.labelColor.set()
            NSRect(origin: .zero, size: tinted.size).fill(using: .sourceAtop)
            tinted.unlockFocus()
            tinted.draw(in: NSRect(x: 0, y: (size.height - symbol.size.height) / 2,
                                   width: symbol.size.width, height: symbol.size.height))
            NSColor.systemGreen.setFill()
            NSBezierPath(ovalIn: NSRect(x: size.width - 6, y: size.height / 2 - 3, width: 6, height: 6)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}
