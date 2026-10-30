import Foundation

extension Prefs {
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

    static var generalArea: PrefsArea {
        PrefsArea(id: "general", defaults: [
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
        ])
    }
}
