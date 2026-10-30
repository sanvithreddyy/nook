import Foundation

extension Prefs {
    static let calendar = "calendar"
    static let calendarLeadMinutes = "calendarLeadMinutes"
    /// The Calendar module's month: WeekStart raw value, a dot under days with events, weekends in grey.
    static let calendarWeekStart = "calendarWeekStart"
    static let calendarDots = "calendarDots"
    static let calendarDimWeekends = "calendarDimWeekends"

    static var calendarArea: PrefsArea {
        PrefsArea(id: "calendar", defaults: [
            // On: the open island shows the month. Access is asked for from the island, not at launch.
            calendar: true,
            calendarLeadMinutes: 10,
            calendarWeekStart: WeekStart.system.rawValue,
            // Off, as Apple's Calendar widget has it; a choice for seeing busy days at a glance.
            calendarDots: false,
            calendarDimWeekends: true,
        ])
    }
}
