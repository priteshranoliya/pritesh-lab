import SwiftUI
import VigilKit

/// Keep the Mac awake, with the lid open or closed.
@MainActor
public final class AwakeFeature: FeatureModule {
    public let id = "awake"
    public let title = "Awake"
    public let systemImage = "eye"
    public let order = 0

    let model: AwakeModel
    private let context: FeatureContext

    public init(context: FeatureContext) {
        self.context = context
        model = AwakeModel()
    }

    public var isActive: Bool { model.isActive }

    public var statusSummary: String {
        guard let current = model.current else { return "Not keeping your Mac awake" }
        if current.closedLid && current.closedLidApplied { return "Keeping your Mac awake, lid closed OK" }
        return "Keeping your Mac awake"
    }

    public func makeMenuBarSection() -> AnyView {
        AnyView(AwakePanel(model: model) { [context, id] in context.openSettings(id) })
    }

    public func makeSettingsPage() -> AnyView? { AnyView(AwakeSettingsView(model: model)) }

    public func start() { model.start() }
    public func popoverVisibilityChanged(_ visible: Bool) { model.popoverVisibilityChanged(visible) }
    public func shutdown() { model.shutdown() }
}
