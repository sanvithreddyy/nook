import AppKit
import Testing
import UniformTypeIdentifiers

/// The island takes drops itself: the place under the drag wins over the island around it, and what's
/// dropped is read straight off the drag, so a file is kept as the file.
@MainActor
struct IslandDropsTests {
    @Test func thePlaceUnderTheDragWinsOverTheIsland() {
        let drops = IslandDrops()
        let owner = UUID()
        drops.register(.shelf, owner: owner, frame: CGRect(x: 0, y: 0, width: 620, height: 190), perform: { _ in true })
        drops.register(.convert, owner: owner, frame: CGRect(x: 420, y: 60, width: 78, height: 107), perform: { _ in true })
        drops.register(.format(.png), owner: owner, frame: CGRect(x: 100, y: 60, width: 78, height: 107), perform: { _ in true })
        #expect(drops.target(at: CGPoint(x: 450, y: 100)) == .convert)
        #expect(drops.target(at: CGPoint(x: 130, y: 100)) == .format(.png))
        #expect(drops.target(at: CGPoint(x: 300, y: 20)) == .shelf)
        #expect(drops.target(at: CGPoint(x: 700, y: 20)) == nil, "past the island nothing takes it")
    }

    @Test func aPlaceLeavingDoesntTakeAwayOneArriving() {
        let drops = IslandDrops()
        let leaving = UUID(), arriving = UUID()
        drops.register(.convert, owner: leaving, frame: CGRect(x: 0, y: 0, width: 10, height: 10), perform: { _ in true })
        drops.register(.convert, owner: arriving, frame: CGRect(x: 0, y: 0, width: 10, height: 10), perform: { _ in true })
        drops.unregister(.convert, owner: leaving)
        #expect(drops.target(at: CGPoint(x: 5, y: 5)) == .convert)
        drops.unregister(.convert, owner: arriving)
        #expect(drops.target(at: CGPoint(x: 5, y: 5)) == nil)
    }

    @Test func aDropClearsTheLightAndRunsItsPlace() {
        let drops = IslandDrops()
        var ran = false
        drops.register(.airDrop, owner: UUID(), frame: CGRect(x: 0, y: 0, width: 10, height: 10), perform: { _ in ran = true; return true })
        drops.hover(.airDrop)
        #expect(drops.hovered == .airDrop)
        #expect(drops.perform(.airDrop, with: NSPasteboard.withUniqueName()))
        #expect(ran && drops.hovered == nil)
    }

    @Test func aPhotoFromFinderIsKeptAsTheFileNotACopy() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let photo = folder.appendingPathComponent("IMG_3001.HEIC")
        try Data("x".utf8).write(to: photo)

        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        // Finder puts the picture beside the file.
        let item = NSPasteboardItem()
        item.setString(photo.absoluteString, forType: .fileURL)
        item.setData(Data([0x49, 0x49, 0x2A, 0x00]), forType: .tiff)
        pasteboard.writeObjects([item])

        let kept = ShelfModel.files(from: pasteboard, writingInto: folder)
        #expect(kept.map(\.lastPathComponent) == ["IMG_3001.HEIC"])
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["IMG_3001.HEIC"], "no Image copy written")
    }

    @Test func picturesLinksAndTextFromOtherAppsBecomeFiles() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }

        pasteboard.clearContents()
        pasteboard.setData(Data([0x89, 0x50, 0x4E, 0x47]), forType: .png)
        #expect(ShelfModel.files(from: pasteboard, writingInto: folder).map(\.lastPathComponent) == ["Image.png"])

        pasteboard.clearContents()
        pasteboard.writeObjects([URL(string: "https://example.com/page")! as NSURL])
        #expect(ShelfModel.files(from: pasteboard, writingInto: folder).map(\.lastPathComponent) == ["example.com.webloc"])

        pasteboard.clearContents()
        pasteboard.setString("Pick up milk\nand eggs", forType: .string)
        #expect(ShelfModel.files(from: pasteboard, writingInto: folder).map(\.lastPathComponent) == ["Pick up milk.txt"])
    }
}
