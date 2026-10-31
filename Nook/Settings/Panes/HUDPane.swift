import AppKit
import Combine
import SwiftUI

struct HUDPane: View {
    @AppStorage(Prefs.volumeHUD) private var volumeHUD = false
    @AppStorage(Prefs.brightnessHUD) private var brightnessHUD = false
    @AppStorage(Prefs.hudStyle) private var style = HUDStyle.ledge.rawValue
    @AppStorage(Prefs.hudDuration) private var duration = 1.6
    @AppStorage(Prefs.hudShowsNumber) private var showsNumber = true
    @State private var trusted = MediaKeyTap.isTrusted
    private let poll = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        SettingsPage(title: "Volume & Brightness", area: Prefs.hudsArea, preview: "Shows the volume on the notch, at its real level, while you change things here.") {
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
                SettingsToggle("Show the level as a number", isOn: $showsNumber)
                SettingsRow("Stays for", value: String(format: "%.1f s", duration), wide: true) {
                    Slider(value: $duration, in: 1...3, step: 0.2)
                }
            }
            .disabled(!volumeHUD && !brightnessHUD)
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
                            .frame(width: 128, height: 58)
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

/// One style drawn small, as the Layout picker draws the home: a little island hanging in the middle of
/// a wallpaper, holding the style's own shapes at 62.
private struct HUDStyleThumbnail: View {
    let style: HUDStyle
    private let level: CGFloat = 0.62
    /// The notch's row, drawn small.
    private let row: CGFloat = 15

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(red: 0.27, green: 0.35, blue: 0.49), Color(red: 0.62, green: 0.69, blue: 0.81)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            switch style {
            case .ledge: ledge(steps: false)
            case .segments: ledge(steps: true)
            case .slider: fill
            case .outline: outline
            }
        }
        .environment(\.colorScheme, .dark)
        .accessibilityHidden(true)
    }

    private var shape: NotchShape { NotchShape(topRadius: 4, bottomRadius: 9) }

    /// The speaker and the level beside the notch.
    private func sides(dark: Bool = false) -> some View {
        HStack {
            Image(systemName: "speaker.wave.2.fill").font(.system(size: 7.5, weight: .semibold))
            Spacer(minLength: 0)
            Text(style == .segments ? "10" : "62").font(.system(size: 7.5, weight: .semibold).monospacedDigit())
        }
        .foregroundStyle(dark ? Color(white: 0.16) : .white)
        .padding(.horizontal, 9)
        .frame(height: row)
    }

    private func ledge(steps: Bool) -> some View {
        VStack(spacing: 0) {
            sides()
            Group {
                if steps {
                    HStack(spacing: 1.4) {
                        ForEach(0..<16, id: \.self) { index in
                            RoundedRectangle(cornerRadius: 0.8).fill(.white.opacity(index < 10 ? 1 : 0.2))
                        }
                    }
                } else {
                    GeometryReader { geo in
                        Capsule().fill(.white.opacity(0.2))
                            .overlay(alignment: .leading) { Capsule().fill(.white).frame(width: geo.size.width * level) }
                    }
                }
            }
            .frame(height: 2.6)
            .padding(.horizontal, 10)
            .padding(.top, 2)
            Spacer(minLength: 0)
        }
        .frame(width: 100, height: 27)
        .background(shape.fill(.black))
    }

    private var fill: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: row)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(.white.opacity(0.13))
                    Rectangle().fill(.white).frame(width: geo.size.width * level)
                    sides()
                    sides(dark: true).mask(alignment: .leading) { Rectangle().frame(width: geo.size.width * level) }
                }
            }
            .padding(.horizontal, 4)
        }
        .frame(width: 92, height: 31)
        .background(shape.fill(.black))
        .clipShape(shape)
    }

    private var outline: some View {
        let size = CGSize(width: 100, height: 19)
        return sides()
            .frame(width: size.width, height: size.height, alignment: .top)
            .background(shape.fill(.black))
            .overlay { HUDOutline(level: Float(level), muted: false, layout: IslandLayout(size: size, topRadius: 4, bottomRadius: 9), line: 1.4) }
    }
}
