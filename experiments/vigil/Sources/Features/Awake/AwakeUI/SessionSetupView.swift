import DesignSystem
import AwakeCore
import SwiftUI

struct SessionSetupView: View {
    @Bindable var model: AwakeModel

    var body: some View {
        VStack(spacing: 8) {
            SessionModePicker(selection: $model.sessionMode)
            .onChange(of: model.sessionMode) { _, mode in
                if mode == .untilTime && model.sessionEndDate <= .now {
                    model.sessionEndDate = .now.addingTimeInterval(30 * 60)
                }
            }

            switch model.sessionMode {
            case .duration:
                DurationEditor(draft: $model.durationDraft, onSubmit: model.startSession)
            case .untilTime:
                SessionEndTimeEditor(selection: $model.sessionEndDate)
            case .untilStopped:
                VStack(spacing: 8) {
                    Image(systemName: "infinity")
                        .font(.system(size: 36, weight: .light))
                        .accessibilityHidden(true)
                    Text("Until you stop it")
                        .font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 6)
            }

            TimelineView(.periodic(from: .now, by: model.isPopoverVisible && model.sessionMode == .untilTime ? 1 : 3600)) { context in
                Button(action: model.startSession) {
                    Label(model.needsSetupToStart ? "Set up & start" : "Start session",
                          systemImage: model.needsSetupToStart ? "lock.open" : "play.fill")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 28)
                }
                .vigilGlassButton(prominent: true)
                .buttonBorderShape(.capsule)
                .controlSize(.regular)
                .keyboardShortcut(.defaultAction)
                .disabled(!(model.requestedSession?.isValid(at: context.date) ?? false) || model.isSending || model.helper.isBusy)
            }

            if model.needsSetupToStart && !model.helper.isBusy {
                Text("First time only: Vigil asks for your Mac password to install its helper, so sessions keep running with the lid closed or if Vigil quits.")
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }


        }
    }
}
