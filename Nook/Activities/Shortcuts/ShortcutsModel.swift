import Foundation
import Observation

/// The shortcuts the Shortcuts module offers, read and run through macOS's own `shortcuts` tool. macOS
/// keeps each shortcut's colour and icon to itself, so the module colours them in order.
@Observable
final class ShortcutsModel {
    private(set) var names: [String] = []
    /// Running now, and finished a moment ago (for the tick).
    private(set) var running: Set<String> = []
    private(set) var finished: Set<String> = []

    @ObservationIgnored private var reading = false

    /// Reads the list again; cheap enough to do whenever the island opens.
    func refresh() {
        guard !reading else { return }
        reading = true
        Task {
            let output = await Self.shortcuts(["list"])
            reading = false
            let found = output?.split(separator: "\n").map(String.init).filter { !$0.isEmpty } ?? names
            if found != names { names = found }
        }
    }

    func run(_ name: String) {
        guard !running.contains(name) else { return }
        running.insert(name)
        Task {
            _ = await Self.shortcuts(["run", name])
            running.remove(name)
            finished.insert(name)
            try? await Task.sleep(for: .seconds(1.2))
            finished.remove(name)
        }
    }

    nonisolated private static func shortcuts(_ arguments: [String]) async -> String? {
        await Task.detached(priority: .userInitiated) { () -> String? in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return process.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil
        }.value
    }

    #if DEBUG
    func debugPreview() {
        names = ["Morning Routine", "Focus Mode", "Send Last Photo", "Log Water"]
    }
    #endif
}
