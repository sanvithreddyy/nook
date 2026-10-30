import AppKit
import EventKit
import SwiftUI

struct CalendarEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let color: Color
    let isAllDay: Bool
    /// A video-call link found in the event's URL, location or notes.
    let joinURL: URL?
    /// EventKit's identifier, for opening the event in Calendar.
    var eventIdentifier: String? = nil
    /// You said no to it: it stays in the calendar but doesn't count down, chime or show its title.
    var isDeclined = false

    /// "Google Meet", "Zoom"… for the join link's host.
    var meetingService: String? {
        guard let host = joinURL?.host()?.lowercased() else { return nil }
        let names = ["zoom.us": "Zoom", "meet.google.com": "Google Meet", "teams.microsoft.com": "Teams", "teams.live.com": "Teams",
                     "facetime.apple.com": "FaceTime", "webex.com": "Webex", "whereby.com": "Whereby"]
        return names.first { host == $0.key || host.hasSuffix("." + $0.key) }?.value
    }
}

@Observable
final class CalendarModel {
    enum Access { case notDetermined, granted, denied }

    /// Events from the start of this month through the end of the next, and at least 30 days ahead.
    private(set) var events: [CalendarEvent] = [] {
        didSet { busyDays = Self.days(covering: events) }
    }
    /// Every day in the window with at least one event, at the start of the day.
    private(set) var busyDays: Set<Date> = []
    /// A month the Calendar module was turned to outside the window, read while it shows.
    private(set) var browsed: [CalendarEvent] = [] {
        didSet { browsedBusyDays = Self.days(covering: browsed) }
    }
    private(set) var browsedBusyDays: Set<Date> = []
    private(set) var access: Access = .notDetermined
    /// The day the window was last read on; a new day refetches.
    private(set) var weekStart = Calendar.current.startOfDay(for: .now)

    var isAuthorized: Bool { access == .granted }

    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var storeObserver: NSObjectProtocol?
    /// Join links by occurrence and edit date, so link detection runs once per event edit.
    @ObservationIgnored private var linkCache: [String: URL?] = [:]
    /// Events whose meeting card was dismissed.
    @ObservationIgnored private var dismissed: Set<String> = []

    var isEnabled: Bool { Prefs.bool(Prefs.calendar) }

    /// Starts reading events when Calendar is on and access exists. Never prompts on its own:
    /// the prompt comes from the Allow button in the island.
    func update() {
        guard isEnabled else {
            stop()
            return
        }
        access = Self.currentAccess()
        if access == .granted { begin() } else { onChange?() }
    }

    func requestAccess() {
        Task {
            let granted = (try? await store.requestFullAccessToEvents()) ?? false
            access = granted ? .granted : .denied
            // The setting may have been turned off while the prompt was open.
            if granted, isEnabled { begin() } else { onChange?() }
        }
    }

    /// Reads events again after Settings changes which calendars or events show.
    func reloadIfRunning() {
        if refreshTask != nil { reload() }
    }

    /// Every calendar that holds events, for Settings to list. Empty without access.
    static func allCalendars() -> [(id: String, title: String, account: String, color: Color)] {
        guard currentAccess() == .granted else { return [] }
        return EKEventStore().calendars(for: .event)
            .map { (id: $0.calendarIdentifier, title: $0.title, account: $0.source.title, color: Color(cgColor: $0.cgColor)) }
            .sorted { ($0.account, $0.title) < ($1.account, $1.title) }
    }

    /// Picks up access granted later in System Settings.
    func recheckAuthorization() {
        guard isEnabled, !isAuthorized, Self.currentAccess() == .granted else { return }
        update()
    }

    func event(id: String) -> CalendarEvent? {
        events.first { $0.id == id }
    }

