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
}

@Observable
final class ShelfModel {
    private(set) var items: [ShelfItem] = []
    /// A drag is over the shelf's drop area.
    var isTargeted = false

    @ObservationIgnored private let directory: URL
    @ObservationIgnored private let indexURL: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
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
            items.append(ShelfItem(id: UUID(), bookmark: bookmark, path: path, isOwned: url.path.hasPrefix(directory.path), addedAt: .now))
            changed = true
        }
        if changed {
            save()
            Haptics.tap()
        }
    }

    /// Accepts files, web links, text and images from a drop.
    func add(_ providers: [NSItemProvider]) {
        Task {
            var urls: [URL] = []
            for provider in providers {
                if let url = await Self.load(provider) { urls.append(url) }
            }
            add(urls)
        }
    }

    #if DEBUG
    /// Shows files on the shelf for screenshots without saving them.
    func debugPreview(_ urls: [URL]) {
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
        if item.isOwned { try? FileManager.default.removeItem(at: item.url) }
        save()
    }

    func clear() {
        for item in items where item.isOwned { try? FileManager.default.removeItem(at: item.url) }
        items.removeAll()
        save()
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
        guard let data = try? Data(contentsOf: indexURL),
              let stored = try? JSONDecoder().decode([ShelfItem].self, from: data)
        else { return }
        // Follow files that moved; drop ones that are gone.
        items = stored.compactMap { item in
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: item.bookmark, options: [.withoutUI], bookmarkDataIsStale: &stale),
                  FileManager.default.fileExists(atPath: url.path)
            else { return nil }
            var updated = item
            updated.path = url.path
            if stale, let fresh = try? url.bookmarkData() { updated.bookmark = fresh }
            return updated
        }
        if items != stored { save() }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    // MARK: Drop decoding

    /// Turns one dropped item into a file URL: the file itself, or a file written for a link, text or image.
    private static func load(_ provider: NSItemProvider) async -> URL? {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
           let url = await loadObject(URL.self, from: provider) {
            return url
        }
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nook/Shelf", isDirectory: true)
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
           let link = await loadObject(URL.self, from: provider), !link.isFileURL {
            let name = (link.host() ?? "Link") + ".webloc"
            let plist: [String: String] = ["URL": link.absoluteString]
            guard let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) else { return nil }
            return write(data, named: name, in: folder)
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            var data = await loadData(UTType.png.identifier, from: provider)
            if data == nil { data = await loadData(UTType.image.identifier, from: provider) }
            if let data { return write(data, named: "Image.png", in: folder) }
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
           let text = await loadObject(String.self, from: provider) {
            let title = text.split(whereSeparator: \.isNewline).first.map { String($0.prefix(40)) } ?? "Text"
            return write(Data(text.utf8), named: "\(title).txt", in: folder)
        }
        return nil
    }

    nonisolated private static func loadObject<T: _ObjectiveCBridgeable & Sendable>(_ type: T.Type, from provider: NSItemProvider) async -> T?
        where T._ObjectiveCType: NSItemProviderReading {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: type) { value, _ in continuation.resume(returning: value) }
        }
    }

    nonisolated private static func loadData(_ type: String, from provider: NSItemProvider) async -> Data? {
        await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier: type) { data, _ in continuation.resume(returning: data) }
        }
    }

    private static func write(_ data: Data, named name: String, in folder: URL) -> URL? {
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
