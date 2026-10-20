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
                if overflows, !Motion.isDisabled {
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

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
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
    }

    func update(content: AnyView, distance: CGFloat, speed: Double, key: String) {
        // Re-host only when the text changes; re-assigning on every SwiftUI pass would loop
        // through hosting-view layout and back into SwiftUI.
        let runKey = "\(key)|\(Int(distance))"
        guard runKey != runningKey else { return }
        runningKey = runKey
        host.rootView = content
        needsLayout = true
        guard let layer = host.layer else { return }
        layer.removeAnimation(forKey: "marquee")
        let pause = 1.6
        let travel = Double(distance) / speed
        let scroll = CAKeyframeAnimation(keyPath: "transform.translation.x")
        scroll.values = [0, 0, -distance]
        scroll.keyTimes = [0, NSNumber(value: pause / (pause + travel)), 1]
        scroll.duration = pause + travel
        scroll.repeatCount = .infinity
        layer.add(scroll, forKey: "marquee")
    }
}

private struct EdgeFade: View {
    let active: Bool

    var body: some View {
        HStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                .frame(width: active ? 6 : 0)
            Rectangle()
            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: active ? 14 : 0)
        }
    }
}
