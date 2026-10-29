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

/// Two big drop targets while a file is dragged or the shelf is empty (Keep in Shelf, AirDrop),
/// like Apple's AirDrop request; otherwise AirDrop beside the files kept here.
struct ShelfCard: View {
    @Environment(ShelfModel.self) private var shelf
    @Environment(NotchModel.self) private var model
    let showsDropTargets: Bool

    var body: some View {
        Group {
            if showsDropTargets {
                HStack(spacing: 10) {
                    KeepTile()
                    AirDropTile(compact: false)
                }
                .frame(height: 74)
                .transition(.blurReplace)
            } else {
                HStack(spacing: 8) {
                    AirDropTile(compact: true)
                        .frame(width: 72)
                    FilesRow()
                }
                .frame(height: 92)
                .transition(.blurReplace)
            }
        }
        .padding(.top, model.notch.size.height + 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(Motion.expand, value: showsDropTargets)
        .contextMenu {
            Button("Add Files…") { shelf.chooseFiles() }
            if !shelf.isEmpty {
                Button("AirDrop All") { AirDrop.send(shelf.urls) }
                Button("Clear Shelf") { withAnimation(Motion.peekOut) { shelf.clear() } }
                Divider()
            }
            SettingsMenuItem()
        }
    }
}

/// The surface every shelf tile shares; lights up while a drag is over it.
private struct TileSurface: ViewModifier {
    let lit: Bool
    let hovering: Bool

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Concentric with the card's 30 pt corner at a 16 pt inset.
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(lit ? 0.2 : (hovering ? 0.12 : 0.08))))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .scaleEffect(lit ? 1.03 : 1)
            .animation(Motion.press, value: lit)
            .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

/// Drop here to keep a file for later; click to choose files. The whole island takes the drop.
private struct KeepTile: View {
    @Environment(ShelfModel.self) private var shelf
    @Environment(NotchModel.self) private var model
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: "tray.and.arrow.down.fill")
                .font(.system(size: 19, weight: .medium))
            Text(model.isDraggingFile ? "Keep in Shelf" : "Add Files")
                .font(.system(size: 12.5, weight: .semibold))
        }
        .foregroundStyle(.white)
        .modifier(TileSurface(lit: shelf.isTargeted, hovering: hovering))
        .onHover { hovering = $0 }
        .onTapGesture { shelf.chooseFiles() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

private struct AirDropTile: View {
    @Environment(ShelfModel.self) private var shelf
    @Environment(NotchModel.self) private var model
    let compact: Bool
    @State private var targeted = false
    @State private var hovering = false

    var body: some View {
        VStack(spacing: compact ? 6 : 7) {
            AirDropGlyph()
                .fill(.white)
                .frame(width: compact ? 20 : 22, height: compact ? 20 : 22)
            Text("AirDrop")
                .font(.system(size: compact ? 11 : 12.5, weight: .semibold))
        }
        .foregroundStyle(.white)
        .modifier(TileSurface(lit: targeted, hovering: hovering))
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

/// The files kept on the shelf, scrolling sideways.
private struct FilesRow: View {
    @Environment(ShelfModel.self) private var shelf

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 2) {
                ForEach(shelf.items) { item in
                    ShelfTile(item: item)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
                AddTile()
            }
            .frame(maxHeight: .infinity)
        }
        .scrollIndicators(.never)
        .animation(Motion.peekIn, value: shelf.items.map(\.id))
    }
}

private struct ShelfTile: View {
    @Environment(ShelfModel.self) private var shelf
    let item: ShelfItem
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 6) {
            Thumbnail(url: item.url)
                .frame(width: 44, height: 44)
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
                    }
                }
            Text(item.name)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .truncationMode(.middle)
                .frame(width: 68)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 2)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(hovering ? 0.07 : 0)))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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

/// The last tile in the row: click to choose more files.
private struct AddTile: View {
    @Environment(ShelfModel.self) private var shelf
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "plus")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(hovering ? 0.9 : 0.6))
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(hovering ? 0.12 : 0.07)))
            Text("Add")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(width: 60)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onHover { inside in withAnimation(.easeOut(duration: 0.15)) { hovering = inside } }
        .onTapGesture { shelf.chooseFiles() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Add Files")
        .accessibilityAddTraits(.isButton)
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
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 44, height: 44),
                                                   scale: 2, representationTypes: .thumbnail)
        guard let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else { return nil }
        return rep.nsImage
    }
}
