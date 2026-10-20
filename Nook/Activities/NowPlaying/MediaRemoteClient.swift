import Foundation

/// One line of the adapter's stream, decoded off the main thread.
nonisolated struct NowPlayingUpdate: Sendable {
    enum Value: Sendable {
        case string(String)
        case number(Double)
        case bool(Bool)
        case null
    }

    /// A full snapshot replaces all state; a diff only touches the keys it carries.
    var isDiff: Bool
    var values: [String: Value]
    /// Decoded artwork bytes when the line carried `artworkData`.
    var artwork: Data?
}

/// MRCommand IDs understood by the adapter's `send` function.
enum MediaCommand: Int {
    case play = 0
    case pause = 1
    case togglePlayPause = 2
    case nextTrack = 4
    case previousTrack = 5
}

/// Talks to MediaRemote through mediaremote-adapter (BSD-3, Vendor/MediaRemoteAdapter).
/// Since macOS 15.4 only Apple-entitled processes can read now-playing state; the adapter
/// loads its framework into /usr/bin/perl, which is entitled, and streams JSON lines.
final class MediaRemoteClient {
    var onUpdate: ((NowPlayingUpdate) -> Void)?

    private var process: Process?
    private var readTask: Task<Void, Never>?
    private var stopped = false
    private var restartDelay: Duration = .seconds(1)
    private var launchedAt = Date()

    private var scriptPath: String? {
        Bundle.main.url(forResource: "mediaremote-adapter", withExtension: "pl")?.path
    }

    private var frameworkPath: String? {
        Bundle.main.privateFrameworksURL?.appendingPathComponent("MediaRemoteAdapter.framework").path
    }

    func start() {
        stopped = false
        Self.endOrphans(scriptPath: scriptPath)
        launchStream()
    }

    func stop() {
        stopped = true
        readTask?.cancel()
        process?.terminate()
        process = nil
    }

    func send(_ command: MediaCommand) {
        runOnce(["send", String(command.rawValue)])
    }

    func seek(to seconds: Double) {
        runOnce(["seek", String(Int((seconds * 1_000_000).rounded()))])
    }

    func setShuffle(_ on: Bool) {
        runOnce(["shuffle", on ? "3" : "1"])
    }

    /// 1 off, 2 one, 3 all.
    func setRepeat(_ mode: Int) {
        runOnce(["repeat", String(mode)])
    }

    // MARK: Process

    private func launchStream() {
        guard !stopped, let scriptPath, let frameworkPath else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [scriptPath, frameworkPath, "stream", "--micros", "--debounce=40"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in self?.streamEnded() }
        }
        do {
            try process.run()
        } catch {
            streamEnded()
            return
        }
        self.process = process
        launchedAt = Date()
        let handle = pipe.fileHandleForReading
        readTask = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                for try await line in handle.bytes.lines {
                    guard let update = Self.decode(line) else { continue }
                    await MainActor.run { self?.receive(update) }
                }
            } catch {}
        }
    }

    private func receive(_ update: NowPlayingUpdate) {
        onUpdate?(update)
    }

    private func streamEnded() {
        process = nil
        guard !stopped else { return }
        // Only a stream that stayed up a while earns a fast restart.
        if Date().timeIntervalSince(launchedAt) > 10 { restartDelay = .seconds(1) }
        let delay = restartDelay
        restartDelay = min(restartDelay * 2, .seconds(30))
        Task { [weak self] in
            try? await Task.sleep(for: delay)
            self?.launchStream()
        }
    }

    private func runOnce(_ arguments: [String]) {
        guard let scriptPath, let frameworkPath else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [scriptPath, frameworkPath] + arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    /// A killed or crashed Nook leaves its perl stream running until its next write fails.
    /// Clean up any of ours that launchd has adopted before starting a new one.
    private static func endOrphans(scriptPath: String?) {
        guard let scriptPath else { return }
        let ps = Process()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-axo", "pid=,ppid=,command="]
        let pipe = Pipe()
        ps.standardOutput = pipe
        guard (try? ps.run()) != nil else { return }
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        ps.waitUntilExit()
        for line in output.split(separator: "\n") where line.contains(scriptPath) {
            let fields = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard fields.count == 3, let pid = Int32(fields[0]), fields[1] == "1" else { continue }
            kill(pid, SIGTERM)
        }
    }

    // MARK: Decoding

    nonisolated private static func decode(_ line: String) -> NowPlayingUpdate? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["type"] as? String == "data",
              let payload = object["payload"] as? [String: Any]
        else { return nil }
        var values: [String: NowPlayingUpdate.Value] = [:]
        var artwork: Data?
        for (key, raw) in payload {
            if key == "artworkData" {
                if let string = raw as? String { artwork = Data(base64Encoded: string) }
                values[key] = raw is NSNull ? .null : .bool(true)
                continue
            }
            switch raw {
            case is NSNull: values[key] = .null
            case let number as NSNumber where CFGetTypeID(number) == CFBooleanGetTypeID():
                values[key] = .bool(number.boolValue)
            case let number as NSNumber: values[key] = .number(number.doubleValue)
            case let string as String: values[key] = .string(string)
            default: continue
            }
        }
        return NowPlayingUpdate(isDiff: object["diff"] as? Bool ?? false, values: values, artwork: artwork)
    }
}
