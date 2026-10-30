import Foundation

extension Prefs {
    static let battery = "battery"
    static let lowBatteryThreshold = "lowBatteryThreshold"
    /// Seconds the charging and on-battery notice stays.
    static let batteryNoticeDuration = "batteryNoticeDuration"
    static let lowBatteryWarning = "lowBatteryWarning"
    /// A system sound with the low battery warning; empty for none.
    static let lowBatterySound = "lowBatterySound"
    static let lowPowerNotice = "lowPowerNotice"

    static var batteryArea: PrefsArea {
        PrefsArea(id: "battery", defaults: [
            battery: true,
            lowBatteryThreshold: 20,
            batteryNoticeDuration: 2.5,
            lowBatteryWarning: true,
            lowBatterySound: "",
            lowPowerNotice: true,
        ])
    }
}
