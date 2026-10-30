import SwiftUI

// Volume and brightness under the notch, in the style picked in Settings (`HUDStyle`).
// The island and the Settings thumbnails draw the same views.

/// The speaker (with its waves filling to the level), the AirPods when sound goes to them, or the sun.
struct HUDGlyph: View {
    let note: NotchNotification
    /// Dark, for the inside of the slider's white fill.
    var dark = false

    var body: some View {
        Group {
            switch note {
            case .volume(let level, let muted, let output):
                if let output, !muted {
                    Image(systemName: output)
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 17, weight: .medium))
                } else {
                    Image(systemName: muted || level == 0 ? "speaker.slash.fill" : "speaker.wave.3.fill", variableValue: Double(level))
                        .font(.system(size: 14, weight: .semibold))
                        .opacity(muted ? 0.55 : 1)
                }
            case .brightness(let level):
                Image(systemName: level < 0.5 ? "sun.min.fill" : "sun.max.fill")
                    .font(.system(size: 15, weight: .semibold))
            default:
                EmptyView()
            }
        }
        .contentTransition(.symbolEffect(.replace))
        .foregroundStyle(dark ? Color(white: 0.16) : .white)
    }
}

/// The level beside the notch: a percentage, or presses out of 16 for the Steps style.
struct HUDValue: View {
    let note: NotchNotification
    let style: HUDStyle
    @AppStorage(Prefs.hudShowsNumber) private var showsNumber = true

    var body: some View {
        if showsNumber, let level = note.hudLevel {
            let value = style == .segments ? Int((level.value * 16).rounded()) : Int((level.value * 100).rounded())
            Text("\(value)")
                .font(.system(size: Compact.fontSize, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(level.muted ? 0.45 : 1))
                .contentTransition(.numericText(value: Double(value)))
                .animation(Motion.level, value: value)
        }
    }
}

/// What drops below the notch for the Ledge, Slider and Steps styles (Outline draws on the island's edge).
struct HUDBelow: View {
    let note: NotchNotification
    let style: HUDStyle
    let bump: Int
    let bumpUp: Bool

    var body: some View {
        if let level = note.hudLevel {
            Group {
                switch style {
                case .ledge:
                    LedgeBar(level: level.value, muted: level.muted)
                        .padding(.top, 5)
                case .slider:
                    ThickSlider(note: note, level: level.value, muted: level.muted)
                        .padding(.top, 6)
                case .segments:
                    Segments(level: level.value, muted: level.muted)
                        .padding(.top, 6)
                case .outline:
                    EmptyView()
                }
            }
            .modifier(BumpStretch(bump: bump, up: bumpUp))
        }
    }
}

/// Pressing past either end pulls the level out a little and lets it spring back, as the iPhone's volume does.
private struct BumpStretch: ViewModifier {
    let bump: Int
    let up: Bool

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: 1.0, trigger: bump) { view, stretch in
            view.scaleEffect(x: stretch, y: 2 - stretch, anchor: up ? .leading : .trailing)
        } keyframes: { _ in
            SpringKeyframe(1.045, duration: 0.12, spring: .snappy)
            SpringKeyframe(1, duration: 0.45, spring: .bouncy)
        }
    }
}

/// Ledge: a thin bar; muted keeps the level but dims it.
private struct LedgeBar: View {
    let level: Float
    let muted: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(muted ? 0.1 : 0.18))
                Capsule().fill(.white.opacity(muted ? 0.3 : 1))
                    .frame(width: max(geo.size.width * CGFloat(min(max(level, 0), 1)), 5))
            }
        }
        .frame(height: 5)
        .animation(Motion.level, value: level)
        .animation(Motion.level, value: muted)
    }
}

/// Slider: Control Center's thick white slider, the glyph inside turning dark where the white covers it.
private struct ThickSlider: View {
    let note: NotchNotification
    let level: Float
    let muted: Bool
    static let height: CGFloat = 28

    var body: some View {
        GeometryReader { geo in
            let fill = max(geo.size.width * CGFloat(min(max(level, 0), 1)), Self.height)
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.14))
                glyph(dark: false)
                Capsule().fill(.white.opacity(muted ? 0.45 : 1))
                    .frame(width: fill)
                    .overlay(alignment: .leading) { glyph(dark: true) }
                    .clipShape(Capsule())
            }
            .animation(Motion.level, value: level)
        }
        .frame(height: Self.height)
    }

    private func glyph(dark: Bool) -> some View {
        HUDGlyph(note: note, dark: dark)
            .frame(width: Self.height + 4, height: Self.height)
            .padding(.leading, 2)
    }
}

/// Steps: sixteen segments, one per press; Option-Shift's quarter steps fill part of one.
private struct Segments: View {
    let level: Float
    let muted: Bool

    var body: some View {
        let steps = CGFloat(min(max(level, 0), 1)) * 16
        HStack(spacing: 3) {
            ForEach(0..<16, id: \.self) { index in
                let fill = min(max(steps - CGFloat(index), 0), 1)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous).fill(.white.opacity(muted ? 0.08 : 0.16))
                        RoundedRectangle(cornerRadius: 2, style: .continuous).fill(.white.opacity(muted ? 0.3 : 1))
                            .frame(width: geo.size.width * fill)
                    }
                }
            }
        }
        .frame(height: 6)
        .animation(Motion.level, value: steps)
    }
}

/// Outline: the island's own edge is the meter, a line from the left side around the bottom and up
/// the right, filled to the level. Drawn over the island inside its outline.
struct HUDOutline: View {
    let level: Float
    let muted: Bool
    let layout: IslandLayout
    let notchHeight: CGFloat

    var body: some View {
        let path = OutlinePath(ear: layout.topRadius, radius: layout.bottomRadius, start: notchHeight * 0.38)
        ZStack {
            path.stroke(.white.opacity(0.14), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            path.trim(from: 0, to: CGFloat(min(max(level, 0), 1)))
                .stroke(.white.opacity(muted ? 0.35 : 1), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .animation(Motion.level, value: level)
        }
    }
}

/// The island's body edge, inset by 3 pt, as an open path from the left side to the right.
nonisolated private struct OutlinePath: Shape {
    let ear: CGFloat
    let radius: CGFloat
    let start: CGFloat

    func path(in rect: CGRect) -> Path {
        let inset: CGFloat = 3
        let left = rect.minX + ear + inset, right = rect.maxX - ear - inset, bottom = rect.maxY - inset
        // The same smoothed corner as NotchShape, a little smaller because it sits inside it.
        let reach = max(0, min((radius - inset) * 1.5, (right - left) / 2, bottom - start))
        let handle = reach * 0.2333
        var p = Path()
        p.move(to: CGPoint(x: left, y: rect.minY + start))
        p.addLine(to: CGPoint(x: left, y: bottom - reach))
        p.addCurve(to: CGPoint(x: left + reach, y: bottom),
                   control1: CGPoint(x: left, y: bottom - handle), control2: CGPoint(x: left + handle, y: bottom))
        p.addLine(to: CGPoint(x: right - reach, y: bottom))
        p.addCurve(to: CGPoint(x: right, y: bottom - reach),
                   control1: CGPoint(x: right - handle, y: bottom), control2: CGPoint(x: right, y: bottom - handle))
        p.addLine(to: CGPoint(x: right, y: rect.minY + start))
        return p
    }
}
