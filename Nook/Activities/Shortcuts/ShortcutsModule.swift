import SwiftUI

/// Apple's Shortcuts widget on the notch: four tiles, each in its colour with the shortcut's glyph at
/// the top and its name at the bottom. Click one to run it; it shows that it's running, then a tick.
struct ShortcutsModule: View {
    @Environment(ShortcutsModel.self) private var shortcuts
    @Environment(\.homeScale) private var k
    @AppStorage(Prefs.shortcutsPicked) private var picked = ""

    var body: some View {
        let names = ShortcutsModel.shown(names: shortcuts.names, picked: ShortcutsModel.picks(from: picked))
        Grid(horizontalSpacing: 7 * k, verticalSpacing: 7 * k) {
            ForEach(0..<2, id: \.self) { row in
                GridRow {
                    ForEach(0..<2, id: \.self) { column in
                        let index = row * 2 + column
                        if index < names.count {
                            ShortcutTile(name: names[index], color: Self.palette[index % Self.palette.count])
                        } else {
                            Color.clear
                        }
                    }
                }
            }
        }
    }

    /// Apple's Shortcuts tile colours: the first four measured from Apple's own widget, the rest from
    /// the same palette by eye.
    static let palette: [Color] = [0xF2D000, 0xFCBC72, 0x00D6E7, 0xF78584, 0x5ACB6E, 0x5E9BF5, 0xA67CEB, 0xF27FBF].map(Color.init(hex:))
}

private struct ShortcutTile: View {
    @Environment(ShortcutsModel.self) private var shortcuts
    @Environment(\.homeScale) private var k
    let name: String
    let color: Color
    @State private var hovering = false

    var body: some View {
        let running = shortcuts.running.contains(name)
        let finished = shortcuts.finished.contains(name)
        Button { shortcuts.run(name) } label: {
            VStack(alignment: .leading, spacing: 0) {
                Group {
                    if running {
                        ProgressView().controlSize(.small).tint(.white)
                    } else {
                        Image(systemName: finished ? "checkmark" : "square.2.layers.3d.top.filled")
                            .font(.system(size: 17 * k, weight: .semibold))
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
                .frame(height: 18 * k)
                Spacer(minLength: 0)
                Text(name)
                    .font(.system(size: 13 * k, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(10 * k)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 12 * k, style: .continuous)
                    .fill(color.gradient)
                    .brightness(hovering ? 0.06 : 0)
            }
            .contentShape(RoundedRectangle(cornerRadius: 12 * k, style: .continuous))
        }
        .buttonStyle(TileButtonStyle())
        .onHover { inside in withAnimation(.easeOut(duration: 0.15)) { hovering = inside } }
        .accessibilityLabel("Run \(name)")
    }
}

/// Dims while pressed, like the island's other buttons, without their round hover.
private struct TileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? ButtonFeedback.pressed : 1)
            .animation(ButtonFeedback.press, value: configuration.isPressed)
    }
}

extension Color {
    /// 0xRRGGBB.
    nonisolated init(hex: Int) {
        self.init(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}
