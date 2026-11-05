import CryptoKit
import Foundation

/// More Formats: the optional download of open-source encoders macOS doesn't have (MP3, WebP, VP9 for
/// WebM, Opus), as one `ffmpeg` built by scripts/formats-pack.sh. Nothing is downloaded until asked.
/// Nook knows the exact file it was built for, by size and SHA-256, so anything else is thrown away
/// before it's unpacked, let alone run.
@Observable
final class FormatPack {
    static let shared = FormatPack()

    enum State: Equatable {
        case notInstalled
        case downloading(Double)
        case installed
        case failed(String)
    }

    private(set) var state: State = .notInstalled

    /// The pack this Nook works with.
    static let version = 1
    static let remote = URL(string: "https://github.com/sanvithreddyy/nook/releases/download/formats-\(version)/NookFormats-\(version).zip")!
    static let sha256 = "918f7dac1ea98de0266db5f2eea2f12e7337d4febd6420d389f049681ee5e412"
    static let size: Int64 = 23921527

    /// Application Support/Nook/Formats; tests pass a temporary folder.
    let folder: URL
    /// Where the pack comes from; tests and debug runs point it at a local file.
    var source: URL

    init(folder: URL? = nil, source: URL? = nil) {
        self.folder = folder ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nook/Formats", isDirectory: true)
        var from = source ?? Self.remote
        #if DEBUG
        // -formats-from <zip>: the pack from a local build, for trying it before it's published.
        if source == nil, let i = CommandLine.arguments.firstIndex(of: "-formats-from"), CommandLine.arguments.indices.contains(i + 1) {
            from = URL(fileURLWithPath: CommandLine.arguments[i + 1])
        }
        #endif
        self.source = from
        if FileManager.default.isExecutableFile(atPath: executable.path) { state = .installed }
    }

    var isInstalled: Bool { state == .installed }
    var executable: URL { folder.appendingPathComponent("NookFormats/ffmpeg") }

    /// A download under way already is waited for rather than started again.
    @ObservationIgnored private var installing: Task<Bool, Never>?

    /// Downloads, checks and unpacks the pack. True once it's ready to use.
    @discardableResult
    func install(expecting sha256: String = FormatPack.sha256) async -> Bool {
        if isInstalled { return true }
        if let installing { return await installing.value }
        let task = Task { await run(expecting: sha256) }
        installing = task
        let done = await task.value
        installing = nil
        return done
    }

    private func run(expecting sha256: String) async -> Bool {
        state = .downloading(0)
        do {
            let zip = try await fetch()
            defer { try? FileManager.default.removeItem(at: zip) }
            guard try Self.digest(of: zip) == sha256 else {
                throw ConvertError.failed("The download didn't match the one Nook expects, so it was thrown away.")
            }
            try unpack(zip)
            state = .installed
            return true
        } catch {
            try? FileManager.default.removeItem(at: folder)
            state = .failed(error.localizedDescription)
            return false
        }
    }

    func remove() {
        try? FileManager.default.removeItem(at: folder)
        state = .notInstalled
    }

    private func fetch() async throws -> URL {
        let local = FileManager.default.temporaryDirectory.appendingPathComponent("NookFormats-\(UUID().uuidString).zip")
        if source.isFileURL {
            try FileManager.default.copyItem(at: source, to: local)
            return local
        }
        let progress = DownloadProgress { [weak self] share in
            Task { @MainActor in if case .downloading = self?.state { self?.state = .downloading(share) } }
        }
        let (downloaded, response) = try await URLSession.shared.download(from: source, delegate: progress)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw ConvertError.failed("More Formats isn't available to download right now.")
        }
        try FileManager.default.moveItem(at: downloaded, to: local)
        return local
    }

    private func unpack(_ zip: URL) throws {
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zip.path, folder.path]
        try ditto.run()
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0, FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw ConvertError.failed("More Formats couldn't be unpacked.")
        }
        // Run it once: that it runs on this Mac is part of installing it, and macOS's check of a new
        // program (a few seconds the first time) happens now rather than in the first conversion.
        let check = Process()
        check.executableURL = executable
        check.arguments = ["-hide_banner", "-version"]
        check.standardOutput = FileHandle.nullDevice
        check.standardError = FileHandle.nullDevice
        try check.run()
        check.waitUntilExit()
        guard check.terminationStatus == 0 else { throw ConvertError.failed("More Formats doesn't run on this Mac.") }
    }

    nonisolated static func digest(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hash.update(data: chunk) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// Reports a download's share done.
private final class DownloadProgress: NSObject, URLSessionTaskDelegate, Sendable {
    let report: @Sendable (Double) -> Void
    init(_ report: @escaping @Sendable (Double) -> Void) { self.report = report }

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        // The task's own progress, watched until it finishes.
        let observation = task.progress.observe(\.fractionCompleted) { [report] progress, _ in report(progress.fractionCompleted) }
        objc_setAssociatedObject(task, Unmanaged.passUnretained(self).toOpaque(), observation, .OBJC_ASSOCIATION_RETAIN)
    }
}
