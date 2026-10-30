import Foundation

extension Prefs {
    static let volumeHUD = "volumeHUD"
    static let brightnessHUD = "brightnessHUD"
    static let hudStyle = "hudStyle"                    // HUDStyle raw value
    /// Seconds a volume or brightness HUD stays after the last press.
    static let hudDuration = "hudDuration"
    /// The level as a number beside the notch, besides the bar.
    static let hudShowsNumber = "hudShowsNumber"

    static var hudsArea: PrefsArea {
        PrefsArea(id: "huds", defaults: [
            volumeHUD: false,
            brightnessHUD: false,
            hudStyle: HUDStyle.ledge.rawValue,
            hudDuration: 1.6,
            hudShowsNumber: true,
        ])
    }
}
