import AppKit
import SwiftUI

/// Every spring the island uses (mass 1, stiffness / damping). Exits are damped like their entrances, so a shrinking island never dips
/// past its size, and feedback (press, hover) answers within about a quarter of a second.
enum Motion {
    static var hoverIn: Animation? { spring(440, 31) }
    static var hoverOut: Animation? { spring(440, 31) }
    static var press: Animation? { spring(630, 43) }
    static var activityIn: Animation? { spring(150, 20) }
    static var activityOut: Animation? { spring(150, 20) }
    static var notificationIn: Animation? { spring(150, 20) }
    static var notificationOut: Animation? { spring(150, 20) }
    static var peekIn: Animation? { spring(250, 25) }
    static var peekOut: Animation? { spring(250, 25) }
    static var expand: Animation? { spring(250, 24) }
    static var collapse: Animation? { spring(250, 28) }
    /// Content settling inside a shape that's already springing: quick, with no overshoot of its own.
    static var content: Animation? { spring(385, 39) }
    /// HUD level changes while a HUD is already showing.
    static var level: Animation? { spring(400, 34) }

    static let unlockHold: Duration = .milliseconds(475)

    /// Snapshot rendering turns motion off so every frame shows a settled state.
    static var isDisabled = false

    /// Reduce Motion: shapes still change, quickly and without overshoot, and nothing travels or scales.
    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    static func ease(_ animation: Animation) -> Animation? {
        if isDisabled { return nil }
        return reduceMotion ? .easeOut(duration: 0.2) : animation
    }

    private static func spring(_ stiffness: Double, _ damping: Double) -> Animation? {
        if isDisabled { return nil }
        if reduceMotion { return .easeOut(duration: 0.2) }
        return .interpolatingSpring(mass: 1, stiffness: stiffness, damping: damping)
    }
}

/// Content entering or leaving the island: blur, fade and squeeze toward the notch.
struct IslandContentModifier: ViewModifier {
    var opacity: Double
    var blur: CGFloat
    var scaleX: CGFloat
    var scaleY: CGFloat
    var anchor: UnitPoint

    func body(content: Content) -> some View {
        content
            .scaleEffect(x: scaleX, y: scaleY, anchor: anchor)
            .blur(radius: blur)
            .opacity(opacity)
    }

    /// The hidden end of a transition; with Reduce Motion it only fades and blurs.
    static func hidden(blur: CGFloat, scaleX: CGFloat, scaleY: CGFloat, anchor: UnitPoint) -> IslandContentModifier {
        let still = Motion.reduceMotion
        return IslandContentModifier(opacity: 0, blur: blur, scaleX: still ? 1 : scaleX, scaleY: still ? 1 : scaleY, anchor: anchor)
    }

    static func shown(anchor: UnitPoint) -> IslandContentModifier {
        IslandContentModifier(opacity: 1, blur: 0, scaleX: 1, scaleY: 1, anchor: anchor)
    }
}

extension AnyTransition {
    /// Side slots of a live activity grow out of the notch edge. The old content leaves quickly and the
    /// new one arrives just after, so the two never crowd the same slot.
    static func islandSide(_ edge: HorizontalEdge) -> AnyTransition {
        let anchor: UnitPoint = edge == .leading ? .trailing : .leading
        return .asymmetric(
            insertion: .modifier(active: IslandContentModifier.hidden(blur: 8, scaleX: 0.2, scaleY: 0.6, anchor: anchor), identity: IslandContentModifier.shown(anchor: anchor))
                .animation(Motion.content?.delay(0.05)),
            removal: .modifier(active: IslandContentModifier.hidden(blur: 8, scaleX: 0.25, scaleY: 0.6, anchor: anchor), identity: IslandContentModifier.shown(anchor: anchor))
                .animation(Motion.ease(.easeOut(duration: 0.12)))
        )
    }

    /// Larger content (quick peek, expanded view) sharpens into place from just under the notch.
    static var islandBody: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: IslandContentModifier.hidden(blur: 10, scaleX: 0.75, scaleY: 0.9, anchor: .top), identity: IslandContentModifier.shown(anchor: .top))
                .animation(Motion.content?.delay(0.05)),
            removal: .modifier(active: IslandContentModifier.hidden(blur: 10, scaleX: 0.75, scaleY: 0.9, anchor: .top), identity: IslandContentModifier.shown(anchor: .top))
                .animation(Motion.ease(.easeOut(duration: 0.16)))
        )
    }

    /// Turning to the next card: the new one comes in from the side it's on, the old one leaves the
    /// other way. `direction` is read while they move, so both agree even though it's set as the turn starts.
    static func cardTurn(_ direction: PageDirection) -> AnyTransition {
        .asymmetric(
            insertion: .modifier(active: CardTurn(progress: 0, arriving: true, direction: direction),
                                 identity: CardTurn(progress: 1, arriving: true, direction: direction)),
            removal: .modifier(active: CardTurn(progress: 0, arriving: false, direction: direction),
                               identity: CardTurn(progress: 1, arriving: false, direction: direction))
        )
    }
}

/// Which way the last card turn went. A reference, so the card leaving reads the same value as the
/// card arriving even though its transition was built before the turn.
final class PageDirection {
    var forward = true
}

struct CardTurn: ViewModifier, Animatable {
    var progress: CGFloat
    let arriving: Bool
    let direction: PageDirection

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        // Forward: arrives from the right, leaves to the left.
        let side: CGFloat = (direction.forward ? 1 : -1) * (arriving ? 1 : -1)
        content
            .offset(x: Motion.reduceMotion ? 0 : (1 - progress) * 16 * side)
            .blur(radius: (1 - progress) * 6)
            .opacity(Double(progress))
            // These follow `progress` frame by frame; animating them again on top makes them lag.
            .transaction { $0.animation = nil }
    }
}

extension EnvironmentValues {
    /// The island's namespace for elements that move between its closed and open forms.
    @Entry var islandNamespace: Namespace.ID?
}

extension View {
    /// Moves between the closed island and the open card instead of fading out and back in.
    func sharedElement(_ id: String) -> some View {
        modifier(SharedElement(id: id))
    }
}

private struct SharedElement: ViewModifier {
    @Environment(\.islandNamespace) private var namespace
    let id: String

    func body(content: Content) -> some View {
        if let namespace, !Motion.reduceMotion {
            content.matchedGeometryEffect(id: id, in: namespace)
        } else {
            content
        }
    }
}

