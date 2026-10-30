import Foundation

extension Prefs {
    static let timerSound = "timerSound"                // a system sound name, or "" for none

    static var timerArea: PrefsArea {
        PrefsArea(id: "timer", defaults: [
            timerSound: "Glass",
        ])
    }
}
