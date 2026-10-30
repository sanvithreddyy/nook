import Observation
import SwiftUI

/// A reminder still to do.
struct ReminderItem: Identifiable, Equatable {
    let id: String
    let title: String
}

/// What the Reminders module shows: one list, how many are left in it, the first few.
@Observable
final class RemindersModel {
    private(set) var listName = "Reminders"
    private(set) var listColor: Color = .blue
    private(set) var items: [ReminderItem] = []
    /// Ticked a moment ago: drawn done until it leaves the list.
    private(set) var completing: Set<String> = []

    func complete(_ item: ReminderItem) {
        completing.insert(item.id)
        Task {
            // Long enough to see the circle fill, as in Reminders.
            try? await Task.sleep(for: .seconds(0.9))
            withAnimation(Motion.content) {
                items.removeAll { $0.id == item.id }
                completing.remove(item.id)
            }
        }
    }

    #if DEBUG
    func debugPreview() {
        items = ["Book flights", "Call the bank", "Pick up dry cleaning", "Renew passport", "Buy a gift"].enumerated()
            .map { ReminderItem(id: "\($0.offset)", title: $0.element) }
    }
    #endif
}
