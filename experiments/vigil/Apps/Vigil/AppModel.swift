import Foundation
import Observation
import VigilKit

/// The shell's state: which features exist and what the popover shows.
/// Feature state lives in each feature's own model.
@MainActor @Observable
final class AppModel {
    @ObservationIgnored private(set) var features: [any FeatureModule] = []
    let loginItem = LoginItemService()
    var showingSettings = false
    var settingsTab = FeatureContext.generalSettings

    init() {
        let context = FeatureContext(openSettings: { [weak self] id in self?.showSettings(id) })
        features = FeatureRegistry.makeFeatures(context: context)
    }

    var isAnyActive: Bool { features.contains { $0.isActive } }

    var statusSummary: String {
        features.first { $0.isActive }?.statusSummary ?? "Vigil — idle"
    }

    func start() { features.forEach { $0.start() } }

    func popoverVisibilityChanged(_ visible: Bool) {
        features.forEach { $0.popoverVisibilityChanged(visible) }
    }

    func showSettings(_ tab: String) {
        settingsTab = tab
        showingSettings = true
    }

    func shutdown() { features.forEach { $0.shutdown() } }
}
