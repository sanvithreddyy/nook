import SwiftUI

/// One side of a transient notification beside the notch, drawn like macOS 27's compact views:
/// large semibold words, glyphs centred on the island's round ends, Apple's colours for status.
struct NotificationSide: View {
    @Environment(NotchModel.self) private var model
    let note: NotchNotification
    let edge: HorizontalEdge

    var body: some View {
        Group {
            switch note {
            case .volume, .brightness:
                if model.hudStyle.usesSides {
                    if edge == .leading {
                        HUDGlyph(note: note)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, Compact.outer)
                    } else {
                        HUDValue(note: note, style: model.hudStyle)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding(.trailing, Compact.outer)
                    }
                }
            case .charging(let level):
                battery(level: level, style: .charging)
            case .onBattery(let level):
                battery(level: level, style: .normal)
            case .lowBattery(let level):
                battery(level: level, style: .low)
            case .lowPowerMode(let on):
                if edge == .leading {
                    words(note.title)
                } else {
                    words(on ? "On" : "Off", color: on ? .status(.yellow) : .white.opacity(0.6), edge: .trailing)
                }
            case .device(_, let symbol, let battery):
                if edge == .leading {
                    Image(systemName: symbol)
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white)
                        .concentric(.leading, height: model.notch.size.height)
                } else {
                    BatteryRing(level: battery.map { Double($0) / 100 })
                        .concentric(.trailing, height: model.notch.size.height)
                }
            case .audioSwitched(let symbol):
                if edge == .leading {
                    Image(systemName: symbol)
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white)
                        .concentric(.leading, height: model.notch.size.height)
                } else {
                    SwitchBadge()
                        .concentric(.trailing, height: model.notch.size.height)
                }
            }
        }
    }

    @ViewBuilder
    private func battery(level: Int, style: BatteryGlyph.Style) -> some View {
        if edge == .leading {
            words(note.title)
        } else {
            HStack(spacing: 6) {
                Text("\(level)%")
                    .font(.system(size: Compact.fontSize, weight: .semibold).monospacedDigit())
                    .foregroundStyle(style.textColor)
                    .contentTransition(.numericText(value: Double(level)))
                BatteryGlyph(level: Double(level) / 100, style: style)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, Compact.outer - 3)
        }
    }

    private func words(_ text: String, color: Color = .white, edge: HorizontalEdge = .leading) -> some View {
        Text(text)
            .font(.system(size: Compact.fontSize, weight: .semibold))
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
            .frame(maxWidth: .infinity, alignment: edge == .leading ? .leading : .trailing)
            .padding(edge == .leading ? .leading : .trailing, Compact.outer)
    }
}

extension View {
    /// Centres a glyph on the island's round end, the way Apple places compact content concentric
    /// with the pill's outer edge. The side's frame includes the island's ear, so that comes off first.
    func concentric(_ edge: HorizontalEdge, height: CGFloat) -> some View {
        frame(width: height, height: height)
            .padding(edge == .leading ? .leading : .trailing, Compact.ear)
            .frame(maxWidth: .infinity, alignment: edge == .leading ? .leading : .trailing)
    }
}

/// Sound moved to these headphones: Apple's blue disc with the turn-back arrow, which swings in.
private struct SwitchBadge: View {
    @State private var shown = false

    var body: some View {
        Image(systemName: "arrow.uturn.backward")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .rotationEffect(.degrees(shown || Motion.reduceMotion ? 0 : 40))
            .frame(width: 20, height: 20)
            .background(Circle().fill(Color.status(.blue, white: .white.opacity(0.22))))
            .scaleEffect(shown || Motion.reduceMotion ? 1 : 0.85)
            .onAppear { withAnimation(Motion.ease(.spring(duration: 0.4, bounce: 0.15))) { shown = true } }
            .accessibilityLabel("Audio switched")
    }
}

/// Apple's battery: a dark body in the status colour with the level in the bright colour.
struct BatteryGlyph: View {
    enum Style {
        case normal, charging, low, lowPower

        var tint: Color {
            switch self {
            case .normal: .white
            case .charging: .status(.green)
            // A warning, so red whichever colours are chosen.
            case .low: .red
            case .lowPower: .status(.yellow)
            }
        }

        var textColor: Color { self == .normal ? .white : tint }
    }

    let level: Double
    let style: Style

    var body: some View {
        let body = RoundedRectangle(cornerRadius: 4, style: .continuous)
        HStack(spacing: 1.5) {
            ZStack(alignment: .leading) {
                body.fill(style.tint.opacity(style == .normal ? 0.3 : 0.38))
                Rectangle().fill(style.tint)
                    .frame(width: max(26 * min(max(level, 0), 1), 4))
            }
            .frame(width: 26, height: 13)
            .clipShape(body)
            .overlay {
                if style == .charging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 8.5, weight: .heavy))
                        .foregroundStyle(.black.opacity(0.75))
                }
            }
            UnevenRoundedRectangle(cornerRadii: .init(topLeading: 0, bottomLeading: 0, bottomTrailing: 1.5, topTrailing: 1.5))
                .fill(style.tint.opacity(style == .normal ? 0.3 : 0.38))
                .frame(width: 2, height: 5)
        }
    }
}

/// A device's battery as a ring in Apple's green. Before the level is known a short arc turns;
/// once it's known the ring fills to it.
struct BatteryRing: View {
    let level: Double?

    var body: some View {
        ZStack {
            Circle().stroke(Color.status(.green).opacity(0.3), lineWidth: Self.line)
            if let level {
                FillingArc(level: min(max(level, 0), 1))
                    .transition(.opacity)
            } else {
                TurningArc()
                    .transition(.opacity)
            }
        }
        .frame(width: 19, height: 19)
        .animation(Motion.level, value: level == nil)
    }

    static let line: CGFloat = 2.6
    static let style = StrokeStyle(lineWidth: line, lineCap: .round)
}

private struct FillingArc: View {
    let level: Double
    @State private var shown = 0.0

    var body: some View {
        Circle()
            .trim(from: 0, to: shown)
            .stroke(Color.status(.green), style: BatteryRing.style)
            .rotationEffect(.degrees(-90))
            .onAppear { withAnimation(Motion.ease(.spring(duration: 0.7, bounce: 0.1))) { shown = level } }
            .onChange(of: level) { _, new in withAnimation(Motion.level) { shown = new } }
    }
}

private struct TurningArc: View {
    @State private var turning = false

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.28)
            .stroke(Color.status(.green), style: BatteryRing.style)
            .rotationEffect(.degrees(turning ? 270 : -90))
            .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: turning)
            // Reduce Motion: the short arc stands still until the level arrives.
            .onAppear { turning = !Motion.reduceMotion }
    }
}

extension Color {
    /// A status colour as Apple uses it (green charging, orange timer…), or white when Settings asks
    /// for white. Read when drawn, so a change shows the next time something appears.
    static func status(_ color: Color, white: Color = .white) -> Color {
        Prefs.bool(Prefs.statusColors) ? color : white
    }
}

