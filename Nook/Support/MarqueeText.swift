import SwiftUI

/// One line that scrolls at 30 pt/s when it doesn't fit, pausing at the start of each pass.
/// Fits stay still and left-aligned.
struct MarqueeText<Label: View>: View {
    var id: String
    var speed: Double = 30
    var gap: CGFloat = 36
    @ViewBuilder var label: () -> Label

    @State private var labelWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var loop: Task<Void, Never>?

    private var overflows: Bool { labelWidth > containerWidth + 0.5 && containerWidth > 0 }

    var body: some View {
        HStack(spacing: gap) {
            label()
                .fixedSize()
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { labelWidth = $0 }
            if overflows {
                label().fixedSize()
            }
        }
        .offset(x: offset)
        // minWidth 0: without it the frame grows to the full label width and pushes siblings aside.
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { containerWidth = $0 }
        .clipped()
        .mask(EdgeFade(active: overflows))
        .onChange(of: id, initial: true) { restart() }
        .onChange(of: overflows) { restart() }
        .onDisappear { loop?.cancel() }
    }

    private func restart() {
        loop?.cancel()
        offset = 0
        guard overflows else { return }
        let distance = labelWidth + gap
        let duration = distance / speed
        loop = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.6))
                guard !Task.isCancelled else { return }
                withAnimation(.linear(duration: duration)) { offset = -distance }
                try? await Task.sleep(for: .seconds(duration))
                guard !Task.isCancelled else { return }
                var reset = Transaction()
                reset.disablesAnimations = true
                withTransaction(reset) { offset = 0 }
            }
        }
    }
}

private struct EdgeFade: View {
    let active: Bool

    var body: some View {
        HStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                .frame(width: active ? 10 : 0)
            Rectangle()
            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: active ? 14 : 0)
        }
    }
}
