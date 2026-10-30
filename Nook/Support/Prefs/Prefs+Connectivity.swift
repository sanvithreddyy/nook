import Foundation

extension Prefs {
    static let connectivity = "connectivity"

    static var connectivityArea: PrefsArea {
        PrefsArea(id: "connectivity", defaults: [
            connectivity: true,
        ])
    }
}
