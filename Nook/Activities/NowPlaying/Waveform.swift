import AppKit
import SwiftUI

/// Bars that move while audio plays and settle to dots when paused.
/// Runs as Core Animation keyframes in the render server, so a playing track costs the app
/// no per-frame work. The motion is decorative, not driven by the audio.
struct Waveform: View {
    let isPlaying: Bool
    let tint: Color

    var body: some View {
        if Motion.isDisabled {
            // ImageRenderer can't draw AppKit views; snapshots get a still frame.
            HStack(spacing: WaveformLayerView.gap) {
                ForEach([0.5, 0.9, 0.65, 0.35], id: \.self) { h in
                    Capsule().fill(tint).frame(width: WaveformLayerView.barWidth, height: isPlaying ? 16 * h : WaveformLayerView.barWidth)
                }
            }
            .frame(width: WaveformLayerView.width, height: 16)
        } else {
            WaveformRepresentable(isPlaying: isPlaying, tint: NSColor(tint))
                .frame(width: WaveformLayerView.width, height: 16)
        }
    }
}

private struct WaveformRepresentable: NSViewRepresentable {
    let isPlaying: Bool
    let tint: NSColor

    func makeNSView(context: Context) -> WaveformLayerView { WaveformLayerView() }

    func updateNSView(_ view: WaveformLayerView, context: Context) {
        view.update(isPlaying: isPlaying, tint: tint)
    }
}

final class WaveformLayerView: NSView {
    static let barWidth: CGFloat = 2.5
    static let gap: CGFloat = 2
    static let count = 4
    static var width: CGFloat { CGFloat(count) * barWidth + CGFloat(count - 1) * gap }

    // Each bar loops through its own heights at its own pace so the group never visibly repeats.
    private static let patterns: [[CGFloat]] = [
        [0.45, 0.9, 0.55, 1.0, 0.35, 0.75, 0.45],
        [0.8, 0.4, 1.0, 0.6, 0.9, 0.3, 0.8],
        [0.55, 1.0, 0.4, 0.8, 0.5, 0.95, 0.55],
        [0.3, 0.7, 0.9, 0.45, 0.65, 0.35, 0.3],
    ]
    private static let durations: [CFTimeInterval] = [1.25, 1.05, 1.4, 1.15]

    private var bars: [CALayer] = []
    private var isPlaying: Bool?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for _ in 0..<Self.count {
            let bar = CALayer()
            bar.cornerRadius = Self.barWidth / 2
            bar.cornerCurve = .continuous
            layer?.addSublayer(bar)
            bars.append(bar)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // Decorative: clicks go to the SwiftUI tap gesture around it.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, bar) in bars.enumerated() {
            bar.position = CGPoint(x: CGFloat(i) * (Self.barWidth + Self.gap) + Self.barWidth / 2, y: bounds.midY)
            if bar.bounds.width == 0 {
                bar.bounds = CGRect(x: 0, y: 0, width: Self.barWidth, height: Self.barWidth)
            }
        }
        CATransaction.commit()
    }

    func update(isPlaying playing: Bool, tint: NSColor) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bars.forEach { $0.backgroundColor = tint.cgColor }
        CATransaction.commit()

        guard playing != isPlaying else { return }
        isPlaying = playing
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let maxHeight = max(bounds.height, 16)
        for (i, bar) in bars.enumerated() {
            let current = bar.presentation()?.bounds.height ?? bar.bounds.height
            bar.removeAllAnimations()
            let rest = playing ? maxHeight * Self.patterns[i][0] : Self.barWidth
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            bar.bounds.size.height = rest
            CATransaction.commit()

            // Settle from wherever the bar was to its resting height.
            let settle = CASpringAnimation(keyPath: "bounds.size.height")
            settle.fromValue = current
            settle.toValue = rest
            settle.stiffness = 260
            settle.damping = 24
            settle.duration = settle.settlingDuration
            bar.add(settle, forKey: "settle")

            guard playing, !reduceMotion else { continue }
            let loop = CAKeyframeAnimation(keyPath: "bounds.size.height")
            loop.values = Self.patterns[i].map { $0 * maxHeight }
            loop.calculationMode = .cubic
            loop.duration = Self.durations[i]
            loop.repeatCount = .infinity
            // Starts where the settle ends (the pattern's first value), so the hand-off is seamless.
            loop.beginTime = CACurrentMediaTime() + settle.settlingDuration
            bar.add(loop, forKey: "loop")
        }
    }
}
