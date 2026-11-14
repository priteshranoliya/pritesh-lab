import DesignSystem
import AwakeCore
import SwiftUI

struct TimerActivityView: View {
    @Bindable var model: AwakeModel

    var body: some View {
        if let current = model.current {
            VStack(spacing: 12) {
                TimelineView(.periodic(from: .now, by: model.isPopoverVisible && current.endsAt != nil ? 1 : 3600)) { context in
                    VStack(spacing: 8) {
                        if let remaining = current.remainingSeconds(at: context.date), let end = current.endsAt {
                            Text(Countdown.string(seconds: remaining))
                                .font(.system(size: 40, weight: .light, design: .rounded))
                                .monospacedDigit()
                                .accessibilityLabel("Time remaining")
                                .accessibilityValue(Countdown.string(seconds: remaining))
                            Text("Until \(end.formatted(date: .abbreviated, time: .shortened))")
                                .font(.callout).foregroundStyle(.secondary)
                        } else {
                            Image(systemName: "infinity")
                                .font(.system(size: 40, weight: .light)).accessibilityHidden(true)
                            Text("Until you stop it")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                HStack(spacing: 10) {
                    if let end = current.endsAt {
                        Button(action: model.extendSession) {
                            Text("+15 min").font(.callout.weight(.medium))
                                .frame(minHeight: 28)
                        }
                        .vigilGlassButton()
                        .accessibilityLabel("Add 15 minutes")
                        .disabled(model.isSending || end.timeIntervalSince(current.startedAt) >= Double(SessionDuration.maximumMinutes) * 60)
                    }
                    Button(action: model.endSession) {
                        Label("End session", systemImage: "stop.fill")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 28)
                    }
                    .vigilGlassButton(prominent: true)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(model.isSending)
                }
                .buttonBorderShape(.capsule).controlSize(.regular)
            }
        } else {
            SessionSetupView(model: model)
        }
    }
}
