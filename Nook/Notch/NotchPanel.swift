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
        // Clicks on buttons and the scrubber work through acceptsFirstMouse; only views that
        // need typing would take key, so the app you're typing in keeps focus.
        becomesKeyOnlyIfNeeded = true
    }

    // Becoming key lets sliders and buttons track drags without activating the app.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Accepts the first click so a press on the island acts immediately, and takes the island's drops (see
/// `IslandDrops`).
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    var onScroll: ((NSEvent) -> Void)?

    var drops: IslandDrops? {
        didSet { registerForDraggedTypes(IslandDrops.types) }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override var safeAreaInsets: NSEdgeInsets { NSEdgeInsetsZero }

    override func scrollWheel(with event: NSEvent) {
        onScroll?(event)
    }

    // MARK: Drops

    /// A point or rect between AppKit's coordinates and SwiftUI's, which start at the top left.
    private func islandPoint(_ sender: NSDraggingInfo) -> CGPoint {
        let point = convert(sender.draggingLocation, from: nil)
        return isFlipped ? point : CGPoint(x: point.x, y: bounds.height - point.y)
    }

    private func viewRect(_ rect: CGRect) -> CGRect {
        isFlipped ? rect : CGRect(x: rect.minX, y: bounds.height - rect.maxY, width: rect.width, height: rect.height)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggingUpdated(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let target = drops?.target(at: islandPoint(sender))
        #if DEBUG
        if target != drops?.hovered { DropLog.write("over \(target.map { "\($0)" } ?? "nothing") at \(islandPoint(sender)) flipped=\(isFlipped)") }
        #endif
        drops?.hover(target)
        return target == nil ? [] : .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        drops?.hover(nil)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let drops, let target = drops.target(at: islandPoint(sender)) else { return false }
        // Onto the shelf, the dragged picture flies into the place the file takes, as Finder settles an icon.
        if target == .shelf, let landing = drops.landing, !IslandDrops.files(on: sender.draggingPasteboard).isEmpty {
            sender.animatesToDestination = true
            let frame = viewRect(landing)
            sender.enumerateDraggingItems(options: [], for: self, classes: [NSPasteboardItem.self], searchOptions: [:]) { item, _, _ in
                item.draggingFrame = frame
            }
        }
        #if DEBUG
        DropLog.write("drop on \(target) at \(islandPoint(sender)) landing=\(drops.landing.map { "\($0)" } ?? "none") animates=\(sender.animatesToDestination)")
        DropLog.windows(after: 0)
        DropLog.windows(after: 0.15)
        DropLog.windows(after: 0.4)
        #endif
        return drops.perform(target, with: sender.draggingPasteboard)
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        drops?.hover(nil)
    }
}

#if DEBUG
/// -drop-log <file>: what each drag over the island is over and where a drop lands, and Nook's windows
/// around a drop, appended to that file.
enum DropLog {
    static let path: String? = {
        let args = CommandLine.arguments
        return args.firstIndex(of: "-drop-log").flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
    }()

    static func write(_ line: String) {
        guard let path else { return }
        let stamped = String(format: "%.3f ", CACurrentMediaTime()) + line + "\n"
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(Data(stamped.utf8))
            try? handle.close()
        } else {
            FileManager.default.createFile(atPath: path, contents: Data(stamped.utf8))
        }
    }

    static func windows(after delay: Double) {
        guard path != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            let list = NSApp.windows.filter(\.isVisible).map { "\(type(of: $0)) \(Int($0.frame.width))x\(Int($0.frame.height))" }
            write("windows +\(delay)s: \(list.joined(separator: ", "))")
        }
    }
}
#endif
