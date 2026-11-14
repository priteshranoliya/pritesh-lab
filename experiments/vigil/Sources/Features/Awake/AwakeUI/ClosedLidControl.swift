import DesignSystem
import SwiftUI

struct ClosedLidControl: View {
    let model: AwakeModel
    var showsSettingsButton = true
    let openSettings: () -> Void

    var body: some View {
        let status = model.closedLidStatus
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "laptopcomputer")
                    .font(.system(size: 17))
                    .accessibilityHidden(true)
                Text("Closed-lid mode").font(.callout.weight(.semibold))
                Spacer(minLength: 4)
                if showsSettingsButton {
                    Button(action: openSettings) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 14))
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Closed-lid settings")
                    .help("Closed-lid, battery and helper settings")
                }
                if let action = status.action {
                    Button(action.title) { model.perform(action) }
                        .controlSize(.small)
                        .disabled(model.helper.isBusy)
                } else if !model.helper.isBusy {
                    Toggle("Keep awake with lid closed", isOn: Binding(
                        get: { model.closedLidToggleValue }, set: { model.setClosedLid($0) }))
                        .toggleStyle(VigilGlassToggleStyle(showsLabel: false))
                        .disabled(model.isSending)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Label(status.title, systemImage: status.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color(status.tone))
                Text(status.detail)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let secondary = status.secondaryAction {
                    Button(secondary.title) { model.perform(secondary) }
                        .buttonStyle(.link).font(.caption)
                }
                if model.helper.isBusy { ProgressView().controlSize(.small) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
        .padding(12)
        .vigilGlassSurface()
    }

    private func color(_ tone: ClosedLidStatus.Tone) -> Color {
        switch tone {
        case .ready: .green
        case .attention: .orange
        case .neutral: .secondary
        }
    }
}
