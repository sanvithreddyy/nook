import Foundation

extension Prefs {
    static let hideMenuBarIcon = "hideMenuBarIcon"
    static let display = "display"                      // DisplayChoice raw value
    /// The closed island's height: ClosedHeight raw value, and the points when it's Custom.
    static let closedHeight = "closedHeight"
    static let closedHeightCustom = "closedHeightCustom"
    /// The island on screens without a notch: NotchlessStyle raw value.
    static let notchlessStyle = "notchlessStyle"
    static let hideInFullscreen = "hideInFullscreen"
    /// Only a full-screen app that is what's playing hides the island (a video, say).
    static let fullscreenMediaOnly = "fullscreenMediaOnly"
    /// The page the island opens on: OpenTo raw value.
    static let openTo = "openTo"
    static let enableHaptics = "enableHaptics"
    /// How strongly: HapticStrength raw value.
    static let hapticStrength = "hapticStrength"
    static let expandOnHover = "expandOnHover"
    /// Seconds the pointer rests on the island before it opens or shows the track.
    static let hoverDelay = "hoverDelay"
    static let swipeGestures = "swipeGestures"
    /// Two fingers down opens the island, up closes it.
    static let swipeToOpen = "swipeToOpen"
    /// Two fingers up closes it; on its own so a swipe up can't close the island by accident.
    static let swipeToClose = "swipeToClose"
    /// Two fingers sideways skips tracks, or turns pages when the island is open.
    static let swipeSideways = "swipeSideways"
    /// Every swipe goes the other way.
    static let swipeReversed = "swipeReversed"
    /// The open island's page follows the fingers sideways; off, a swipe turns it at once.
    static let swipePagesFollow = "swipePagesFollow"
    /// How far the fingers travel before a swipe counts: SwipeSensitivity raw value.
    static let swipeSensitivity = "swipeSensitivity"
    /// Apple's status colours (green charging, orange timer…), or white; low battery stays red.
    static let statusColors = "statusColors"
    /// A second activity (a timer, a meeting about to start) shows as its own drop beside the island.
    static let showCompanion = "showCompanion"
    /// A soft shadow under the open island and the track peek.
    static let islandShadow = "islandShadow"
    /// A faint line around the island, so it shows against a black menu bar or wallpaper.
    static let islandOutline = "islandOutline"
    /// The island leaves screenshots and screen recordings out.
    static let hideFromCapture = "hideFromCapture"
    /// The Settings window's look: SettingsAppearance raw value. The island is always black.
    static let settingsAppearance = "settingsAppearance"

    static var generalArea: PrefsArea {
        PrefsArea(id: "general", defaults: [
            hideMenuBarIcon: false,
            display: DisplayChoice.builtIn.rawValue,
            closedHeight: ClosedHeight.notch.rawValue,
            closedHeightCustom: 32.0,
            notchlessStyle: NotchlessStyle.notch.rawValue,
            // Off by default: detection of other apps' fullscreen spaces is heuristic.
            hideInFullscreen: false,
            fullscreenMediaOnly: false,
            openTo: OpenTo.whatsHappening.rawValue,
            enableHaptics: true,
            hapticStrength: HapticStrength.medium.rawValue,
            // On: pointing at the notch opens it.
            expandOnHover: true,
            hoverDelay: 0.18,
            swipeGestures: true,
            swipeToOpen: true,
            swipeToClose: true,
            swipeSideways: true,
            swipeReversed: false,
            swipePagesFollow: true,
            swipeSensitivity: SwipeSensitivity.medium.rawValue,
            statusColors: true,
            showCompanion: true,
            islandShadow: true,
            islandOutline: false,
            hideFromCapture: false,
            settingsAppearance: SettingsAppearance.light.rawValue,
        ])
    }
}
