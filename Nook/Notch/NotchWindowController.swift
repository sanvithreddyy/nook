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
    /// A press that started on the island keeps the panel taking events until release,
    /// so the scrubber gets its mouse-up even when released outside.
    private var dragBeganOnIsland = false
    private(set) var screen: NSScreen

    var onSwipe: ((SwipeDirection) -> Void)?
    /// A file, link or text drag from another app is in progress.
    var isFileDragActive: () -> Bool = { false }

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
        observeLayout()
    }

    /// Hidden while a fullscreen app owns the screen: ordered out so nothing composites over it.
    func setSuppressed(_ suppressed: Bool) {
        if suppressed {
            if model.isHovering { hoverChanged(false) }
            panel.ignoresMouseEvents = true
            panel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
            pointerMoved()
        }
    }

    /// The island can grow or shrink under a still pointer (a HUD ends, a swipe collapses it),
    /// so re-run hit testing whenever the layout changes, not only when the mouse moves.
    private func observeLayout() {
        withObservationTracking {
            _ = model.layout
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.pointerMoved(fromLayoutChange: true)
                self?.observeLayout()
            }
        }
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

    private func hitRect() -> CGRect {
        Self.hitRect(for: model.layout, presentation: model.presentation, in: panel.frame)
    }

    /// The island's target rect in screen coordinates, padded so the notch is easy to hit.
    static func hitRect(for layout: IslandLayout, presentation: Presentation, in frame: CGRect) -> CGRect {
        var rect = CGRect(x: frame.midX - layout.size.width / 2,
                          y: frame.maxY - layout.size.height,
                          width: layout.size.width,
                          height: layout.size.height)
        switch presentation {
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
        // The pointer pushed into the notch sits on the screen's top edge (y == maxY), which
        // `contains` leaves out. Reach one point past it so that edge counts as inside.
        rect.size.height += 1
        return rect
    }

    /// Where a file drag opens the shelf: the island, or the menu-bar strip a little either side of
    /// the notch. Kept out of app windows below, so drags into a browser's tab bar don't trigger it.
    func catchesDrag(at point: CGPoint) -> Bool {
        guard !model.isSuppressed else { return false }
        let frame = panel.frame
        let width = model.notch.size.width + 120
        let strip = CGRect(x: frame.midX - width / 2, y: frame.maxY - model.notch.size.height,
                           width: width, height: model.notch.size.height)
        return hitRect().union(strip).contains(point)
    }

    /// Within reach of the island: a file drag may wander this far without the shelf closing.
    private func isNearIsland(_ point: CGPoint) -> Bool {
        hitRect().insetBy(dx: -60, dy: -60).contains(point)
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
        if let press = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] event in
            if let self, event.window === self.panel { self.dragBeganOnIsland = true }
            return event
        }) { monitors.append(press) }
        let release: (NSEvent) -> Void = { [weak self] _ in
            guard let self, self.dragBeganOnIsland else { return }
            self.dragBeganOnIsland = false
            self.pointerMoved()
        }
        if let globalUp = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp, handler: release) { monitors.append(globalUp) }
        if let localUp = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp, handler: { event in
            release(event)
            return event
        }) { monitors.append(localUp) }
        // A click anywhere else closes the expanded island.
        if let outside = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            self?.model.collapse()
        }) { monitors.append(outside) }
    }

    /// `fromLayoutChange`: the island resized under a still pointer. That can end a hover
    /// but never starts one, so a peek growing under a parked cursor doesn't hold itself open.
    func pointerMoved(fromLayoutChange: Bool = false) {
        guard !model.isSuppressed else {
            panel.ignoresMouseEvents = true
            return
        }
        // A drag out of a tile or a context menu runs its own event loop and eats the mouse-up.
        if dragBeganOnIsland, NSEvent.pressedMouseButtons & 1 == 0 { dragBeganOnIsland = false }
        let inside = hitRect().contains(NSEvent.mouseLocation)
        panel.ignoresMouseEvents = !inside && !dragBeganOnIsland
        guard inside != model.isHovering else { return }
        if inside, fromLayoutChange { return }
        hoverChanged(inside)
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
            // Whatever opened the track peek, leaving the island closes it.
            if model.peek == .track { model.hidePeek() }
            if model.isExpanded {
                collapseTask = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(140))
                    // Stay open while the scrubber is dragged past the edge, or while a file drag
                    // lingers near the island looking for the drop area.
                    while !Task.isCancelled, let self,
                          (self.dragBeganOnIsland && NSEvent.pressedMouseButtons & 1 != 0)
                            || (self.isFileDragActive() && self.isNearIsland(NSEvent.mouseLocation)) {
                        try? await Task.sleep(for: .milliseconds(50))
                    }
                    guard !Task.isCancelled, let self, !self.model.isHovering else { return }
                    self.model.collapse()
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
