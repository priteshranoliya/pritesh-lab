import DesignSystem
import SwiftUI
import VigilKit

struct SettingsView: View {
    @Bindable var model: AppModel
    @Environment(\.settingsScrollDisabled) private var scrollDisabled

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    model.showingSettings = false
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Back")
                .help("Back")
                Text("Settings").font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            Picker("Settings section", selection: $model.settingsTab) {
                Text("General").tag(FeatureContext.generalSettings)
                ForEach(pages, id: \.id) { page in
                    Text(page.title).tag(page.id)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(12)
            Divider()
            ZStack {
                GeneralSettingsView(model: model)
                    .modifier(SettingsPageVisibility(isSelected: model.settingsTab == FeatureContext.generalSettings))
                ForEach(pages, id: \.id) { page in
                    page.view.modifier(SettingsPageVisibility(isSelected: model.settingsTab == page.id))
                }
            }
        }
        .frame(width: 340, height: scrollDisabled ? nil : 520)
        .onAppear { model.loginItem.refresh() }
    }

    private var pages: [(id: String, title: String, view: AnyView)] {
        model.features.compactMap { feature in
            feature.makeSettingsPage().map { (feature.id, feature.title, $0) }
        }
    }
}

// Keep pages mounted so drafts and scroll positions survive tab changes.
// Hidden pages cannot receive input, shortcuts, or accessibility focus.
private struct SettingsPageVisibility: ViewModifier {
    let isSelected: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isSelected ? 1 : 0)
            .disabled(!isSelected)
            .allowsHitTesting(isSelected)
            .accessibilityHidden(!isSelected)
            .zIndex(isSelected ? 1 : 0)
    }
}

struct GeneralSettingsView: View {
    let model: AppModel

    var body: some View {
        SettingsScrollPage {
            SettingsGlassSection(title: "Startup", detail: "Vigil opens in the menu bar. Sessions start when you choose.") {
                Toggle("Launch at login", isOn: Binding(
                    get: { model.loginItem.isRegistered }, set: { model.loginItem.setEnabled($0) }))
                if model.loginItem.needsApproval {
                    Button("Allow in System Settings…") { model.loginItem.openSystemSettings() }
                        .vigilGlassButton()
                }
                if let error = model.loginItem.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            SettingsGlassSection(title: "Command line",
                                 detail: "Agents and scripts can start sessions with the vigil command. Requires the helper.") {
                Text("vigil start 2h --closed-lid\nvigil status\nvigil stop")
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
            HStack {
                Text("Vigil")
                Spacer()
                Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
            }
            .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 4)
        }
    }
}
