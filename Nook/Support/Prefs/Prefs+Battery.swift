import Foundation

extension Prefs {
    static let battery = "battery"
    static let lowBatteryThreshold = "lowBatteryThreshold"

    static var batteryArea: PrefsArea {
        PrefsArea(id: "battery", defaults: [
            battery: true,
            lowBatteryThreshold: 20,
        ])
    }
}
