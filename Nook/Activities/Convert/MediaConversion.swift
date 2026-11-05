import AudioToolbox
import AVFoundation
import CoreMedia
import ImageIO
import UniformTypeIdentifiers

/// Video and sound, through AVFoundation and Audio Toolbox.
nonisolated enum MediaConversion {
    // MARK: Video

    /// A video into MP4 or MOV. It's only re-encoded when it has to be: MOV takes any video as it is,
    /// MP4 takes H.264 as it is (so "MP4" always plays everywhere), and the smaller MP4 is HEVC.
    static func export(_ url: URL, to target: ConvertTarget, into dest: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        let asset = AVURLAsset(url: url)
        let fileType: AVFileType = target == .mov || target == .prores ? .mov : .mp4
        let preset = try await preset(for: target, asset: asset, fileType: fileType)
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw ConvertError.failed("\(url.lastPathComponent) can't become \(target.name).")
        }
        // The session reports its state while it exports; that's what its state stream is for.
        nonisolated(unsafe) let watched = session
        let watcher = Task {
            for await state in watched.states(updateInterval: 0.2) {
                if case .exporting(let share) = state { progress(share.fractionCompleted) }
            }
        }
        defer { watcher.cancel() }
        do {
            try await session.export(to: dest, as: fileType)
        } catch {
            try? FileManager.default.removeItem(at: dest)
            if error is CancellationError { throw error }
            throw ConvertError.failed("Couldn't convert \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    private static func preset(for target: ConvertTarget, asset: AVURLAsset, fileType: AVFileType) async throws -> String {
        switch target {
        case .prores: return AVAssetExportPresetAppleProRes422LPCM
        case .mp4HEVC: return AVAssetExportPresetHEVCHighestQuality
        case .mov:
            let asIs = await AVAssetExportSession.compatibility(ofExportPreset: AVAssetExportPresetPassthrough, with: asset, outputFileType: .mov)
            return asIs ? AVAssetExportPresetPassthrough : AVAssetExportPresetHighestQuality
        default:
            guard try await isH264(asset) else { return AVAssetExportPresetHighestQuality }
            let asIs = await AVAssetExportSession.compatibility(ofExportPreset: AVAssetExportPresetPassthrough, with: asset, outputFileType: .mp4)
            return asIs ? AVAssetExportPresetPassthrough : AVAssetExportPresetHighestQuality
        }
    }

    private static func isH264(_ asset: AVURLAsset) async throws -> Bool {
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard !tracks.isEmpty else { return false }
        for track in tracks {
            for description in try await track.load(.formatDescriptions)
            where CMFormatDescriptionGetMediaSubType(description) != kCMVideoCodecType_H264 { return false }
        }
        return true
    }

    /// A video as a looping GIF: up to 15 frames a second and 640 across, and never more than 900 frames,
    /// so a long video gets fewer frames a second rather than a huge file.
    static func videoToGIF(_ url: URL, to dest: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        guard duration > 0, duration.isFinite else { throw ConvertError.unreadable(url.lastPathComponent) }
        let fps = min(15, 900 / duration)
        let count = max(1, Int(duration * fps))
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 640)
        let tolerance = CMTime(seconds: 0.5 / fps, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance
        guard let destination = CGImageDestinationCreateWithURL(dest as CFURL, UTType.gif.identifier as CFString, count, nil) else {
            throw ConvertError.failed("Couldn't write \(dest.lastPathComponent).")
        }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let frame = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1 / fps]] as CFDictionary
        let times = (0..<count).map { CMTime(seconds: Double($0) / fps, preferredTimescale: 600) }
        var last: CGImage?
        var done = 0
        for await result in generator.images(for: times) {
            try Task.checkCancellation()
            // A frame that can't be read repeats the one before, so the GIF keeps its timing.
            if let image = (try? result.image) ?? last {
                CGImageDestinationAddImage(destination, image, frame)
                last = image
            }
            done += 1
            progress(Double(done) / Double(count))
        }
        guard last != nil, CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: dest)
            throw ConvertError.failed("Couldn't make a GIF from \(url.lastPathComponent).")
        }
    }

    /// An animated GIF as an H.264 video, each frame held as long as the GIF holds it.
    static func gifToVideo(_ url: URL, fileType: AVFileType, to dest: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        guard let file = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(file) > 0,
              let first = CGImageSourceCreateImageAtIndex(file, 0, nil)
        else { throw ConvertError.unreadable(url.lastPathComponent) }
        let count = CGImageSourceGetCount(file)
        // H.264 wants even sides.
        let width = max(2, first.width / 2 * 2), height = max(2, first.height / 2 * 2)
        let writer = try AVAssetWriter(outputURL: dest, fileType: fileType)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(input)
        guard writer.startWriting() else { throw ConvertError.failed("Couldn't write \(dest.lastPathComponent).") }
        writer.startSession(atSourceTime: .zero)
        var time = CMTime.zero
        for index in 0..<count {
            try Task.checkCancellation()
            guard let image = CGImageSourceCreateImageAtIndex(file, index, nil) else { continue }
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            if let buffer = pixelBuffer(image, pool: adaptor.pixelBufferPool, width: width, height: height) {
                adaptor.append(buffer, withPresentationTime: time)
            }
            time = time + CMTime(seconds: delay(file, index), preferredTimescale: 600)
            progress(Double(index + 1) / Double(count))
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: time)
        await writer.finishWriting()
        guard writer.status == .completed else {
            try? FileManager.default.removeItem(at: dest)
            throw ConvertError.failed("Couldn't make a video from \(url.lastPathComponent).")
        }
    }

    /// How long a GIF holds a frame. Very short delays mean "as fast as you can", which browsers play
    /// at a tenth of a second.
    private static func delay(_ file: CGImageSource, _ index: Int) -> Double {
        let properties = CGImageSourceCopyPropertiesAtIndex(file, index, nil) as? [CFString: Any]
        let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        let value = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double) ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
        return value < 0.011 ? 0.1 : value
    }

    /// A frame on black, since video has no transparency.
    private static func pixelBuffer(_ image: CGImage, pool: CVPixelBufferPool?, width: Int, height: Int) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        if let pool { CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) }
        guard let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)
        else { return nil }
        context.setFillColor(.black)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }

    // MARK: Sound

    /// A file's sound (an audio file, or a video's soundtrack) into another audio format, read as
    /// floating-point samples and written by Audio Toolbox, which does the encoding.
    static func audio(_ url: URL, to target: ConvertTarget, bitRate: Int, into dest: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { throw ConvertError.noAudio(url.lastPathComponent) }
        let duration = try await asset.load(.duration).seconds
        guard let description = try await track.load(.formatDescriptions).first,
              let source = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee
        else { throw ConvertError.unreadable(url.lastPathComponent) }
        let rate = source.mSampleRate, channels = max(1, source.mChannelsPerFrame)
        // Lossless sources say their depth in their flags; plain PCM in its bits.
        let deep = source.mBitsPerChannel > 16
            || [kAppleLosslessFormatFlag_20BitSourceData, kAppleLosslessFormatFlag_24BitSourceData, kAppleLosslessFormatFlag_32BitSourceData]
                .contains(source.mFormatFlags) && [kAudioFormatAppleLossless, kAudioFormatFLAC].contains(source.mFormatID)

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false, AVLinearPCMIsBigEndianKey: false,
            AVSampleRateKey: rate, AVNumberOfChannelsKey: channels,
        ])
        reader.add(output)
        guard reader.startReading() else { throw ConvertError.unreadable(url.lastPathComponent) }

        var fileFormat = format(for: target, rate: rate, channels: channels, deep: deep)
        var file: ExtAudioFileRef?
        guard ExtAudioFileCreateWithURL(dest as CFURL, fileFormat.type, &fileFormat.description, nil, AudioFileFlags.eraseFile.rawValue, &file) == noErr,
              let file
        else { throw ConvertError.failed("Couldn't write \(dest.lastPathComponent).") }
        var finished = false
        defer {
            ExtAudioFileDispose(file)
            if !finished { try? FileManager.default.removeItem(at: dest) }
        }
        var client = AudioStreamBasicDescription(mSampleRate: rate, mFormatID: kAudioFormatLinearPCM,
                                                 mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
                                                 mBytesPerPacket: 4 * channels, mFramesPerPacket: 1, mBytesPerFrame: 4 * channels,
                                                 mChannelsPerFrame: channels, mBitsPerChannel: 32, mReserved: 0)
        guard ExtAudioFileSetProperty(file, kExtAudioFileProperty_ClientDataFormat, UInt32(MemoryLayout.size(ofValue: client)), &client) == noErr
        else { throw ConvertError.failed("\(target.name) can't hold \(url.lastPathComponent)'s sound.") }
        if target == .m4a { setBitRate(bitRate, on: file) }

        while let buffer = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            var blockBuffer: CMBlockBuffer?
            var list = AudioBufferList()
            guard CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
                buffer, bufferListSizeNeededOut: nil, bufferListOut: &list, bufferListSize: MemoryLayout<AudioBufferList>.size,
                blockBufferAllocator: nil, blockBufferMemoryAllocator: nil,
                flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment, blockBufferOut: &blockBuffer) == noErr
            else { continue }
            let frames = UInt32(CMSampleBufferGetNumSamples(buffer))
            guard ExtAudioFileWrite(file, frames, &list) == noErr else { throw ConvertError.failed("Couldn't write \(dest.lastPathComponent).") }
            if duration > 0 { progress(min(1, CMSampleBufferGetPresentationTimeStamp(buffer).seconds / duration)) }
        }
        guard reader.status == .completed else { throw ConvertError.unreadable(url.lastPathComponent) }
        finished = true
    }

    /// The file type and encoding for a sound target. AAC tops out at 48 kHz, so faster sources are
    /// resampled; lossless formats keep 24-bit sources at 24 bits.
    private static func format(for target: ConvertTarget, rate: Double, channels: UInt32, deep: Bool) -> (type: AudioFileTypeID, description: AudioStreamBasicDescription) {
        let bits: UInt32 = deep ? 24 : 16
        let losslessFlags = deep ? kAppleLosslessFormatFlag_24BitSourceData : kAppleLosslessFormatFlag_16BitSourceData
        var description = AudioStreamBasicDescription()
        description.mChannelsPerFrame = channels
        description.mSampleRate = rate
        switch target {
        case .m4a:
            description.mFormatID = kAudioFormatMPEG4AAC
            description.mSampleRate = min(rate, 48000)
            return (kAudioFileM4AType, description)
        case .alac:
            description.mFormatID = kAudioFormatAppleLossless
            description.mFormatFlags = losslessFlags
            description.mFramesPerPacket = 4096
            return (kAudioFileM4AType, description)
        case .flac:
            description.mFormatID = kAudioFormatFLAC
            description.mFormatFlags = losslessFlags
            description.mFramesPerPacket = 4096
            return (kAudioFileFLACType, description)
        case .aiff:
            pcm(&description, bits: bits, channels: channels, bigEndian: true)
            return (kAudioFileAIFFType, description)
        default:
            pcm(&description, bits: bits, channels: channels, bigEndian: false)
            return (kAudioFileWAVEType, description)
        }
    }

    private static func pcm(_ description: inout AudioStreamBasicDescription, bits: UInt32, channels: UInt32, bigEndian: Bool) {
        description.mFormatID = kAudioFormatLinearPCM
        description.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked | (bigEndian ? kAudioFormatFlagIsBigEndian : 0)
        description.mBitsPerChannel = bits
        description.mFramesPerPacket = 1
        description.mBytesPerFrame = bits / 8 * channels
        description.mBytesPerPacket = description.mBytesPerFrame
    }

    /// Asks the AAC encoder for this bit rate, or the nearest below it that the sample rate and channels
    /// allow (mono at 22 kHz tops out far under 256 kbps, and a rate it can't do fails every write).
    private static func setBitRate(_ bitRate: Int, on file: ExtAudioFileRef) {
        var converter: AudioConverterRef?
        var size = UInt32(MemoryLayout<AudioConverterRef?>.size)
        guard ExtAudioFileGetProperty(file, kExtAudioFileProperty_AudioConverter, &size, &converter) == noErr, let converter else { return }
        var rangesSize: UInt32 = 0
        guard AudioConverterGetPropertyInfo(converter, kAudioConverterApplicableEncodeBitRates, &rangesSize, nil) == noErr, rangesSize > 0 else { return }
        var ranges = [AudioValueRange](repeating: AudioValueRange(), count: Int(rangesSize) / MemoryLayout<AudioValueRange>.size)
        guard AudioConverterGetProperty(converter, kAudioConverterApplicableEncodeBitRates, &rangesSize, &ranges) == noErr else { return }
        let allowed = ranges.flatMap { [$0.mMinimum, $0.mMaximum] }.filter { $0 > 0 }.sorted()
        guard let chosen = allowed.last(where: { $0 <= Double(bitRate) }) ?? allowed.first else { return }
        var value = UInt32(chosen)
        guard AudioConverterSetProperty(converter, kAudioConverterEncodeBitRate, UInt32(MemoryLayout<UInt32>.size), &value) == noErr else { return }
        var config: CFArray?
        ExtAudioFileSetProperty(file, kExtAudioFileProperty_ConverterConfig, UInt32(MemoryLayout<CFArray?>.size), &config)
    }
}
