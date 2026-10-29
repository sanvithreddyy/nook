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
            case .volume(let level, let muted, let output):
                if edge == .leading {
                    // Sound going to AirPods shows the AirPods, as the iPhone's volume does.
                    Group {
                        if let output, !muted {
                            Image(systemName: output)
                                .symbolRenderingMode(.hierarchical)
                                .font(.system(size: 17, weight: .medium))
                        } else {
                            Image(systemName: muted || level == 0 ? "speaker.slash.fill" : "speaker.wave.3.fill", variableValue: Double(level))
                                .font(.system(size: 14, weight: .semibold))
                        }
                    }
                    .contentTransition(.symbolEffect(.replace))
                    .foregroundStyle(.white.opacity(muted ? 0.55 : 1))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, Compact.outer)
                } else {
                    LevelValue(level: level, dimmed: muted)
                }
            case .brightness(let level):
                if edge == .leading {
                    Image(systemName: level < 0.5 ? "sun.min.fill" : "sun.max.fill")
                        .contentTransition(.symbolEffect(.replace))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, Compact.outer)
                } else {
                    LevelValue(level: level, dimmed: false)
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
                    words(on ? "On" : "Off", color: on ? .yellow : .white.opacity(0.6), edge: .trailing)
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

private extension View {
    /// Centres a glyph on the island's round end, the way Apple places compact content
    /// concentric with the pill's outer edge.
    func concentric(_ edge: HorizontalEdge, height: CGFloat) -> some View {
        frame(width: height, height: height)
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
            .rotationEffect(.degrees(shown ? 0 : 50))
            .frame(width: 20, height: 20)
            .background(Circle().fill(.blue))
            .scaleEffect(shown ? 1 : 0.5)
            .onAppear { withAnimation(Motion.ease(.spring(duration: 0.45, bounce: 0.35).delay(0.08))) { shown = true } }
            .accessibilityLabel("Audio switched")
    }
}

/// Volume or brightness as a number on the trailing side: "62".
private struct LevelValue: View {
    let level: Float
    let dimmed: Bool

    var body: some View {
        let value = Int((level * 100).rounded())
        Text("\(value)")
            .font(.system(size: Compact.fontSize, weight: .semibold).monospacedDigit())
            .foregroundStyle(.white.opacity(dimmed ? 0.45 : 1))
            .contentTransition(.numericText(value: Double(value)))
            .animation(Motion.level, value: value)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, Compact.outer)
    }
}

/// The level on a ledge under the notch. Pressing past either end stretches the bar a little and lets
/// it spring back, as the iPhone's volume does; muted keeps the level but dims it.
struct HUDLedge: View {
    let level: Float
    let muted: Bool
    /// Counts presses past an end; `bumpUp` says which end.
    let bump: Int
    let bumpUp: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(muted ? 0.1 : 0.18))
                Capsule().fill(.white.opacity(muted ? 0.3 : 1))
                    .frame(width: max(geo.size.width * CGFloat(min(max(level, 0), 1)), 5))
            }
            .keyframeAnimator(initialValue: 1.0, trigger: bump) { bar, stretch in
                bar.scaleEffect(x: stretch, y: 2 - stretch, anchor: bumpUp ? .leading : .trailing)
            } keyframes: { _ in
                SpringKeyframe(1.045, duration: 0.12, spring: .snappy)
                SpringKeyframe(1, duration: 0.45, spring: .bouncy)
            }
        }
        .frame(height: 5)
        .animation(Motion.level, value: level)
        .animation(Motion.level, value: muted)
    }
}

/// Apple's battery: a dark body in the status colour with the level in the bright colour.
struct BatteryGlyph: View {
    enum Style {
        case normal, charging, low, lowPower

        var tint: Color {
            switch self {
            case .normal: .white
            case .charging: .green
            case .low: .red
            case .lowPower: .yellow
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
            Circle().stroke(Color.green.opacity(0.3), lineWidth: Self.line)
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
            .stroke(Color.green, style: BatteryRing.style)
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
            .stroke(Color.green, style: BatteryRing.style)
            .rotationEffect(.degrees(turning ? 270 : -90))
            .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: turning)
            .onAppear { turning = true }
    }
}
