import AppKit
import SwiftUI

/// Where on the island a drag can be let go.
enum DropTarget: Hashable {
    /// The island itself: onto the shelf.
    case shelf
    case airDrop
    case convert
    case format(ConvertTarget)
    case more
}

/// The island's drops, taken in AppKit rather than through SwiftUI's `onDrop`. SwiftUI ran its own drop
/// animation in a window of its own and left the dragged picture wherever the button came up, so a file
/// never settled into its place. Each target reports its frame and what a drop on it does; the hosting
/// view asks which one is under the drag, lights it, and on a drop onto the shelf flies the dragged
/// picture into the place the file is about to take.
@Observable
final class IslandDrops {
    /// The target under the drag, lit while it's there.
    private(set) var hovered: DropTarget?

    /// The empty place a file let go on the shelf takes, for the dragged picture to land in.
    @ObservationIgnored var landing: CGRect?
    /// A drop onto the shelf is settling into its place. The drag ending doesn't put the shelf back until it has.
    @ObservationIgnored var isLanding = false

    @ObservationIgnored private var targets: [DropTarget: Entry] = [:]

    /// A file let go on the shelf: its picture flying from where the button came up into its place.
    var flight: Flight?
    /// The dragged picture and where it was when the button came up, for the flight.
    @ObservationIgnored var arriving: (image: NSImage, frame: CGRect)?

    struct Flight: Equatable {
        let id = UUID()
        let image: NSImage
        let from: CGRect
        let to: CGRect
        static func == (a: Flight, b: Flight) -> Bool { a.id == b.id }
    }

    /// How long the picture takes to settle into its place; the file takes the place as it does.
    static let landingTime: Duration = .milliseconds(300)

    private struct Entry {
        var frame: CGRect
        var owner: UUID
        var perform: (NSPasteboard) -> Bool
    }

    /// What the island takes: files, and pictures, links or text from other apps.
    static let types: [NSPasteboard.PasteboardType] = [.fileURL, .URL, .string, .png, .tiff, NSPasteboard.PasteboardType("public.image")]

    func register(_ target: DropTarget, owner: UUID, frame: CGRect, perform: @escaping (NSPasteboard) -> Bool) {
        targets[target] = Entry(frame: frame, owner: owner, perform: perform)
    }

    /// Only the view that registered a target takes it away, so one arriving as another leaves keeps its place.
    func unregister(_ target: DropTarget, owner: UUID) {
        if targets[target]?.owner == owner { targets[target] = nil }
    }

    /// The target under a point, in the island's own coordinates (top left origin): a place in the row before
    /// the island around it.
    func target(at point: CGPoint) -> DropTarget? {
        if let place = targets.first(where: { $0.key != .shelf && $0.value.frame.contains(point) })?.key { return place }
        return targets[.shelf]?.frame.contains(point) == true ? .shelf : nil
    }

    func hover(_ target: DropTarget?) {
        if hovered != target { hovered = target }
    }

    func perform(_ target: DropTarget, with pasteboard: NSPasteboard) -> Bool {
        hover(nil)
        return targets[target]?.perform(pasteboard) ?? false
    }

    /// The files a drag carries, read off its pasteboard.
    static func files(on pasteboard: NSPasteboard) -> [URL] {
        (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }
}

extension View {
    /// A place on the island a drag can be let go on. `perform` reads what was dropped and says whether it was taken.
    func dropTarget(_ target: DropTarget, perform: @escaping (NSPasteboard) -> Bool) -> some View {
        modifier(DropTargetModifier(target: target, perform: perform))
    }

    /// The empty place a file dropped on the shelf will take.
    func dropLanding() -> some View {
        modifier(DropLandingModifier())
    }
}

private struct DropTargetModifier: ViewModifier {
    @Environment(NotchModel.self) private var model
    let target: DropTarget
    let perform: (NSPasteboard) -> Bool
    @State private var owner = UUID()

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                model.drops.register(target, owner: owner, frame: frame, perform: perform)
            }
            .onDisappear { model.drops.unregister(target, owner: owner) }
    }
}

private struct DropLandingModifier: ViewModifier {
    @Environment(NotchModel.self) private var model

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { model.drops.landing = $0 }
            .onDisappear { if !model.drops.isLanding { model.drops.landing = nil } }
    }
}
