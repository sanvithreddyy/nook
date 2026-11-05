import AppKit
import AudioToolbox
import AVFoundation
import ImageIO
import PDFKit
import Testing
import UniformTypeIdentifiers

/// What a dragged file is offered, in tile order.
struct ConvertCatalogTests {
    private func url(_ name: String) -> URL { URL(fileURLWithPath: "/tmp/\(name)") }

    @Test func aPhotoIsOfferedOtherPictureFormatsButNotItsOwn() {
        let heic = ConvertCatalog.targets(for: [url("IMG_2063.HEIC")], withPack: false)
        #expect(Array(heic.prefix(4)) == [.jpeg, .png, .pdf, .tiff])
        #expect(!heic.contains(.heic))
        let png = ConvertCatalog.targets(for: [url("Shot.png")], withPack: false)
        #expect(Array(png.prefix(4)) == [.jpeg, .pdf, .heic, .tiff])
    }

    @Test func theLastFormatUsedComesFirst() {
        let list = ConvertCatalog.targets(for: [url("IMG_2063.HEIC")], withPack: false, lastUsed: .tiff)
        #expect(list.first == .tiff)
        #expect(list.filter { $0 == .tiff }.count == 1)
    }

    @Test func severalPicturesCanBecomeOnePDF() {
        let list = ConvertCatalog.targets(for: [url("a.jpg"), url("b.png")], withPack: false, lastUsed: .png)
        #expect(list.first == .onePDF)
        // PNG is one of the files' own formats, so it isn't offered even though it was used last.
        #expect(!list.contains(.png))
    }

    @Test func videosAudioAndDocuments() {
        #expect(Array(ConvertCatalog.targets(for: [url("Trip.mov")], withPack: false).prefix(4)) == [.mp4, .mp4HEVC, .animatedGIF, .m4a])
        #expect(Array(ConvertCatalog.targets(for: [url("Song.wav")], withPack: false).prefix(4)) == [.m4a, .flac, .aiff, .alac])
        #expect(Array(ConvertCatalog.targets(for: [url("Notes.docx")], withPack: false).prefix(4)) == [.pdf, .rtf, .text, .html])
    }

    @Test func mixedKindsShareNothingAndUnknownFilesGetNothing() {
        #expect(ConvertCatalog.targets(for: [url("a.jpg"), url("Trip.mov")], withPack: false).isEmpty)
        #expect(ConvertCatalog.targets(for: [url("Archive.zip")], withPack: false).isEmpty)
    }

    @Test func downloadFormatsOnlyWithTheDownload() {
        let plain = ConvertCatalog.targets(for: [url("a.jpg")], withPack: false)
        #expect(plain.allSatisfy { !$0.needsPack })
        #expect(ConvertCatalog.targets(for: [url("a.jpg")], withPack: true).contains(.webp))
    }

    @Test func everyOfferedTargetHasARoute() {
        // The engine's switch must cover everything the catalogue offers natively.
        for source in ConvertSource.allCases {
            for target in ConvertCatalog.targets(for: source) where !target.needsPack {
                #expect(target.fileExtension.isEmpty == false, "\(source) → \(target)")
            }
        }
    }
}

/// Real conversions, on files made for the test.
@MainActor
struct ConvertEngineTests {
    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("convert-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private func run(_ urls: [URL], to target: ConvertTarget) async throws -> [URL] {
        try await ConvertEngine.run(urls, to: target, options: ConvertOptions(), progress: { _ in })
    }

    // MARK: Pictures

