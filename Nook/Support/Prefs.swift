import Foundation
import CoreGraphics

/// UserDefaults keys. Views read them with `@AppStorage(Prefs.x)`, services with `Prefs.bool(.x)`.
/// Each area keeps its keys and defaults in its own file (Support/Prefs/Prefs+Area.swift), listed in
/// `areas`; Settings uses the same list to reset a page, and to export and import everything.
enum Prefs {
    /// Every area's defaults. An area lists every key it owns here, so reset and export see it.
    static var areas: [PrefsArea] {
        [generalArea, homeArea, mediaArea, hudsArea, timerArea, batteryArea, connectivityArea, calendarArea, lockArea, shelfArea, shortcutsArea, advancedArea]
    }

    static func registerDefaults() {
        var all: [String: Any] = [:]
        for area in areas { all.merge(area.defaults) { first, _ in first } }
        UserDefaults.standard.register(defaults: all)
    }

    static func bool(_ key: String) -> Bool { UserDefaults.standard.bool(forKey: key) }
    static func int(_ key: String) -> Int { UserDefaults.standard.integer(forKey: key) }
    static func double(_ key: String) -> Double { UserDefaults.standard.double(forKey: key) }
    static func string(_ key: String) -> String { UserDefaults.standard.string(forKey: key) ?? "" }

    /// Puts an area back to how Nook ships.
    static func reset(_ area: PrefsArea) {
        for key in area.defaults.keys { UserDefaults.standard.removeObject(forKey: key) }
    }
}

/// One area's settings: a name for Settings, and every key it owns with its default.
struct PrefsArea {
    let id: String
    let defaults: [String: Any]
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
