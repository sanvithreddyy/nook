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

/// The shelf's page, laid out like a Finder window's icons: the files kept here, then AirDrop after a
/// divider, always in the same place at the right end. While a file is dragged, a place at the end of
/// the row shows where it will land and lights up, Finder-style, when the drop is over the island. The
/// row never scrolls, so a sideways swipe always turns the page: past six places the last becomes a
/// tile of how many more there are, which opens them all.
struct ShelfPage: View {
    @Environment(ShelfModel.self) private var shelf
    @Environment(NotchModel.self) private var model

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            FilesRow(dragging: model.isDraggingFile)
                .frame(maxWidth: .infinity, alignment: .leading)
            Rectangle()
                .fill(.white.opacity(0.14))
                .frame(width: 1, height: ShelfMetrics.thumb)
                .padding(.top, ShelfMetrics.pad)
                .padding(.horizontal, (ShelfMetrics.separator - 1) / 2)
            AirDropTarget()
        }
        // In the middle of the space under the notch.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, model.notch.size.height)
        // Across the notch from the page dots, as Notification Center puts Clear All over a stack.
        .overlay(alignment: .topLeading) {
            if !shelf.isEmpty {
                ClearAllButton()
                    .frame(height: model.notch.size.height)
                    .transition(.opacity)
            }
        }
        .animation(Motion.reshape, value: model.isDraggingFile)
        .onAppear { shelf.refresh() }
        .contextMenu {
            Button("Add Files…") { shelf.chooseFiles() }
            if !shelf.isEmpty {
                Button("AirDrop All") { AirDrop.send(shelf.urls) }
                Button("Clear Shelf") { withAnimation(Motion.peekOut) { shelf.clear() } }
                Divider()
            }
            AppMenuItems(pane: .shelf)
        }
    }
}

/// Sizes of the shelf page: 78 pt places with a 60 pt picture and two lines of name, a divider,
/// AirDrop's place.
enum ShelfMetrics {
    static let inset: CGFloat = 20
    static let tile: CGFloat = 78
    nonisolated static let thumb: CGFloat = 60
    /// Two lines of 11 pt names.
    static let label: CGFloat = 28
    /// Around each place's picture and name, inside its highlight.
    static let pad: CGFloat = 6
    static let corner: CGFloat = 12
    static let separator: CGFloat = 17
    /// Below the notch line.
    static let height: CGFloat = 112
    static let minWidth: CGFloat = 320
    static let maxWidth: CGFloat = 640

    /// Places in the row; past this the last one counts the rest.
    static let places = 6

    /// As wide as its places (the landing place among them while dragging), between the two limits.
    static func size(items: Int, dragging: Bool) -> CGSize {
        let slots = CGFloat(min(items + (dragging ? 1 : 0), places))
        let files = items == 0 && !dragging ? tile * 2 : slots * tile
        let width = inset * 2 + files + separator + tile
        return CGSize(width: min(max(width, minWidth), maxWidth), height: height)
    }
}

/// A place in the row: a picture, its name under it on up to two lines, a highlight behind both.
private struct ShelfPlace<Picture: View>: View {
    let name: String
    var nameOpacity = 0.92
    var highlight = 0.0
    var ring = false
    @ViewBuilder var picture: Picture

    var body: some View {
        VStack(spacing: 7) {
            picture
                .frame(width: ShelfMetrics.thumb, height: ShelfMetrics.thumb)
            Text(name)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(nameOpacity))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .truncationMode(.middle)
                .frame(width: ShelfMetrics.tile - 8, height: ShelfMetrics.label, alignment: .top)
        }
        .padding(.vertical, ShelfMetrics.pad)
        .frame(width: ShelfMetrics.tile - 2)
        .background(RoundedRectangle(cornerRadius: ShelfMetrics.corner, style: .continuous).fill(.white.opacity(highlight)))
        .overlay(RoundedRectangle(cornerRadius: ShelfMetrics.corner, style: .continuous)
            .strokeBorder(Color.accentColor.opacity(ring ? 0.95 : 0), lineWidth: 2))
        .contentShape(RoundedRectangle(cornerRadius: ShelfMetrics.corner, style: .continuous))
        .padding(.horizontal, 1)
    }
}

/// Drop files here to AirDrop them; click to AirDrop everything on the shelf.
private struct AirDropTarget: View {
    @Environment(ShelfModel.self) private var shelf
    @Environment(NotchModel.self) private var model
    @State private var targeted = false
    @State private var hovering = false

    var body: some View {
        // A place like the files beside it, lit the way Finder lights a folder under a drag.
        ShelfPlace(name: "AirDrop", highlight: targeted ? 0.1 : hovering ? 0.08 : 0, ring: targeted) {
            AirDropIcon()
                .frame(width: 56, height: 56)
        }
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
            GeometryReader { box in
                Image("airdrop", bundle: bundle)
                    .font(.system(size: box.size.width / 2))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: box.size.width, height: box.size.height)
                    .background(Circle().fill(.white))
            }
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

/// The files kept on the shelf, then the landing place while a file is dragged.
private struct FilesRow: View {
    @Environment(ShelfModel.self) private var shelf
    let dragging: Bool

