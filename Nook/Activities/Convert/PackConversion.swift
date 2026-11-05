import AVFoundation
import Foundation

/// Conversions macOS can't do itself, through More Formats' `ffmpeg`: MP3, WebP, WebM, MKV and Opus, and
/// anything from files AVFoundation can't open (WebM, MKV, Ogg…). Video and AAC still use the Mac's own
/// encoders (VideoToolbox, AudioToolbox) through it.
nonisolated enum PackConversion {
    static func run(_ url: URL, source: ConvertSource, to target: ConvertTarget, ffmpeg: URL, options: ConvertOptions,
                    into dest: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        let seconds = await duration(of: url, ffmpeg: ffmpeg)
        let process = Process()
        process.executableURL = ffmpeg
        process.arguments = ["-hide_banner", "-nostdin", "-y", "-i", url.path] + arguments(for: target, source: source, options: options)
            + ["-progress", "pipe:1", "-nostats", dest.path]
        let output = Pipe(), errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        let finished = AsyncStream<Int32> { continuation in
            process.terminationHandler = { continuation.yield($0.terminationStatus); continuation.finish() }
        }
        try process.run()
        // What went wrong, if it does: ffmpeg's last words.
        let complaint = Task { () -> String in
            var last = ""
            for try await line in errors.fileHandleForReading.bytes.lines where !line.isEmpty { last = line }
            return last
        }
        try await withTaskCancellationHandler {
            for try await line in output.fileHandleForReading.bytes.lines {
                guard line.hasPrefix("out_time_us="), let micro = Double(line.dropFirst(12)), let seconds, seconds > 0 else { continue }
                progress(min(1, max(0, micro / 1_000_000 / seconds)))
            }
        } onCancel: {
            process.terminate()
        }
        var status: Int32 = -1
        for await code in finished { status = code }
        try Task.checkCancellation()
        guard status == 0 else {
            try? FileManager.default.removeItem(at: dest)
            let why = (try? await complaint.value) ?? ""
            throw ConvertError.failed("Couldn't convert \(url.lastPathComponent) to \(target.name)." + (why.isEmpty ? "" : " \(why)"))
        }
        complaint.cancel()
    }

    static func arguments(for target: ConvertTarget, source: ConvertSource, options: ConvertOptions) -> [String] {
        let kbps = options.audioBitRate / 1000
        switch target {
        case .mp3: return ["-vn", "-c:a", "libmp3lame", "-b:a", "\(max(128, min(kbps, 320)))k"]
        case .opus: return ["-vn", "-c:a", "libopus", "-b:a", "128k"]
        case .webm: return ["-c:v", "libvpx-vp9", "-crf", "32", "-b:v", "0", "-row-mt", "1", "-deadline", "good", "-cpu-used", "4",
                            "-c:a", "libopus", "-b:a", "128k"]
        // MKV holds anything, so the streams go across as they are.
        case .mkv: return ["-map", "0:v?", "-map", "0:a?", "-c", "copy"]
        case .webp:
            if source == .animatedGIF { return ["-c:v", "libwebp_anim", "-loop", "0", "-quality", "80"] }
            return ["-frames:v", "1", "-c:v", "libwebp", "-quality", "\(Int(options.photoQuality * 100))"]
        case .mp4: return ["-c:v", "h264_videotoolbox", "-b:v", "8M", "-c:a", "aac_at", "-b:a", "192k", "-movflags", "+faststart"]
        case .mp4HEVC: return ["-c:v", "hevc_videotoolbox", "-tag:v", "hvc1", "-b:v", "5M", "-c:a", "aac_at", "-b:a", "192k", "-movflags", "+faststart"]
        case .mov: return ["-c:v", "h264_videotoolbox", "-b:v", "8M", "-c:a", "aac_at", "-b:a", "192k"]
        case .prores: return ["-c:v", "prores_ks", "-profile:v", "2", "-c:a", "pcm_s16le"]
        case .animatedGIF:
            return ["-vf", "fps=12,scale='min(640,iw)':-2:flags=lanczos,split[a][b];[a]palettegen[p];[b][p]paletteuse", "-loop", "0"]
        case .m4a: return ["-vn", "-c:a", "aac_at", "-b:a", "\(kbps)k"]
        case .alac: return ["-vn", "-c:a", "alac"]
        case .wav: return ["-vn", "-c:a", "pcm_s16le"]
        case .aiff: return ["-vn", "-c:a", "pcm_s16be"]
        case .flac: return ["-vn", "-c:a", "flac"]
        default: return []
        }
    }

    /// How long the file plays, for the progress ring: from AVFoundation when it can open it, otherwise
    /// from what ffmpeg says about it.
    static func duration(of url: URL, ffmpeg: URL) async -> Double? {
        if ConvertCatalog.opensNatively(url), let seconds = try? await AVURLAsset(url: url).load(.duration).seconds, seconds > 0 {
            return seconds
        }
        let probe = Process()
        probe.executableURL = ffmpeg
        probe.arguments = ["-hide_banner", "-nostdin", "-i", url.path]
        let errors = Pipe()
        probe.standardError = errors
        probe.standardOutput = FileHandle.nullDevice
        guard (try? probe.run()) != nil else { return nil }
        let text = String(decoding: (try? errors.fileHandleForReading.readToEnd()) ?? Data(), as: UTF8.self)
        probe.waitUntilExit()
        guard let match = text.firstMatch(of: /Duration: (\d+):(\d+):(\d+(?:\.\d+)?)/),
              let hours = Double(match.1), let minutes = Double(match.2), let secs = Double(match.3) else { return nil }
        return hours * 3600 + minutes * 60 + secs
    }
}
