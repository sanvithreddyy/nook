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
                    .foregroundStyle(.white)
            } else {
                TimelineView(.everyMinute) { context in
                    let text = EventTiming.short(event, now: context.date)
                    Text(text)
                        .font(.system(size: 12.5, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .contentTransition(.numericText(countsDown: true))
                        .animation(Motion.level, value: text)
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

// MARK: Cards

/// An event about to start or under way, laid out like Apple's AirDrop request: the icon beside the
/// notch, the title and one grey line under it, then Dismiss and Join.
struct MeetingCard: View {
    @Environment(CalendarModel.self) private var calendar
    @Environment(NotchModel.self) private var model
    let eventID: String

    var body: some View {
        if let event = calendar.event(id: eventID) {
            TimelineView(.everyMinute) { context in
                VStack(alignment: .leading, spacing: 0) {
                    CardGlyph(symbol: "calendar")
                    EventHeading(title: event.title,
                                 detail: [EventTiming.relative(event, now: context.date), event.meetingService ?? EventTiming.range(event)])
                    Spacer(minLength: 0)
                    HStack(spacing: 10) {
                        CardButton("Dismiss") {
                            model.collapse()
                            calendar.dismiss(event.id)
                        }
                        if let url = event.joinURL {
                            CardButton("Join", style: .primary) {
                                model.collapse()
                                NSWorkspace.shared.open(url)
                            }
                        } else {
                            CardButton("Open Calendar", style: .primary) {
                                model.collapse()
                                CalendarModel.openCalendarApp()
                            }
                        }
                    }
                    .padding(.bottom, Card.inset)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }
}

/// The next event, then the rest of the month scrolling under it. Without calendar access, the prompt.
struct UpNextCard: View {
    @Environment(CalendarModel.self) private var calendar

    var body: some View {
        if calendar.access == .granted {
            TimelineView(.everyMinute) { context in
                let upcoming = calendar.upcoming(now: context.date)
                VStack(alignment: .leading, spacing: 0) {
                    CardGlyph(symbol: "calendar")
                    if let next = upcoming.first {
                        HStack(alignment: .bottom, spacing: 12) {
                            EventHeading(title: next.title,
                                         detail: [EventTiming.relative(next, now: context.date), EventTiming.range(next), next.meetingService])
                            if let url = next.joinURL {
                                JoinButton(url: url)
                                    .padding(.bottom, 1)
                            }
                        }
                        Rectangle().fill(.white.opacity(0.09)).frame(height: 1)
                            .padding(.top, 12)
                        LaterByDay(events: Array(upcoming.dropFirst()), now: context.date)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        } else {
            AccessPromptCard()
        }
    }
}

/// Calendar access is missing: ask from here, so nobody is prompted at launch.
private struct AccessPromptCard: View {
    @Environment(CalendarModel.self) private var calendar

    var body: some View {
        let denied = calendar.access == .denied
        VStack(alignment: .leading, spacing: 0) {
            CardGlyph(symbol: "calendar")
            EventHeading(title: denied ? "Calendar access is off" : "See what's coming up", detail: [])
            Spacer(minLength: 0)
            CardButton(denied ? "Open Privacy Settings" : "Allow Calendar Access", style: .primary) {
                if denied {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
                } else {
                    calendar.requestAccess()
                }
            }
            .padding(.bottom, Card.inset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Access granted in System Settings shows up the next time the island opens.
        .onAppear { calendar.recheckAuthorization() }
    }
}

/// A card's icon, in the wing left of the notch.
struct CardGlyph: View {
    @Environment(NotchModel.self) private var model
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(.white)
            .frame(height: model.notch.size.height, alignment: .center)
            .accessibilityHidden(true)
    }
}

/// Title and one grey line, just under the notch line.
private struct EventHeading: View {
    let title: String
    let detail: [String?]

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            let line = detail.compactMap { $0 }.joined(separator: " · ")
            if !line.isEmpty {
                Text(line)
                    .font(.system(size: 13).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Card.titleGap)
    }
}

/// The only filled button on the Up next card.
private struct JoinButton: View {
    let url: URL

    var body: some View {
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

/// Everything after the next event, under a caption per day. Scrolls; the bottom edge fades so it's clear there's more.
private struct LaterByDay: View {
    let events: [CalendarEvent]
    let now: Date
    /// Space above the first day: room below the divider, or none beside the next event.
    var topInset: CGFloat = 8

    var body: some View {
        let days = Dictionary(grouping: events) { Calendar.current.startOfDay(for: $0.start) }.sorted { $0.key < $1.key }
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(days, id: \.key) { day in
                    Caption(EventTiming.dayName(day.key, now: now), bright: false)
                        .padding(.top, day.key == days.first?.key ? topInset : 10)
                        .padding(.bottom, 2)
                    ForEach(day.value) { event in
                        LaterRow(event: event, time: event.start.formatted(date: .omitted, time: .shortened))
                    }
                }
            }
            .padding(.bottom, 14)
        }
        .scrollIndicators(.never)
        .mask {
            VStack(spacing: 0) {
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

enum EventTiming {
    /// Beside the notch: "5 min", "Now", or the start time.
    static func short(_ event: CalendarEvent, now: Date) -> String {
        let minutes = Int((event.start.timeIntervalSince(now) / 60).rounded(.up))
        if minutes <= 0 { return "Now" }
        if minutes < 60 { return "\(minutes) min" }
        return event.start.formatted(date: .omitted, time: .shortened)
    }

    /// In the drop beside a playing track, where there's room for three characters: "5m", "Now".
    static func minimal(_ event: CalendarEvent, now: Date) -> String {
        let minutes = Int((event.start.timeIntervalSince(now) / 60).rounded(.up))
        if minutes <= 0 { return "Now" }
        return minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h"
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

    /// "Today", "Tomorrow", "Monday" within the week, then "Mon, Nov 2".
    static func dayName(_ date: Date, now: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) { return "Tomorrow" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
        return days < 7 ? date.formatted(.dateTime.weekday(.wide)) : date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }
}
