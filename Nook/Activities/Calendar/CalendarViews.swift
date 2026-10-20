import AppKit
import SwiftUI

struct CalendarActivitySide: View {
    @Environment(CalendarModel.self) private var calendar
    let eventID: String
    let edge: HorizontalEdge

    var body: some View {
        if let event = calendar.event(id: eventID) {
            if edge == .leading {
                Image(systemName: "calendar")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(event.color)
            } else {
                TimelineView(.everyMinute) { context in
                    Text(EventTiming.short(event, now: context.date))
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white)
                }
            }
        }
    }
}

struct EventPeek: View {
    @Environment(CalendarModel.self) private var calendar
    let eventID: String

    var body: some View {
        if let event = calendar.event(id: eventID) {
            MarqueeText(id: event.id) {
                Text("\(Text(event.title).foregroundStyle(.white))\(Text("  ·  \(EventTiming.range(event))").foregroundStyle(.white.opacity(0.55)))")
                    .font(.system(size: 13, weight: .medium))
            }
        }
    }
}

/// The calendar half of the expanded island: this week as a strip of days, the chosen day's events below.
struct CalendarColumn: View {
    @Environment(CalendarModel.self) private var calendar
    @State private var selected = Calendar.current.startOfDay(for: .now)

    var body: some View {
        switch calendar.access {
        case .granted:
            VStack(alignment: .leading, spacing: 8) {
                WeekStrip(selected: $selected)
                Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
                DayEvents(day: selected)
            }
            // Roll the selection forward when the week moves past it (overnight).
            .onChange(of: calendar.weekStart) { _, start in
                if selected < start { selected = start }
            }
        case .notDetermined:
            AccessPrompt(message: "See your week here", button: "Allow access") { calendar.requestAccess() }
                // Access granted from Settings or System Settings shows up the next time the island opens.
                .onAppear { calendar.recheckAuthorization() }
        case .denied:
            AccessPrompt(message: "Calendar access is off", button: "Open Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
            }
            .onAppear { calendar.recheckAuthorization() }
        }
    }
}

private struct AccessPrompt: View {
    let message: String
    let button: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.55))
            Button(action: action) {
                Text(button)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct WeekStrip: View {
    @Environment(CalendarModel.self) private var calendar
    @Binding var selected: Date

    private var days: [Date] {
        let today = Calendar.current.startOfDay(for: .now)
        return (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: today) }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(selected.formatted(.dateTime.month(.wide)))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            Spacer(minLength: 8)
            HStack(spacing: 2) {
                ForEach(days, id: \.self) { day in
                    DayCell(day: day,
                            isSelected: Calendar.current.isDate(day, inSameDayAs: selected),
                            hasEvents: !calendar.events(on: day).isEmpty)
                        .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { selected = day } }
                }
            }
        }
    }
}

private struct DayCell: View {
    let day: Date
    let isSelected: Bool
    let hasEvents: Bool

    private var isToday: Bool { Calendar.current.isDateInToday(day) }

    var body: some View {
        VStack(spacing: 2) {
            Text(day.formatted(.dateTime.weekday(.narrow)))
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
            Text(day.formatted(.dateTime.day()))
                .font(.system(size: 12.5, weight: isToday ? .bold : .medium).monospacedDigit())
                .foregroundStyle(isSelected ? .black : .white.opacity(isToday ? 1 : 0.8))
                .frame(width: 24, height: 24)
                .background(Circle().fill(isSelected ? .white : .clear))
            Circle()
                .fill(.white.opacity(hasEvents && !isSelected ? 0.45 : 0))
                .frame(width: 3, height: 3)
        }
        .frame(width: 26)
        .contentShape(Rectangle())
    }
}

private struct DayEvents: View {
    @Environment(CalendarModel.self) private var calendar
    let day: Date

    var body: some View {
        let events = calendar.events(on: day)
        if events.isEmpty {
            Text(Calendar.current.isDateInToday(day) ? "Nothing else today" : "No events")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.45))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, 2)
        } else {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(events) { event in
                        EventRow(event: event, day: day)
                    }
                }
            }
            .scrollIndicators(.never)
        }
    }
}

private struct EventRow: View {
    let event: CalendarEvent
    let day: Date

    /// A timed event that began on an earlier day shows when it ends instead.
    private var timeLabel: String {
        if event.isAllDay { return "All day" }
        if event.start < Calendar.current.startOfDay(for: day) {
            return "→ " + event.end.formatted(date: .omitted, time: .shortened)
        }
        return event.start.formatted(date: .omitted, time: .shortened)
    }

    var body: some View {
        TimelineView(.everyMinute) { context in
            let now = context.date
            let isPast = event.end <= now
            let isNow = event.start <= now && event.end > now && !event.isAllDay
            HStack(spacing: 8) {
                Circle().fill(event.color).frame(width: 6, height: 6)
                Text(isNow ? "Now" : timeLabel)
                    .font(.system(size: 11, weight: isNow ? .semibold : .regular).monospacedDigit())
                    .foregroundStyle(.white.opacity(isNow ? 0.9 : 0.5))
                    .frame(width: 58, alignment: .leading)
                Text(event.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let url = event.joinURL, !isPast {
                    Button { NSWorkspace.shared.open(url) } label: {
                        Text("Join")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(.white.opacity(isNow ? 0.22 : 0.1)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .opacity(isPast ? 0.4 : 1)
        }
    }
}

enum EventTiming {
    static func short(_ event: CalendarEvent, now: Date) -> String {
        let minutes = Int((event.start.timeIntervalSince(now) / 60).rounded(.up))
        if minutes <= 0 { return "Now" }
        if minutes < 60 { return "in \(minutes)m" }
        return event.start.formatted(date: .omitted, time: .shortened)
    }

    static func range(_ event: CalendarEvent) -> String {
        if event.isAllDay { return "All day" }
        let start = event.start.formatted(date: .omitted, time: .shortened)
        let end = event.end.formatted(date: .omitted, time: .shortened)
        return "\(start) – \(end)"
    }
}