    /// One day's events as the Calendar widget lists them: all-day events first, then by start.
    /// Today leaves out what has already ended.
    func events(on day: Date, now: Date = .now) -> [CalendarEvent] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        let isToday = calendar.isDate(day, inSameDayAs: now)
        return (window.isEmpty || window.contains(start) ? events : browsed)
            .filter { $0.start < end && $0.end > start && (!isToday || $0.isAllDay || $0.end > now) }
            .sorted { ($0.isAllDay ? 0 : 1, $0.start) < ($1.isAllDay ? 0 : 1, $1.start) }
    }

    private static func days(covering events: [CalendarEvent]) -> Set<Date> {
        let calendar = Calendar.current
        var days: Set<Date> = []
        for event in events {
            var day = calendar.startOfDay(for: event.start)
            // An event ending at midnight doesn't touch the next day.
            while day < event.end, days.count < 400 {
                days.insert(day)
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
        }
        return days
    }

    /// Shows the event in Calendar, or opens Calendar when the event can't be addressed.
    static func open(_ event: CalendarEvent) {
        if let id = event.eventIdentifier?.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
           let url = URL(string: "ical://ekevent/\(id)?method=show&options=more"),
           NSWorkspace.shared.open(url) {
            return
        }
        openCalendarApp()
    }

    /// Timed events under way or still to come in the window, soonest first. All-day events are left
    /// out: "up next" is about where to be, and a holiday or a birthday would always lead.
    func upcoming(now: Date = .now) -> [CalendarEvent] {
        events.filter { !$0.isAllDay && $0.end > now }
    }

    /// The timed event starting within the lead time, or one under way for less than Settings'
    /// "once it starts" time, unless its meeting card was dismissed.
    /// A meeting in its first five minutes comes first: it's the one to join. After that a meeting
    /// about to start wins over one still going ("until it ends"), so the next countdown shows.
    func eventForLiveActivity(now: Date = .now, leadMinutes: Int = Prefs.int(Prefs.calendarLeadMinutes),
                              stayMinutes: Int = Prefs.int(Prefs.calendarStayMinutes)) -> CalendarEvent? {
        let lead = TimeInterval(max(leadMinutes, 1) * 60)
        let candidates = events.filter { event in
            !event.isAllDay
                && !event.isDeclined
                && !dismissed.contains(event.id)
                && event.end > now
                && event.start.timeIntervalSince(now) <= lead
                && (stayMinutes < 0 || now.timeIntervalSince(event.start) < TimeInterval(stayMinutes * 60))
        }
        let justStarted = candidates.first { $0.start <= now && now.timeIntervalSince($0.start) < 5 * 60 }
        return justStarted ?? candidates.first { $0.start > now } ?? candidates.first
    }

    /// Its meeting card was dismissed, so it shouldn't chime or show its title either.
    func isDismissed(_ id: String) -> Bool { dismissed.contains(id) }

    /// Dismiss on the meeting card: stop showing that event in the notch. Kept until Nook quits.
    func dismiss(_ id: String) {
        guard dismissed.insert(id).inserted else { return }
        onChange?()
    }

    static func openCalendarApp() {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") else { return }
        NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
    }

    #if DEBUG
    /// Events as given, for tests.
    func debugSet(_ events: [CalendarEvent]) { self.events = events }

    /// Sample week for screenshots; never touches EventKit. `meetingSoon` starts the design review in 4 minutes,
    /// `startsIn` in that many seconds (to watch it start).
    func debugPreview(meetingSoon: Bool = false, startsIn: Double? = nil) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            cal.date(byAdding: .minute, value: day * 1440 + hour * 60 + minute, to: today)!
        }
        let now = Date()
        let soon = startsIn.map { now.addingTimeInterval($0) }
            ?? cal.date(bySetting: .second, value: 0, of: now.addingTimeInterval((meetingSoon ? 4 : 20) * 60)) ?? now
        events = [
            CalendarEvent(id: "a", title: "Ops sync", start: now.addingTimeInterval(-40 * 60), end: now.addingTimeInterval(-10 * 60), color: .orange, isAllDay: false, joinURL: nil),
            CalendarEvent(id: "b", title: "Design review", start: soon, end: soon.addingTimeInterval(45 * 60), color: .blue, isAllDay: false, joinURL: URL(string: "https://meet.google.com/abc")),
            CalendarEvent(id: "c", title: "Dinner", start: now.addingTimeInterval(3 * 3600), end: now.addingTimeInterval(4.5 * 3600), color: .green, isAllDay: false, joinURL: nil),
            CalendarEvent(id: "d", title: "Inventory audit", start: at(1, 10), end: at(1, 11), color: .orange, isAllDay: false, joinURL: nil),
            CalendarEvent(id: "e", title: "Vendor call", start: at(1, 13, 30), end: at(1, 14), color: .blue, isAllDay: false, joinURL: URL(string: "https://zoom.us/j/1")),
            CalendarEvent(id: "f", title: "Gym", start: at(1, 16), end: at(1, 17), color: .green, isAllDay: false, joinURL: nil),
            CalendarEvent(id: "g", title: "Farmers market", start: at(2, 9, 30), end: at(2, 11), color: .green, isAllDay: false, joinURL: nil),
            CalendarEvent(id: "h", title: "Launch", start: at(4, 0), end: at(5, 0), color: .red, isAllDay: true, joinURL: nil),
            CalendarEvent(id: "i", title: "Product demo", start: at(5, 14), end: at(5, 15), color: .blue, isAllDay: false, joinURL: URL(string: "https://zoom.us/j/1")),
            CalendarEvent(id: "j", title: "Quarterly planning", start: at(9, 10), end: at(9, 12), color: .purple, isAllDay: false, joinURL: nil),
        ]
        access = .granted
        onChange?()
    }
    #endif

    private static func currentAccess() -> Access {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    private func begin() {
        if storeObserver == nil {
            storeObserver = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.reload() }
            }
        }
        reload()
        refreshTask?.cancel()
        // Event edits arrive through EKEventStoreChanged. The tick only re-evaluates the live
        // activity, and refetches when the day rolls over.
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard let self else { return }
                if Calendar.current.startOfDay(for: .now) != self.weekStart { self.reload() } else { self.onChange?() }
            }
        }
    }

    private func stop() {
        refreshTask?.cancel()
        refreshTask = nil
        if let storeObserver { NotificationCenter.default.removeObserver(storeObserver) }
        storeObserver = nil
        if !events.isEmpty {
            events = []
            onChange?()
        }
    }

    private func reload() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        if weekStart != today { weekStart = today }
        // The Calendar module shows this month and the next; the meeting and live activity look 30 days ahead.
        let start = calendar.dateInterval(of: .month, for: today)?.start ?? today
        let end = max(calendar.date(byAdding: .month, value: 2, to: start) ?? today,
                      calendar.date(byAdding: .day, value: Self.windowDays, to: today) ?? today)
        window = start..<end
        var seenLinks: [String: URL?] = [:]
        let fetched = fetch(from: start, to: end) { cachedMeetingLink(for: $0, into: &seenLinks) }
        linkCache = seenLinks
        if fetched != events { events = fetched }
        if let browsedMonth { browse(browsedMonth) }
        onChange?()
    }

    /// The days events were last read for; a day outside them comes from the browsed month.
    @ObservationIgnored private var window: Range<Date> = Date.distantPast..<Date.distantPast
    @ObservationIgnored private var browsedMonth: Date?

    /// Reads a month the module turned to, if it's outside the window; nil (or a month inside it)
    /// lets the browsed events go.
    func browse(_ month: Date?) {
        let calendar = Calendar.current
        guard isAuthorized, let month, let interval = calendar.dateInterval(of: .month, for: month),
              !(window.contains(interval.start) && window.contains(interval.end.addingTimeInterval(-1)))
        else {
            browsedMonth = nil
            if !browsed.isEmpty { browsed = [] }
            return
        }
        browsedMonth = interval.start
        let fetched = fetch(from: interval.start, to: interval.end) { _ in nil }
        if fetched != browsed { browsed = fetched }
    }

    /// Events between two dates from the calendars Settings shows, as the module lists them.
    private func fetch(from start: Date, to end: Date, link: (EKEvent) -> URL?) -> [CalendarEvent] {
        // Calendars Settings leaves out are never read.
        let hidden = Set(Prefs.string(Prefs.calendarHidden).split(separator: ",").map(String.init))
        let calendars = store.calendars(for: .event).filter { !hidden.contains($0.calendarIdentifier) }
        let hideAllDay = Prefs.bool(Prefs.calendarHideAllDay)
        guard !calendars.isEmpty else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        return store.events(matching: predicate)
            .filter { $0.status != .canceled && !(hideAllDay && $0.isAllDay) }
            .sorted { $0.startDate < $1.startDate }
            .prefix(1000)
            .map { event in
                // Occurrences of a recurring event share eventIdentifier; the start date tells them apart.
                CalendarEvent(id: "\(event.eventIdentifier ?? "event")@\(Int(event.startDate.timeIntervalSince1970))",
                              title: event.title ?? "Untitled",
                              start: event.startDate,
                              end: event.endDate,
                              color: Color(cgColor: event.calendar.cgColor),
                              isAllDay: event.isAllDay,
                              joinURL: link(event),
                              eventIdentifier: event.eventIdentifier,
                              isDeclined: event.attendees?.first(where: \.isCurrentUser)?.participantStatus == .declined)
            }
    }

    private func cachedMeetingLink(for event: EKEvent, into seen: inout [String: URL?]) -> URL? {
        let key = "\(event.eventIdentifier ?? "")@\(event.startDate.timeIntervalSince1970)|\(event.lastModifiedDate?.timeIntervalSince1970 ?? 0)"
        let link = linkCache[key] ?? Self.meetingLink(in: event)
        seen[key] = link
        return link
    }

    /// How far ahead meetings are looked for, at least.
    static let windowDays = 30

    private static let linkDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    private static let meetingHosts = ["zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com", "facetime.apple.com", "webex.com", "whereby.com"]

    private static func meetingLink(in event: EKEvent) -> URL? {
        if let url = event.url, isMeeting(url) { return url }
        let text = [event.location, event.notes].compactMap { $0 }.joined(separator: "\n")
        guard !text.isEmpty, let detector = linkDetector else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, range: range).compactMap(\.url).first(where: isMeeting)
    }

    private static func isMeeting(_ url: URL) -> Bool {
        guard let host = url.host()?.lowercased() else { return false }
        return meetingHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }
}