    @Test(arguments: [ConvertTarget.jpeg, .heic, .tiff, .pdf, .gif, .bmp, .ico, .icns, .avif])
    func aPictureBecomesEachPictureFormat(_ target: ConvertTarget) async throws {
        guard Capabilities.canWrite(target) else { return }
        let source = try Fixtures.png(in: folder, name: "Shot")
        let made = try await run([source], to: target)
        #expect(made.count == 1)
        #expect(made[0].pathExtension == target.fileExtension)
        #expect(made[0].deletingLastPathComponent() == folder, "saved next to the original")
        let file = try #require(CGImageSourceCreateWithURL(made[0] as CFURL, nil))
        #expect(CGImageSourceGetCount(file) >= 1)
        #expect((CGImageSourceGetType(file) as String?) == target.imageWriter?.identifier)
        if target == .icns { #expect(CGImageSourceGetCount(file) >= 5, "every icon size") }
    }

    @Test func seeThroughPicturesGetWhiteForJPEG() async throws {
        let source = try Fixtures.png(in: folder, name: "Clear", transparent: true)
        let made = try await run([source], to: .jpeg)
        let image = try #require(CGImageSourceCreateWithURL(made[0] as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) })
        let corner = Fixtures.pixel(image, x: 0, y: 0)
        #expect(corner.r > 240 && corner.g > 240 && corner.b > 240, "transparent corner should be white, was \(corner)")
    }

    @Test func aTakenNameGetsANumber() async throws {
        let source = try Fixtures.png(in: folder, name: "Shot")
        _ = try await run([source], to: .jpeg)
        let second = try await run([source], to: .jpeg)
        #expect(second[0].lastPathComponent == "Shot 2.jpg")
    }

    @Test func anSVGIsDrawnLarge() async throws {
        let svg = folder.appendingPathComponent("Logo.svg")
        try #"<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24"><circle cx="12" cy="12" r="10" fill="red"/></svg>"#
            .write(to: svg, atomically: true, encoding: .utf8)
        let made = try await run([svg], to: .png)
        let image = try #require(CGImageSourceCreateWithURL(made[0] as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) })
        #expect(image.width >= 1024)
    }

    @Test func picturesBecomeOnePDF() async throws {
        let a = try Fixtures.png(in: folder, name: "A"), b = try Fixtures.png(in: folder, name: "B")
        let made = try await run([a, b], to: .onePDF)
        #expect(made[0].lastPathComponent == "A and 1 more.pdf")
        #expect(PDFDocument(url: made[0])?.pageCount == 2)
    }

    @Test func aPDFsPagesBecomePicturesInAFolder() async throws {
        let pdf = try Fixtures.pdf(in: folder, pages: 3)
        let made = try await run([pdf], to: .png)
        #expect(made.count == 1)
        var isFolder: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: made[0].path, isDirectory: &isFolder) && isFolder.boolValue)
        let pages = try FileManager.default.contentsOfDirectory(atPath: made[0].path).sorted()
        #expect(pages == ["Pages 1.png", "Pages 2.png", "Pages 3.png"])
    }

    @Test func aOnePagePDFBecomesOnePictureAndText() async throws {
        let pdf = try Fixtures.pdf(in: folder, pages: 1)
        let picture = try await run([pdf], to: .jpeg)
        #expect(picture[0].lastPathComponent == "Pages.jpg")
        let text = try await run([pdf], to: .text)
        #expect(try String(contentsOf: text[0], encoding: .utf8).contains("Page 1"))
    }

    @Test func anAnimatedGIFBecomesAVideo() async throws {
        let gif = try Fixtures.gif(in: folder, frames: 6, delay: 0.25)
        for target in [ConvertTarget.mp4, .mov] {
            let made = try await run([gif], to: target)
            let asset = AVURLAsset(url: made[0])
            let seconds = try await asset.load(.duration).seconds
            #expect(abs(seconds - 1.5) < 0.1, "\(target): \(seconds) s")
            #expect(try await asset.loadTracks(withMediaType: .video).count == 1)
        }
        let still = try await run([gif], to: .png)
        #expect(CGImageSourceCreateWithURL(still[0] as CFURL, nil).map(CGImageSourceGetCount) == 1)
    }

    // MARK: Video

    @Test func aVideoBecomesMP4MOVAndGIF() async throws {
        let movie = try await Fixtures.movie(in: folder)
        let mp4 = try await run([movie], to: .mp4)
        #expect(try await Fixtures.codec(mp4[0]) == kCMVideoCodecType_H264)
        let smaller = try await run([movie], to: .mp4HEVC)
        #expect(try await Fixtures.codec(smaller[0]) == kCMVideoCodecType_HEVC)
        // An HEVC video made into the plain MP4 is re-encoded, so it plays everywhere.
        let again = try await run([smaller[0]], to: .mp4)
        #expect(try await Fixtures.codec(again[0]) == kCMVideoCodecType_H264)
        let gif = try await run([movie], to: .animatedGIF)
        #expect((CGImageSourceCreateWithURL(gif[0] as CFURL, nil).map(CGImageSourceGetCount) ?? 0) >= 10)
    }

    @Test func aVideosSoundBecomesAudio() async throws {
        let movie = try await Fixtures.movie(in: folder)
        for target in [ConvertTarget.m4a, .wav] {
            let made = try await run([movie], to: target)
            let seconds = try await AVURLAsset(url: made[0]).load(.duration).seconds
            #expect(abs(seconds - 1) < 0.15, "\(target): \(seconds) s")
        }
    }

    // MARK: Sound

    @Test(arguments: [ConvertTarget.m4a, .alac, .flac, .aiff, .wav])
    func audioBecomesEachSoundFormat(_ target: ConvertTarget) async throws {
        guard Capabilities.canWrite(target) else { return }
        let wav = try Fixtures.wav(in: folder, name: target == .wav ? "Tone.aiff" : "Tone.wav")
        let made = try await run([wav], to: target)
        let asset = AVURLAsset(url: made[0])
        let seconds = try await asset.load(.duration).seconds
        #expect(abs(seconds - 1) < 0.1, "\(target): \(seconds) s")
        #expect(try await asset.loadTracks(withMediaType: .audio).count == 1)
    }

    /// Spoken-word recordings are often mono at 22 kHz, where AAC can't reach 256 kbps.
    @Test func slowMonoSoundBecomesM4A() async throws {
        let wav = try Fixtures.wav(in: folder, name: "Voice.wav", rate: 22050, channels: 1)
        let made = try await run([wav], to: .m4a)
        let seconds = try await AVURLAsset(url: made[0]).load(.duration).seconds
        #expect(abs(seconds - 1) < 0.1, "\(seconds) s")
    }

    // MARK: Documents

    @Test(arguments: [ConvertTarget.pdf, .docx, .rtf, .text, .html, .odt])
    func aDocumentBecomesEachTextFormat(_ target: ConvertTarget) async throws {
        let rtf = folder.appendingPathComponent("Notes.rtf")
        let text = NSAttributedString(string: "Shopping list\nMilk and bread", attributes: [.font: NSFont.boldSystemFont(ofSize: 14)])
        try text.rtf(from: NSRange(location: 0, length: text.length), documentAttributes: [:])?.write(to: rtf)
        let made = try await run([rtf], to: target)
        if target == .pdf {
            let pdf = try #require(PDFDocument(url: made[0]))
            #expect(pdf.pageCount >= 1)
            #expect(pdf.string?.contains("Milk and bread") == true)
        } else {
            let back = try NSAttributedString(url: made[0], options: [:], documentAttributes: nil)
            #expect(back.string.contains("Milk and bread"), "\(target)")
        }
    }

    @Test func markdownKeepsItsTextAndEmphasis() async throws {
        let md = folder.appendingPathComponent("Readme.md")
        try "# Title\nSome **bold** words".write(to: md, atomically: true, encoding: .utf8)
        let made = try await run([md], to: .rtf)
        let back = try NSAttributedString(url: made[0], options: [:], documentAttributes: nil)
        #expect(back.string.contains("Some bold words"))
        let font = back.attribute(.font, at: (back.string as NSString).range(of: "bold").location, effectiveRange: nil) as? NSFont
        #expect(font?.fontDescriptor.symbolicTraits.contains(.bold) == true)
    }
}

