import Foundation

extension Prefs {
    /// The open island's home: HomeLayout raw value, modules per page side by side (2 or 3),
    /// the modules' order and the ones turned off (comma lists of HomeModule), HomeSize raw value.
    static let homeLayout = "homeLayout"
    static let homeColumns = "homeColumns"
    static let homeOrder = "homeOrder"
    static let homeHidden = "homeHidden"
    static let homeSize = "homeSize"

    /// Module options, kept with the home so resetting Home resets them.
    /// Music: what the player's two side buttons do (MusicButton raw values), and whether the time
    /// right of the bar is the track's length instead of what's left.
    static let musicLeftButton = "musicLeftButton"
    static let musicRightButton = "musicRightButton"
    static let musicShowsTotal = "musicShowsTotal"
    /// Calendar: WeekStart raw value, a dot under days with events, weekends in grey.
    static let calendarWeekStart = "calendarWeekStart"
    static let calendarDots = "calendarDots"
    static let calendarDimWeekends = "calendarDimWeekends"
    /// Batteries: this Mac's own battery first.
    static let batteriesIncludeMac = "batteriesIncludeMac"

    static var homeArea: PrefsArea {
        PrefsArea(id: "home", defaults: [
            // Side by side, two to a page: Music and Calendar together.
            homeLayout: HomeLayout.sideBySide.rawValue,
            homeColumns: 2,
            homeOrder: HomeOrder.string(HomeModule.allCases),
            homeHidden: "",
            homeSize: HomeSize.medium.rawValue,
            musicLeftButton: MusicButton.favorite.rawValue,
            musicRightButton: MusicButton.output.rawValue,
            musicShowsTotal: false,
            calendarWeekStart: WeekStart.system.rawValue,
            // Off, as Apple's Calendar widget has it; a choice for seeing busy days at a glance.
            calendarDots: false,
            calendarDimWeekends: true,
            batteriesIncludeMac: true,
        ])
    }
}
