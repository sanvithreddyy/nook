import SwiftUI

// Volume and brightness under the notch, in the style picked in Settings (`HUDStyle`).
// The island and the Settings thumbnails draw the same views.

/// The speaker (with its waves filling to the level), the AirPods when sound goes to them, or the sun.
struct HUDGlyph: View {
    let note: NotchNotification
    /// Dark, for the inside of the slider's white fill.
    var dark = false
    /// Presses that raised or lowered the level: each one bounces the glyph the way it went.
    var ups = 0
    var downs = 0

    var body: some View {
        Group {
            switch note {
            case .volume(let level, let muted, let output):
                if let output, !muted {
                    Image(systemName: output)
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 17, weight: .medium))
                } else {
                    // Muting swaps glyphs with a blur rather than a symbol replace, which the next quick
                    // press (moving the waves) would cut short halfway.
                    let name = muted || level == 0 ? "speaker.slash.fill" : "speaker.wave.3.fill"
                    Image(systemName: name, variableValue: Double(level))
                        .font(.system(size: 14, weight: .semibold))
                        .opacity(muted ? 0.55 : 1)
                        .id(name)
                        .transition(.blurReplace)
                }
            case .brightness(let level):
                Image(systemName: level < 0.5 ? "sun.min.fill" : "sun.max.fill")
                    .font(.system(size: 15, weight: .semibold))
            default:
                EmptyView()
            }
        }
        .contentTransition(.symbolEffect(.replace))
        .symbolEffect(.bounce.up, options: .speed(1.6), value: Motion.reduceMotion ? 0 : ups)
        .symbolEffect(.bounce.down, options: .speed(1.6), value: Motion.reduceMotion ? 0 : downs)
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
    /// The bar draws in from empty to the level as the HUD arrives, then follows each press.
    @State private var drawn = Motion.reduceMotion || Motion.isDisabled

    var body: some View {
        if let level = note.hudLevel {
            let shown = drawn ? level.value : 0
            Group {
                switch style {
                case .ledge:
                    LedgeBar(level: shown, muted: level.muted)
                        .padding(.top, 5)
                case .slider:
                    FillBand(note: note, level: shown, muted: level.muted)
                case .segments:
                    Segments(level: shown, muted: level.muted)
                        .padding(.top, 6)
                case .outline:
                    EmptyView()
                }
            }
            .modifier(BumpStretch(bump: bump, up: bumpUp))
            .onAppear { drawn = true }
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
        .animation(Motion.levelKick, value: level)
        .animation(Motion.level, value: muted)
    }
}

/// Slider: the island's lower band is the slider. It fills with white to the level, rounded by the
/// island's own bottom, as Control Center's sliders fill their shape; the glyph and the level sit inside
/// it, dark where the white has reached them.
private struct FillBand: View {
    let note: NotchNotification
    let level: Float
    let muted: Bool
    @AppStorage(Prefs.hudShowsNumber) private var showsNumber = true

    var body: some View {
        GeometryReader { geo in
            let fill = geo.size.width * CGFloat(min(max(level, 0), 1))
            ZStack(alignment: .leading) {
                Rectangle().fill(.white.opacity(0.12))
                Rectangle().fill(.white.opacity(muted ? 0.5 : 1))
                    .frame(width: fill)
                labels(dark: false)
                labels(dark: true)
                    .mask(alignment: .leading) { Rectangle().frame(width: fill) }
            }
            .animation(Motion.levelKick, value: level)
            .animation(Motion.level, value: muted)
        }
    }

    private func labels(dark: Bool) -> some View {
        HStack {
            HUDGlyph(note: note, dark: dark)
            Spacer(minLength: 0)
            if showsNumber, let level = note.hudLevel {
                let value = Int((level.value * 100).rounded())
                Text("\(value)")
                    .font(.system(size: Compact.fontSize, weight: .semibold).monospacedDigit())
                    .foregroundStyle(dark ? Color(white: 0.16) : .white.opacity(level.muted ? 0.45 : 1))
                    .contentTransition(.numericText(value: Double(value)))
                    .animation(Motion.level, value: value)
            }
        }
        .padding(.horizontal, 15)
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
        .animation(Motion.levelKick, value: steps)
    }
}

/// Outline: the island's own edge is the meter. A light runs along its silhouette, from the left ear
/// where it meets the top of the screen, down, across the bottom and up to the right ear, lit to the level
/// with a soft glow at its head.
struct HUDOutline: View {
    let level: Float
    let muted: Bool
    let layout: IslandLayout
    var line: CGFloat = 2.5

    var body: some View {
        let edge = IslandEdge(ear: layout.topRadius, radius: layout.bottomRadius, inset: line * 0.6)
        ZStack {
            edge.stroke(.white.opacity(0.14), style: StrokeStyle(lineWidth: line, lineCap: .round))
            edge.trim(from: 0, to: CGFloat(min(max(level, 0), 1)))
                .stroke(.white.opacity(muted ? 0.35 : 1), style: StrokeStyle(lineWidth: line, lineCap: .round))
                .shadow(color: .white.opacity(muted ? 0 : 0.6), radius: line * 1.4)
                .animation(Motion.levelKick, value: level)
                .animation(Motion.level, value: muted)
        }
    }
}

/// The island's outline without its top, which is the screen's edge: from the left ear round to the
/// right one, a little inside so the light stays on the island. The same smoothed corners as NotchShape.
nonisolated private struct IslandEdge: Shape {
    let ear: CGFloat
    let radius: CGFloat
    let inset: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = CGRect(x: rect.minX + inset, y: rect.minY, width: rect.width - inset * 2, height: rect.height - inset)
        let e = max(0, min(ear, r.width / 4, r.height / 2))
        let reach = max(0, min((radius - inset) * 1.5, (r.width - e * 2) / 2, r.height - e))
        let handle = reach * 0.2333
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX + e, y: r.minY + e), control: CGPoint(x: r.minX + e, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + e, y: r.maxY - reach))
        p.addCurve(to: CGPoint(x: r.minX + e + reach, y: r.maxY),
                   control1: CGPoint(x: r.minX + e, y: r.maxY - handle), control2: CGPoint(x: r.minX + e + handle, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - e - reach, y: r.maxY))
        p.addCurve(to: CGPoint(x: r.maxX - e, y: r.maxY - reach),
                   control1: CGPoint(x: r.maxX - e - handle, y: r.maxY), control2: CGPoint(x: r.maxX - e, y: r.maxY - handle))
        p.addLine(to: CGPoint(x: r.maxX - e, y: r.minY + e))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.maxX - e, y: r.minY))
        return p
    }
}