/// Files made for the tests.
enum Fixtures {
    static func png(in folder: URL, name: String, transparent: Bool = false) throws -> URL {
        let width = 64, height = 48
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        if !transparent {
            context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        context.setFillColor(CGColor(red: 0.9, green: 0.3, blue: 0.2, alpha: 1))
        context.fillEllipse(in: CGRect(x: 16, y: 8, width: 32, height: 32))
        let url = folder.appendingPathComponent("\(name).png")
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        guard CGImageDestinationFinalize(destination) else { throw ConvertError.failed("fixture") }
        return url
    }

    static func gif(in folder: URL, frames: Int, delay: Double) throws -> URL {
        let url = folder.appendingPathComponent("Spin.gif")
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frames, nil)!
        for index in 0..<frames {
            let context = CGContext(data: nil, width: 40, height: 30, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(CGColor(red: Double(index) / Double(frames), green: 0.4, blue: 0.6, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
            CGImageDestinationAddImage(destination, context.makeImage()!,
                                       [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else { throw ConvertError.failed("fixture") }
        return url
    }

    @MainActor
    static func pdf(in folder: URL, pages: Int) throws -> URL {
        let url = folder.appendingPathComponent("Pages.pdf")
        var box = CGRect(x: 0, y: 0, width: 300, height: 400)
        let context = CGContext(url as CFURL, mediaBox: &box, nil)!
        for index in 1...pages {
            context.beginPDFPage(nil)
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: "Page \(index)", attributes: [.font: NSFont.systemFont(ofSize: 24)]))
            context.textPosition = CGPoint(x: 40, y: 300)
            CTLineDraw(line, context)
            context.endPDFPage()
        }
        context.closePDF()
        return url
    }

    /// One second of a 440 Hz tone, 16-bit; stereo at 44.1 kHz unless asked otherwise.
    static func wav(in folder: URL, name: String, rate: Double = 44100, channels: UInt32 = 2) throws -> URL {
        let url = folder.appendingPathComponent(name)
        let aiff = url.pathExtension == "aiff"
        var format = AudioStreamBasicDescription(mSampleRate: rate, mFormatID: kAudioFormatLinearPCM,
                                                 mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked | (aiff ? kAudioFormatFlagIsBigEndian : 0),
                                                 mBytesPerPacket: 2 * channels, mFramesPerPacket: 1, mBytesPerFrame: 2 * channels, mChannelsPerFrame: channels, mBitsPerChannel: 16, mReserved: 0)
        var file: ExtAudioFileRef?
        guard ExtAudioFileCreateWithURL(url as CFURL, aiff ? kAudioFileAIFFType : kAudioFileWAVEType, &format, nil, AudioFileFlags.eraseFile.rawValue, &file) == noErr,
              let file else { throw ConvertError.failed("fixture") }
        var client = AudioStreamBasicDescription(mSampleRate: rate, mFormatID: kAudioFormatLinearPCM, mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
                                                 mBytesPerPacket: 4 * channels, mFramesPerPacket: 1, mBytesPerFrame: 4 * channels, mChannelsPerFrame: channels, mBitsPerChannel: 32, mReserved: 0)
        ExtAudioFileSetProperty(file, kExtAudioFileProperty_ClientDataFormat, UInt32(MemoryLayout.size(ofValue: client)), &client)
        let frames = Int(rate)
        var samples = [Float](repeating: 0, count: frames * Int(channels))
        for i in 0..<frames {
            let value = Float(sin(Double(i) * 2 * .pi * 440 / rate)) * 0.3
            for c in 0..<Int(channels) { samples[Int(channels) * i + c] = value }
        }
        let status = samples.withUnsafeMutableBytes { raw in
            var list = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: channels, mDataByteSize: UInt32(raw.count), mData: raw.baseAddress))
            return ExtAudioFileWrite(file, UInt32(frames), &list)
        }
        ExtAudioFileDispose(file)
        guard status == noErr else { throw ConvertError.failed("fixture") }
        return url
    }

    /// One second of H.264 video, 160 by 120 at 30 frames a second, with a tone.
    static func movie(in folder: URL) async throws -> URL {
        let url = folder.appendingPathComponent("Trip.mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 160, AVVideoHeightKey: 120])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: 160, kCVPixelBufferHeightKey as String: 120])
        let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 1])
        writer.add(video)
        writer.add(audio)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<30 {
            while !video.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
            CVPixelBufferLockBaseAddress(buffer!, [])
            memset(CVPixelBufferGetBaseAddress(buffer!), Int32(frame * 8), CVPixelBufferGetDataSize(buffer!))
            CVPixelBufferUnlockBaseAddress(buffer!, [])
            adaptor.append(buffer!, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 30))
        }
        video.markAsFinished()
        // The tone, in 1024-sample buffers.
        var format = AudioStreamBasicDescription(mSampleRate: 44100, mFormatID: kAudioFormatLinearPCM, mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
                                                 mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4, mChannelsPerFrame: 1, mBitsPerChannel: 32, mReserved: 0)
        var description: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(allocator: nil, asbd: &format, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &description)
        var start = 0
        while start < 44100 {
            let count = min(1024, 44100 - start)
            var samples = (0..<count).map { Float(sin(Double(start + $0) * 2 * .pi * 440 / 44100)) * 0.3 }
            var block: CMBlockBuffer?
            CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: count * 4, blockAllocator: nil, customBlockSource: nil,
                                               offsetToData: 0, dataLength: count * 4, flags: 0, blockBufferOut: &block)
            samples.withUnsafeMutableBytes { _ = CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block!, offsetIntoDestination: 0, dataLength: count * 4) }
            var sample: CMSampleBuffer?
            CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: nil, dataBuffer: block!, formatDescription: description!, sampleCount: count,
                                                                 presentationTimeStamp: CMTime(value: CMTimeValue(start), timescale: 44100),
                                                                 packetDescriptions: nil, sampleBufferOut: &sample)
            while !audio.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
            audio.append(sample!)
            start += count
        }
        audio.markAsFinished()
        writer.endSession(atSourceTime: CMTime(value: 1, timescale: 1))
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? ConvertError.failed("fixture") }
        return url
    }

    static func codec(_ url: URL) async throws -> FourCharCode? {
        let track = try await AVURLAsset(url: url).loadTracks(withMediaType: .video).first
        return try await track?.load(.formatDescriptions).first.map(CMFormatDescriptionGetMediaSubType)
    }

    static func pixel(_ image: CGImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
        var data = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: -x, y: -y, width: image.width, height: image.height))
        return (data[0], data[1], data[2])
    }
}

