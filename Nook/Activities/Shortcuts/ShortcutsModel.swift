import Foundation
import Observation

/// The shortcuts the Shortcuts module offers, read and run through macOS's own `shortcuts` tool. macOS
/// keeps each shortcut's colour and icon to itself, so the module colours them in order.
/// Settings picks up to four of them; with none picked the module shows the first four.
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
            let found = await Self.list() ?? names
            reading = false
            if found != names { names = found }
        }
    }

    /// Every shortcut by name, as Shortcuts lists them; nil when the tool fails.
    nonisolated static func list() async -> [String]? {
        await shortcuts(["list"])?.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    /// The four the module shows: the picked ones that still exist, in their order, or the first four
    /// when none are picked (or none of the picked are left).
    static func shown(names: [String], picked: [String]) -> [String] {
        let kept = picked.filter(names.contains)
        return Array((kept.isEmpty ? names : kept).prefix(4))
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

    /// The picked names, saved as a JSON array (names can hold commas).
    static func picks(from json: String) -> [String] {
        (try? JSONDecoder().decode([String].self, from: Data(json.utf8))) ?? []
    }

    static func json(_ picks: [String]) -> String {
        picks.isEmpty ? "" : String(decoding: (try? JSONEncoder().encode(picks)) ?? Data(), as: UTF8.self)
    }

    #if DEBUG
    func debugPreview() {
        names = ["Morning Routine", "Focus Mode", "Send Last Photo", "Log Water"]
    }
    #endif
}
