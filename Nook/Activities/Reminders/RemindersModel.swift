import EventKit
import Observation
import SwiftUI

/// A reminder still to do.
struct ReminderItem: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
}

/// What the Reminders module shows: one list (the one Settings picked, or the default), how many are
/// left in it and the first few, oldest first as a new list fills. Ticking one off and adding one go
/// straight to Reminders. Asks for access only from the module's button.
@Observable
final class RemindersModel {
    enum Access { case notDetermined, granted, denied }

    private(set) var access: Access = .notDetermined
    private(set) var listName = "Reminders"
    private(set) var listColor: Color = .blue
    private(set) var items: [ReminderItem] = []
    /// Ticked a moment ago: drawn done until it leaves the list.
    private(set) var completing: Set<String> = []

    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var storeObserver: NSObjectProtocol?
    @ObservationIgnored private var reading = false

    var isEnabled: Bool { HomeConfig.current.modules.contains(.reminders) }

    /// Starts reading when the module is on and access exists. Never prompts on its own.
    func update() {
        access = Self.currentAccess()
        guard access == .granted, isEnabled else { return }
        if storeObserver == nil {
            storeObserver = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.reload() }
            }
        }
        reload()
    }

    func requestAccess() {
        Task {
            let granted = (try? await store.requestFullAccessToReminders()) ?? false
            access = granted ? .granted : .denied
            if granted { update() }
        }
    }

    /// Picks up access granted later in System Settings.
    func recheckAuthorization() {
        if access != .granted, Self.currentAccess() == .granted { update() }
    }

    func complete(_ item: ReminderItem) {
        completing.insert(item.id)
        if let reminder = store.calendarItem(withIdentifier: item.id) as? EKReminder {
            reminder.isCompleted = true
            try? store.save(reminder, commit: true)
        }
        Task {
            // Long enough to see the circle fill, as in Reminders.
            try? await Task.sleep(for: .seconds(0.9))
            withAnimation(Motion.content) {
                items.removeAll { $0.id == item.id }
                completing.remove(item.id)
            }
        }
    }

    /// A new reminder at the end of the list, as Reminders adds one.
    func add(_ title: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, access == .granted, let list else { return }
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.calendar = list
        try? store.save(reminder, commit: true)
        reload()
    }

    /// Every list, for Settings to offer. Empty without access.
    static func allLists() -> [(id: String, title: String, color: Color)] {
        guard currentAccess() == .granted else { return [] }
        return EKEventStore().calendars(for: .reminder)
            .map { (id: $0.calendarIdentifier, title: $0.title, color: Color(cgColor: $0.cgColor)) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private var list: EKCalendar? {
        let saved = Prefs.string(Prefs.remindersList)
        return (saved.isEmpty ? nil : store.calendar(withIdentifier: saved)) ?? store.defaultCalendarForNewReminders()
    }

    private func reload() {
        guard !reading, let list else { return }
        reading = true
        listName = list.title
        listColor = Color(cgColor: list.cgColor)
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: [list])
        store.fetchReminders(matching: predicate) { @Sendable [weak self] found in
            // EventKit answers on its own queue; only plain values cross back.
            let fresh = (found ?? [])
                .sorted { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }
                .map { ReminderItem(id: $0.calendarItemIdentifier, title: $0.title ?? "") }
            Task { @MainActor in self?.show(fresh) }
        }
    }

    /// The list as read, keeping a just-ticked reminder where it was until its circle has filled.
    private func show(_ fresh: [ReminderItem]) {
        reading = false
        var next = fresh
        for (index, item) in items.enumerated() where completing.contains(item.id) && !next.contains(item) {
            next.insert(item, at: min(index, next.count))
        }
        guard next != items else { return }
        withAnimation(Motion.content) { items = next }
    }

    private static func currentAccess() -> Access {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    #if DEBUG
    func debugPreview() {
        access = .granted
        items = ["Book flights", "Call the bank", "Pick up dry cleaning", "Renew passport", "Buy a gift"].enumerated()
            .map { ReminderItem(id: "\($0.offset)", title: $0.element) }
    }
    #endif
}
