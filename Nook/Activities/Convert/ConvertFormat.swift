import AudioToolbox
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// What kind of file is being converted, which decides what it can become.
nonisolated enum ConvertSource: String, Sendable, CaseIterable {
    case image, svg, animatedGIF, video, audio, pdf, document

    /// Reads only the file's type, and for a GIF how many frames it has.
    static func of(_ url: URL) -> ConvertSource? {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else { return nil }
        if type.conforms(to: .svg) { return .svg }
        if type.conforms(to: .pdf) { return .pdf }
        if type.conforms(to: .gif) {
            let frames = CGImageSourceCreateWithURL(url as CFURL, nil).map(CGImageSourceGetCount) ?? 1
            return frames > 1 ? .animatedGIF : .image
        }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .movie) { return .video }
        if type.conforms(to: .audio) { return .audio }
        if documentTypes.contains(where: { type.conforms(to: $0) }) { return .document }
        return nil
    }

    /// Text the system reads into styled text: Word, OpenDocument, RTF, web pages, plain text, Markdown.
    static let documentTypes: [UTType] = [.rtf, .rtfd, .flatRTFD, .html, .plainText]
        + ["org.openxmlformats.wordprocessingml.document", "com.microsoft.word.doc", "org.oasis-open.opendocument.text",
           "net.daringfireball.markdown"].compactMap { UTType($0) }
}

/// A format Nook can turn files into.
nonisolated enum ConvertTarget: String, Sendable, CaseIterable, Codable {
    // Pictures
    case jpeg, png, heic, pdf, tiff, avif, gif, bmp, ico, icns
    // Several pictures as one document
    case onePDF
    // Video
    case mp4, mp4HEVC, mov, prores, animatedGIF
    // Sound, from audio or from a video's soundtrack
    case m4a, alac, wav, aiff, flac
    // Text
    case text, docx, rtf, html, odt
    // From the More Formats download
    case webp, jpegXL, webm, mkv, mp3, opus

    var name: String {
        switch self {
        case .jpeg: "JPEG"
        case .png: "PNG"
        case .heic: "HEIC"
        case .pdf: "PDF"
        case .tiff: "TIFF"
        case .avif: "AVIF"
        case .gif: "GIF"
        case .bmp: "BMP"
        case .ico: "ICO"
        case .icns: "ICNS"
        case .onePDF: "One PDF"
        case .mp4: "MP4"
        case .mp4HEVC: "MP4 Smaller"
        case .mov: "MOV"
        case .prores: "ProRes"
        case .animatedGIF: "GIF"
        case .m4a: "M4A"
        case .alac: "Apple Lossless"
        case .wav: "WAV"
        case .aiff: "AIFF"
        case .flac: "FLAC"
        case .text: "Text"
        case .docx: "Word"
        case .rtf: "RTF"
        case .html: "HTML"
        case .odt: "OpenDocument"
        case .webp: "WebP"
        case .jpegXL: "JPEG XL"
        case .webm: "WebM"
        case .mkv: "MKV"
        case .mp3: "MP3"
        case .opus: "Opus"
        }
    }

    var fileExtension: String {
        switch self {
        case .jpeg: "jpg"
        case .png: "png"
        case .heic: "heic"
        case .pdf, .onePDF: "pdf"
        case .tiff: "tiff"
        case .avif: "avif"
        case .gif, .animatedGIF: "gif"
        case .bmp: "bmp"
        case .ico: "ico"
        case .icns: "icns"
        case .mp4, .mp4HEVC: "mp4"
        case .mov, .prores: "mov"
        case .m4a, .alac: "m4a"
        case .wav: "wav"
        case .aiff: "aiff"
        case .flac: "flac"
        case .text: "txt"
        case .docx: "docx"
        case .rtf: "rtf"
        case .html: "html"
        case .odt: "odt"
        case .webp: "webp"
        case .jpegXL: "jxl"
        case .webm: "webm"
        case .mkv: "mkv"
        case .mp3: "mp3"
        case .opus: "opus"
        }
    }

    /// The file type it makes, for the document icon the system draws for it.
    var type: UTType { UTType(filenameExtension: fileExtension) ?? .data }

    /// Made by the More Formats download rather than by macOS.
    var needsPack: Bool {
        switch self {
        case .webp, .jpegXL, .webm, .mkv, .mp3, .opus: true
        default: false
        }
    }

    /// The ImageIO writer for a picture target.
    var imageWriter: UTType? {
        switch self {
        case .jpeg: .jpeg
        case .png: .png
        case .heic: .heic
        case .pdf: .pdf
        case .tiff: .tiff
        case .avif: UTType("public.avif")
        case .gif: .gif
        case .bmp: .bmp
        case .ico: .ico
        case .icns: .icns
        default: nil
        }
    }

    /// Whether the file is already in this format, so it isn't offered.
    func matches(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else { return false }
        switch self {
        case .mp4HEVC, .prores, .alac, .onePDF, .animatedGIF: return false
        case .mov: return type.conforms(to: .quickTimeMovie)
        case .mp4: return type.conforms(to: .mpeg4Movie)
        case .m4a: return type.conforms(to: .mpeg4Audio)
        case .text: return type.conforms(to: .plainText) && !type.conforms(to: .html)
        default: return type.conforms(to: self.type) || self.type.conforms(to: type)
        }
    }
}

