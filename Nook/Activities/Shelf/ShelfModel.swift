import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Something kept on the shelf. Files stay where they are (tracked by bookmark, so moves are
/// followed); dropped text, links and images are written into Nook's own shelf folder.
struct ShelfItem: Identifiable, Codable, Equatable {
    let id: UUID
    var bookmark: Data
    var path: String
    /// Nook wrote this file itself and deletes it when the item is removed.
    var isOwned: Bool
    var addedAt: Date

    var url: URL { URL(fileURLWithPath: path) }
    var name: String { url.lastPathComponent }
    /// The file can't be found (an unplugged disk, a deleted file) or sits in a Trash. Shown dimmed,
    /// and let go when the shelf opens if Settings asks.
    var isMissing: Bool {
        !FileManager.default.fileExists(atPath: path) || url.pathComponents.contains { $0 == ".Trash" || $0 == ".Trashes" }
    }
}

@Observable
final class ShelfModel {
    private(set) var items: [ShelfItem] = []
    /// A drag is over the shelf's drop area.
    var isTargeted = false
    /// One of the shelf's files started being dragged out of it.
    @ObservationIgnored var onDragOut: (() -> Void)?

    @ObservationIgnored let directory: URL
    @ObservationIgnored private let indexURL: URL

    /// `root` is Application Support/Nook; tests pass a temporary folder.
    init(root: URL? = nil) {
        let support = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nook", isDirectory: true)
        directory = support.appendingPathComponent("Shelf", isDirectory: true)
        indexURL = support.appendingPathComponent("shelf.json")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        load()
    }

    var isEmpty: Bool { items.isEmpty }
    var urls: [URL] { items.map(\.url) }

    // MARK: Adding

    func add(_ urls: [URL]) {
        var changed = false
        for url in urls where url.isFileURL {
            let path = url.standardizedFileURL.path
            guard !items.contains(where: { $0.path == path }),
                  let bookmark = try? url.bookmarkData()
            else { continue }
            items.append(ShelfItem(id: UUID(), bookmark: bookmark, path: path, isOwned: isInShelfFolder(url), addedAt: .now))
            changed = true
        }
        if changed {
            save()
            Haptics.tap()
        }
    }

    /// Accepts files, web links, text and images from a drop: the files themselves, or a file written for
    /// a picture, link or text dragged out of another app.
    func add(from pasteboard: NSPasteboard) {
        add(Self.files(from: pasteboard, writingInto: directory))
    }

    #if DEBUG
    /// Shows files on the shelf for screenshots without saving them.
    func debugPreview(_ urls: [URL]) {
        isPreview = true
        items = urls.compactMap { url in
            (try? url.bookmarkData()).map { ShelfItem(id: UUID(), bookmark: $0, path: url.path, isOwned: false, addedAt: .now) }
        }
    }
    #endif

    /// Click-to-add: a standard open panel for files and folders.
    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.prompt = "Add to Shelf"
        NSApp.activate()
        if panel.runModal() == .OK { add(panel.urls) }
    }

    // MARK: Removing

    func remove(_ item: ShelfItem) {
        items.removeAll { $0.id == item.id }
        discardIfOwned(item)
        save()
    }

    func clear() {
        items.forEach(discardIfOwned)
        items.removeAll()
        save()
    }

    /// Only a file Nook wrote that still sits directly in the shelf folder is discarded, and it
    /// goes to the Trash. Anything moved out of the folder is the user's now and is left alone.
    private func discardIfOwned(_ item: ShelfItem) {
        guard item.isOwned, isInShelfFolder(item.url) else { return }
        try? FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
    }

    func isInShelfFolder(_ url: URL) -> Bool {
        url.resolvingSymlinksInPath().deletingLastPathComponent().standardizedFileURL.path
            == directory.resolvingSymlinksInPath().standardizedFileURL.path
    }

    // MARK: Actions

    func open(_ item: ShelfItem) { NSWorkspace.shared.open(item.url) }

    func reveal(_ item: ShelfItem) { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }

    func copy(_ item: ShelfItem) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([item.url as NSURL])
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: indexURL) else { return }
        guard let stored = try? JSONDecoder().decode([ShelfItem].self, from: data) else {
            // Keep an unreadable index rather than overwriting it on the next save.
            let aside = indexURL.deletingPathExtension().appendingPathExtension("unreadable.json")
            try? FileManager.default.removeItem(at: aside)
            try? FileManager.default.moveItem(at: indexURL, to: aside)
            return
        }
        items = stored.map(followed)
        if items != stored { save() }
    }

    /// Follows files that moved since the shelf last looked, and lets go of ones that are gone when
    /// Settings asks. Runs as the shelf opens.
    func refresh() {
        var current = items.map(followed)
        if Prefs.bool(Prefs.shelfDropMissing) { current.removeAll(where: \.isMissing) }
        guard current != items else { return }
        items = current
        save()
    }

    /// The shelf shows sample files for screenshots (a debug run), so nothing is saved.
    @ObservationIgnored private var isPreview = false

    /// Where an item's file is now, by its bookmark. Items that can't be found right now stay as
    /// they are, so an unplugged disk doesn't empty the shelf.
    private func followed(_ item: ShelfItem) -> ShelfItem {
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: item.bookmark, options: [.withoutUI, .withoutMounting], bookmarkDataIsStale: &stale)
        else { return item }
        var updated = item
        updated.path = url.path
        if item.isOwned, !isInShelfFolder(url) { updated.isOwned = false }
        if stale, let fresh = try? url.bookmarkData() { updated.bookmark = fresh }
        return updated
    }

    private func save() {
        // Sample files shown for screenshots never replace the real shelf.
        guard !isPreview else { return }
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    // MARK: Drop decoding

    /// What a drop carries, as files. Files come first: a photo dragged from Finder also carries its picture,
    /// and it's the file that's kept, not a copy of the picture.
    static func files(from pasteboard: NSPasteboard, writingInto folder: URL) -> [URL] {
        let files = IslandDrops.files(on: pasteboard)
        if !files.isEmpty { return files }
        // Images before links: a web image also carries its URL, but the picture is what was dragged.
        for type in pasteboard.types ?? [] {
            guard let kind = UTType(type.rawValue), kind.conforms(to: .image), let data = pasteboard.data(forType: type) else { continue }
            return write(data, named: "Image." + (kind.preferredFilenameExtension ?? "png"), in: folder).map { [$0] } ?? []
        }
        if let link = (pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL])?.first(where: { !$0.isFileURL }) {
            let plist: [String: String] = ["URL": link.absoluteString]
            guard let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) else { return [] }
            return write(data, named: (link.host() ?? "Link") + ".webloc", in: folder).map { [$0] } ?? []
        }
        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            let title = text.split(whereSeparator: \.isNewline).first.map { String($0.prefix(40)) } ?? "Text"
            return write(Data(text.utf8), named: "\(title).txt", in: folder).map { [$0] } ?? []
        }
        return []
    }

    static func write(_ data: Data, named name: String, in folder: URL) -> URL? {
        let safe = name.replacingOccurrences(of: "/", with: "-")
        var url = folder.appendingPathComponent(safe)
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(base) \(n)").appendingPathExtension(ext)
            n += 1
        }
        return (try? data.write(to: url)) != nil ? url : nil
    }
}
