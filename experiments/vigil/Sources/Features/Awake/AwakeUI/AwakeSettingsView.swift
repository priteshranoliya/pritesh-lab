import AwakeCore
import DesignSystem
import SwiftUI
import VigilIPC

struct AwakeSettingsView: View {
    let model: AwakeModel
    @State private var confirmingRemoval = false

    var body: some View {
        @Bindable var preferences = model.preferences
        let locked = model.isActive
        SettingsScrollPage {
            ClosedLidControl(model: model, showsSettingsButton: false, openSettings: {})
            SettingsGlassSection(title: "Sessions") {
                Toggle("Remember last duration", isOn: $preferences.rememberDuration)
                Divider()
                Toggle("Keep display awake", isOn: Binding(
                    get: { model.preferences.keepDisplayAwake }, set: { model.setDisplayAwake($0) }))
                    .help("Keeps the display awake during an active session.")
            }
            SessionPowerSettings(preferences: preferences, closedLidEnabled: locked)
            ClosedLidBatterySettings(preferences: preferences, modeEnabled: locked)
            SettingsGlassSection(title: "Closed-lid time limit",
                                 detail: "Closed-lid mode always turns off if your Mac gets too warm.") {
                HStack {
                    Text("Turn off after")
                    Spacer()
                    Picker("Closed-lid time limit", selection: $preferences.closedLidMaxHours) {
                        Text("No limit").tag(SessionRules.noClosedLidTimeLimit)
                        ForEach(SessionRules.closedLidHourLimits, id: \.self) { hours in
                            Text(hours == 1 ? "1 hour" : "\(hours) hours").tag(hours)
                        }
                    }
                    .labelsHidden().frame(width: 120)
                }
                .disabled(locked)
            }
            helperSection
            VStack(alignment: .leading, spacing: 10) {
                DisclosureGroup("How it works") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("With the helper installed, your session runs in a small background service. If Vigil quits or crashes, the session and its limits keep running.")
                        Text("Closed-lid mode turns off when your battery or time limits are reached, or when your Mac gets too warm. Your session keeps running with the lid open.")
                        Text("Sessions never continue after a restart, and normal sleep settings are always restored.")
                        Text("Keep your Mac on a hard surface with room for airflow, and check that it stays awake before leaving work unattended.")
                    }
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 10)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private var helperSection: some View {
        SettingsGlassSection(title: "Helper", detail: model.helper.message) {
            SettingsValueRow(title: "Status", value: helperStatus)
            if let action = model.closedLidStatus.action {
                Button(action.title) { model.perform(action) }
                    .vigilGlassButton(prominent: true).buttonBorderShape(.capsule)
                    .disabled(model.helper.isBusy)
            }
            if model.helper.isInstalled {
                Button("Remove helper…") { confirmingRemoval = true }
                    .vigilGlassButton().buttonBorderShape(.capsule)
                    .disabled(model.helper.isBusy)
                    .confirmationDialog("Remove the Vigil helper?", isPresented: $confirmingRemoval) {
                        Button("Remove", role: .destructive, action: model.uninstallHelper)
                    } message: {
                        Text("Any running session ends and normal sleep settings are restored. You can set it up again later.")
                    }
            }
        }
    }

    private var helperStatus: String {
        switch model.helper.installation {
        case .ready: "Running (\(VigilIdentity.version))"
        case .outdated(let installed): "Older version (\(installed))"
        case .notResponding: "Not responding"
        case .notInstalled: "Not installed"
        }
    }
}
