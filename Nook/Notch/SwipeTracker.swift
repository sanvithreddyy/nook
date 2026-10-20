import AppKit

enum SwipeDirection {
    case up, down, left, right
}

/// Turns one two-finger trackpad gesture into at most one swipe, in finger direction.
final class SwipeTracker {
    private var dx: CGFloat = 0
    private var dy: CGFloat = 0
    private var fired = false

    private let verticalThreshold: CGFloat = 26
    private let horizontalThreshold: CGFloat = 44

    func consume(_ event: NSEvent) -> SwipeDirection? {
        // Mouse wheels have no phases; trackpads report began/changed/ended.
        guard event.hasPreciseScrollingDeltas else { return nil }
        if event.phase == .began || event.phase == .mayBegin {
            dx = 0; dy = 0; fired = false
        }
        if event.phase == .ended || event.phase == .cancelled || event.momentumPhase != [] {
            return nil
        }
        guard !fired else { return nil }
        // With natural scrolling the deltas already follow the fingers.
        let sign: CGFloat = event.isDirectionInvertedFromDevice ? 1 : -1
        dx += event.scrollingDeltaX * sign
        dy += event.scrollingDeltaY * sign
        if abs(dy) > verticalThreshold, abs(dy) > abs(dx) * 1.2 {
            fired = true
            return dy > 0 ? .down : .up
        }
        if abs(dx) > horizontalThreshold, abs(dx) > abs(dy) * 1.5 {
            fired = true
            return dx > 0 ? .right : .left
        }
        return nil
    }
}
