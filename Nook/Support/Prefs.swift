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
    /// The Settings window's look: SettingsAppearance raw value. The island is always black.
    static let settingsAppearance = "settingsAppearance"

    /// The open island's home: HomeLayout raw value, modules per page side by side (2 or 3),
    /// the modules' order and the ones turned off (comma lists of HomeModule), HomeSize raw value.
    static let homeLayout = "homeLayout"
    static let homeColumns = "homeColumns"
    static let homeOrder = "homeOrder"
    static let homeHidden = "homeHidden"
    static let homeSize = "homeSize"

    static let nowPlaying = "nowPlaying"
    static let peekOnTrackChange = "peekOnTrackChange"
    static let peekOnHover = "peekOnHover"
    static let showWaveform = "showWaveform"
    static let tintWaveform = "tintWaveform"
    /// The Music module's favourite star (shown only for players that take favourites) and output button.
    static let musicFavorite = "musicFavorite"
    static let musicOutput = "musicOutput"

    static let volumeHUD = "volumeHUD"
    static let brightnessHUD = "brightnessHUD"
    static let hudStyle = "hudStyle"                    // HUDStyle raw value

    static let timerSound = "timerSound"                // a system sound name, or "" for none

    static let battery = "battery"
    static let lowBatteryThreshold = "lowBatteryThreshold"
    /// The Batteries module lists this Mac's own battery first.
    static let batteriesIncludeMac = "batteriesIncludeMac"

    static let connectivity = "connectivity"

    static let calendar = "calendar"
    static let calendarLeadMinutes = "calendarLeadMinutes"
    /// The Calendar module's month: WeekStart raw value, a dot under days with events, weekends in grey.
    static let calendarWeekStart = "calendarWeekStart"
    static let calendarDots = "calendarDots"
    static let calendarDimWeekends = "calendarDimWeekends"

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
            settingsAppearance: SettingsAppearance.light.rawValue,
            // Side by side, two to a page: Music and Calendar together.
            homeLayout: HomeLayout.sideBySide.rawValue,
            homeColumns: 2,
            homeOrder: HomeOrder.string(HomeModule.allCases),
            homeHidden: "",
            homeSize: HomeSize.medium.rawValue,
            nowPlaying: true,
            peekOnTrackChange: true,
            peekOnHover: true,
            showWaveform: true,
            tintWaveform: true,
            musicFavorite: true,
            musicOutput: true,
            volumeHUD: false,
            brightnessHUD: false,
            hudStyle: HUDStyle.ledge.rawValue,
            timerSound: "Glass",
            battery: true,
            lowBatteryThreshold: 20,
            batteriesIncludeMac: true,
            connectivity: true,
            // On: the expanded island shows the week. Access is asked for from the island, not at launch.
            calendar: true,
            calendarLeadMinutes: 10,
            calendarWeekStart: WeekStart.system.rawValue,
            // Off, as Apple's Calendar widget has it; a choice for seeing busy days at a glance.
            calendarDots: false,
            calendarDimWeekends: true,
            lockActivity: true,
            shelf: true,
        ])
    }

    static func bool(_ key: String) -> Bool { UserDefaults.standard.bool(forKey: key) }
    static func int(_ key: String) -> Int { UserDefaults.standard.integer(forKey: key) }
}

/// The Settings window's look: the system's, or always light or dark.
enum SettingsAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    static var saved: SettingsAppearance {
        UserDefaults.standard.string(forKey: Prefs.settingsAppearance).flatMap(SettingsAppearance.init) ?? .light
    }
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

/// The first column of the Calendar module's month.
enum WeekStart: String, CaseIterable, Identifiable {
    case system, sunday, monday

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .sunday: "Sunday"
        case .monday: "Monday"
        }
    }

    /// Calendar's numbering: 1 is Sunday.
    var firstWeekday: Int {
        switch self {
        case .system: Calendar.current.firstWeekday
        case .sunday: 1
        case .monday: 2
        }
    }

    static var current: WeekStart { WeekStart(rawValue: UserDefaults.standard.string(forKey: Prefs.calendarWeekStart) ?? "") ?? .system }
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
