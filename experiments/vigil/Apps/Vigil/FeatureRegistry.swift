import AwakeUI
import VigilKit

/// The one place features are listed. To add a feature, create its module
/// under Sources/Features/<Name>/ and add it here.
@MainActor
enum FeatureRegistry {
    static func makeFeatures(context: FeatureContext) -> [any FeatureModule] {
        let features: [any FeatureModule] = [
            AwakeFeature(context: context),
            // ClaudeUsageFeature(context: context),
        ]
        return features.sorted { $0.order < $1.order }
    }
}
