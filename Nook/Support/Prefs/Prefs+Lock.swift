import Foundation

extension Prefs {
    static let lockActivity = "lockActivity"

    static var lockArea: PrefsArea {
        PrefsArea(id: "lock", defaults: [
            lockActivity: true,
        ])
    }
}