    var body: some View {
        if shelf.isEmpty, !dragging {
            Button { shelf.chooseFiles() } label: {
                VStack(spacing: 9) {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.white.opacity(0.45))
                    Text("Drop files here")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .frame(maxWidth: .infinity)
                .padding(.top, ShelfMetrics.pad + 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Click to choose files")
            .transition(.opacity)
        } else {
            // The landing place takes a place while dragging; the count of the rest takes the last when
            // files overflow.
            let room = ShelfMetrics.places - (dragging ? 1 : 0)
            let overflows = shelf.items.count > room
            let shown = overflows ? Array(shelf.items.prefix(room - 1)) : shelf.items
            HStack(alignment: .top, spacing: 0) {
                ForEach(shown) { item in
                    ShelfTile(item: item)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
                if overflows {
                    MoreTile(hidden: shelf.items.count - shown.count)
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

/// How many more files there are than places, on a quiet tile. Click to see every file on the shelf.
private struct MoreTile: View {
    @Environment(NotchModel.self) private var model
    let hidden: Int
    @State private var showing = false
    @State private var hovering = false

    var body: some View {
        Button { showing = true } label: {
            ShelfPlace(name: "More", highlight: hovering || showing ? 0.08 : 0) {
                RoundedRectangle(cornerRadius: ShelfMetrics.corner, style: .continuous)
                    .fill(.white.opacity(0.1))
                    .overlay(
                        Text("+\(hidden)")
                            .font(.system(size: 20, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.88))
                    )
            }
        }
        .buttonStyle(.plain)
        .onHover { inside in withAnimation(.easeOut(duration: 0.15)) { hovering = inside } }
        .popover(isPresented: $showing, arrowEdge: .bottom) { AllFiles() }
        // The island stays open under the list, as it does under the output menu.
        .onChange(of: showing) { _, now in model.holdsOpen = now }
        .accessibilityLabel("\(hidden) more files")
        #if DEBUG
        // -shelf-show-all: the list open, for stills.
        .task {
            guard CommandLine.arguments.contains("-shelf-show-all") else { return }
            try? await Task.sleep(for: .seconds(0.8))
            showing = true
        }
        #endif
    }
}

/// Every file on the shelf in a Finder-style grid, for when the row can't show them all.
private struct AllFiles: View {
    @Environment(ShelfModel.self) private var shelf

    var body: some View {
        let rowHeight = ShelfMetrics.thumb + 7 + ShelfMetrics.label + ShelfMetrics.pad * 2
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(ShelfMetrics.tile), spacing: 0), count: 4), spacing: 4) {
                ForEach(shelf.items) { ShelfTile(item: $0) }
            }
            .padding(12)
        }
        .frame(width: ShelfMetrics.tile * 4 + 24,
               height: min(CGFloat((shelf.items.count + 3) / 4) * (rowHeight + 4) + 24, 320))
        .background(.black)
        .environment(\.colorScheme, .dark)
    }
}

/// Where a dragged file will land: an empty place that lights up with the system's accent when the drop
/// is over the island, as Finder highlights a folder under a drag.
private struct LandingSlot: View {
    @Environment(ShelfModel.self) private var shelf

    var body: some View {
        let lit = shelf.isTargeted
        ShelfPlace(name: lit ? "Keep Here" : " ", nameOpacity: 0.8, highlight: lit ? 0.1 : 0, ring: lit) {
            RoundedRectangle(cornerRadius: ShelfMetrics.corner, style: .continuous)
                .fill(.white.opacity(lit ? 0.12 : 0.07))
                .overlay(
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .light))
                        .foregroundStyle(.white.opacity(lit ? 0.9 : 0.5))
                )
        }
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
        ShelfPlace(name: FileManager.default.displayName(atPath: item.path), highlight: hovering ? 0.08 : 0) {
            Thumbnail(url: item.url)
        }
        // On the highlight's corner, where a notification has it, whatever shape the picture is.
        .overlay(alignment: .topLeading) {
            if hovering {
                RemoveButton { withAnimation(Motion.peekOut) { shelf.remove(item) } }
                    .offset(x: -5, y: -5)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
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
        #if DEBUG
        .onAppear { if ShelfDebug.hovered == item.name { hovering = true } }
        #endif
    }
}

/// Apple's control for taking one thing out: a white × on a red circle, on the file under the pointer.
private struct RemoveButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 19, height: 19)
                .background(Circle().fill(Color.red))
                .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove from Shelf")
    }
}

/// Clear All in the words, as Notification Center shows it over a stack, brighter under the pointer.
/// Files Nook made go to the Trash; others stay put.
private struct ClearAllButton: View {
    @Environment(ShelfModel.self) private var shelf
    @State private var hovering = false

    var body: some View {
        Button { withAnimation(Motion.peekOut) { shelf.clear() } } label: {
            Text("Clear All")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
                .padding(.horizontal, 10)
                .frame(height: 21)
                .background(Capsule().fill(Color(white: hovering ? 0.3 : 0.2)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { inside in withAnimation(.easeOut(duration: 0.15)) { hovering = inside } }
        .help("Clear the shelf")
        #if DEBUG
        .onAppear { if CommandLine.arguments.contains("-shelf-hover-clear") { hovering = true } }
        #endif
    }
}

/// A file's picture: Quick Look's, with rounded corners and a hairline edge, for photos, videos and
/// documents; its Finder icon, as Finder draws it, for everything else.
private struct Thumbnail: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
                .frame(width: ShelfMetrics.thumb, height: ShelfMetrics.thumb)
        } else {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .task(id: url) { image = await Self.thumbnail(for: url) }
        }
    }

    /// Only files Quick Look draws a picture of; others keep their icon, which isn't framed.
    nonisolated private static func thumbnail(for url: URL) async -> NSImage? {
        guard let type = UTType(filenameExtension: url.pathExtension),
              type.conforms(to: .image) || type.conforms(to: .movie) || type.conforms(to: .pdf) else { return nil }
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: ShelfMetrics.thumb, height: ShelfMetrics.thumb),
                                                   scale: 2, representationTypes: .thumbnail)
        guard let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else { return nil }
        return rep.nsImage
    }
}

#if DEBUG
/// -shelf-hover <file name>: that file's place drawn as under the pointer, for stills.
enum ShelfDebug {
    static var hovered: String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "-shelf-hover"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
}
#endif
