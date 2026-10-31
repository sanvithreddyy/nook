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
    /// Where and when the pointer last moved, for its speed.
    private var lastPointer: (point: CGPoint, time: CFTimeInterval)?
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
        model.notch = screen.islandMetrics
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

    /// The island can grow or shrink under a still pointer (a HUD ends, a swipe collapses it, the
    /// meeting drop comes and goes), so re-run hit testing whenever that changes, not only when the mouse moves.
    private func observeLayout() {
        withObservationTracking {
            _ = model.layout
            _ = model.showsCompanion
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.pointerMoved(fromLayoutChange: true)
                self?.observeLayout()
            }
        }
    }

    func place(on screen: NSScreen) {
        self.screen = screen
        model.notch = screen.islandMetrics
        var size = model.maximumSize
        size.width = min(size.width, screen.frame.width)
        model.panelSize = size
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
        let settled = model.settledPresentation
        return Self.hitRect(for: model.layout(for: settled), presentation: settled, in: panel.frame, inset: model.notch.topInset)
    }

    /// The island's target rect in screen coordinates, padded so the notch is easy to hit.
    /// `inset`: a pill starts this far below the top edge; the strip above it counts as the island.
    static func hitRect(for layout: IslandLayout, presentation: Presentation, in frame: CGRect, inset: CGFloat = 0) -> CGRect {
        var rect = CGRect(x: frame.midX + layout.shift - layout.size.width / 2,
                          y: frame.maxY - layout.size.height - inset,
                          width: layout.size.width,
                          height: layout.size.height + inset)
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

    /// The drop beside the island (a timer, a meeting about to start), when it shows.
    private func companionRect() -> CGRect? {
        guard model.showsCompanion else { return nil }
        return Self.companionRect(island: model.layout, drop: model.companionSize, in: panel.frame, inset: model.notch.topInset)
    }

    /// The drop's target rect: just right of the island, padded a little below like the island's.
    static func companionRect(island: IslandLayout, drop: CGSize, in frame: CGRect, inset: CGFloat = 0) -> CGRect {
        var rect = CGRect(x: frame.midX + island.shift + island.size.width / 2 + NotchModel.companionGap,
                          y: frame.maxY - drop.height - inset,
                          width: drop.width,
                          height: drop.height + inset)
        rect.origin.y -= 4
        // Same reach past the top edge as the island, for a pointer pushed into the menu bar.
        rect.size.height += 5
        return rect
    }

    /// Where a file drag opens the shelf: the island, or the menu-bar strip a little either side of
    /// the notch. Kept out of app windows below, so drags into a browser's tab bar don't trigger it,
    /// unless Settings asks for the wide area, which reaches further along and a little below.
    func catchesDrag(at point: CGPoint) -> Bool {
        guard !model.isSuppressed else { return false }
        let frame = panel.frame
        let wide = Prefs.bool(Prefs.shelfCatchWide)
        let width = model.notch.size.width + (wide ? 420 : 120)
        let height = model.notch.size.height + (wide ? 30 : 0)
        let strip = CGRect(x: frame.midX - width / 2, y: frame.maxY - height, width: width, height: height)
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
            // Clicking another app also ends Settings' preview, which would otherwise hold the island open.
            IslandPreview.shared.isOn = false
            // The page the preview showed isn't one you left open, so "Last page" doesn't keep it.
            guard let self else { return }
            self.model.collapse(remembering: !self.model.isPreviewing)
        }) { monitors.append(outside) }
    }

    /// `fromLayoutChange`: the island resized under a still pointer. That can end a hover
    /// but never starts one, so a peek growing under a parked cursor doesn't hold itself open.
    func pointerMoved(fromLayoutChange: Bool = false) {
        guard !model.isSuppressed else {
            setIgnoresMouse(true)
            return
        }
        // A drag out of a tile or a context menu runs its own event loop and eats the mouse-up.
        if dragBeganOnIsland, NSEvent.pressedMouseButtons & 1 == 0 { dragBeganOnIsland = false }
        let pointer = NSEvent.mouseLocation
        let inside = hitRect().contains(pointer) || companionRect()?.contains(pointer) == true
        setIgnoresMouse(!inside && !dragBeganOnIsland)
        if !fromLayoutChange {
            let now = CACurrentMediaTime()
            let speed = lastPointer.map { hypot(pointer.x - $0.point.x, pointer.y - $0.point.y) / max(now - $0.time, 0.001) } ?? 0
            lastPointer = (pointer, now)
            // Sweeping across the menu bar passes over the notch; only a pointer that slows down there opens it.
            if inside, model.isHovering, !model.isExpanded, speed > 300 { startDwell() }
        }
        guard inside != model.isHovering else { return }
        // The island resized under a still pointer. That never starts a hover, and an open island
        // that turned to a shorter card stays open until the pointer itself moves.
        if fromLayoutChange, inside || model.isExpanded { return }
        hoverChanged(inside)
    }

    /// Setting it messages the window server and commits a window transaction even when it doesn't
    /// change, and this runs on every mouse move anywhere on screen.
    private func setIgnoresMouse(_ ignores: Bool) {
        if panel.ignoresMouseEvents != ignores { panel.ignoresMouseEvents = ignores }
    }

    private func hoverChanged(_ inside: Bool) {
        model.setHovering(inside)
        hoverIntentTask?.cancel()
        if inside {
            collapseTask?.cancel()
            startDwell()
        } else {
            // Whatever opened the track peek, leaving the island closes it.
            if model.peek == .track { model.hidePeek() }
            if model.isExpanded {
                collapseTask = Task { [weak self] in
                    // A small overshoot past the edge doesn't close it.
                    try? await Task.sleep(for: .milliseconds(250))
                    // Stay open while the scrubber is dragged past the edge, while a file drag
                    // lingers near the island looking for the drop area, or under the island's menu.
                    while !Task.isCancelled, let self,
                          (self.dragBeganOnIsland && NSEvent.pressedMouseButtons & 1 != 0)
                            || (self.isFileDragActive() && self.isNearIsland(NSEvent.mouseLocation))
                            || self.model.holdsOpen || self.model.isPreviewing {
                        try? await Task.sleep(for: .milliseconds(50))
                    }
                    guard !Task.isCancelled, let self, !self.model.isHovering else { return }
                    self.model.collapse()
                }
            }
        }
    }

    /// The island opens once the pointer has rested on it for a moment.
    private func startDwell() {
        hoverIntentTask?.cancel()
        hoverIntentTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(Prefs.double(Prefs.hoverDelay), 0.05)))
            guard !Task.isCancelled else { return }
            self?.hoverDwelled()
        }
    }

    private func hoverDwelled() {
        guard model.isHovering, !model.isExpanded else { return }
        if Prefs.bool(Prefs.expandOnHover) {
            // Pointing at the drop opens what it shows; anywhere else, the most relevant card.
            if let card = model.companion?.card, companionRect()?.contains(NSEvent.mouseLocation) == true {
                model.expand(card: card)
            } else {
                model.expand()
            }
        } else if model.liveActivity == .nowPlaying, model.notification == nil, Prefs.bool(Prefs.peekOnHover),
                  companionRect()?.contains(NSEvent.mouseLocation) != true {
            // The peek would cover the meeting drop being pointed at, so it only shows over the island.
            model.showPeek(.track, for: nil)
        }
    }

    // MARK: Swipe

    private func handleScroll(_ event: NSEvent) {
        guard Prefs.bool(Prefs.swipeGestures), let direction = swipe.consume(event) else { return }
        switch direction {
        case .down, .up:
            guard Prefs.bool(Prefs.swipeOpenClose) else { return }
            if direction == .down, !model.isExpanded { model.expand() }
            if direction == .up, model.isExpanded { model.collapse() }
        case .left, .right:
            guard Prefs.bool(Prefs.swipeSideways) else { return }
            onSwipe?(direction)
        }
    }
}
