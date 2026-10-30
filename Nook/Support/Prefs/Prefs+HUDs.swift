import Foundation

extension Prefs {
    static let volumeHUD = "volumeHUD"
    static let brightnessHUD = "brightnessHUD"
    static let hudStyle = "hudStyle"                    // HUDStyle raw value

    static var hudsArea: PrefsArea {
        PrefsArea(id: "huds", defaults: [
            volumeHUD: false,
            brightnessHUD: false,
            hudStyle: HUDStyle.ledge.rawValue,
        ])
    }
}
