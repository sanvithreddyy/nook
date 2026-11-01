import AppKit

enum SwipeDirection {
    case up, down, left, right
}

/// Turns one two-finger trackpad gesture into at most one swipe, in finger direction.
final class SwipeTracker {
    private var dx: CGFloat = 0
    private var dy: CGFloat = 0
    private var fired = false
    /// Read once per gesture: the sensitivity's distance and whether swipes are reversed.
    private var distance: CGFloat = 1
    private var reversed = false

    private let verticalThreshold: CGFloat = 26
    private let horizontalThreshold: CGFloat = 44

    func consume(_ event: NSEvent) -> SwipeDirection? {
        // Mouse wheels have no phases; trackpads report began/changed/ended.
        guard event.hasPreciseScrollingDeltas else { return nil }
        if event.phase == .began || event.phase == .mayBegin {
            dx = 0; dy = 0; fired = false
            distance = SwipeSensitivity.current.distance
            reversed = Prefs.bool(Prefs.swipeReversed)
        }
        if event.phase == .ended || event.phase == .cancelled || event.momentumPhase != [] {
            return nil
        }
        guard !fired else { return nil }
        // With natural scrolling the deltas already follow the fingers.
        let sign: CGFloat = (event.isDirectionInvertedFromDevice ? 1 : -1) * (reversed ? -1 : 1)
        dx += event.scrollingDeltaX * sign
        dy += event.scrollingDeltaY * sign
        if abs(dy) > verticalThreshold * distance, abs(dy) > abs(dx) * 1.2 {
            fired = true
            return dy > 0 ? .down : .up
        }
        if abs(dx) > horizontalThreshold * distance, abs(dx) > abs(dy) * 1.5 {
            fired = true
            return dx > 0 ? .right : .left
        }
        return nil
    }
}

/// Two fingers sideways on the open island carry its page with them: each gesture's axis is decided from
/// its first few points of travel, and while it's sideways the page follows, let go at the fingers' speed.
final class PageTracker {
    private enum Axis { case horizontal, vertical }
    /// Decided once per gesture, from its first few points of travel.
    private var axis: Axis?
    private var x: CGFloat = 0
    private var y: CGFloat = 0
    /// The last tenth of a second of travel, for the speed at release.
    private var samples: [(time: CFTimeInterval, x: CGFloat)] = []

    /// The page goes half again as far as the fingers, so a short swipe carries it.
    private static let gain: CGFloat = 1.5

    /// Returns whether the event was the page's; up and down stay with the open and close swipes.
    func consume(_ event: NSEvent, model: NotchModel) -> Bool {
        guard event.hasPreciseScrollingDeltas else { return false }
        if event.phase == .began || event.phase == .mayBegin {
            axis = nil
            x = 0
            y = 0
            samples = []
            return false
        }
        // The trackpad's momentum after the fingers lift belongs to the settle already under way.
        if event.momentumPhase != [] { return axis == .horizontal }
        guard model.isExpanded, Prefs.bool(Prefs.swipeSideways), Prefs.bool(Prefs.swipePagesFollow) else { return false }
        if event.phase == .ended || event.phase == .cancelled {
            guard axis == .horizontal else { return false }
            axis = nil
            model.endPageDrag(velocity: velocity)
            return true
        }
        guard event.phase == .changed else { return false }
        // Finger direction, as the swipes read it (reversed if Settings says so).
        let sign: CGFloat = (event.isDirectionInvertedFromDevice ? 1 : -1) * (Prefs.bool(Prefs.swipeReversed) ? -1 : 1)
        x += event.scrollingDeltaX * sign * Self.gain
        y += event.scrollingDeltaY * sign * Self.gain
        if axis == nil, hypot(x, y) > 6 {
            axis = abs(x) > abs(y) ? .horizontal : .vertical
            // Only fingers going sideways take the page. Fingers that rest, or go up or down, leave a page
            // that's settling to settle, rather than holding it part-way with nothing to let it go.
            if axis == .horizontal { model.beginPageDrag() }
        }
        guard axis == .horizontal else { return false }
        let now = CACurrentMediaTime()
        samples.append((now, x))
        samples.removeAll { now - $0.time > 0.1 }
        model.dragPage(to: x)
        return true
    }

    private var velocity: CGFloat {
        guard let first = samples.first, let last = samples.last, last.time > first.time else { return 0 }
        return (last.x - first.x) / CGFloat(last.time - first.time)
    }
}
