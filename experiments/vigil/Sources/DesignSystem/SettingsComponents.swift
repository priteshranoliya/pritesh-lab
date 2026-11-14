import SwiftUI

public struct SettingsScrollPage<Content: View>: View {
    let content: Content

    public init(@ViewBuilder content: () -> Content) { self.content = content() }

    @Environment(\.settingsScrollDisabled) private var scrollDisabled

    public var body: some View {
        Group {
            if scrollDisabled { page } else { ScrollView { page } }
        }
        .toggleStyle(VigilGlassToggleStyle())
        .font(.body)
    }

    private var page: some View {
        VigilGlassGroup {
            VStack(alignment: .leading, spacing: 16) { content }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

public extension EnvironmentValues {
    /// Renders settings pages without scrolling, for offscreen snapshots.
    @Entry var settingsScrollDisabled = false
}

public struct SettingsGlassSection<Content: View>: View {
    let title: String
    var detail: String? = nil
    let content: Content

    public init(title: String, detail: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.detail = detail
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline).accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 4)
            VStack(alignment: .leading, spacing: 10) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .vigilGlassSurface()
            if let detail {
                Text(detail).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
    }
}

public struct SettingsValueRow: View {
    let title: String
    let value: String

    public init(title: String, value: String) {
        self.title = title
        self.value = value
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 20) {
            Text(title)
            Spacer(minLength: 8)
            Text(value).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}
