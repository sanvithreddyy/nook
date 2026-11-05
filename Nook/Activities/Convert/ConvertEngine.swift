import Foundation

/// How conversions come out, from Settings.
nonisolated struct ConvertOptions: Sendable {
    /// JPEG, HEIC and AVIF quality, 0…1.
    var photoQuality: Double = 0.9
    /// AAC bit rate, bits per second.
    var audioBitRate: Int = 256_000
    /// Save results in Downloads instead of next to the original.
    var toDownloads = false
    /// More Formats' ffmpeg, when it's installed.
    var ffmpeg: URL?
}

nonisolated enum ConvertError: LocalizedError {
    case unreadable(String)
    case noAudio(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unreadable(let name): "Couldn't read \(name)."
        case .noAudio(let name): "\(name) has no sound."
        case .failed(let reason): reason
        }
    }
}

/// Where a converted file goes: beside the original, or in Downloads when the original's folder can't
/// be written to (a disk image, another user's folder) or Settings asks.
nonisolated enum ConvertOutput {
    static func folder(for source: URL, toDownloads: Bool) -> URL {
        let beside = source.deletingLastPathComponent()
        if !toDownloads, FileManager.default.isWritableFile(atPath: beside.path) { return beside }
        return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    }

    /// `name.ext`, or `name 2.ext` and so on if that's taken, as Finder names a copy.
    static func unique(in folder: URL, name: String, ext: String) -> URL {
        var url = folder.appendingPathComponent(name).appendingPathExtension(ext)
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(name) \(n)").appendingPathExtension(ext)
            n += 1
        }
        return url
    }

    /// A new folder named `name` (or `name 2`…), for results that come as several files.
    static func uniqueFolder(in folder: URL, name: String) throws -> URL {
        var url = folder.appendingPathComponent(name, isDirectory: true)
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(name) \(n)", isDirectory: true)
            n += 1
        }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    static func baseName(_ url: URL) -> String { url.deletingPathExtension().lastPathComponent }
}

/// Converts files with what macOS provides: ImageIO for pictures, PDFKit for PDFs, AVFoundation and
/// Audio Toolbox for video and sound, the text system for documents. Nothing leaves the Mac.
nonisolated enum ConvertEngine {
    /// Converts each file (or all of them, into one PDF) and returns what it made. `progress` gets the
    /// share done so far, 0…1, from whatever thread the work is on.
    @concurrent
    static func run(_ urls: [URL], to target: ConvertTarget, options: ConvertOptions,
                    progress: @escaping @Sendable (Double) -> Void) async throws -> [URL] {
        if target == .onePDF {
            let dest = ConvertOutput.unique(in: ConvertOutput.folder(for: urls[0], toDownloads: options.toDownloads),
                                            name: urls.count > 1 ? "\(ConvertOutput.baseName(urls[0])) and \(urls.count - 1) more" : ConvertOutput.baseName(urls[0]),
                                            ext: "pdf")
            try ImageConversion.combine(urls, into: dest)
            progress(1)
            return [dest]
        }
        var made: [URL] = []
        for (index, url) in urls.enumerated() {
            try Task.checkCancellation()
            let share: @Sendable (Double) -> Void = { part in progress((Double(index) + part) / Double(urls.count)) }
            made += try await convert(url, to: target, options: options, progress: share)
            share(1)
        }
        return made
    }

    @concurrent
    private static func convert(_ url: URL, to target: ConvertTarget, options: ConvertOptions,
                                progress: @escaping @Sendable (Double) -> Void) async throws -> [URL] {
        guard let source = ConvertSource.of(url) else { throw ConvertError.unreadable(url.lastPathComponent) }
        let folder = ConvertOutput.folder(for: url, toDownloads: options.toDownloads)
        let name = ConvertOutput.baseName(url)
        let dest = { ConvertOutput.unique(in: folder, name: name, ext: target.fileExtension) }

        if ConvertCatalog.needsPack(target, for: [url]) {
            guard let ffmpeg = options.ffmpeg else { throw ConvertError.failed("\(target.name) needs More Formats, from Settings → Converter.") }
            let out = dest()
            try await PackConversion.run(url, source: source, to: target, ffmpeg: ffmpeg, options: options, into: out, progress: progress)
            return [out]
        }

        switch (source, target) {
        case (.pdf, .text):
            let out = dest()
            try ImageConversion.pdfText(url, to: out)
            return [out]
        case (.pdf, _):
            return try ImageConversion.pdfPages(url, to: target, quality: options.photoQuality, folder: folder, name: name)
        case (.image, _), (.svg, _), (.animatedGIF, .png), (.animatedGIF, .jpeg), (.animatedGIF, .heic):
            let out = dest()
            try ImageConversion.image(url, source: source, to: target, quality: options.photoQuality, into: out)
            return [out]
        case (.animatedGIF, .mp4), (.animatedGIF, .mov):
            let out = dest()
            try await MediaConversion.gifToVideo(url, fileType: target == .mov ? .mov : .mp4, to: out, progress: progress)
            return [out]
        case (.video, .mp4), (.video, .mp4HEVC), (.video, .mov), (.video, .prores):
            let out = dest()
            try await MediaConversion.export(url, to: target, into: out, progress: progress)
            return [out]
        case (.video, .animatedGIF):
            let out = dest()
            try await MediaConversion.videoToGIF(url, to: out, progress: progress)
            return [out]
        case (.video, .m4a), (.video, .wav), (.audio, .m4a), (.audio, .alac), (.audio, .wav), (.audio, .aiff), (.audio, .flac):
            let out = dest()
            try await MediaConversion.audio(url, to: target, bitRate: options.audioBitRate, into: out, progress: progress)
            return [out]
        case (.document, _):
            let out = dest()
            try await DocumentConversion.convert(url, to: target, into: out)
            return [out]
        default:
            throw ConvertError.failed("\(url.lastPathComponent) can't become \(target.name).")
        }
    }
}
