import Foundation

extension Prefs {
    static let calendar = "calendar"
    static let calendarLeadMinutes = "calendarLeadMinutes"
    /// After an event starts, the minutes it stays beside the notch: 0 leaves at the start, -1 stays to the end.
    static let calendarStayMinutes = "calendarStayMinutes"
    /// Calendars left out, comma separated calendar identifiers.
    static let calendarHidden = "calendarHidden"
    static let calendarHideAllDay = "calendarHideAllDay"
    /// When an event starts, its title drops below the island for a moment.
    static let calendarPeekAtStart = "calendarPeekAtStart"
    /// A system sound when an event starts; empty for none.
    static let calendarChime = "calendarChime"

    static var calendarArea: PrefsArea {
        PrefsArea(id: "calendar", defaults: [
            // On: the open island shows the month. Access is asked for from the island, not at launch.
            calendar: true,
            calendarLeadMinutes: 10,
            calendarStayMinutes: 5,
            calendarHidden: "",
            calendarHideAllDay: false,
            calendarPeekAtStart: true,
            calendarChime: "",
        ])
    }
}
