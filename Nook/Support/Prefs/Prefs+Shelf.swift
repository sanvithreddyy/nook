import Foundation

extension Prefs {
    static let shelf = "shelf"
    /// A file drag opens the shelf from a wider area around the notch.
    static let shelfCatchWide = "shelfCatchWide"
    /// Files that were deleted, or sit on a disk that isn't connected, leave the shelf when it opens.
    static let shelfDropMissing = "shelfDropMissing"

    static var shelfArea: PrefsArea {
        PrefsArea(id: "shelf", defaults: [
            shelf: true,
            shelfCatchWide: false,
            shelfDropMissing: false,
        ])
    }
}
