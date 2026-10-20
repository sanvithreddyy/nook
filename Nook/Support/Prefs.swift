import Foundation

/// UserDefaults keys. Views read them with `@AppStorage(Prefs.x)`, services with `Prefs.bool(.x)`.
enum Prefs {
    static let hideMenuBarIcon = "hideMenuBarIcon"
    static let display = "display"                      // DisplayChoice raw value
    static let hideInFullscreen = "hideInFullscreen"
    static let enableHaptics = "enableHaptics"
    static let expandOnHover = "expandOnHover"
    static let swipeGestures = "swipeGestures"

    static let nowPlaying = "nowPlaying"
    static let peekOnTrackChange = "peekOnTrackChange"
    static let peekOnHover = "peekOnHover"
    static let showWaveform = "showWaveform"
    static let tintWaveform = "tintWaveform"

    static let volumeHUD = "volumeHUD"
    static let brightnessHUD = "brightnessHUD"

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
            expandOnHover: false,
            swipeGestures: true,
            nowPlaying: true,
            peekOnTrackChange: true,
            peekOnHover: true,
            showWaveform: true,
            tintWaveform: true,
            volumeHUD: false,
            brightnessHUD: false,
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
