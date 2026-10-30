import AppKit
import SwiftUI

/// Apple's Calendar widget on the notch: the day on the left (red weekday, large date, that day's
/// events), the month on the right. Click a date to see that day; click the large date to come back
/// to today. Next month is a click away on the chevrons that show when the pointer is over the month.
struct CalendarModule: View {
    @Environment(\.homeScale) private var k
    /// Nil is today, so the module follows the date past midnight.
    @State private var selected: Date?
    @State private var monthOffset = 0

    init() {
        #if DEBUG
        // -select-day N: open on the day N days from today, for captures.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "-select-day"), i + 1 < args.count, let days = Int(args[i + 1]) {
            _selected = State(initialValue: Calendar.current.date(byAdding: .day, value: days, to: Calendar.current.startOfDay(for: .now)))
        }
        #endif
    }

    var body: some View {
        TimelineView(.everyMinute) { context in
            let today = Calendar.current.startOfDay(for: context.date)
            let day = selected ?? today
            HStack(alignment: .top, spacing: 14 * k) {
                DayColumn(day: day, today: today, now: context.date) {
                    withAnimation(Motion.content) {
                        selected = nil
                        monthOffset = 0
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                MonthGrid(today: today, selected: day, offset: $monthOffset) { date in
                    withAnimation(Motion.content) { selected = date == today ? nil : date }
                }
                .frame(width: 164 * k)
            }
        }
    }
}

// MARK: Day

private struct DayColumn: View {
    @Environment(CalendarModel.self) private var calendar
    @Environment(\.homeScale) private var k
    let day: Date
    let today: Date
    let now: Date
    let backToToday: () -> Void

    var body: some View {
        let isToday = day == today
        VStack(alignment: .leading, spacing: 0) {
            Button(action: backToToday) {
                VStack(alignment: .leading, spacing: 0) {
                    ModuleHeading(text: day.formatted(.dateTime.weekday(.wide)))
                    Text(day.formatted(.dateTime.day()))
                        .font(.system(size: 44 * k, weight: .light))
                        .tracking(-1.3 * k)
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                        .frame(height: 46 * k)
                        .padding(.top, 2 * k)
                }
                .contentShape(Rectangle())
            }
            // Not disabled on today: a disabled button dims its label.
            .buttonStyle(.plain)
            .help(isToday ? "" : "Back to today")
            if calendar.access == .granted {
                let events = calendar.events(on: day, now: now)
                if events.isEmpty {
                    Text(isToday ? "No more events today" : "No events")
                        .font(.system(size: 13 * k, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.top, 8 * k)
                } else {
                    ForEach(events.prefix(2)) { EventBlock(event: $0) }
                    if events.count > 2 {
                        Text(events.count == 3 ? "1 more event" : "\(events.count - 2) more events")
                            .font(.system(size: 11.5 * k))
                            .foregroundStyle(.white.opacity(0.6))
                            .padding(.top, 5 * k)
                    }
                }
            } else {
                AccessButton()
                    .padding(.top, 10 * k)
            }
        }
    }
}

/// An event as the Calendar widget draws it: a block tinted with its calendar's colour, the title
/// and time in a lighter shade of it. Click to open it in Calendar.
private struct EventBlock: View {
    @Environment(\.homeScale) private var k
    let event: CalendarEvent
    @State private var hovering = false

    var body: some View {
        Button { CalendarModel.open(event) } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text(event.title)
                    .font(.system(size: 12.5 * k, weight: .semibold))
                    .foregroundStyle(event.color.towardWhite(0.45))
                    .lineLimit(1)
                Text(EventTiming.range(event))
                    .font(.system(size: 11.5 * k).monospacedDigit())
                    .foregroundStyle(event.color.towardWhite(0.3).opacity(0.8))
                    .lineLimit(1)
            }
            .padding(.horizontal, 8 * k)
            .padding(.top, 4 * k)
            .padding(.bottom, 5 * k)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 7 * k, style: .continuous).fill(event.color.opacity(hovering ? 0.32 : 0.24)))
            .contentShape(RoundedRectangle(cornerRadius: 7 * k, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { inside in withAnimation(.easeOut(duration: 0.15)) { hovering = inside } }
        .padding(.top, 5 * k)
        .help("Open in Calendar")
        .accessibilityLabel("\(event.title), \(EventTiming.range(event))")
    }
}

/// Without calendar access the widget still shows the date and month; the events' place holds the ask.
private struct AccessButton: View {
    @Environment(CalendarModel.self) private var calendar
    @Environment(\.homeScale) private var k

    var body: some View {
        let denied = calendar.access == .denied
        Button {
            if denied {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
            } else {
                calendar.requestAccess()
            }
        } label: {
            Text(denied ? "Allow in Settings" : "Show Events")
                .font(.system(size: 12 * k, weight: .semibold))
                .padding(.horizontal, 12 * k)
                .frame(height: 26 * k)
        }
        .buttonStyle(CardButtonStyle(style: .primary))
    }
}

// MARK: Month

private struct MonthGrid: View {
    @Environment(CalendarModel.self) private var calendar
    @Environment(\.homeScale) private var k
    @AppStorage(Prefs.calendarWeekStart) private var weekStart = WeekStart.system.rawValue
    @AppStorage(Prefs.calendarDots) private var dots = false
    @AppStorage(Prefs.calendarDimWeekends) private var dimWeekends = true
    let today: Date
    let selected: Date
    @Binding var offset: Int
    let pick: (Date) -> Void
    @State private var hovering = false

    /// This month and the next: the events Nook reads reach that far.
    private static let months = 2

    var body: some View {
        let cal = calendarStarting(on: WeekStart(rawValue: weekStart) ?? .system)
        let thisMonth = cal.dateInterval(of: .month, for: today)?.start ?? today
        let month = cal.date(byAdding: .month, value: offset, to: thisMonth) ?? thisMonth
        let days = cal.range(of: .day, in: .month, for: month)?.count ?? 30
        let lead = (cal.component(.weekday, from: month) - cal.firstWeekday + 7) % 7
        let rows = (lead + days + 6) / 7
        // Six-week months tighten their rows to stay in the module's height.
        let row = min(21, (HomeMetrics.height - 31) / CGFloat(rows)) * k
        let busy = dots && calendar.access == .granted ? calendar.busyDays : []

        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ModuleHeading(text: month.formatted(.dateTime.month(.wide)))
                Spacer(minLength: 0)
                if hovering {
                    HStack(spacing: 2 * k) {
                        Chevron(symbol: "chevron.left", label: "Previous month", enabled: offset > 0) { offset -= 1 }
                        Chevron(symbol: "chevron.right", label: "Next month", enabled: offset < Self.months - 1) { offset += 1 }
                    }
                    .transition(.opacity)
                }
            }
            .frame(height: 13 * k)
            .padding(.bottom, 2 * k)
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { column in
                    let weekday = (cal.firstWeekday - 1 + column) % 7
                    Text(cal.veryShortStandaloneWeekdaySymbols[weekday])
                        .font(.system(size: 10.5 * k, weight: .semibold))
                        .foregroundStyle(.white.opacity(dimWeekends && Self.isWeekend(weekday) ? 0.42 : 0.85))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 16 * k)
            ForEach(0..<rows, id: \.self) { r in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { c in
                        let number = r * 7 + c - lead + 1
                        if number >= 1, number <= days, let date = cal.date(byAdding: .day, value: number - 1, to: month) {
                            DayCell(number: number,
                                    isToday: date == today,
                                    isSelected: date == selected,
                                    isWeekend: dimWeekends && cal.isDateInWeekend(date),
                                    isBusy: busy.contains(date)) { pick(date) }
                        } else {
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                }
                .frame(height: row)
            }
        }
        .contentTransition(.numericText())
        .animation(Motion.content, value: offset)
        .onHover { inside in withAnimation(.easeOut(duration: 0.15)) { hovering = inside } }
    }

    /// Calendar's weekday numbering from 0: Sunday and Saturday.
    private static func isWeekend(_ weekday: Int) -> Bool { weekday == 0 || weekday == 6 }

    private func calendarStarting(on start: WeekStart) -> Calendar {
        var cal = Calendar.current
        cal.firstWeekday = start.firstWeekday
        return cal
    }
}

