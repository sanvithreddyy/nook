import AppKit
import SwiftUI

/// One line that scrolls at 30 pt/s when it doesn't fit, pausing at the start of each pass.
/// Fits stay still and left-aligned. The scroll is a Core Animation keyframe on a hosted copy of
/// the label, so it costs no per-frame work in the app.
struct MarqueeText<Label: View>: View {
    var id: String
    var speed: Double = 30
    var gap: CGFloat = 36
    @ViewBuilder var label: () -> Label

    @State private var labelSize: CGSize = .zero
    @State private var containerWidth: CGFloat = 0

    private var overflows: Bool { labelSize.width > containerWidth + 0.5 && containerWidth > 0 }

    var body: some View {
        label()
            .fixedSize()
            .hidden()
            .onGeometryChange(for: CGSize.self) { $0.size } action: { labelSize = $0 }
            // minWidth 0: without it the frame grows to the full label width and pushes siblings aside.
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { containerWidth = $0 }
            .overlay(alignment: .leading) {
                if overflows, !Motion.isDisabled, !Motion.reduceMotion {
                    MarqueeScroller(
                        content: AnyView(HStack(spacing: gap) {
                            label().fixedSize()
                            label().fixedSize()
                        }),
                        distance: labelSize.width + gap,
                        speed: speed,
                        key: id
                    )
                } else {
                    label().fixedSize()
                }
            }
            .clipped()
            .mask(EdgeFade(active: overflows))
    }
}

private struct MarqueeScroller: NSViewRepresentable {
    let content: AnyView
    let distance: CGFloat
    let speed: Double
    let key: String

    func makeNSView(context: Context) -> MarqueeScrollView { MarqueeScrollView() }

    func updateNSView(_ view: MarqueeScrollView, context: Context) {
        view.update(content: content, distance: distance, speed: speed, key: key)
    }
}

final class MarqueeScrollView: NSView {
    private let host = NSHostingView(rootView: AnyView(EmptyView()))
    private var runningKey: String?
    /// The scroll waiting for a width to time its fade against.
    private var pending: (distance: CGFloat, speed: Double)?
    /// SwiftUI's mask doesn't reach an AppKit layer, so the edges fade here. The right edge always
    /// fades, where the text runs out of room; the left only while the text is moving, so the first
    /// letter is whole while it rests.
    private let fade = CAGradientLayer()
    private static let pause = 1.6
    private static let left: CGFloat = 10, right: CGFloat = 16

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        fade.startPoint = CGPoint(x: 0, y: 0.5)
        fade.endPoint = CGPoint(x: 1, y: 0.5)
        fade.colors = [NSColor.clear.cgColor, NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
        layer?.mask = fade
        host.wantsLayer = true
        addSubview(host)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // Display only: clicks go to the island underneath.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        let size = host.fittingSize
        host.frame = CGRect(x: 0, y: (bounds.height - size.height) / 2, width: size.width, height: size.height)
        guard bounds.width > 0 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fade.frame = bounds
        fade.locations = locations(moving: false)
        CATransaction.commit()
        if let pending {
            self.pending = nil
            start(distance: pending.distance, speed: pending.speed)
        }
    }

    func update(content: AnyView, distance: CGFloat, speed: Double, key: String) {
        // Re-host only when the text changes; re-assigning on every SwiftUI pass would loop
        // through hosting-view layout and back into SwiftUI.
        let runKey = "\(key)|\(Int(distance))"
        guard runKey != runningKey else { return }
        runningKey = runKey
        host.rootView = content
        host.layer?.removeAnimation(forKey: "marquee")
        fade.removeAnimation(forKey: "fade")
        // The fade's timing needs the width, which the next layout pass knows.
        pending = (distance, speed)
        needsLayout = true
    }

    /// The scroll and the left edge's fade, started together so they stay in step.
    private func start(distance: CGFloat, speed: Double) {
        guard let layer = host.layer else { return }
        let pause = Self.pause
        let travel = Double(distance) / speed
        let total = pause + travel
        let begin = CACurrentMediaTime()

        let scroll = CAKeyframeAnimation(keyPath: "transform.translation.x")
        scroll.values = [0, 0, -distance]
        scroll.keyTimes = [0, NSNumber(value: pause / total), 1]
        scroll.duration = total
        scroll.repeatCount = .infinity
        scroll.beginTime = begin
        layer.add(scroll, forKey: "marquee")

        // Fades in as the text sets off and out as the next copy arrives at the start.
        let ramp = min(0.25, travel / 4)
        let edge = CAKeyframeAnimation(keyPath: "locations")
        edge.values = [locations(moving: false), locations(moving: false), locations(moving: true),
                       locations(moving: true), locations(moving: false)]
        edge.keyTimes = [0, pause / total, (pause + ramp) / total, (total - ramp) / total, 1].map { NSNumber(value: $0) }
        edge.duration = total
        edge.repeatCount = .infinity
        edge.beginTime = begin
        fade.add(edge, forKey: "fade")
    }

    private func locations(moving: Bool) -> [NSNumber] {
        let width = max(bounds.width, 1)
        let left = moving ? Self.left / width : 0.0001
        return [0, NSNumber(value: left), NSNumber(value: 1 - Self.right / width), 1]
    }
}

private struct EdgeFade: View {
    let active: Bool

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: active ? 16 : 0)
        }
    }
}
