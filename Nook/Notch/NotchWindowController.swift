import AppKit
import SwiftUI

/// Owns the panel on one screen and turns raw pointer events into hover, press and swipe.
final class NotchWindowController {
    let panel: NotchPanel
    private let model: NotchModel
    private let swipe = SwipeTracker()
    private var monitors: [Any] = []
    private var collapseTask: Task<Void, Never>?
    private var hoverIntentTask: Task<Void, Never>?
    private(set) var screen: NSScreen

    var onSwipe: ((SwipeDirection) -> Void)?

    init<Content: View>(screen: NSScreen, model: NotchModel, @ViewBuilder content: () -> Content) {
        self.screen = screen
        self.model = model
        model.notch = screen.notchMetrics
        panel = NotchPanel(contentRect: .zero)
        let host = NotchHostingView(rootView: AnyView(content().ignoresSafeArea()))
        host.sizingOptions = []
        host.onScroll = { [weak self] event in self?.handleScroll(event) }
        panel.contentView = host
        place(on: screen)
        panel.orderFrontRegardless()
        installMonitors()
    }

    func place(on screen: NSScreen) {
        self.screen = screen
        model.notch = screen.notchMetrics
        let size = model.maximumSize
        let frame = NSRect(x: screen.frame.midX - size.width / 2,
                           y: screen.frame.maxY - size.height,
                           width: size.width,
                           height: size.height)
        panel.setFrame(frame, display: true)
    }

    func tearDown() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        panel.orderOut(nil)
    }

    // MARK: Hit testing

    /// The island's target rect in screen coordinates, padded so the notch is easy to hit.
    private func hitRect() -> CGRect {
        let layout = model.layout
        let frame = panel.frame
        var rect = CGRect(x: frame.midX - layout.size.width / 2,
                          y: frame.maxY - layout.size.height,
                          width: layout.size.width,
                          height: layout.size.height)
        switch model.presentation {
        case .idle:
            rect = rect.insetBy(dx: -10, dy: 0)
            rect.origin.y -= 6
            rect.size.height += 6
        case .expanded:
            // Leaving needs a little more travel than entering, so the edge doesn't flicker.
            rect = rect.insetBy(dx: -8, dy: 0)
            rect.origin.y -= 8
            rect.size.height += 8
        default:
            rect = rect.insetBy(dx: -4, dy: 0)
            rect.origin.y -= 4
            rect.size.height += 4
        }
        return rect
    }

    // MARK: Pointer

    private func installMonitors() {
        let moves: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: moves, handler: { [weak self] _ in
            self?.pointerMoved()
        }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: moves, handler: { [weak self] event in
            self?.pointerMoved()
            return event
        }) { monitors.append(local) }
        // A click anywhere else closes the expanded island.
        if let outside = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            self?.model.collapse()
        }) { monitors.append(outside) }
    }

    func pointerMoved() {
        guard !model.isSuppressed else {
            panel.ignoresMouseEvents = true
            return
        }
        let inside = hitRect().contains(NSEvent.mouseLocation)
        panel.ignoresMouseEvents = !inside
        if inside != model.isHovering { hoverChanged(inside) }
    }

    private func hoverChanged(_ inside: Bool) {
        model.setHovering(inside)
        hoverIntentTask?.cancel()
        if inside {
            collapseTask?.cancel()
            hoverIntentTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(180))
                guard !Task.isCancelled else { return }
                self?.hoverDwelled()
            }
        } else {
            model.setPressed(false)
            if model.peek == .track, Prefs.bool(Prefs.peekOnHover) { model.hidePeek() }
            if model.isExpanded {
                collapseTask = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(140))
                    guard !Task.isCancelled else { return }
                    self?.model.collapse()
                }
            }
        }
    }

    private func hoverDwelled() {
        guard model.isHovering, !model.isExpanded else { return }
        if Prefs.bool(Prefs.expandOnHover) {
            model.expand()
        } else if model.liveActivity == .nowPlaying, model.notification == nil, Prefs.bool(Prefs.peekOnHover) {
            model.showPeek(.track, for: nil)
        }
    }

    // MARK: Swipe

    private func handleScroll(_ event: NSEvent) {
        guard Prefs.bool(Prefs.swipeGestures), let direction = swipe.consume(event) else { return }
        switch direction {
        case .down where !model.isExpanded:
            model.expand()
        case .up where model.isExpanded:
            model.collapse()
        default:
            onSwipe?(direction)
        }
    }
}
