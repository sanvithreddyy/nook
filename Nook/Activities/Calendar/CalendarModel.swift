import EventKit
import SwiftUI

struct CalendarEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let color: Color
    let isAllDay: Bool
}

@Observable
final class CalendarModel {
    private(set) var events: [CalendarEvent] = []
    private(set) var isAuthorized = false

    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var storeObserver: NSObjectProtocol?

    var isEnabled: Bool { Prefs.bool(Prefs.calendar) }

    /// Starts reading events when Calendar is on; asks for access the first time.
    func update() {
        guard isEnabled else {
            stop()
            return
        }
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            isAuthorized = true
            begin()
        case .notDetermined:
            Task {
                let granted = (try? await store.requestFullAccessToEvents()) ?? false
                isAuthorized = granted
                // The toggle may have been turned off while the prompt was open.
                if granted, isEnabled { begin() } else { onChange?() }
            }
        default:
            isAuthorized = false
            onChange?()
        }
    }

    /// Picks up access granted later in System Settings.
    func recheckAuthorization() {
        guard isEnabled, !isAuthorized, EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return }
        update()
    }

    func event(id: String) -> CalendarEvent? {
        events.first { $0.id == id }
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

    var upcoming: [CalendarEvent] {
        let now = Date()
        return events.filter { $0.end > now }
    }

    private func begin() {
        if storeObserver == nil {
            storeObserver = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.reload() }
            }
        }
        reload()
        refreshTask?.cancel()
        // A minute tick moves events in and out of the live-activity window.
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
        let now = Date()
        let end = Calendar.current.date(byAdding: .hour, value: 24, to: Calendar.current.startOfDay(for: now)) ?? now
        let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-3600), end: end, calendars: nil)
        let fetched = store.events(matching: predicate)
            .filter { $0.status != .canceled && $0.endDate > now }
            .sorted { $0.startDate < $1.startDate }
            .prefix(12)
            .map { event in
                // Occurrences of a recurring event share eventIdentifier; the start date tells them apart.
                CalendarEvent(id: "\(event.eventIdentifier ?? "event")@\(Int(event.startDate.timeIntervalSince1970))",
                              title: event.title ?? "Untitled",
                              start: event.startDate,
                              end: event.endDate,
                              color: Color(cgColor: event.calendar.cgColor),
                              isAllDay: event.isAllDay)
            }
        if fetched != events { events = Array(fetched) }
        onChange?()
    }
}
