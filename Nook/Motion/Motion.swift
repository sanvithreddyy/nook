import AppKit
import SwiftUI

/// Every spring the island uses (mass 1, stiffness / damping).
enum Motion {
    static var hoverIn: Animation? { spring(250, 14) }
    static var hoverOut: Animation? { spring(200, 20) }
    static var press: Animation? { spring(160, 18) }
    static var activityIn: Animation? { spring(150, 20) }
    static var activityOut: Animation? { spring(175, 17.5) }
    static var notificationIn: Animation? { spring(150, 20) }
    static var notificationOut: Animation? { spring(150, 16) }
    static var peekIn: Animation? { spring(250, 21) }
    static var peekOut: Animation? { spring(250, 25) }
    static var expand: Animation? { spring(250, 24) }
    static var collapse: Animation? { spring(250, 28) }
    /// HUD level changes while a HUD is already showing.
    static var level: Animation? { spring(400, 34) }

    static let unlockHold: Duration = .milliseconds(475)

    /// Snapshot rendering turns motion off so every frame shows a settled state.
    static var isDisabled = false

    static func ease(_ animation: Animation) -> Animation? { isDisabled ? nil : animation }

    private static func spring(_ stiffness: Double, _ damping: Double) -> Animation? {
        if isDisabled { return nil }
        // Reduce Motion: the island still changes shape, but quickly and without overshoot.
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { return .easeOut(duration: 0.2) }
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
}

extension AnyTransition {
    /// Side slots of a live activity grow out of the notch edge.
    static func islandSide(_ edge: HorizontalEdge) -> AnyTransition {
        let anchor: UnitPoint = edge == .leading ? .trailing : .leading
        return .asymmetric(
            insertion: .modifier(
                active: IslandContentModifier(opacity: 0, blur: 8, scaleX: 0.2, scaleY: 0.6, anchor: anchor),
                identity: IslandContentModifier(opacity: 1, blur: 0, scaleX: 1, scaleY: 1, anchor: anchor)
            ),
            removal: .modifier(
                active: IslandContentModifier(opacity: 0, blur: 4, scaleX: 0.25, scaleY: 0.6, anchor: anchor),
                identity: IslandContentModifier(opacity: 1, blur: 0, scaleX: 1, scaleY: 1, anchor: anchor)
            )
        )
    }

    /// Larger content (quick peek, expanded view) sharpens into place from just under the notch.
    static var islandBody: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: IslandContentModifier(opacity: 0, blur: 10, scaleX: 0.75, scaleY: 0.9, anchor: .top),
                identity: IslandContentModifier(opacity: 1, blur: 0, scaleX: 1, scaleY: 1, anchor: .top)
            ).animation(Motion.peekIn?.delay(0.05)),
            removal: .modifier(
                active: IslandContentModifier(opacity: 0, blur: 10, scaleX: 0.75, scaleY: 0.9, anchor: .top),
                identity: IslandContentModifier(opacity: 1, blur: 0, scaleX: 1, scaleY: 1, anchor: .top)
            ).animation(Motion.ease(.easeOut(duration: 0.16)))
        )
    }
}
