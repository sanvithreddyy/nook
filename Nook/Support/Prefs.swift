import Foundation
import CoreGraphics

/// UserDefaults keys. Views read them with `@AppStorage(Prefs.x)`, services with `Prefs.bool(.x)`.
enum Prefs {
    static let hideMenuBarIcon = "hideMenuBarIcon"
    static let display = "display"                      // DisplayChoice raw value
    static let hideInFullscreen = "hideInFullscreen"
    static let enableHaptics = "enableHaptics"
    static let expandOnHover = "expandOnHover"
    static let swipeGestures = "swipeGestures"
    /// Apple's status colours (green charging, orange timer…), or white; low battery stays red.
    static let statusColors = "statusColors"
    /// A second activity (a timer, a meeting about to start) shows as its own drop beside the island.
    static let showCompanion = "showCompanion"

    static let nowPlaying = "nowPlaying"
    static let peekOnTrackChange = "peekOnTrackChange"
    static let peekOnHover = "peekOnHover"
    static let showWaveform = "showWaveform"
    static let tintWaveform = "tintWaveform"

    static let volumeHUD = "volumeHUD"
    static let brightnessHUD = "brightnessHUD"
    static let hudStyle = "hudStyle"                    // HUDStyle raw value

    static let timerSound = "timerSound"                // a system sound name, or "" for none

    static let battery = "battery"
    static let lowBatteryThreshold = "lowBatteryThreshold"

    static let connectivity = "connectivity"

    static let calendar = "calendar"
    static let calendarLeadMinutes = "calendarLeadMinutes"

    static let lockActivity = "lockActivity"

    static let shelf = "shelf"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            hideMenuBarIcon: false,
            display: DisplayChoice.builtIn.rawValue,
            // Off by default: detection of other apps' fullscreen spaces is heuristic.
            hideInFullscreen: false,
            enableHaptics: true,
            // On: pointing at the notch opens it.
            expandOnHover: true,
            swipeGestures: true,
            statusColors: true,
            showCompanion: true,
            nowPlaying: true,
            peekOnTrackChange: true,
            peekOnHover: true,
            showWaveform: true,
            tintWaveform: true,
            volumeHUD: false,
            brightnessHUD: false,
            hudStyle: HUDStyle.ledge.rawValue,
            timerSound: "Glass",
            battery: true,
            lowBatteryThreshold: 20,
            connectivity: true,
            // On: the expanded island shows the week. Access is asked for from the island, not at launch.
            calendar: true,
            calendarLeadMinutes: 10,
            lockActivity: true,
            shelf: true,
        ])
    }

    static func bool(_ key: String) -> Bool { UserDefaults.standard.bool(forKey: key) }
    static func int(_ key: String) -> Int { UserDefaults.standard.integer(forKey: key) }
}

/// How volume and brightness show under the notch.
enum HUDStyle: String, CaseIterable, Identifiable {
    /// Glyph and value beside the notch, a thin bar on a ledge below.
    case ledge
    /// A thick slider like Control Center's, the glyph inside it.
    case slider
    /// Sixteen segments, one per press, like the Mac's old volume overlay.
    case segments
    /// The island's own edge fills with the level.
    case outline

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ledge: "Ledge"
        case .slider: "Slider"
        case .segments: "Steps"
        case .outline: "Outline"
        }
    }

    /// How far the island drops below the notch.
    var below: CGFloat {
        switch self {
        case .ledge: 18
        case .slider: 42
        case .segments: 20
        case .outline: 16
        }
    }

    /// The slider carries the glyph itself; the others show it, and the value, beside the notch.
    var usesSides: Bool { self != .slider }

    static var current: HUDStyle { HUDStyle(rawValue: UserDefaults.standard.string(forKey: Prefs.hudStyle) ?? "") ?? .ledge }
}

enum DisplayChoice: String, CaseIterable, Identifiable {
    case builtIn, main
    var id: String { rawValue }
    var label: String {
        switch self {
        case .builtIn: "Built-in display"
        case .main: "Main display"
        }
    }
}
