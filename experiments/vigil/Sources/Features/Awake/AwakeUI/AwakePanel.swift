import DesignSystem
import SwiftUI

/// The Awake feature's section in the menu-bar popover.
struct AwakePanel: View {
    let model: AwakeModel
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 0) {
                TimerActivityView(model: model)
                SessionStatusMessage(message: model.statusMessage,
                                     attentionTrigger: model.blockedStartAttempts)
            }
            if model.batteryBlocks {
                HStack(spacing: 10) {
                    Image(systemName: "battery.75percent").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("On battery").font(.callout.weight(.semibold))
                        Text("Stops at \(model.preferences.closedLidBatteryCutoff)% battery or if your Mac gets hot.")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    Button("Allow", action: model.allowBatteryUse)
                        .controlSize(.small)
                        .help("Let sessions and closed-lid mode run on battery. Change limits in Settings.")
                }
                .padding(12)
                .vigilGlassSurface()
            }
            ClosedLidControl(model: model, openSettings: openSettings)
        }
    }
}
