import AppKit
import SwiftUI

/// Borderless panel pinned over the notch. It never resizes: the island animates inside it,
/// so window-server resizes never land mid-spring.
final class NotchPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isFloatingPanel = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = true
        // Above the menu bar, on every space, including beside fullscreen apps.
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        animationBehavior = .none
    }

    // Becoming key lets sliders and buttons track drags without activating the app.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Accepts the first click so a press on the island acts immediately.
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    var onScroll: ((NSEvent) -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override var safeAreaInsets: NSEdgeInsets { NSEdgeInsetsZero }

    override func scrollWheel(with event: NSEvent) {
        onScroll?(event)
    }
}
