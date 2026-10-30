import Foundation

/// Something a keyboard shortcut can do from anywhere.
enum ShortcutAction: String, CaseIterable, Identifiable {
    case toggleIsland, playPause, nextTrack, previousTrack, timer, shelf, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .toggleIsland: "Open or close the island"
        case .playPause: "Play or pause"
        case .nextTrack: "Next track"
        case .previousTrack: "Previous track"
        case .timer: "Start or pause a timer"
        case .shelf: "Open the shelf"
        case .settings: "Open Settings"
        }
    }

    /// The key it's stored under: "keyCode,modifiers,label", or empty for none.
    var key: String { "shortcut.\(rawValue)" }
}

/// A key and its modifiers as the system hotkey API takes them, with the label Settings shows.
struct Shortcut: Equatable {
    var keyCode: UInt32
    /// Carbon modifier flags.
    var modifiers: UInt32
    /// "⌃⌥N".
    var label: String

    init(keyCode: UInt32, modifiers: UInt32, label: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.label = label
    }

    init?(stored: String) {
        let parts = stored.split(separator: ",", maxSplits: 2).map(String.init)
        guard parts.count == 3, let code = UInt32(parts[0]), let mods = UInt32(parts[1]) else { return nil }
        self.init(keyCode: code, modifiers: mods, label: parts[2])
    }

    var stored: String { "\(keyCode),\(modifiers),\(label)" }

    static func saved(_ action: ShortcutAction) -> Shortcut? { Shortcut(stored: Prefs.string(action.key)) }
}

extension Prefs {
    /// None set: a shortcut that collides with another app's is worse than none.
    static var shortcutsArea: PrefsArea {
        PrefsArea(id: "shortcuts", defaults: Dictionary(uniqueKeysWithValues: ShortcutAction.allCases.map { ($0.key, "") }))
    }
}
