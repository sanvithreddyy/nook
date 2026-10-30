import Foundation

extension Prefs {
    static let connectivity = "connectivity"
    /// Seconds a device's connection notice stays once its battery is known.
    static let deviceNoticeDuration = "deviceNoticeDuration"

    static var connectivityArea: PrefsArea {
        PrefsArea(id: "connectivity", defaults: [
            connectivity: true,
            deviceNoticeDuration: 2.5,
        ])
    }
}
