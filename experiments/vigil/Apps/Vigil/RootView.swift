import AppKit
import DesignSystem
import SwiftUI
import VigilKit

struct RootView: View {
    let model: AppModel

    var body: some View {
        if model.showingSettings {
            SettingsView(model: model)
        } else {
            VigilGlassGroup {
                VStack(spacing: 12) {
                    ForEach(model.features, id: \.id) { feature in
                        feature.makeMenuBarSection()
                    }
                    footer
                }
                .padding(14)
            }
            .frame(width: 340)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button { model.showSettings(FeatureContext.generalSettings) } label: {
                Label("Settings", systemImage: "gearshape")
                    .font(.callout)
                    .frame(minHeight: 30)
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(",", modifiers: .command)
            .help("Open Settings (⌘,)")
            Spacer()
            Button("Quit", systemImage: "power") { NSApp.terminate(nil) }
                .buttonStyle(.borderless)
                .help("Quit Vigil (⌘Q). Sessions run by the helper keep going.")
        }
        .foregroundStyle(.secondary)
    }
}
