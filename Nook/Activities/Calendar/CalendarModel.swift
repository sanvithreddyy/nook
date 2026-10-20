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
}

@Observable
final class CalendarModel {
    enum Access { case notDetermined, granted, denied }

    /// Events from the start of today through the next six days.
    private(set) var events: [CalendarEvent] = []
    private(set) var access: Access = .notDetermined

    var isAuthorized: Bool { access == .granted }

    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var storeObserver: NSObjectProtocol?

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

    func events(on day: Date) -> [CalendarEvent] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        return events.filter { $0.start < end && $0.end > start }
            .sorted { ($0.isAllDay ? 0 : 1, $0.start) < ($1.isAllDay ? 0 : 1, $1.start) }
    }

    /// The timed event starting within the lead time, or one that started less than five minutes ago.
    func eventForLiveActivity(now: Date = .now) -> CalendarEvent? {
        let lead = TimeInterval(max(Prefs.int(Prefs.calendarLeadMinutes), 1) * 60)
        return events.first { event in
            !event.isAllDay
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
        ]
        access = .granted
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
        // Moves events in and out of the live-activity window and rolls the week at midnight.
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                self?.reload()
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
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let fetched = store.events(matching: predicate)
            .filter { $0.status != .canceled }
            .sorted { $0.startDate < $1.startDate }
            .prefix(120)
            .map { event in
                // Occurrences of a recurring event share eventIdentifier; the start date tells them apart.
                CalendarEvent(id: "\(event.eventIdentifier ?? "event")@\(Int(event.startDate.timeIntervalSince1970))",
                              title: event.title ?? "Untitled",
                              start: event.startDate,
                              end: event.endDate,
                              color: Color(cgColor: event.calendar.cgColor),
                              isAllDay: event.isAllDay,
                              joinURL: Self.meetingLink(in: event))
            }
        if fetched != events { events = Array(fetched) }
        onChange?()
    }

    private static let meetingHosts = ["zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com", "facetime.apple.com", "webex.com", "whereby.com"]

    private static func meetingLink(in event: EKEvent) -> URL? {
        if let url = event.url, isMeeting(url) { return url }
        let text = [event.location, event.notes].compactMap { $0 }.joined(separator: "\n")
        guard !text.isEmpty,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, range: range).compactMap(\.url).first(where: isMeeting)
    }

    private static func isMeeting(_ url: URL) -> Bool {
        guard let host = url.host()?.lowercased() else { return false }
        return meetingHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }
}
