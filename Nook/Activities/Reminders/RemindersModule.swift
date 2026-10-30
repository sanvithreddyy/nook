import SwiftUI

/// Apple's Reminders widget on the notch: the list's name and how many are left, in the list's colour,
/// then the first few with their circles. Click a circle to tick it off.
struct RemindersModule: View {
    @Environment(RemindersModel.self) private var reminders
    @Environment(\.homeScale) private var k

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(reminders.listName)
                    .font(.system(size: 15 * k, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 8 * k)
                Text("\(reminders.items.count)")
                    .font(.system(size: 26 * k, weight: .semibold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText(value: Double(reminders.items.count)))
            }
            .foregroundStyle(reminders.listColor)
            .frame(height: 30 * k)
            if reminders.items.isEmpty {
                Text("No Reminders")
                    .font(.system(size: 13 * k, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(reminders.items.prefix(4).enumerated()), id: \.element.id) { index, item in
                        ReminderRow(item: item, separated: index > 0)
                            .transition(.opacity)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

/// One reminder: an empty circle that fills in the list's colour when clicked, and its title. Rows
/// after the first have a hairline above them, starting where the titles do.
private struct ReminderRow: View {
    @Environment(RemindersModel.self) private var reminders
    @Environment(\.homeScale) private var k
    let item: ReminderItem
    let separated: Bool

    var body: some View {
        let done = reminders.completing.contains(item.id)
        HStack(spacing: 9 * k) {
            Button {
                withAnimation(Motion.press) { reminders.complete(item) }
            } label: {
                ZStack {
                    Circle().strokeBorder(done ? reminders.listColor : .white.opacity(0.32), lineWidth: 1.5 * k)
                    if done {
                        Circle().fill(reminders.listColor).padding(3 * k)
                    }
                }
                .frame(width: 17 * k, height: 17 * k)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Complete \(item.title)")
            Text(item.title)
                .font(.system(size: 13 * k))
                .foregroundStyle(.white.opacity(done ? 0.5 : 1))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 27 * k)
                .overlay(alignment: .top) {
                    if separated {
                        Rectangle().fill(.white.opacity(0.12)).frame(height: 1)
                    }
                }
        }
    }
}
