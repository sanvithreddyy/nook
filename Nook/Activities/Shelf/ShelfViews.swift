import AppKit
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

/// AirDrop through the system sharing service.
enum AirDrop {
    static var service: NSSharingService? { NSSharingService(named: .sendViaAirDrop) }

    /// Where macOS keeps AirDrop's own glyph, the one Control Center draws: among its private symbols,
    /// which `Image(_:bundle:)` still reads. Nil if a release moves it.
    static let glyphBundle = Bundle(path: "/System/Library/CoreServices/CoreGlyphsPrivate.bundle")
        .flatMap { NSImage(symbolName: "airdrop", bundle: $0, variableValue: 0) != nil ? $0 : nil }

    /// Without the glyph, the icon macOS shows beside AirDrop in its Share menus.
    static let icon: NSImage = service?.image
        ?? NSWorkspace.shared.icon(forFile: "/System/Library/CoreServices/Finder.app/Contents/Applications/AirDrop.app")

    static func send(_ urls: [URL]) {
        guard !urls.isEmpty, let service, service.canPerform(withItems: urls) else { return }
        // The AirDrop sheet is a window of ours; bring Nook forward so it appears on top.
        NSApp.activate()
        service.perform(withItems: urls)
    }
}

let shelfDropTypes: [UTType] = [.fileURL, .url, .image, .plainText]

/// The shelf's page, laid out like a Finder window's icons: the files kept here, then AirDrop after
/// a divider, the row in the middle of the island. While a file is dragged, a slot at the end of the
/// row shows where it will land and lights up, Finder-style, when the drop is over the island. The row
/// never scrolls, so a sideways swipe always turns the page: past six places the last becomes a stack
/// of the rest, which opens them all.
struct ShelfPage: View {
    @Environment(ShelfModel.self) private var shelf
    @Environment(NotchModel.self) private var model

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            FilesRow(dragging: model.isDraggingFile)
            Rectangle()
                .fill(.white.opacity(0.16))
                .frame(width: 1, height: 52)
                .padding(.horizontal, (ShelfMetrics.separator - 1) / 2)
            AirDropTarget()
        }
        // In the middle of the space under the notch when another page sets a taller island.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, model.notch.size.height)
        .animation(Motion.reshape, value: model.isDraggingFile)
        .onAppear { shelf.refresh() }
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

    /// Places in the row; past this the last one is a stack of the rest.
    static let places = 6

    /// As wide as its places (the landing slot among them while dragging), between the two limits.
    static func size(items: Int, dragging: Bool) -> CGSize {
        let slots = CGFloat(min(items + (dragging ? 1 : 0), places))
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
        // A tile like the files beside it, lit the way Finder lights a folder under a drag.
        VStack(spacing: 6) {
            AirDropIcon()
                .frame(width: 52, height: 52)
            Text("AirDrop")
                .font(.system(size: 11.5))
                .foregroundStyle(.white)
        }
        .frame(width: ShelfMetrics.tile - 4)
        .padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(targeted ? 0.1 : hovering ? 0.08 : 0)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.accentColor.opacity(targeted ? 0.95 : 0), lineWidth: 2))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 2)
        .scaleEffect(targeted ? 1.03 : 1)
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

/// AirDrop as Control Center shows it while it's on: the glyph in the accent colour on a white circle.
private struct AirDropIcon: View {
    var body: some View {
        if let bundle = AirDrop.glyphBundle {
            // Half the circle's width, as Control Center sizes it.
            Image("airdrop", bundle: bundle)
                .font(.system(size: 23))
                .foregroundStyle(Color.accentColor)
                .frame(width: 46, height: 46)
                .background(Circle().fill(.white))
        } else {
            Image(nsImage: AirDrop.icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
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
                    .frame(width: ShelfMetrics.tile * 2, height: 52)
            }
            .buttonStyle(.plain)
            .help("Click to choose files")
            .transition(.opacity)
        } else {
            // The landing slot takes a place while dragging; a stack takes the last when files overflow.
            let room = ShelfMetrics.places - (dragging ? 1 : 0)
            let overflows = shelf.items.count > room
            let shown = overflows ? Array(shelf.items.prefix(room - 1)) : shelf.items
            HStack(alignment: .top, spacing: 0) {
                ForEach(shown) { item in
                    ShelfTile(item: item)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
                if overflows {
                    StackTile(hidden: Array(shelf.items.dropFirst(room - 1)))
                        .transition(.opacity)
                }
                if dragging {
                    LandingSlot()
                        .transition(.scale(scale: 0.6, anchor: .leading).combined(with: .opacity))
                }
            }
            .animation(Motion.peekIn, value: shelf.items.map(\.id))
        }
    }
}

/// The files that don't fit, as a Dock stack: up to three of them fanned behind each other with how
/// many there are. Click to see every file on the shelf.
private struct StackTile: View {
    @Environment(NotchModel.self) private var model
    let hidden: [ShelfItem]
    @State private var showing = false
    @State private var hovering = false

    var body: some View {
        Button { showing = true } label: {
            VStack(spacing: 6) {
                ZStack {
                    ForEach(Array(hidden.prefix(3).enumerated().reversed()), id: \.element.id) { index, item in
                        Thumbnail(url: item.url)
                            .frame(width: 44, height: 44)
                            .rotationEffect(.degrees(Double(index) * -6))
                            .offset(x: CGFloat(index) * 3, y: CGFloat(index) * -2)
                    }
                }
                .frame(width: 52, height: 52)
                Text("\(hidden.count) More")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .frame(width: ShelfMetrics.tile - 4)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(hovering || showing ? 0.08 : 0)))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 2)
        .onHover { inside in withAnimation(.easeOut(duration: 0.15)) { hovering = inside } }
        .popover(isPresented: $showing, arrowEdge: .bottom) { AllFiles() }
        // The island stays open under the list, as it does under the output menu.
        .onChange(of: showing) { _, now in model.holdsOpen = now }
        .accessibilityLabel("\(hidden.count) more files")
    }
}

/// Every file on the shelf in a Finder-style grid, for when the row can't show them all.
private struct AllFiles: View {
    @Environment(ShelfModel.self) private var shelf

    var body: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(ShelfMetrics.tile), spacing: 0), count: 4), spacing: 8) {
                ForEach(shelf.items) { ShelfTile(item: $0) }
            }
            .padding(12)
        }
        .frame(width: ShelfMetrics.tile * 4 + 24, height: min(CGFloat((shelf.items.count + 3) / 4) * 84 + 24, 300))
        .background(.black)
        .environment(\.colorScheme, .dark)
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
            ShareLink(item: item.url) { Text("Share") }
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
