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

struct ShelfView: View {
    @Environment(ShelfModel.self) private var shelf

    var body: some View {
        HStack(spacing: 12) {
            AirDropTile()
                .frame(width: 104)
            DropArea()
        }
    }
}

private struct AirDropTile: View {
    @Environment(ShelfModel.self) private var shelf
    @State private var targeted = false
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 10) {
            AirDropGlyph()
                .fill(.white.opacity(hovering || targeted ? 0.95 : 0.8))
                .frame(width: 28, height: 28)
            Text("AirDrop")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(targeted ? 0.12 : (hovering ? 0.08 : 0.05)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(targeted ? 0.55 : 0.08), lineWidth: targeted ? 1.5 : 1)
        )
        .scaleEffect(targeted ? 1.03 : 1)
        .animation(Motion.press, value: targeted)
        .animation(.easeOut(duration: 0.15), value: hovering)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onHover { hovering = $0 }
        // Click sends everything on the shelf; a drop sends just what was dropped.
        .onTapGesture { AirDrop.send(shelf.urls) }
        .help(shelf.isEmpty ? "Drop files here to AirDrop them" : "AirDrop everything on the shelf")
        // AirDrop sends files, so only file drops are offered here.
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
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

private struct DropArea: View {
    @Environment(ShelfModel.self) private var shelf

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(shelf.isTargeted ? 0.07 : 0.03))
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(shelf.isTargeted ? 0.45 : 0.08),
                              style: StrokeStyle(lineWidth: shelf.isTargeted ? 1.5 : 1, dash: shelf.isTargeted ? [6, 4] : []))
            if shelf.isEmpty {
                Text("Drop files here, or click to choose")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.45))
            } else {
                ScrollView(.horizontal) {
                    // Thumbnails line up along the top; the row as a whole is centered.
                    HStack(alignment: .top, spacing: 6) {
                        ForEach(shelf.items) { item in
                            ShelfTile(item: item)
                                .transition(.scale(scale: 0.8).combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, 10)
                    .frame(maxHeight: .infinity)
                }
                .scrollIndicators(.never)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        // Tiles handle their own clicks; a click on the empty space picks files.
        .onTapGesture { shelf.chooseFiles() }
        .animation(Motion.peekIn, value: shelf.items.map(\.id))
        .animation(.easeOut(duration: 0.15), value: shelf.isTargeted)
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
                    }
                }
            Text(item.name)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .truncationMode(.middle)
                .frame(width: 76)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 2)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(hovering ? 0.07 : 0)))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { inside in withAnimation(.easeOut(duration: 0.15)) { hovering = inside } }
        .opacity(item.isMissing ? 0.4 : 1)
        .onTapGesture(count: 2) { if !item.isMissing { shelf.open(item) } }
        // Absorb single clicks so they don't reach the drop area's click-to-choose.
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
