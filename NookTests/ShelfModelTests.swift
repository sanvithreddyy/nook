import Foundation
import Testing


/// Removing things from the shelf must never destroy a user's file.
@MainActor
struct ShelfModelTests {
    let root: URL
    let elsewhere: URL

    init() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("NookShelfTests-\(UUID().uuidString)")
        root = base.appendingPathComponent("Nook")
        elsewhere = base.appendingPathComponent("Documents")
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
    }

    private func makeFile(_ name: String, in folder: URL) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name)
        try Data("x".utf8).write(to: url)
        return url
    }

    @Test func removingAUserFileKeepsTheFile() throws {
        let shelf = ShelfModel(root: root)
        let file = try makeFile("report.pdf", in: elsewhere)
        shelf.add([file])
        #expect(shelf.items.count == 1)
        #expect(shelf.items[0].isOwned == false)

        shelf.remove(shelf.items[0])
        #expect(shelf.items.isEmpty)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func clearKeepsUserFiles() throws {
        let shelf = ShelfModel(root: root)
        let a = try makeFile("a.txt", in: elsewhere)
        let b = try makeFile("b.txt", in: elsewhere)
        shelf.add([a, b])
        shelf.clear()
        #expect(FileManager.default.fileExists(atPath: a.path))
        #expect(FileManager.default.fileExists(atPath: b.path))
    }

    @Test func removingANookFileDiscardsIt() throws {
        let shelf = ShelfModel(root: root)
        let url = try #require(ShelfModel.write(Data("note".utf8), named: "Note.txt", in: shelf.directory))
        shelf.add([url])
        #expect(shelf.items[0].isOwned)

        shelf.remove(shelf.items[0])
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func aNookFileMovedOutBecomesTheUsers() throws {
        let first = ShelfModel(root: root)
        let url = try #require(ShelfModel.write(Data("note".utf8), named: "Note.txt", in: first.directory))
        first.add([url])

        // The user moves the file out of Nook's folder, then Nook relaunches.
        let moved = elsewhere.appendingPathComponent("Note.txt")
        try FileManager.default.moveItem(at: url, to: moved)
        let relaunched = ShelfModel(root: root)
        let item = try #require(relaunched.items.first)
        #expect(URL(fileURLWithPath: item.path).resolvingSymlinksInPath() == moved.resolvingSymlinksInPath())
        #expect(item.isOwned == false)

        relaunched.remove(item)
        #expect(FileManager.default.fileExists(atPath: moved.path))
    }

    @Test func aSimilarlyNamedFolderIsNotTheShelf() throws {
        let shelf = ShelfModel(root: root)
        let lookalike = try makeFile("x.txt", in: root.appendingPathComponent("Shelf Backup"))
        #expect(shelf.isInShelfFolder(lookalike) == false)
        shelf.add([lookalike])
        shelf.remove(shelf.items[0])
        #expect(FileManager.default.fileExists(atPath: lookalike.path))
    }

    @Test func missingFilesStayOnTheShelf() throws {
        let first = ShelfModel(root: root)
        let file = try makeFile("gone.txt", in: elsewhere)
        first.add([file])
        try FileManager.default.removeItem(at: file)

        let relaunched = ShelfModel(root: root)
        #expect(relaunched.items.count == 1)
        #expect(relaunched.items[0].isMissing)
    }

    @Test func addingTheSameFileTwiceKeepsOneItem() throws {
        let shelf = ShelfModel(root: root)
        let file = try makeFile("once.txt", in: elsewhere)
        shelf.add([file])
        shelf.add([file])
        #expect(shelf.items.count == 1)
    }
}