/// What each kind of file can become, in the order the tiles show them.
nonisolated enum ConvertCatalog {
    /// The first four show as tiles; the rest are under More, then the download's.
    static func targets(for source: ConvertSource) -> [ConvertTarget] {
        switch source {
        case .image: [.jpeg, .png, .pdf, .heic, .tiff, .avif, .gif, .bmp, .ico, .icns, .webp, .jpegXL]
        case .svg: [.png, .jpeg, .pdf, .heic, .tiff, .ico, .icns, .webp]
        case .animatedGIF: [.mp4, .mov, .png, .jpeg, .heic, .webp, .webm]
        case .video: [.mp4, .mp4HEVC, .mov, .animatedGIF, .m4a, .wav, .prores, .webm, .mkv, .mp3]
        case .audio: [.m4a, .wav, .flac, .aiff, .alac, .mp3, .opus]
        case .pdf: [.png, .jpeg, .text, .heic, .tiff]
        case .document: [.pdf, .docx, .rtf, .text, .html, .odt]
        }
    }

    /// The formats offered for these files: ones every file can become, minus any file's own format,
    /// with the last one used for this kind first. Formats this Mac can't write are left out, and the
    /// download's are left out unless `withPack`.
    static func targets(for urls: [URL], withPack: Bool, lastUsed: ConvertTarget? = nil) -> [ConvertTarget] {
        let sources = urls.map(ConvertSource.of)
        guard let first = sources.first, let kind = first, !sources.contains(where: { $0 == nil }) else { return [] }
        var list = targets(for: kind)
        for case let other? in sources.dropFirst() where other != kind {
            let theirs = Set(targets(for: other))
            list = list.filter(theirs.contains)
        }
        list = list.filter { target in
            !urls.contains(where: target.matches) && (withPack || !target.needsPack) && Capabilities.canWrite(target)
        }
        // Several pictures can also become one PDF, offered first.
        if urls.count > 1, sources.allSatisfy({ $0 == .image || $0 == .svg }) { list.insert(.onePDF, at: 0) }
        if let lastUsed, let index = list.firstIndex(of: lastUsed) {
            list.remove(at: index)
            list.insert(lastUsed, at: list.first == .onePDF ? 1 : 0)
        }
        return list
    }
}

/// What this Mac can write, asked once. Nook runs on macOS 15 and later, and some writers (AVIF, for
/// one) depend on the version, so nothing is assumed.
nonisolated enum Capabilities {
    static let imageWriters: Set<String> = Set(CGImageDestinationCopyTypeIdentifiers() as? [String] ?? [])

    static let audioEncoders: Set<AudioFormatID> = {
        var size: UInt32 = 0
        guard AudioFormatGetPropertyInfo(kAudioFormatProperty_EncodeFormatIDs, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioFormatID](repeating: 0, count: Int(size) / MemoryLayout<AudioFormatID>.size)
        guard AudioFormatGetProperty(kAudioFormatProperty_EncodeFormatIDs, 0, nil, &size, &ids) == noErr else { return [] }
        return Set(ids)
    }()

    static func canWrite(_ target: ConvertTarget) -> Bool {
        if let writer = target.imageWriter { return imageWriters.contains(writer.identifier) }
        switch target {
        case .flac: return audioEncoders.contains(kAudioFormatFLAC)
        case .alac: return audioEncoders.contains(kAudioFormatAppleLossless)
        case .m4a: return audioEncoders.contains(kAudioFormatMPEG4AAC)
        default: return true
        }
    }
}
