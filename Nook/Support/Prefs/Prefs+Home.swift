import Foundation

extension Prefs {
    /// The open island's home: HomeLayout raw value, modules per page side by side (2 or 3),
    /// the modules' order and the ones turned off (comma lists of HomeModule), HomeSize raw value.
    static let homeLayout = "homeLayout"
    static let homeColumns = "homeColumns"
    static let homeOrder = "homeOrder"
    static let homeHidden = "homeHidden"
    static let homeSize = "homeSize"

    static var homeArea: PrefsArea {
        PrefsArea(id: "home", defaults: [
            // Side by side, two to a page: Music and Calendar together.
            homeLayout: HomeLayout.sideBySide.rawValue,
            homeColumns: 2,
            homeOrder: HomeOrder.string(HomeModule.allCases),
            homeHidden: "",
            homeSize: HomeSize.medium.rawValue,
        ])
    }
}
