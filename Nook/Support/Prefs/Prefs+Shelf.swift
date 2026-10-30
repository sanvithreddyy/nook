import Foundation

extension Prefs {
    static let shelf = "shelf"

    static var shelfArea: PrefsArea {
        PrefsArea(id: "shelf", defaults: [
            shelf: true,
        ])
    }
}
