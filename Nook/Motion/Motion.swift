import AppKit
import SwiftUI

/// Every spring the island uses (mass 1, stiffness / damping), fitted to frame-by-frame measurements
/// of a well-made notch island, then made livelier where the closed band felt stiff. Opening and the
/// closed band growing settle a little past their size; closing and shrinking never do. One kind of
/// content hands over to another at the bare notch.
enum Motion {
    /// Opening: response 0.445 s at 0.6 damping, about 9 % past the open size before it settles.
    static var expand: Animation? { spring(199, 17) }
    /// Closing: critically damped, so it never dips below the closed size.
    static var collapse: Animation? { spring(266, 34) }
    /// The open island changing shape: another page, the shelf making room for a drop.
    static var reshape: Animation? { spring(250, 24) }
    /// The closed band growing into new content, quicker than the reference and with a soft settle about
    /// 5 % past its size, as the Dynamic Island does (response 0.5 s at 0.68 damping); shrinking away from
    /// it (0.38 s) stays critically damped.
    static var grow: Animation? { spring(158, 17) }
    static var shrink: Animation? { spring(273, 33) }
    /// How long after the old content goes the band turns from shrinking to growing into the new one.
    /// As in the reference, it turns a little before it reaches the bare notch (290–380 ms there).
    static let handOff: Duration = .milliseconds(320)
    static var peekIn: Animation? { spring(439, 36) }
    static var peekOut: Animation? { spring(816, 57) }
    /// Content sharpening into the open island: quicker than the shape, done before its overshoot.
    static var content: Animation? { spring(987, 63) }
    /// HUD level changes while a HUD is already showing.
    static var level: Animation? { spring(400, 34) }
    /// Volume and brightness arriving and leaving: straight from what the band shows and back, quickly,
    /// with a little life (response 0.32 s at 0.78 damping). A key's answer can't wait for a hand-over.
    static var hud: Animation? { spring(386, 31) }
    /// The HUD's bar meeting a new level: a quick kick a few percent past it (0.28 s at 0.7 damping).
    static var levelKick: Animation? { spring(503, 31) }

    /// Drop targets lighting up under a drag.
    static var press: Animation? { spring(630, 43) }

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
    /// Content beside the notch blurs in while the band grows and blurs out fast as it shrinks, so old
    /// and new never share a slot.
    /// `quick`: a key's answer (volume, brightness), in almost at once.
    static func islandSide(_ edge: HorizontalEdge, quick: Bool = false) -> AnyTransition {
        let anchor: UnitPoint = edge == .leading ? .trailing : .leading
        return .asymmetric(
            insertion: .modifier(active: IslandContentModifier.hidden(blur: 6, scaleX: 0.9, scaleY: 0.9, anchor: anchor), identity: IslandContentModifier.shown(anchor: anchor))
                .animation(Motion.ease(.easeOut(duration: quick ? 0.16 : 0.2))?.delay(quick ? 0.03 : 0.12)),
            removal: .modifier(active: IslandContentModifier.hidden(blur: 6, scaleX: 0.9, scaleY: 0.9, anchor: anchor), identity: IslandContentModifier.shown(anchor: anchor))
                .animation(Motion.ease(.easeOut(duration: 0.08)))
        )
    }

    /// Volume and brightness beside the notch: in as quickly as `islandSide`. Out to the bare notch, they
    /// stay inside the band and ride its edges back into the notch, sharp at first, then shrinking and
    /// blurring away as they reach it, so the island and what it holds close as one thing rather than an
    /// empty shape after the content. Out to other content (the music), they clear quickly so it comes
    /// into an empty slot.
    /// `travel`: the side's slot width, how far the island's edge moves in to reach the notch. A view on its
    /// way out keeps its last place, so it's moved there itself, on the band's spring, to stay with the edge.
    static func hudSide(_ edge: HorizontalEdge, toNotch: Bool, travel: CGFloat) -> AnyTransition {
        let anchor: UnitPoint = edge == .leading ? .trailing : .leading
        let inward = toNotch ? (edge == .leading ? travel : -travel) : 0
        let shrink: AnyTransition = Motion.reduceMotion ? .identity
            : AnyTransition.scale(scale: toNotch ? 0.7 : 0.84, anchor: anchor).combined(with: .offset(x: inward))
        return .asymmetric(
            insertion: islandSide(edge, quick: true),
            removal: fadeBlur(5, toNotch ? absorbed(0.26) : Motion.ease(.easeOut(duration: 0.1)))
                .combined(with: shrink.animation(Motion.shrink))
        )
    }

    /// The HUD's bar under the notch: in as `islandBody`; out, it rises back into the notch with the band's
    /// bottom edge and narrows on the same spring, fading as `hudSide` does.
    static func hudBelow(toNotch: Bool) -> AnyTransition {
        let retract: AnyTransition = Motion.reduceMotion ? .identity
            : AnyTransition.modifier(active: IslandContentModifier(opacity: 1, blur: 0, scaleX: toNotch ? 0.6 : 0.8, scaleY: 1, anchor: .top),
                                     identity: IslandContentModifier.shown(anchor: .top))
                .combined(with: .offset(y: -14))
        return .asymmetric(
            insertion: islandBody,
            removal: fadeBlur(4, toNotch ? absorbed(0.22) : Motion.ease(.easeOut(duration: 0.1)))
                .combined(with: retract.animation(Motion.shrink))
        )
    }

    /// A fade that holds while the content travels with the band, then goes quickly as it reaches the notch.
    private static func absorbed(_ duration: Double) -> Animation? {
        Motion.ease(.timingCurve(0.77, 0, 0.175, 1, duration: duration))
    }

    private static func fadeBlur(_ blur: CGFloat, _ animation: Animation?) -> AnyTransition {
        .modifier(active: FadeBlur(opacity: 0, blur: blur), identity: FadeBlur(opacity: 1, blur: 0))
            .animation(animation)
    }

    /// Larger content (quick peek, expanded view) sharpens into place from just under the notch while
    /// the shape is still opening, and is gone within a few frames when it closes.
    static var islandBody: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: IslandContentModifier.hidden(blur: 6, scaleX: 0.88, scaleY: 0.88, anchor: .top), identity: IslandContentModifier.shown(anchor: .top))
                .animation(Motion.content?.delay(0.06)),
            removal: .modifier(active: IslandContentModifier.hidden(blur: 6, scaleX: 0.88, scaleY: 0.88, anchor: .top), identity: IslandContentModifier.shown(anchor: .top))
                .animation(Motion.ease(.easeOut(duration: 0.06)))
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

/// Fading and blurring together, for a fade that runs on its own curve beside a move.
struct FadeBlur: ViewModifier {
    var opacity: Double
    var blur: CGFloat

    func body(content: Content) -> some View {
        content
            .blur(radius: blur)
            .opacity(opacity)
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

