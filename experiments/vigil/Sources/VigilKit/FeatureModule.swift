import SwiftUI

/// The contract every Vigil feature implements. The app shell knows nothing
/// about individual features: it shows each module's menu-bar section in the
/// popover, lists its settings page, and shows the activity dot when any
/// module is active. Adding a feature = one new module + one line in
/// `FeatureRegistry`.
@MainActor
public protocol FeatureModule: AnyObject {
    /// Stable identifier, also used as the settings tab tag.
    var id: String { get }
    var title: String { get }
    var systemImage: String { get }
    /// Lower numbers appear first in the popover.
    var order: Int { get }

    /// Drives the menu-bar activity indicator.
    var isActive: Bool { get }
    /// One-line description for the menu-bar tooltip and accessibility.
    var statusSummary: String { get }

    func makeMenuBarSection() -> AnyView
    func makeSettingsPage() -> AnyView?

    /// Called once after launch, and when the popover opens or closes.
    func start()
    func popoverVisibilityChanged(_ visible: Bool)
    /// Called on quit. Features must not stop work owned by the helper.
    func shutdown()
}

public extension FeatureModule {
    var order: Int { 100 }
    func makeSettingsPage() -> AnyView? { nil }
    func start() {}
    func popoverVisibilityChanged(_ visible: Bool) {}
    func shutdown() {}
}

/// Services the shell hands to every feature.
@MainActor
public struct FeatureContext {
    /// Opens the settings tab for a feature id (or `FeatureContext.generalSettings`).
    public let openSettings: (String) -> Void

    public static let generalSettings = "general"

    public init(openSettings: @escaping (String) -> Void) {
        self.openSettings = openSettings
    }
}
