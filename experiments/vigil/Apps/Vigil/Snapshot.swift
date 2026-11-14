import AppKit
import SwiftUI

/// Development aid: `VIGIL_SNAPSHOT=/dir Vigil.app/Contents/MacOS/Vigil` renders
/// the popover and each settings tab offscreen to PNGs, then quits. Lets UI
/// changes be checked without opening the menu bar.
@MainActor
enum Snapshot {
    static var directory: URL? {
        ProcessInfo.processInfo.environment["VIGIL_SNAPSHOT"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    static func run(model: AppModel, into directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        model.start()
        // Let features fetch their first status before rendering.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            render(model, name: "popover", into: directory)
            model.showSettings("general")
            render(model, name: "settings-general", into: directory)
            for feature in model.features where feature.makeSettingsPage() != nil {
                model.showSettings(feature.id)
                render(model, name: "settings-\(feature.id)", into: directory)
            }
            model.shutdown()
            NSApp.terminate(nil)
        }
    }

    private static func render(_ model: AppModel, name: String, into directory: URL) {
        let host = NSHostingView(rootView: RootView(model: model)
            .environment(\.settingsScrollDisabled, true)
            .frame(width: 340, alignment: .top)
            .background(Color(nsColor: .windowBackgroundColor)))
        let size = host.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?
            .write(to: directory.appendingPathComponent("\(name).png"))
    }
}
