import AppKit
import SwiftUI

/// Owns the panel on one screen and turns raw pointer events into hover, press and swipe.
final class NotchWindowController {
    let panel: NotchPanel
    private let model: NotchModel
    private let swipe = SwipeTracker()
    private let pages = PageTracker()
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
        #if DEBUG
        if CommandLine.arguments.contains("-scroll-probe") { runScrollProbe() }
        if CommandLine.arguments.contains("-island-menu") { runMenuStill() }
        if CommandLine.arguments.contains("-gesture-fuzz") { runGestureFuzz() }
        #endif
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
        // Seen before the views: over a list that scrolls, a sideways gesture is still the page turn.
        if let scrolls = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] event in
            self?.routeOverList(event) ?? event
        }) { monitors.append(scrolls) }
        // A click anywhere else closes the expanded island.
        if let outside = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            #if DEBUG
            // A recorded swipe runs on its own while the Mac is in use.
            if CommandLine.arguments.contains("-preview-swipe") || Self.ignoresPointer { return }
            #endif
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
        #if DEBUG
        // -ignore-pointer: a recording runs on its own while the Mac is in use; the pointer passes through.
        if Self.ignoresPointer {
            setIgnoresMouse(true)
            return
        }
        #endif
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
        guard Prefs.bool(Prefs.swipeGestures) else { return }
        if pages.consume(event, model: model) { return }
        guard let direction = swipe.consume(event) else { return }
        switch direction {
        case .down:
            if Prefs.bool(Prefs.swipeToOpen), !model.isExpanded { model.expand() }
        case .up:
            if Prefs.bool(Prefs.swipeToClose), model.isExpanded { model.collapse() }
        case .left, .right:
            // Open, pages follow the fingers (PageTracker) unless Settings turns them at once; closed, it skips tracks.
            guard Prefs.bool(Prefs.swipeSideways), !model.isExpanded || !Prefs.bool(Prefs.swipePagesFollow) else { return }
            onSwipe?(direction)
        }
    }

    // MARK: Lists that scroll

    private enum ListUnder { case none, scrolls, still }
    /// What the gesture under way began over: a list that scrolls (a busy day's events), one whose
    /// content fits, or neither.
    private var gestureList = ListUnder.none
    /// The view under the fingers when the gesture under way began. AppKit hands each event to whatever
    /// is under the pointer at that moment, and a page following the fingers slides its list there; the
    /// list would keep the rest of the gesture, the lift too, and the page would stop part-way.
    private weak var gestureView: NSView?

    /// A list that scrolls keeps up and down for itself, but its scroll view would also keep sideways
    /// gestures from the page turn. So over one, the page turn reads the gesture first, and once it has
    /// it sideways the list gets no more of it. A scroll view with nothing to scroll gets none of the
    /// gesture, so swiping over it opens, closes and turns pages as anywhere else. Anywhere else, the
    /// whole gesture goes to the view it began over.
    private func routeOverList(_ event: NSEvent) -> NSEvent? {
        guard event.window === panel else { return event }
        return routeOverList(event, at: event.locationInWindow)
    }

    private func routeOverList(_ event: NSEvent, at point: NSPoint) -> NSEvent? {
        guard event.hasPreciseScrollingDeltas else { return event }
        if event.phase == .began || event.phase == .mayBegin {
            gestureView = view(at: point)
            gestureList = model.isExpanded ? list(at: point) : .none
        }
        guard Prefs.bool(Prefs.swipeGestures) else { return event }
        switch gestureList {
        case .none:
            guard let gestureView, gestureView.window === panel else { return event }
            gestureView.scrollWheel(with: event)
            return nil
        case .still:
            handleScroll(event)
            return nil
        case .scrolls:
            return pages.consume(event, model: model) ? nil : event
        }
    }

    private func view(at point: NSPoint) -> NSView? {
        panel.contentView.flatMap { $0.hitTest($0.convert(point, from: nil)) }
    }

    /// The scroll view under a point, and whether its content is taller than it.
    private func list(at point: NSPoint) -> ListUnder {
        guard var view = view(at: point) else { return .none }
        while true {
            if let scroller = view as? NSScrollView {
                return (scroller.documentView?.frame.height ?? 0) > scroller.contentView.bounds.height + 1 ? .scrolls : .still
            }
            guard let parent = view.superview else { return .none }
            view = parent
        }
    }

    #if DEBUG
    private static let ignoresPointer = CommandLine.arguments.contains("-ignore-pointer")

    // -gesture-fuzz [seed]: two-finger gestures as a trackpad sends them (rests, flicks with
    // momentum, drags that settle back, pulls past the end, small up-down moves), at random moments, through
    // the app's own event path. After each burst and a pause, the page must be at rest: FUZZ lines, STUCK
    // for a page left mid-turn. -gesture-fuzz-x <fraction>: where across the island the fingers are.
    // -gesture-script adds "swipe" (a steady swipe on the trackpad's 120 Hz clock) and "dot" (a page dot
    // clicked); with -probe-swipes, each swipe's missed frames print as GESTURE lines. scripts/gestures.sh runs it.
    private func runGestureFuzz() {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3.5))
            guard let host = panel.contentView else { return }
            let args = CommandLine.arguments
            func value(_ flag: String) -> String? { args.firstIndex(of: flag).flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } }
            var rng = FuzzRandom(state: value("-gesture-fuzz").flatMap { UInt64($0) } ?? 1)
            let bursts = value("-gesture-fuzz-bursts").flatMap { Int($0) } ?? 60
            let size = model.layout(for: .expanded).size
            let across = value("-gesture-fuzz-x").flatMap { Double($0) } ?? 0.25
            @MainActor func scrollers(_ view: NSView) -> [NSScrollView] {
                ((view as? NSScrollView).map { [$0] } ?? []) + view.subviews.flatMap(scrollers)
            }
            // -gesture-fuzz-list: over the middle of a list that scrolls (a busy day's events).
            let scrolling = args.contains("-gesture-fuzz-list")
                ? scrollers(host).first { ($0.documentView?.frame.height ?? 0) > $0.contentView.bounds.height + 1 } : nil
            // -gesture-fuzz-beside-list <points>: level with the first list, this far from its left edge
            // (negative: left of it), where a page moving sideways slides the list under the fingers.
            let besideList = value("-gesture-fuzz-beside-list").flatMap(Double.init).flatMap { dx in
                scrollers(host).first.map { list in
                    let frame = list.convert(list.bounds, to: nil)
                    return NSPoint(x: frame.minX + dx, y: frame.midY)
                }
            }
            let inWindow = besideList ?? scrolling.map { $0.convert(NSPoint(x: $0.bounds.midX, y: $0.bounds.midY), to: nil) }
                ?? NSPoint(x: host.bounds.midX - size.width / 2 + size.width * across, y: host.bounds.maxY - model.notch.size.height - 50)
            let onScreen = panel.convertPoint(toScreen: host.convert(inWindow, to: nil))
            let screenPoint = CGPoint(x: onScreen.x, y: (NSScreen.screens.first?.frame.height ?? 0) - onScreen.y)
            let target = host.hitTest(host.convert(inWindow, from: nil))
            print("FUZZ start seed=\(rng.state) cards=\(model.cards.count) page=\(model.card.name) target=\(target.map { String(describing: type(of: $0)) } ?? "none") list=\(list(at: inWindow)) at=\(Int(inWindow.x)),\(Int(inWindow.y)) lists=\(scrollers(host).map { "\($0.convert($0.bounds, to: nil).integral)" })")
            fflush(stdout)
            // CGEvent's phases: began 1, changed 2, ended 4, cancelled 8, may begin 128; momentum 1 2 3.
            @MainActor func send(_ phase: Int64, momentum: Int64 = 0, dx: Int32 = 0, dy: Int32 = 0) {
                guard let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0) else { return }
                cg.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
                cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
                cg.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum)
                cg.location = screenPoint
                if let event = NSEvent(cgEvent: cg), let routed = routeOverList(event, at: inWindow),
                   let view = host.hitTest(host.convert(inWindow, from: nil)) {
                    view.scrollWheel(with: routed)
                }
            }
            @MainActor func pause(_ seconds: Double) async { try? await Task.sleep(for: .seconds(seconds)) }
            @MainActor func r(_ range: ClosedRange<Double>) -> Double { Double.random(in: range, using: &rng) }
            @MainActor func ri(_ range: ClosedRange<Int>) -> Int { Int.random(in: range, using: &rng) }
            @MainActor func coin() -> Bool { ri(0...1) == 1 }
            let kinds = ["rest", "flick", "nudge", "pull", "updown", "tap", "swipe", "dot"]
            /// One gesture; returns its name for the log. `touch`: the fingers rest a moment first (^ in a script).
            @MainActor func gesture(_ kind: Int, dir: Int32, touch: Bool) async -> String {
                if touch { send(128); await pause(r(0.0...0.06)) }
                switch kind {
                case 0:
                    // Fingers rest and lift without moving.
                    if !touch { send(128) }
                    await pause(r(0.03...0.4))
                    send(8)
                    return "rest"
                case 1:
                    send(1)
                    for _ in 0..<ri(4...8) { send(2, dx: dir * Int32(ri(15...35))); await pause(0.008) }
                    send(4)
                    // Momentum after the fingers lift, unless they come down again first.
                    var speed = 30
                    send(0, momentum: 1, dx: dir * Int32(speed))
                    for _ in 0..<ri(0...14) { speed = max(speed * 4 / 5, 1); send(0, momentum: 2, dx: dir * Int32(speed)); await pause(0.008) }
                    send(0, momentum: 3)
                    return "flick\(dir > 0 ? "+" : "-")"
                case 2:
                    send(1)
                    for _ in 0..<ri(5...12) { send(2, dx: dir * Int32(ri(1...4))); await pause(0.016) }
                    send(4)
                    return "nudge\(dir > 0 ? "+" : "-")"
                case 3:
                    send(1)
                    for _ in 0..<ri(20...40) { send(2, dx: dir * Int32(ri(3...8))); await pause(0.01) }
                    send(coin() ? 4 : 8)
                    return "pull\(dir > 0 ? "+" : "-")"
                case 4:
                    send(1)
                    for _ in 0..<ri(2...4) { send(2, dx: Int32(ri(-1...1)), dy: Int32(ri(-4...4))); await pause(0.016) }
                    send(4)
                    return "updown"
                case 6:
                    // A steady swipe as the trackpad reports one, on its 120 Hz clock whatever the main
                    // thread is doing: touch, 0.3 s of travel that speeds up and eases off (about 190 pt),
                    // the lift, then 0.4 s of momentum.
                    let clock = ContinuousClock()
                    let start = clock.now
                    var tick = 0
                    func at(_ n: Int) async { try? await Task.sleep(until: start + .microseconds(8333 * n), clock: clock) }
                    send(128); tick += 1; await at(tick)
                    send(1); tick += 1; await at(tick)
                    for i in 0..<36 {
                        let speed = sin(Double(i + 1) / 37 * .pi) * 5.5
                        send(2, dx: dir * Int32(speed.rounded(.up))); tick += 1; await at(tick)
                    }
                    send(4); tick += 1; await at(tick)
                    var speed = 6.0
                    send(0, momentum: 1, dx: dir * Int32(speed)); tick += 1; await at(tick)
                    for _ in 0..<48 { speed *= 0.93; send(0, momentum: 2, dx: dir * Int32(speed.rounded())); tick += 1; await at(tick) }
                    send(0, momentum: 3)
                    return "swipe\(dir > 0 ? "+" : "-")"
                case 7:
                    // The next or previous page's dot clicked.
                    model.page(dir > 0 ? 1 : -1)
                    return "dot\(dir > 0 ? "+" : "-")"
                default:
                    // A quick touch that moves a little sideways.
                    send(1)
                    send(2, dx: dir * 6)
                    send(4)
                    return "tap\(dir > 0 ? "+" : "-")"
                }
            }
            // -gesture-script "nudge+ 0.1 rest": the same gestures and pauses every burst instead of random ones.
            let script = value("-gesture-script")?.split(separator: " ").map(String.init)
            var stuck = 0
            // Each burst starts on the page the run opened on.
            let firstPage = model.card
            for burst in 1...bursts {
                var names: [String] = []
                if let script {
                    for token in script {
                        if let gap = Double(token) {
                            names.append(token)
                            await pause(gap)
                            continue
                        }
                        let touch = token.hasPrefix("^")
                        let word = token.drop { $0 == "^" }
                        let dir: Int32 = word.hasSuffix("-") ? -1 : 1
                        guard let kind = kinds.firstIndex(of: String(word.filter(\.isLetter))) else { continue }
                        names.append((touch ? "^" : "") + (await gesture(kind, dir: dir, touch: touch)))
                        names.append("[drag=\(Int(model.pageDrag)) settling=\(model.pageSettle != nil) page=\(model.cards.firstIndex(of: model.card) ?? -1)]")
                    }
                } else {
                    for _ in 0..<ri(1...4) {
                        let dir: Int32 = coin() ? 1 : -1
                        let touch = coin()
                        names.append((touch ? "^" : "") + (await gesture(ri(0...5), dir: dir, touch: touch)))
                        let gap = r(0.0...0.5)
                        names.append(String(format: "%.2fs", gap))
                        await pause(gap)
                    }
                }
                await pause(1.0)
                let atRest = model.pageDrag == 0 && model.pageSettle == nil
                if !atRest { stuck += 1 }
                print("FUZZ \(burst) \(atRest ? "ok" : "STUCK drag=\(Int(model.pageDrag)) settling=\(model.pageSettle != nil)") open=\(model.isExpanded) page=\(model.cards.firstIndex(of: model.card) ?? -1) \(names.joined(separator: " "))")
                fflush(stdout)
                // Put it back for the next burst: open, at rest.
                if !atRest { model.collapse(); await pause(0.6) }
                if !model.isExpanded { model.expand(); await pause(1.0) }
                if model.card != firstPage, model.cards.contains(firstPage) { model.show(firstPage); await pause(0.6) }
            }
            print("FUZZ done stuck=\(stuck) of \(bursts)")
            fflush(stdout)
            NSApp.terminate(nil)
        }
    }

    /// A seeded generator, so a fuzz run can be repeated.
    private struct FuzzRandom: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    /// -island-menu: the open island's right-click menu, open for a few seconds, for a still.
    private func runMenuStill() {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard let host = panel.contentView else { return }
            let point = NSPoint(x: host.bounds.midX - 120, y: host.bounds.maxY - 120)
            guard let click = NSEvent.mouseEvent(with: .rightMouseDown, location: host.convert(point, to: nil), modifierFlags: [],
                                                 timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber,
                                                 context: nil, eventNumber: 0, clickCount: 1, pressure: 1),
                  let menu = host.menu(for: click) else {
                print("MENU none"); fflush(stdout); return
            }
            print("MENU " + menu.items.map { $0.isSeparatorItem ? "—" : $0.title }.joined(separator: " | "))
            fflush(stdout)
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { menu.cancelTracking() }
            NSMenu.popUpContextMenu(menu, with: click, for: host)
        }
    }

    /// -scroll-probe: two-finger gestures through the app's own event path, as a trackpad sends them:
    /// over the day's events (up, down, sideways) and elsewhere on the island (sideways, then up). Prints
    /// what each moved (SCROLL lines).
    private func runScrollProbe() {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3.5))
            @MainActor func scrollers(_ view: NSView) -> [NSScrollView] {
                ((view as? NSScrollView).map { [$0] } ?? []) + view.subviews.flatMap(scrollers)
            }
            // -scroll-probe-short: the day's events fit, so the list doesn't scroll; only a swipe up over it.
            let short = CommandLine.arguments.contains("-scroll-probe-short")
            guard let host = panel.contentView,
                  let list = short
                      ? scrollers(host).first(where: { $0.convert($0.bounds, to: nil).midX > host.bounds.width * 0.4 && $0.convert($0.bounds, to: nil).midX < host.bounds.width * 0.6 })
                      : scrollers(host).first(where: { ($0.documentView?.frame.height ?? 0) > $0.contentView.bounds.height + 1 }) else {
                print("SCROLL no list"); fflush(stdout); return
            }
            // Screen points (top-left origin, as CGEvent wants): the list's middle, and the island's left
            // part, over the music.
            @MainActor func global(_ view: NSView, _ x: CGFloat, _ y: CGFloat) -> CGPoint {
                let inWindow = view.convert(NSPoint(x: view.bounds.width * x, y: view.bounds.height * y), to: nil)
                let onScreen = panel.convertPoint(toScreen: inWindow)
                return CGPoint(x: onScreen.x, y: (NSScreen.screens.first?.frame.height ?? 0) - onScreen.y)
            }
            let overList = global(list, 0.5, 0.5)
            let elsewhere = CGPoint(x: panel.frame.minX + panel.frame.width * 0.3, y: overList.y)
            @MainActor func state(_ step: String) {
                print("SCROLL \(step): list at \(Int(list.contentView.bounds.origin.y)) of \(Int((list.documentView?.frame.height ?? 0) - list.contentView.bounds.height)), page \(model.card.name), open \(model.isExpanded)")
                fflush(stdout)
            }
            @MainActor func gesture(dx: Int32, dy: Int32, at point: CGPoint) async {
                // began, changed ×12, ended: phases as CGEvent numbers them.
                for (phase, count) in [(Int64(1), 1), (2, 12), (4, 1)] {
                    for _ in 0..<count {
                        guard let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                                               wheel1: phase == 2 ? dy : 0, wheel2: phase == 2 ? dx : 0, wheel3: 0) else { continue }
                        cg.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
                        cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
                        cg.location = point
                        cg.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(panel.windowNumber))
                        cg.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(panel.windowNumber))
                        // Made this way an event has no window, so AppKit won't deliver it: do what it does,
                        // the monitor's routing, then the view under the point.
                        let screenY = (NSScreen.screens.first?.frame.height ?? 0) - point.y
                        let inWindow = panel.convertPoint(fromScreen: NSPoint(x: point.x, y: screenY))
                        if let event = NSEvent(cgEvent: cg), let routed = routeOverList(event, at: inWindow),
                           let target = host.hitTest(host.convert(inWindow, from: nil)) {
                            target.scrollWheel(with: routed)
                        }
                        try? await Task.sleep(for: .milliseconds(12))
                    }
                }
                try? await Task.sleep(for: .seconds(0.9))
            }
            state("start")
            // -scroll-demo: slow scrolls down the list in two steps and back, for a recording.
            if CommandLine.arguments.contains("-scroll-demo") {
                @MainActor func slow(_ dy: Int32, steps: Int) async {
                    for (phase, count) in [(Int64(1), 1), (2, steps), (4, 1)] {
                        for _ in 0..<count {
                            guard let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                                                   wheel1: phase == 2 ? dy : 0, wheel2: 0, wheel3: 0) else { continue }
                            cg.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
                            cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
                            if let event = NSEvent(cgEvent: cg) { list.scrollWheel(with: event) }
                            try? await Task.sleep(for: .milliseconds(16))
                        }
                    }
                    try? await Task.sleep(for: .seconds(1.2))
                }
                await slow(-3, steps: 40)
                await slow(-3, steps: 40)
                await slow(-3, steps: 40)
                state("at the end")
                await slow(3, steps: 120)
                state("after the demo")
                return
            }
            if short {
                await gesture(dx: 0, dy: 12, at: overList)
                state("after a swipe up over the events")
                return
            }
            await gesture(dx: 0, dy: -10, at: overList)
            state("after up-down over the list")
            await gesture(dx: 0, dy: 10, at: overList)
            state("after back over the list")
            await gesture(dx: -14, dy: 0, at: overList)
            state("after sideways over the list")
            await gesture(dx: 14, dy: 0, at: elsewhere)
            state("after sideways back, elsewhere")
            await gesture(dx: 0, dy: 12, at: elsewhere)
            state("after a swipe up elsewhere")
        }
    }
    #endif
}
