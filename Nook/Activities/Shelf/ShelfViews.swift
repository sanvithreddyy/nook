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


/// The shelf's page, laid out like a Finder window's icons: the files kept here, then AirDrop after a
/// divider, always in the same place at the right end. While a file is dragged, a place at the end of
/// the row shows where it will land and lights up, Finder-style, when the drop is over the island. The
/// row never scrolls, so a sideways swipe always turns the page: past six places the last becomes a
/// tile of how many more there are, which opens them all.
struct ShelfPage: View {
    @Environment(ShelfModel.self) private var shelf
    @Environment(NotchModel.self) private var model
    @Environment(ConvertModel.self) private var convert

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Sprung open, Convert's formats take the files' places.
            Group {
                if convert.isOpen {
                    ConvertFormatsRow()
                } else {
                    FilesRow(dragging: model.isDraggingFile && !model.dragIsFromShelf)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Rectangle()
                .fill(.white.opacity(0.14))
                .frame(width: 1, height: ShelfMetrics.thumb)
                .padding(.top, ShelfMetrics.pad)
                .padding(.horizontal, (ShelfMetrics.separator - 1) / 2)
            // Convert comes in beside AirDrop, so AirDrop keeps its place at the end.
            if model.shelfConvert != .hidden {
                ConvertPlace()
                    .transition(.scale(scale: 0.6, anchor: .trailing).combined(with: .opacity))
            }
            AirDropTarget()
        }
        // In the middle of the space under the notch.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, model.notch.size.height)
        // Across the notch from the page dots, as Notification Center puts Clear All over a stack.
        .overlay(alignment: .topLeading) {
            if convert.isOpen {
                ConvertTitle()
                    .frame(height: model.notch.size.height)
                    .transition(.opacity)
            } else if !shelf.isEmpty {
                ClearAllButton()
                    .frame(height: model.notch.size.height)
                    .transition(.opacity)
            }
        }
        .animation(Motion.reshape, value: model.isDraggingFile)
        .animation(Motion.reshape, value: model.shelfConvert)
        .onAppear { shelf.refresh() }
        // The island closing or turning the page puts the shelf back.
        .onDisappear { convert.close() }
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

    /// As wide as its places (the landing place among them while dragging, Convert beside AirDrop when
    /// it's offered, and its formats when it's open), between the two limits.
    static func size(items: Int, dragging: Bool, convert: ShelfConvert = .hidden) -> CGSize {
        let files: CGFloat
        if case .open(let formats) = convert {
            files = CGFloat(formats) * tile
        } else {
            files = items == 0 && !dragging ? tile * 2 : CGFloat(min(items + (dragging ? 1 : 0), places)) * tile
        }
        let width = inset * 2 + files + separator + tile + (convert == .hidden ? 0 : tile)
        return CGSize(width: min(max(width, minWidth), maxWidth), height: height)
    }
}

/// A place in the row: a picture, its name under it on up to two lines, a highlight behind both.
struct ShelfPlace<Picture: View>: View {
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
    @State private var hovering = false

    var body: some View {
        let targeted = model.drops.hovered == .airDrop
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
        // AirDrop sends files, so only file drops are taken here.
        .dropTarget(.airDrop) { pasteboard in
            let urls = IslandDrops.files(on: pasteboard)
            guard !urls.isEmpty else { return false }
            model.setDraggingFile(false)
            AirDrop.send(urls)
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


/// The files kept on the shelf, then the landing place while a file is dragged.
private struct FilesRow: View {
    @Environment(ShelfModel.self) private var shelf
    @Environment(ConvertModel.self) private var convert
    let dragging: Bool

    var body: some View {
        if shelf.isEmpty, !dragging, convert.jobs.isEmpty {
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
            // The landing place takes a place while dragging, and each file being converted takes one;
            // the count of the rest takes the last when files overflow.
            let pending = Array(convert.jobs.prefix(ShelfMetrics.places - 2))
            let room = ShelfMetrics.places - (dragging ? 1 : 0) - pending.count
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
                ForEach(pending) { job in
                    ConvertingPlace(job: job)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
                if dragging {
                    // In, it grows out of the row; out, it goes at once, as a dropped file takes its place.
                    LandingSlot()
                        .transition(.asymmetric(insertion: .scale(scale: 0.6, anchor: .leading).combined(with: .opacity),
                                                removal: .opacity.animation(Motion.ease(.easeOut(duration: 0.08)))))
                }
            }
            .animation(Motion.peekIn, value: shelf.items.map(\.id))
            .animation(Motion.peekIn, value: convert.jobs.map(\.id))
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
                .dropLanding()
        }
        .scaleEffect(lit ? 1.03 : 1)
        .animation(Motion.press, value: lit)
        .accessibilityLabel("Drop to keep on the shelf")
    }
}

private struct ShelfTile: View {
    @Environment(ShelfModel.self) private var shelf
    @Environment(ConvertModel.self) private var convert
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
        // Dragged out, the file's picture alone, not the place under the pointer with its remove button.
        .onDrag {
            shelf.onDragOut?()
            return NSItemProvider(contentsOf: item.url) ?? NSItemProvider()
        } preview: {
            // Read when the place is drawn: SwiftUI builds the preview ahead of the drag and keeps it.
            Image(nsImage: Thumbnail.drawn.object(forKey: item.url as NSURL) ?? NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: ShelfMetrics.thumb, height: ShelfMetrics.thumb)
        }
        .contextMenu {
            Button("Open") { shelf.open(item) }
            Button("Show in Finder") { shelf.reveal(item) }
            Button("AirDrop") { AirDrop.send([item.url]) }
            ShareLink(item: item.url) { Text("Share") }
            Button("Copy") { shelf.copy(item) }
            let formats = item.isMissing ? [] : ConvertCatalog.targets(for: [item.url], withPack: true,
                                                                       lastUsed: ConvertSource.of(item.url).flatMap(Prefs.convertLastUsed))
            if !formats.isEmpty {
                Divider()
                Menu("Convert To") {
                    let ready = formats.filter { !convert.downloads($0, for: [item.url]) }
                    let later = formats.filter { convert.downloads($0, for: [item.url]) }
                    ForEach(ready, id: \.self) { target in
                        Button(target.name) { convert.convert([item.url], to: target) }
                    }
                    // Picking one of these downloads More Formats first.
                    if !later.isEmpty {
                        Section("More Formats (downloads first)") {
                            ForEach(later, id: \.self) { target in
                                Button(target.name) { convert.convert([item.url], to: target) }
                            }
                        }
                    }
                }
            }
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
struct Thumbnail: View {
    let url: URL
    @State private var image: NSImage?

    /// Pictures already drawn, so a file's picture shows at once wherever it appears again, a drag's
    /// preview included.
    static let drawn = NSCache<NSURL, NSImage>()

    init(url: URL) {
        self.url = url
        _image = State(initialValue: Self.drawn.object(forKey: url as NSURL))
    }

    var body: some View {
        // The file's icon until Quick Look has drawn its picture, then the picture fades in over it.
        ZStack {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .opacity(image == nil ? 1 : 0)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
                    .transition(.opacity)
            }
        }
        .frame(width: ShelfMetrics.thumb, height: ShelfMetrics.thumb)
        .animation(Motion.ease(.easeOut(duration: 0.2)), value: image != nil)
        .task(id: url) {
            guard image == nil, let drawn = await Self.thumbnail(for: url) else { return }
            Self.drawn.setObject(drawn, forKey: url as NSURL)
            image = drawn
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
