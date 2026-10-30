import Foundation

extension Prefs {
    static let connectivity = "connectivity"
    /// Seconds a device's connection notice stays, and the notice when sound switches to it.
    static let deviceNoticeDuration = "deviceNoticeDuration"

    static var connectivityArea: PrefsArea {
        PrefsArea(id: "connectivity", defaults: [
            connectivity: true,
            deviceNoticeDuration: 2.5,
        ])
    }
}