/// Convert on the shelf: when it's offered, how it opens and pages, and what puts the shelf back.
@MainActor
struct ConvertModelTests {
    init() { Prefs.registerDefaults() }

    private let photo = URL(fileURLWithPath: "/tmp/IMG_2063.HEIC")

    @Test func offeredOnlyWhileFilesAreDragged() {
        let convert = ConvertModel()
        #expect(convert.shelfState(dragging: true) == .hidden, "a drag of text or a link isn't offered Convert")
        convert.dragCarriesFiles = true
        #expect(convert.shelfState(dragging: true) == .offered)
        #expect(convert.shelfState(dragging: false) == .hidden)
    }

    @Test func opensFourAtATimeAndPagesRoundToTheStart() {
        let convert = ConvertModel()
        #expect(convert.open(with: [photo]))
        #expect(convert.shownTargets.count == 4)
        #expect(convert.shelfState(dragging: true) == .open(places: 5), "four formats and More")
        var seen = Set(convert.shownTargets)
        while !convert.isLastPage {
            convert.nextPage()
            seen.formUnion(convert.shownTargets)
        }
        #expect(seen == Set(convert.targets))
        convert.nextPage()
        #expect(convert.page == 0)
    }

    @Test func nothingToOfferDoesntOpen() {
        let convert = ConvertModel()
        #expect(!convert.open(with: [URL(fileURLWithPath: "/tmp/Archive.zip")]))
        #expect(!convert.isOpen)
    }

