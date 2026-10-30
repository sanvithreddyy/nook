import Foundation

extension Prefs {
    static let battery = "battery"
    static let lowBatteryThreshold = "lowBatteryThreshold"
    /// The Batteries module lists this Mac's own battery first.
    static let batteriesIncludeMac = "batteriesIncludeMac"

    static var batteryArea: PrefsArea {
        PrefsArea(id: "battery", defaults: [
            battery: true,
            lowBatteryThreshold: 20,
            batteriesIncludeMac: true,
        ])
    }
}
