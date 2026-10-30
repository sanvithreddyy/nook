import AppKit
import Combine
import SwiftUI

struct HUDPane: View {
    @AppStorage(Prefs.volumeHUD) private var volumeHUD = false
    @AppStorage(Prefs.brightnessHUD) private var brightnessHUD = false
    @AppStorage(Prefs.hudStyle) private var style = HUDStyle.ledge.rawValue
    @State private var trusted = MediaKeyTap.isTrusted
    private let poll = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        SettingsPage(title: "Volume & Brightness") {
            SettingsSection {
                SettingsToggle("Replace the volume HUD", isOn: $volumeHUD)
                SettingsToggle("Replace the brightness HUD", description: "Option-Shift with a key moves in quarter steps.", isOn: $brightnessHUD)
                if (volumeHUD || brightnessHUD) && !trusted {
                    SettingsRow("Accessibility access",
                                description: "Nook needs Accessibility access to handle the volume and brightness keys. It only reads those keys.") {
                        Button("Allow…") { MediaKeyTap.requestTrust() }
                    }
                }
            }
            SettingsSection("Style") {
                HUDStylePicker(selection: $style)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
        }
        .onReceive(poll) { _ in trusted = MediaKeyTap.isTrusted }
    }
}
private struct HUDStylePicker: View {
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 12) {
            ForEach(HUDStyle.allCases) { style in
                let selected = selection == style.rawValue
                Button { selection = style.rawValue } label: {
                    VStack(spacing: 6) {
                        HUDStyleThumbnail(style: style)
                            .frame(width: 118, height: 46)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: selected ? 3 : 1)
                            )
                        Text(style.title)
                            .font(.callout)
                            .foregroundStyle(selected ? .primary : .secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

/// One style drawn at real size on a sample island, scaled down.
private struct HUDStyleThumbnail: View {
    let style: HUDStyle

    var body: some View {
        let note = NotchNotification.volume(level: 0.62, muted: false, output: nil)
        let notch = NotchMetrics.simulated.size
        let side = notch.height + 4 + (style == .slider ? 13 : 8)
        let size = CGSize(width: notch.width + side * 2, height: notch.height + style.below)
        let layout = IslandLayout(size: size, topRadius: 6, bottomRadius: Compact.bottomRadius)
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(red: 0.27, green: 0.35, blue: 0.49), Color(red: 0.62, green: 0.69, blue: 0.81)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        if style.usesSides {
                            HUDGlyph(note: note)
                                .frame(width: side, alignment: .leading)
                                .padding(.leading, Compact.outer)
                            Spacer(minLength: 0)
                            HUDValue(note: note, style: style)
                                .frame(width: side - Compact.outer, alignment: .trailing)
                                .padding(.trailing, Compact.outer)
                        }
                    }
                    .frame(height: notch.height)
                    HUDBelow(note: note, style: style, bump: 0, bumpUp: true)
                        .padding(.horizontal, layout.topRadius + (style == .slider ? 4 : 12))
                }
                if style == .outline {
                    HUDOutline(level: 0.62, muted: false, layout: layout, notchHeight: notch.height)
                }
            }
            .frame(width: size.width, height: size.height, alignment: .top)
            .background(NotchShape(topRadius: layout.topRadius, bottomRadius: layout.bottomRadius).fill(.black))
            .scaleEffect(0.42, anchor: .top)
        }
        .environment(\.colorScheme, .dark)
        .accessibilityHidden(true)
    }
}
