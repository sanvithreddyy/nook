import AppKit
import SwiftUI

struct CalendarActivitySide: View {
    @Environment(CalendarModel.self) private var calendar
    @Environment(NotchModel.self) private var model
    let eventID: String
    let edge: HorizontalEdge

    var body: some View {
        if let event = calendar.event(id: eventID) {
            if edge == .leading {
                Image(systemName: "calendar")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .concentric(.leading, height: model.notch.size.height)
            } else {
                TimelineView(.minutes(to: event.start)) { context in
                    let text = EventTiming.short(event, now: context.date)
                    Text(text)
                        .font(.system(size: Compact.fontSize, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .contentTransition(.numericText(countsDown: true))
                        .animation(Motion.level, value: text)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, Compact.outer)
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

extension TimelineSchedule where Self == PeriodicTimelineSchedule {
    /// Once a minute, on the minutes counted to `start`, so a countdown turns to "Now" as it starts.
    static func minutes(to start: Date) -> PeriodicTimelineSchedule {
        .periodic(from: start.addingTimeInterval(-86_400), by: 60)
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
