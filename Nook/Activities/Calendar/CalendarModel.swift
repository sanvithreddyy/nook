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

    /// Events from the start of today through the next 30 days.
    private(set) var events: [CalendarEvent] = []
    private(set) var access: Access = .notDetermined
    /// Start of the day the window begins on; changes at midnight.
    private(set) var weekStart = Calendar.current.startOfDay(for: .now)

    var isAuthorized: Bool { access == .granted }

    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var storeObserver: NSObjectProtocol?
    /// Join links by occurrence and edit date, so link detection runs once per event edit.
    @ObservationIgnored private var linkCache: [String: URL?] = [:]

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

    /// Picks up access granted later in System Settings.
    func recheckAuthorization() {
        guard isEnabled, !isAuthorized, Self.currentAccess() == .granted else { return }
        update()
    }

    func event(id: String) -> CalendarEvent? {
        events.first { $0.id == id }
    }

    /// Timed events under way or still to come in the window, soonest first. All-day events are left
    /// out: "up next" is about where to be, and a holiday or a birthday would always lead.
    func upcoming(now: Date = .now) -> [CalendarEvent] {
        events.filter { !$0.isAllDay && $0.end > now }
    }

    /// The timed event starting within the lead time, or one that started less than five minutes ago.
    func eventForLiveActivity(now: Date = .now) -> CalendarEvent? {
        let lead = TimeInterval(max(Prefs.int(Prefs.calendarLeadMinutes), 1) * 60)
        return events.first { event in
            !event.isAllDay
                && event.end > now
                && event.start.timeIntervalSince(now) <= lead
                && now.timeIntervalSince(event.start) < 5 * 60
        }
    }

    #if DEBUG
    /// Sample week for screenshots; never touches EventKit.
    func debugPreview() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            cal.date(byAdding: .minute, value: day * 1440 + hour * 60 + minute, to: today)!
        }
        let now = Date()
        let soon = cal.date(bySetting: .second, value: 0, of: now.addingTimeInterval(20 * 60)) ?? now
        events = [
            CalendarEvent(id: "a", title: "Ops sync", start: now.addingTimeInterval(-40 * 60), end: now.addingTimeInterval(-10 * 60), color: .orange, isAllDay: false, joinURL: nil),
            CalendarEvent(id: "b", title: "Design review", start: soon, end: soon.addingTimeInterval(45 * 60), color: .blue, isAllDay: false, joinURL: URL(string: "https://meet.google.com/abc")),
            CalendarEvent(id: "c", title: "Dinner", start: now.addingTimeInterval(3 * 3600), end: now.addingTimeInterval(4.5 * 3600), color: .green, isAllDay: false, joinURL: nil),
            CalendarEvent(id: "d", title: "Inventory audit", start: at(1, 10), end: at(1, 11), color: .purple, isAllDay: false, joinURL: nil),
            CalendarEvent(id: "e", title: "Launch", start: at(3, 0), end: at(4, 0), color: .red, isAllDay: true, joinURL: nil),
            CalendarEvent(id: "f", title: "Payroll review", start: at(2, 11), end: at(2, 12), color: .blue, isAllDay: false, joinURL: nil),
            CalendarEvent(id: "g", title: "Product demo", start: at(5, 14), end: at(5, 15), color: .blue, isAllDay: false, joinURL: URL(string: "https://zoom.us/j/1")),
            CalendarEvent(id: "h", title: "Quarterly planning", start: at(9, 10), end: at(9, 12), color: .purple, isAllDay: false, joinURL: nil),
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
        let start = calendar.startOfDay(for: .now)
        let end = calendar.date(byAdding: .day, value: Self.windowDays, to: start) ?? start
        if weekStart != start { weekStart = start }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        var seenLinks: [String: URL?] = [:]
        let fetched = store.events(matching: predicate)
            .filter { $0.status != .canceled }
            .sorted { $0.startDate < $1.startDate }
            .prefix(500)
            .map { event in
                // Occurrences of a recurring event share eventIdentifier; the start date tells them apart.
                CalendarEvent(id: "\(event.eventIdentifier ?? "event")@\(Int(event.startDate.timeIntervalSince1970))",
                              title: event.title ?? "Untitled",
                              start: event.startDate,
                              end: event.endDate,
                              color: Color(cgColor: event.calendar.cgColor),
                              isAllDay: event.isAllDay,
                              joinURL: cachedMeetingLink(for: event, into: &seenLinks))
            }
        linkCache = seenLinks
        if fetched != events { events = Array(fetched) }
        onChange?()
    }

    private func cachedMeetingLink(for event: EKEvent, into seen: inout [String: URL?]) -> URL? {
        let key = "\(event.eventIdentifier ?? "")@\(event.startDate.timeIntervalSince1970)|\(event.lastModifiedDate?.timeIntervalSince1970 ?? 0)"
        let link = linkCache[key] ?? Self.meetingLink(in: event)
        seen[key] = link
        return link
    }

    /// How far ahead the island's list reaches.
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
