import AppKit
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

/// AirDrop through the system sharing service.
enum AirDrop {
    static var service: NSSharingService? { NSSharingService(named: .sendViaAirDrop) }

    static func send(_ urls: [URL]) {
        guard !urls.isEmpty, let service, service.canPerform(withItems: urls) else { return }
        // The AirDrop sheet is a window of ours; bring Nook forward so it appears on top.
        NSApp.activate()
        service.perform(withItems: urls)
    }
}

let shelfDropTypes: [UTType] = [.fileURL, .url, .image, .plainText]

/// The shelf's page, laid out like a Finder window's icons: the files kept here, then AirDrop after
/// a divider. While a file is dragged, a slot at the end of the row shows where it will land and
/// lights up, Finder-style, when the drop is over the island.
struct ShelfPage: View {
    @Environment(ShelfModel.self) private var shelf
    @Environment(NotchModel.self) private var model

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            FilesRow(dragging: model.isDraggingFile)
                .frame(maxWidth: .infinity, alignment: .leading)
            Rectangle()
                .fill(.white.opacity(0.16))
                .frame(width: 1, height: 52)
                .padding(.horizontal, (ShelfMetrics.separator - 1) / 2)
            AirDropTarget()
        }
        .padding(.top, model.notch.size.height + 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(Motion.reshape, value: model.isDraggingFile)
        .contextMenu {
            Button("Add Files…") { shelf.chooseFiles() }
            if !shelf.isEmpty {
                Button("AirDrop All") { AirDrop.send(shelf.urls) }
                Button("Clear Shelf") { withAnimation(Motion.peekOut) { shelf.clear() } }
                Divider()
            }
            SettingsMenuItem(pane: .shelf)
        }
    }
}

/// Sizes of the shelf page: 78 pt per icon, a divider, AirDrop.
enum ShelfMetrics {
    static let inset: CGFloat = 20
    static let tile: CGFloat = 78
    static let separator: CGFloat = 17
    /// Below the notch line.
    static let height: CGFloat = 102
    static let minWidth: CGFloat = 320
    static let maxWidth: CGFloat = 640

    /// As wide as its icons (plus the landing slot while dragging), between the two limits; more scroll.
    static func size(items: Int, dragging: Bool) -> CGSize {
        let slots = CGFloat(items + (dragging ? 1 : 0))
        let files = items == 0 && !dragging ? tile * 2 : slots * tile
        let width = inset * 2 + files + separator + tile
        return CGSize(width: min(max(width, minWidth), maxWidth), height: height)
    }
}

/// Drop files here to AirDrop them; click to AirDrop everything on the shelf.
private struct AirDropTarget: View {
    @Environment(ShelfModel.self) private var shelf
    @Environment(NotchModel.self) private var model
    @State private var targeted = false
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 6) {
            AirDropGlyph()
                .fill(.white)
                .frame(width: 22, height: 22)
                .frame(width: 48, height: 48)
                .background(Circle().fill(.white.opacity(targeted ? 0.3 : (hovering ? 0.2 : 0.14))))
                .scaleEffect(targeted ? 1.08 : 1)
                .frame(height: 52)
            Text("AirDrop")
                .font(.system(size: 11.5))
                .foregroundStyle(.white)
        }
        .frame(width: ShelfMetrics.tile)
        .contentShape(Rectangle())
        .animation(Motion.press, value: targeted)
        .animation(.easeOut(duration: 0.15), value: hovering)
        .onHover { hovering = $0 }
        // Click sends everything on the shelf; a drop sends just what was dropped.
        .onTapGesture { AirDrop.send(shelf.urls) }
        .help(shelf.isEmpty ? "Drop files here to AirDrop them" : "AirDrop everything on the shelf")
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        // AirDrop sends files, so only file drops are offered here.
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            model.setDraggingFile(false)
            Task {
                var urls: [URL] = []
                for provider in providers {
                    if let url = await loadFileURL(provider) { urls.append(url) }
                }
                AirDrop.send(urls)
            }
            return true
        }
    }
}

/// The AirDrop mark as one monochrome shape: a dot inside two rings, cut open by a wedge below.
/// The system's AirDrop image is a colored app icon and there is no public symbol for it.
nonisolated private struct AirDropGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let r = min(rect.width, rect.height) / 2
        let c = CGPoint(x: rect.midX, y: rect.midY)
        // Angles run clockwise from the right with y pointing down, so 90° is straight down.
        let gap = 27.0
        let start = Angle.degrees(90 + gap), sweep = Angle.degrees(360 - gap * 2)
        func point(_ radius: CGFloat, _ angle: Angle) -> CGPoint {
            CGPoint(x: c.x + radius * cos(angle.radians), y: c.y + radius * sin(angle.radians))
        }

        var p = Path()
        p.addEllipse(in: CGRect(x: c.x - r * 0.2, y: c.y - r * 0.2, width: r * 0.4, height: r * 0.4))
        for (inner, outer) in [(r * 0.4, r * 0.6), (r * 0.78, r)] {
            p.move(to: point(outer, start))
            p.addRelativeArc(center: c, radius: outer, startAngle: start, delta: sweep)
            p.addLine(to: point(inner, start + sweep))
            p.addRelativeArc(center: c, radius: inner, startAngle: start + sweep, delta: -sweep)
            p.closeSubpath()
        }
        return p
    }
}

