import SwiftUI

/// Apple's Reminders widget (medium) on the notch: on the left the list's round icon in its colour,
/// how many are left and the list's name; on the right the first few with their circles. Click a
/// circle to tick it off.
struct RemindersModule: View {
    @Environment(RemindersModel.self) private var reminders
    @Environment(\.homeScale) private var k

    var body: some View {
        HStack(alignment: .top, spacing: 14 * k) {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: "list.bullet")
                    .font(.system(size: 13 * k, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30 * k, height: 30 * k)
                    .background(Circle().fill(reminders.listColor))
                Spacer(minLength: 0)
                Text("\(reminders.items.count)")
                    .font(.system(size: 30 * k, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .contentTransition(.numericText(value: Double(reminders.items.count)))
                Text(reminders.listName)
                    .font(.system(size: 13 * k, weight: .semibold))
                    .foregroundStyle(reminders.listColor)
                    .lineLimit(1)
            }
            .frame(width: 80 * k, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .leading)
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
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.vertical, 4 * k)
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
                .font(.system(size: 13 * k, weight: .medium))
                .foregroundStyle(.white.opacity(done ? 0.5 : 1))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 30 * k)
                .overlay(alignment: .top) {
                    if separated {
                        Rectangle().fill(.white.opacity(0.12)).frame(height: 1)
                    }
                }
        }
    }
}
