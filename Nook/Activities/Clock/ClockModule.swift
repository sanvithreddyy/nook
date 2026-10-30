import SwiftUI

/// A place on the world clock.
struct ClockCity: Identifiable, Hashable {
    let timeZone: TimeZone
    var id: String { timeZone.identifier }

    /// "America/New_York" → "New York".
    var name: String {
        (timeZone.identifier.split(separator: "/").last.map(String.init) ?? timeZone.identifier)
            .replacingOccurrences(of: "_", with: " ")
    }

    /// "+16HRS", "−3HRS", "+5:30HRS" from here; "+0HRS" here, as the widget writes it.
    func offset(at date: Date) -> String {
        let seconds = timeZone.secondsFromGMT(for: date) - TimeZone.current.secondsFromGMT(for: date)
        let sign = seconds < 0 ? "−" : "+"
        let hours = abs(seconds) / 3600, minutes = abs(seconds) % 3600 / 60
        return minutes == 0 ? "\(sign)\(hours)HRS" : "\(sign)\(hours):\(String(format: "%02d", minutes))HRS"
    }

    /// "Today", "Tomorrow" or "Yesterday" there, against here.
    func day(at date: Date) -> String {
        var there = Calendar(identifier: .gregorian)
        there.timeZone = timeZone
        let a = there.dateComponents([.year, .month, .day], from: date)
        let b = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let difference = Calendar(identifier: .gregorian).dateComponents([.day], from: b, to: a).day ?? 0
        return difference > 0 ? "Tomorrow" : difference < 0 ? "Yesterday" : "Today"
    }

    /// Here, then three of Apple's usual cities that aren't here.
    static var defaults: [ClockCity] {
        let here = ClockCity(timeZone: .current)
        let others = ["America/Los_Angeles", "America/New_York", "Europe/London", "Asia/Tokyo", "Australia/Sydney"]
            .compactMap(TimeZone.init(identifier:))
            .filter { $0.identifier != here.id }
            .map(ClockCity.init(timeZone:))
        return [here] + others.prefix(3)
    }
}

/// Apple's World Clock widget on the notch: four clocks, each with its city, its day and how far it is
/// from here. A face is white in its daytime and dark at night, as Apple draws them; the second hand ticks.
struct ClockModule: View {
    @Environment(\.homeScale) private var k
    let cities = ClockCity.defaults

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 0) {
                ForEach(cities) { city in
                    VStack(spacing: 0) {
                        ClockFace(date: context.date, timeZone: city.timeZone)
                            .frame(width: 66 * k, height: 66 * k)
                        Text(city.name)
                            .font(.system(size: 12.5 * k, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .padding(.top, 9 * k)
                        Group {
                            Text(city.day(at: context.date))
                            Text(city.offset(at: context.date))
                        }
                        .font(.system(size: 11 * k, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(city.name), \(context.date.formatted(Date.FormatStyle(time: .shortened, timeZone: city.timeZone)))")
                }
            }
            .frame(maxHeight: .infinity)
        }
    }
}

/// An analog face with its twelve numbers, the hour and minute hands narrowing to a thin neck at the
/// centre, and an orange second hand.
private struct ClockFace: View {
    let date: Date
    let timeZone: TimeZone

    var body: some View {
        Canvas { context, size in
            let r = min(size.width, size.height) / 2
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            let now = calendar.dateComponents([.hour, .minute, .second], from: date)
            let hour = Double(now.hour ?? 0), minute = Double(now.minute ?? 0), second = Double(now.second ?? 0)
            let day = (6..<18).contains(now.hour ?? 0)
            let face = day ? Color.white : Color(white: 0.24)
            let ink = day ? Color.black : Color.white

            context.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(face))
            for n in 1...12 {
                let angle = Double(n) / 12 * 2 * .pi
                let at = CGPoint(x: c.x + sin(angle) * r * 0.76, y: c.y - cos(angle) * r * 0.76)
                context.draw(Text("\(n)").font(.system(size: r * 0.235, weight: .semibold)).foregroundStyle(ink), at: at)
            }

            func point(_ fraction: Double, _ length: CGFloat) -> CGPoint {
                let angle = fraction * 2 * .pi
                return CGPoint(x: c.x + sin(angle) * length, y: c.y - cos(angle) * length)
            }
            func hand(_ fraction: Double, length: CGFloat, color: Color) {
                var neck = Path()
                neck.move(to: c)
                neck.addLine(to: point(fraction, r * 0.16))
                context.stroke(neck, with: .color(color), style: StrokeStyle(lineWidth: r * 0.05, lineCap: .round))
                var blade = Path()
                blade.move(to: point(fraction, r * 0.16))
                blade.addLine(to: point(fraction, length))
                context.stroke(blade, with: .color(color), style: StrokeStyle(lineWidth: r * 0.1, lineCap: .round))
            }
            hand((hour.truncatingRemainder(dividingBy: 12) + minute / 60) / 12, length: r * 0.5, color: ink)
            hand((minute + second / 60) / 60, length: r * 0.8, color: ink)

            var seconds = Path()
            seconds.move(to: point(second / 60 + 0.5, r * 0.18))
            seconds.addLine(to: point(second / 60, r * 0.88))
            context.stroke(seconds, with: .color(.orange), style: StrokeStyle(lineWidth: r * 0.035, lineCap: .round))
            context.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.075, y: c.y - r * 0.075, width: r * 0.15, height: r * 0.15)), with: .color(.orange))
            context.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.03, y: c.y - r * 0.03, width: r * 0.06, height: r * 0.06)), with: .color(face))
        }
    }
}
