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

/// Beside the player: the event under way or next, then the two after it.
struct AgendaColumn: View {
    @Environment(CalendarModel.self) private var calendar

    var body: some View {
        if calendar.access == .granted {
            TimelineView(.everyMinute) { context in
                let upcoming = calendar.upcoming(now: context.date)
                VStack(alignment: .leading, spacing: 0) {
                    if let next = upcoming.first {
                        HStack(spacing: 12) {
                            UpNext(event: next, now: context.date, titleSize: 16)
                            Spacer(minLength: 0)
                            JoinButton(url: next.joinURL)
                        }
                        Rectangle().fill(.white.opacity(0.09)).frame(height: 1)
                            .padding(.top, 12).padding(.bottom, 5)
                        ForEach(upcoming.dropFirst().prefix(2)) { event in
                            LaterRow(event: event, time: EventTiming.dayAndTime(event, now: context.date))
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        } else {
            AccessPrompt()
        }
    }
}

/// Nothing playing: the next event takes the player's place, and the rest of the week sits beside it.
struct AgendaSpread: View {
    @Environment(CalendarModel.self) private var calendar

    var body: some View {
        if calendar.access == .granted {
            TimelineView(.everyMinute) { context in
                let upcoming = calendar.upcoming(now: context.date)
                HStack(alignment: .top, spacing: 40) {
                    if let next = upcoming.first {
                        VStack(alignment: .leading, spacing: 14) {
                            UpNext(event: next, now: context.date, titleSize: 22)
                            JoinButton(url: next.joinURL)
                        }
                        .frame(width: 300, alignment: .leading)
                    }
                    LaterByDay(events: Array(upcoming.dropFirst().prefix(3)), now: context.date)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        } else {
            AccessPrompt()
        }
    }
}

/// When, what and where for one event: "In 20 min", the title, "2:00 – 2:45 PM · Google Meet".
private struct UpNext: View {
    let event: CalendarEvent
    let now: Date
    let titleSize: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Caption(EventTiming.relative(event, now: now), bright: event.start <= now)
            Text(event.title)
                .font(.system(size: titleSize, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.top, titleSize > 18 ? 6 : 4)
            Text([EventTiming.range(event), event.meetingService].compactMap { $0 }.joined(separator: " · "))
                .font(.system(size: 12.5).monospacedDigit())
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
                .padding(.top, 3)
        }
    }
}

private struct LaterByDay: View {
    let events: [CalendarEvent]
    let now: Date

    var body: some View {
        let days = Dictionary(grouping: events) { Calendar.current.startOfDay(for: $0.start) }.sorted { $0.key < $1.key }
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(days.enumerated()), id: \.element.key) { index, day in
                Caption(EventTiming.dayName(day.key, now: now), bright: false)
                    .padding(.top, index == 0 ? 0 : 10)
                    .padding(.bottom, 3)
                ForEach(day.value) { event in
                    LaterRow(event: event, time: event.start.formatted(date: .omitted, time: .shortened))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LaterRow: View {
    let event: CalendarEvent
    let time: String

    var body: some View {
        HStack(spacing: 10) {
            Text(event.title)
                .foregroundStyle(.white.opacity(0.82))
                .lineLimit(1)
            Spacer(minLength: 0)
            Text(time)
                .foregroundStyle(.white.opacity(0.45))
        }
        .font(.system(size: 12.5).monospacedDigit())
        .frame(height: 22)
    }
}

/// Small capitals above a value: "NOW · 20 MIN LEFT", "TOMORROW". `bright` lifts the first part.
private struct Caption: View {
    let text: String
    let bright: Bool

    init(_ text: String, bright: Bool) {
        self.text = text
        self.bright = bright
    }

    var body: some View {
        let parts = text.split(separator: " · ", maxSplits: 1).map(String.init)
        Group {
            if bright, let head = parts.first {
                Text("\(Text(head.uppercased()).foregroundStyle(.white))\(Text(parts.count > 1 ? " · " + parts[1].uppercased() : ""))")
            } else {
                Text(text.uppercased())
            }
        }
        .font(.system(size: 10.5, weight: .semibold))
        .tracking(0.6)
        .foregroundStyle(.white.opacity(0.45))
        .lineLimit(1)
    }
}

/// The only filled button in the island.
private struct JoinButton: View {
    let url: URL?

    var body: some View {
        if let url {
            Button { NSWorkspace.shared.open(url) } label: {
                Text("Join")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 14)
                    .frame(height: 26)
                    .background(Capsule().fill(.white))
            }
            .buttonStyle(IslandButtonStyle())
        }
    }
}

private struct AccessPrompt: View {
    @Environment(CalendarModel.self) private var calendar

    var body: some View {
        let denied = calendar.access == .denied
        VStack(alignment: .leading, spacing: 12) {
            Text(denied ? "Calendar access is off" : "See what's coming up")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
            Button {
                if denied {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
                } else {
                    calendar.requestAccess()
                }
            } label: {
                Text(denied ? "Open Settings" : "Allow access")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 14)
                    .frame(height: 26)
                    .background(Capsule().fill(.white))
            }
            .buttonStyle(IslandButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        // Access granted in System Settings shows up the next time the island opens.
        .onAppear { calendar.recheckAuthorization() }
    }
}

enum EventTiming {
    static func short(_ event: CalendarEvent, now: Date) -> String {
        let minutes = Int((event.start.timeIntervalSince(now) / 60).rounded(.up))
        if minutes <= 0 { return "Now" }
        if minutes < 60 { return "in \(minutes)m" }
        return event.start.formatted(date: .omitted, time: .shortened)
    }

    /// "10:00 – 10:45 AM": the shared AM/PM is written once.
    static func range(_ event: CalendarEvent) -> String {
        if event.isAllDay { return "All day" }
        return timeRange.string(from: event.start, to: event.end)
    }

    private static let timeRange: DateIntervalFormatter = {
        let formatter = DateIntervalFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    /// "Now · 20 min left", "In 25 min", "Today", "Tomorrow", "Monday".
    static func relative(_ event: CalendarEvent, now: Date) -> String {
        if event.start <= now {
            let left = Int((event.end.timeIntervalSince(now) / 60).rounded(.up))
            return left <= 60 ? "Now · \(left) min left" : "Now · until " + event.end.formatted(date: .omitted, time: .shortened)
        }
        let minutes = Int((event.start.timeIntervalSince(now) / 60).rounded(.up))
        if minutes <= 60 { return "In \(minutes) min" }
        return dayName(event.start, now: now)
    }

    static func dayName(_ date: Date, now: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) { return "Tomorrow" }
        return date.formatted(.dateTime.weekday(.wide))
    }

    /// The time alone for today, with the weekday otherwise: "2:00 PM", "Sun 4:00 PM".
    static func dayAndTime(_ event: CalendarEvent, now: Date) -> String {
        let time = event.start.formatted(date: .omitted, time: .shortened)
        return Calendar.current.isDate(event.start, inSameDayAs: now) ? time : event.start.formatted(.dateTime.weekday(.abbreviated)) + " " + time
    }
}
