import Foundation

extension Prefs {
    static let calendar = "calendar"
    static let calendarLeadMinutes = "calendarLeadMinutes"

    static var calendarArea: PrefsArea {
        PrefsArea(id: "calendar", defaults: [
            // On: the open island shows the month. Access is asked for from the island, not at launch.
            calendar: true,
            calendarLeadMinutes: 10,
        ])
    }
}
