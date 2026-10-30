import SwiftUI

/// A place on the world clock.
struct ClockCity: Identifiable, Hashable {
    let name: String
    let timeZone: TimeZone
    var id: String { "\(name)@\(timeZone.identifier)" }

    init(name: String, timeZone: TimeZone) {
        self.name = name
        self.timeZone = timeZone
    }

    /// Named after its zone: "America/New_York" → "New York".
    init(timeZone: TimeZone) {
        let city = timeZone.identifier.split(separator: "/").last.map(String.init) ?? timeZone.identifier
        self.init(name: city.replacingOccurrences(of: "_", with: " "), timeZone: timeZone)
    }

    /// The cities Settings picked (four at most), or here and three of Apple's usual ones before any
    /// were picked.
    static func saved(_ json: String) -> [ClockCity] {
        json.isEmpty ? defaults : Place.list(from: json).prefix(4).map { ClockCity(name: $0.name, timeZone: $0.timeZone) }
    }

    /// "+16HRS", "−3HRS", "+5:30HRS" from here; "+0HRS" here, as the widget writes it.
    func offset(at date: Date, from here: TimeZone = .current) -> String {
        let seconds = timeZone.secondsFromGMT(for: date) - here.secondsFromGMT(for: date)
        let sign = seconds < 0 ? "−" : "+"
        let hours = abs(seconds) / 3600, minutes = abs(seconds) % 3600 / 60
        return minutes == 0 ? "\(sign)\(hours)HRS" : "\(sign)\(hours):\(String(format: "%02d", minutes))HRS"
    }

    /// "Today", "Tomorrow" or "Yesterday" there, against here.
    func day(at date: Date, from here: TimeZone = .current) -> String {
        var there = Calendar(identifier: .gregorian)
        there.timeZone = timeZone
        var ours = Calendar(identifier: .gregorian)
        ours.timeZone = here
        let a = there.dateComponents([.year, .month, .day], from: date)
        let b = ours.dateComponents([.year, .month, .day], from: date)
        let difference = Calendar(identifier: .gregorian).dateComponents([.day], from: b, to: a).day ?? 0
        return difference > 0 ? "Tomorrow" : difference < 0 ? "Yesterday" : "Today"
    }

    /// Here, then three of Apple's usual cities that aren't here.
    static var defaults: [ClockCity] {
        let here = ClockCity(timeZone: .current)
        let others = ["America/Los_Angeles", "America/New_York", "Europe/London", "Asia/Tokyo", "Australia/Sydney"]
            .compactMap(TimeZone.init(identifier:))
            .filter { $0.identifier != here.timeZone.identifier }
            .map { ClockCity(timeZone: $0) }
        return [here] + others.prefix(3)
    }
}

/// How the World Clock tells the time: Apple's faces, or the time in digits as Clock's list shows it.
enum ClockStyle: String, CaseIterable, Identifiable {
    case analog, digital

    var id: String { rawValue }

    var title: String {
        switch self {
        case .analog: "Analog"
        case .digital: "Digital"
        }
    }
}

/// Apple's World Clock widget on the notch: four clocks, each with its city, its day and how far it is
/// from here. A face is white in its daytime and dark at night, as Apple draws them; the second hand ticks.
struct ClockModule: View {
    @Environment(\.homeScale) private var k
    @AppStorage(Prefs.clockPlaces) private var placesJSON = ""
    @AppStorage(Prefs.clockStyle) private var style = ClockStyle.analog

    var body: some View {
        let cities = ClockCity.saved(placesJSON)
        // Faces tick each second; digits change on the minute.
        let minute = Calendar.current.dateInterval(of: .minute, for: .now)?.start ?? .now
        TimelineView(.periodic(from: minute, by: style == .analog ? 1 : 60)) { context in
            HStack(spacing: 0) {
                ForEach(cities) { city in
                    VStack(spacing: 0) {
                        Group {
                            switch style {
                            case .analog:
                                ClockFace(date: context.date, timeZone: city.timeZone)
                                    .frame(width: 66 * k)
                            case .digital:
                                // One size for all, set by how many share the width: "10:30 PM" fits four across.
                                DigitalTime(date: context.date, timeZone: city.timeZone, size: cities.count > 3 ? 22 : cities.count > 2 ? 26 : 30)
                                    .padding(.horizontal, 3 * k)
                            }
                        }
                        .frame(height: 66 * k)
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

/// The time there in large light digits, AM or PM small beside them where the Mac uses a 12-hour clock,
/// as Clock's World Clock list writes it.
private struct DigitalTime: View {
    @Environment(\.homeScale) private var k
    let date: Date
    let timeZone: TimeZone
    let size: CGFloat

    var body: some View {
        let style = Date.FormatStyle(timeZone: timeZone)
        let digits = Text(date.formatted(style.hour(.defaultDigits(amPM: .omitted)).minute()))
            .font(.system(size: size * k, weight: .light).monospacedDigit())
        let half = Text(Self.twelveHour ? " " + date.formatted(style.hour(.defaultDigits(amPM: .abbreviated))).filter(\.isLetter) : "")
            .font(.system(size: 11 * k, weight: .semibold))
        // One text, so a time too wide for its column shrinks rather than overlapping its neighbour.
        Text("\(digits)\(half)")
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .contentTransition(.numericText())
    }

    private static let twelveHour = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current)?.contains("a") ?? false
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