private struct DayCell: View {
    @Environment(\.homeScale) private var k
    let number: Int
    let isToday: Bool
    let isSelected: Bool
    let isWeekend: Bool
    let isBusy: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text("\(number)")
                .font(.system(size: 12.5 * k, weight: isToday || isSelected ? .semibold : .medium).monospacedDigit())
                .foregroundStyle(isSelected && !isToday ? .black : .white.opacity(isWeekend && !isToday ? 0.42 : 1))
                .frame(width: 20 * k, height: 20 * k)
                .background(Circle().fill(fill))
                .overlay(alignment: .bottom) {
                    if isBusy, !isToday, !isSelected {
                        Circle().fill(.white.opacity(0.55)).frame(width: 3 * k, height: 3 * k).padding(.bottom, 1 * k)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var fill: Color {
        if isToday { return .red }
        if isSelected { return .white }
        return .white.opacity(hovering ? 0.14 : 0)
    }
}

private struct Chevron: View {
    @Environment(\.homeScale) private var k
    let symbol: String
    let label: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10 * k, weight: .bold))
                .foregroundStyle(.white.opacity(enabled ? 0.7 : 0.2))
                .frame(width: 16 * k, height: 14 * k)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}

extension Color {
    /// The colour moved toward white, as the Calendar widget lightens a calendar's colour for text on its tint.
    func towardWhite(_ fraction: CGFloat) -> Color {
        guard let color = NSColor(self).usingColorSpace(.sRGB) else { return self }
        return Color(nsColor: color.blended(withFraction: fraction, of: .white) ?? color)
    }
}
