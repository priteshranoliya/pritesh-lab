import AppKit
import VigilKit

@main
@MainActor
struct VigilApp {
    static func main() {
        // AppKit owns one status item. No SwiftUI window scenes can be opened
        // or restored independently of its popover.
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let directory = Snapshot.directory {
            NSApp.setActivationPolicy(.accessory)
            Snapshot.run(model: model, into: directory)
            return
        }
        // Vigil intentionally lives in the menu bar, with no persistent Dock icon.
        NSApp.setActivationPolicy(.accessory)
        menuBar = MenuBarController(model: model)
        NSApp.mainMenu = ApplicationMenu.make(target: self, settingsAction: #selector(openSettings))
        model.start()
        if LaunchPresentation.shouldShowPopover(for: NSAppleEventManager.shared().currentAppleEvent) {
            DispatchQueue.main.async { [weak self] in self?.menuBar?.show() }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        menuBar?.show()
        return false
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }

    @objc private func openSettings() {
        model.showSettings(FeatureContext.generalSettings)
        menuBar?.show()
    }

    func applicationWillTerminate(_ notification: Notification) {
        menuBar?.stop()
        model.shutdown()
    }
}
