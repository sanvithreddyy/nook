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

struct UpNextList: View {
    @Environment(CalendarModel.self) private var calendar

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Up next")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
            if !calendar.isAuthorized {
                Text("Calendar access is off. Allow it in System Settings.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
            } else if calendar.upcoming.isEmpty {
                Text("Nothing else today")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
            } else {
                ForEach(calendar.upcoming.prefix(3)) { event in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle().fill(event.color).frame(width: 6, height: 6)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(event.title)
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Text(EventTiming.range(event))
                                .font(.system(size: 11).monospacedDigit())
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