    @Test func aDragEndingWithoutADropPutsTheShelfBack() {
        let convert = ConvertModel()
        convert.open(with: [photo])
        convert.dragEnded()
        #expect(!convert.isOpen)
        // Let go on Convert: it stays open for a click.
        convert.open(with: [photo], awaitingClick: true)
        convert.dragEnded()
        #expect(convert.isOpen)
        convert.close()
        #expect(!convert.isOpen && !convert.awaitingClick)
    }

    @Test func theShelfMakesRoomForConvert() {
        let plain = ShelfMetrics.size(items: 3, dragging: true)
        let offered = ShelfMetrics.size(items: 3, dragging: true, convert: .offered)
        #expect(offered.width == plain.width + ShelfMetrics.tile)
        let open = ShelfMetrics.size(items: 3, dragging: true, convert: .open(places: 5))
        #expect(open.width <= ShelfMetrics.maxWidth)
        #expect(open.width == ShelfMetrics.inset * 2 + 5 * ShelfMetrics.tile + ShelfMetrics.separator + 2 * ShelfMetrics.tile)
    }
}

/// More Formats: only the exact pack Nook expects is unpacked, and it comes out again cleanly.
@MainActor
struct FormatPackTests {
    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("pack-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    /// A pack-shaped zip whose ffmpeg is a tiny script.
    private func zip() throws -> URL {
        let staging = folder.appendingPathComponent("NookFormats", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let tool = staging.appendingPathComponent("ffmpeg")
        try "#!/bin/sh\necho ffmpeg\n".write(to: tool, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        let zip = folder.appendingPathComponent("NookFormats-test.zip")
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-c", "-k", "--keepParent", staging.path, zip.path]
        try ditto.run()
        ditto.waitUntilExit()
        try FileManager.default.removeItem(at: staging)
        return zip
    }

    @Test func aDownloadThatIsntTheExpectedOneIsThrownAway() async throws {
        let pack = FormatPack(folder: folder.appendingPathComponent("Formats"), source: try zip())
        #expect(await pack.install(expecting: String(repeating: "0", count: 64)) == false)
        #expect(!pack.isInstalled)
        #expect(!FileManager.default.fileExists(atPath: pack.executable.path))
        if case .failed = pack.state {} else { Issue.record("should say it failed") }
    }

    @Test func theExpectedDownloadInstallsAndRemoves() async throws {
        let zip = try zip()
        let pack = FormatPack(folder: folder.appendingPathComponent("Formats"), source: zip)
        #expect(await pack.install(expecting: try FormatPack.digest(of: zip)))
        #expect(pack.isInstalled)
        #expect(FileManager.default.isExecutableFile(atPath: pack.executable.path))
        pack.remove()
        #expect(!pack.isInstalled)
        #expect(!FileManager.default.fileExists(atPath: pack.folder.path))
    }
}

/// Conversions through a built pack (scripts/formats-pack.sh); skipped when it hasn't been built.
@MainActor
struct PackConversionTests {
    let folder: URL
    let ffmpeg = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("build/formats/NookFormats/ffmpeg")

    init() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("pack-convert-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private var built: Bool { FileManager.default.isExecutableFile(atPath: ffmpeg.path) }

    private func run(_ urls: [URL], to target: ConvertTarget) async throws -> [URL] {
        var options = ConvertOptions()
        options.ffmpeg = ffmpeg
        return try await ConvertEngine.run(urls, to: target, options: options, progress: { _ in })
    }

    @Test func soundBecomesMP3AndOpus() async throws {
        guard built else { return }
        let wav = try Fixtures.wav(in: folder, name: "Tone.wav")
        let mp3 = try await run([wav], to: .mp3)
        let seconds = try await AVURLAsset(url: mp3[0]).load(.duration).seconds
        #expect(abs(seconds - 1) < 0.15, "MP3 \(seconds) s")
        let opus = try await run([wav], to: .opus)
        #expect((try FileManager.default.attributesOfItem(atPath: opus[0].path)[.size] as? Int ?? 0) > 1000)
    }

    @Test func aPictureBecomesWebP() async throws {
        guard built else { return }
        let png = try Fixtures.png(in: folder, name: "Shot")
        let webp = try await run([png], to: .webp)
        let file = try #require(CGImageSourceCreateWithURL(webp[0] as CFURL, nil))
        #expect((CGImageSourceGetType(file) as String?) == "org.webmproject.webp")
    }

    @Test func aVideoBecomesWebMAndMKVAndMKVComesBack() async throws {
        guard built else { return }
        let movie = try await Fixtures.movie(in: folder)
        let webm = try await run([movie], to: .webm)
        #expect((try FileManager.default.attributesOfItem(atPath: webm[0].path)[.size] as? Int ?? 0) > 1000)
        let mkv = try await run([movie], to: .mkv)
        // macOS can't open MKV, so this one goes through ffmpeg too, onto the Mac's own H.264 encoder.
        #expect(!ConvertCatalog.opensNatively(mkv[0]))
        #expect(ConvertCatalog.targets(for: [mkv[0]], withPack: false).isEmpty, "nothing without More Formats")
        let back = try await run([mkv[0]], to: .mp4)
        #expect(try await Fixtures.codec(back[0]) == kCMVideoCodecType_H264)
        let seconds = try await AVURLAsset(url: back[0]).load(.duration).seconds
        #expect(abs(seconds - 1) < 0.2, "MP4 from MKV \(seconds) s")
    }
}