nonisolated private func loadFileURL(_ provider: NSItemProvider) async -> URL? {
    await withCheckedContinuation { continuation in
        _ = provider.loadObject(ofClass: URL.self) { url, _ in continuation.resume(returning: url) }
    }
}

/// The files kept on the shelf, scrolling sideways, then the landing slot while a file is dragged.
private struct FilesRow: View {
    @Environment(ShelfModel.self) private var shelf
    let dragging: Bool

    var body: some View {
        if shelf.isEmpty, !dragging {
            Button { shelf.chooseFiles() } label: {
                Text("Drop files here")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
            }
            .buttonStyle(.plain)
            .help("Click to choose files")
            .transition(.opacity)
        } else {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(shelf.items) { item in
                            ShelfTile(item: item)
                                .transition(.scale(scale: 0.8).combined(with: .opacity))
                        }
                        if dragging {
                            LandingSlot()
                                .id("slot")
                                .transition(.scale(scale: 0.6, anchor: .leading).combined(with: .opacity))
                        }
                    }
                }
                .scrollIndicators(.never)
                .onChange(of: dragging) { _, now in
                    if now { withAnimation(Motion.content) { proxy.scrollTo("slot", anchor: .trailing) } }
                }
            }
            .animation(Motion.peekIn, value: shelf.items.map(\.id))
        }
    }
}

/// Where a dragged file will land: an empty icon place that lights up with the system's accent when
/// the drop is over the island, as Finder highlights a folder under a drag.
private struct LandingSlot: View {
    @Environment(ShelfModel.self) private var shelf

    var body: some View {
        let lit = shelf.isTargeted
        VStack(spacing: 6) {
            Image(systemName: "plus")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(lit ? 0.9 : 0.4))
                .frame(height: 52)
            Text(lit ? "Keep Here" : " ")
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.8))
        }
        .frame(width: ShelfMetrics.tile - 4)
        .padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(lit ? 0.1 : 0.05)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.accentColor.opacity(lit ? 0.95 : 0), lineWidth: 2))
        .padding(.horizontal, 2)
        .scaleEffect(lit ? 1.03 : 1)
        .animation(Motion.press, value: lit)
        .accessibilityLabel("Drop to keep on the shelf")
    }
}

private struct ShelfTile: View {
    @Environment(ShelfModel.self) private var shelf
    let item: ShelfItem
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 6) {
            Thumbnail(url: item.url)
                .frame(width: 52, height: 52)
                .overlay(alignment: .topTrailing) {
                    if hovering {
                        Button { withAnimation(Motion.peekOut) { shelf.remove(item) } } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 15))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.black, .white.opacity(0.9))
                        }
                        .buttonStyle(.plain)
                        .offset(x: 6, y: -6)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                        .accessibilityLabel("Remove from Shelf")
                    }
                }
            Text(item.name)
                .font(.system(size: 11.5))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 4)
        }
        .frame(width: ShelfMetrics.tile - 4)
        .padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(hovering ? 0.08 : 0)))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 2)
        .onHover { inside in withAnimation(.easeOut(duration: 0.15)) { hovering = inside } }
        .opacity(item.isMissing ? 0.4 : 1)
        .onTapGesture(count: 2) { if !item.isMissing { shelf.open(item) } }
        // Absorb single clicks so they don't reach the island's tap.
        .onTapGesture {}
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
        .contextMenu {
            Button("Open") { shelf.open(item) }
            Button("Show in Finder") { shelf.reveal(item) }
            Button("AirDrop") { AirDrop.send([item.url]) }
            Button("Copy") { shelf.copy(item) }
            Divider()
            Button("Remove from Shelf") { shelf.remove(item) }
        }
        .help(item.path)
    }
}

/// Quick Look thumbnail for a file, falling back to its Finder icon.
private struct Thumbnail: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
        }
        .task(id: url) { image = await Self.thumbnail(for: url) }
    }

    nonisolated private static func thumbnail(for url: URL) async -> NSImage? {
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 52, height: 52),
                                                   scale: 2, representationTypes: .thumbnail)
        guard let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else { return nil }
        return rep.nsImage
    }
}
