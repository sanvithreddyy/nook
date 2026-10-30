import AppKit
import SwiftUI

// Settings pages: a large title, then titled groups of rows on one soft
// rounded surface with hairlines between rows, a label on the left and a compact control on the right.

enum SettingsTheme {
    /// Grouped rows: a faint wash toward the opposite ink, so groups read without borders.
    static let group = adaptive(dark: .white.withAlphaComponent(0.05), light: .black.withAlphaComponent(0.035))

    private static func adaptive(dark: NSColor, light: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light })
    }
}

/// A scrolling settings page with a title. With an area, the page ends with Reset to Defaults.
struct SettingsPage<Content: View>: View {
    let title: String
    var area: PrefsArea?
    @ViewBuilder var content: Content
    @State private var confirmingReset = false

    init(title: String, area: PrefsArea? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.area = area
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.title2.weight(.semibold))
                content
                if area != nil {
                    Button("Reset to Defaults…") { confirmingReset = true }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.top, 20)
                }
            }
            .padding(24)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .softTopEdge()
        .confirmationDialog("Reset \(title) settings?", isPresented: $confirmingReset) {
            Button("Reset", role: .destructive) { if let area { Prefs.reset(area) } }
        } message: {
            Text("Everything on this page goes back to how Nook comes.")
        }
    }
}

/// A titled group of rows on one rounded surface, with hairlines between rows.
struct SettingsSection<Content: View>: View {
    let title: String?
    var footer: String?
    @ViewBuilder var content: Content

    init(_ title: String? = nil, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title { Text(title).font(.headline) }
            VStack(spacing: 0) {
                Group(subviews: content) { rows in
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        if index > 0 { Divider() }
                        row
                    }
                }
            }
            .padding(.horizontal, 14)
            .background(SettingsTheme.group, in: .rect(cornerRadius: 12))
            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 2)
            }
        }
        .padding(.top, 20)
    }
}

/// Label on the left with a value or a small control on the right. A wide control (a slider, a row of
/// thumbnails) goes on its own line below with `wide`. A plain description closes the row.
struct SettingsRow<Control: View>: View {
    let title: String
    var value: String?
    var description: String?
    var wide = false
    @ViewBuilder var control: Control

    init(_ title: String, value: String? = nil, description: String? = nil, wide: Bool = false,
         @ViewBuilder control: () -> Control) {
        self.title = title
        self.value = value
        self.description = description
        self.wide = wide
        self.control = control()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(title)
                Spacer(minLength: 12)
                if let value {
                    Text(value).foregroundStyle(.secondary).monospacedDigit()
                } else if !wide {
                    control
                }
            }
            if wide { control }
            if let description {
                Text(description).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 11)
    }
}

extension SettingsRow where Control == EmptyView {
    /// A row that only states something: a label and its value.
    init(_ title: String, value: String, description: String? = nil) {
        self.init(title, value: value, description: description) { EmptyView() }
    }
}

/// A switch that reads as one: label on the row, switch on the right.
struct SettingsToggle: View {
    let title: String
    var description: String?
    @Binding var isOn: Bool

    init(_ title: String, description: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.description = description
        _isOn = isOn
    }

    var body: some View {
        SettingsRow(title, description: description) {
            Toggle(title, isOn: $isOn).toggleStyle(.switch).labelsHidden()
        }
    }
}

extension View {
    /// Rows fade as they scroll up under the window's toolbar instead of running into it.
    @ViewBuilder func softTopEdge() -> some View {
        if #available(macOS 26.0, *) {
            scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            self
        }
    }

    /// A segmented picker sized to its options, label hidden (the row carries it).
    func segmentedStyle() -> some View {
        pickerStyle(.segmented).labelsHidden().fixedSize()
    }

    /// A pop-up menu sized to its options, label hidden (the row carries it).
    func menuStyle() -> some View {
        pickerStyle(.menu).labelsHidden().fixedSize()
    }
}
