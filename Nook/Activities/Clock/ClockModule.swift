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

/// Apple's World Clock on the notch, in either style. Analog: a face per city, as macOS's Clock draws
/// them, with the city, its day and how far it is from here under each; the faces grow into the room
/// the page gives them. Digital: Clock's World Clock list, a row per city with the time large on the right.
struct ClockModule: View {
    @Environment(\.homeScale) private var k
    @AppStorage(Prefs.clockPlaces) private var placesJSON = ""
    @AppStorage(Prefs.clockStyle) private var style = ClockStyle.analog

    var body: some View {
        let cities = ClockCity.saved(placesJSON)
        // Faces tick each second; digits change on the minute.
        let minute = Calendar.current.dateInterval(of: .minute, for: .now)?.start ?? .now
        TimelineView(.periodic(from: minute, by: style == .analog ? 1 : 60)) { context in
            switch style {
            case .analog: AnalogClocks(cities: cities, date: context.date)
            case .digital: DigitalClocks(cities: cities, date: context.date)
            }
        }
    }
}

/// A face per city side by side, each as large as its share of the width and the height left under it
/// for the three lines allow.
private struct AnalogClocks: View {
    @Environment(\.homeScale) private var k
    let cities: [ClockCity]
    let date: Date

    var body: some View {
        GeometryReader { geometry in
            let cell = geometry.size.width / CGFloat(max(cities.count, 1))
            let labels = 52 * k
            let diameter = max(min(cell * 0.8, geometry.size.height - labels, 112 * k), 0)
            HStack(spacing: 0) {
                ForEach(cities) { city in
                    VStack(spacing: 0) {
                        ClockFace(date: date, timeZone: city.timeZone)
                            .frame(width: diameter, height: diameter)
                        Text(city.name)
                            .font(.system(size: 12.5 * k, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .padding(.top, 9 * k)
                        Group {
                            Text(city.day(at: date))
                            Text(city.offset(at: date))
                        }
                        .font(.system(size: 11 * k, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(city.name), \(date.formatted(Date.FormatStyle(time: .shortened, timeZone: city.timeZone)))")
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}

/// Clock's World Clock list: a row per city, "Today, +1HRS" in grey over the city's name on the left and
/// the time in large light digits on the right, hairlines between. The rows share the height.
private struct DigitalClocks: View {
    @Environment(\.homeScale) private var k
    let cities: [ClockCity]
    let date: Date

    var body: some View {
        GeometryReader { geometry in
            let row = geometry.size.height / CGFloat(max(cities.count, 1))
            VStack(spacing: 0) {
                ForEach(Array(cities.enumerated()), id: \.element.id) { index, city in
                    HStack(alignment: .center, spacing: 12 * k) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("\(city.day(at: date)), \(city.offset(at: date))")
                                .font(.system(size: min(max(row * 0.19, 11 * k), 13 * k)))
                                .foregroundStyle(.white.opacity(0.5))
                            Text(city.name)
                                .font(.system(size: min(max(row * 0.28, 14 * k), 21 * k)))
                                .foregroundStyle(.white)
                        }
                        .lineLimit(1)
                        Spacer(minLength: 0)
                        DigitalTime(date: date, timeZone: city.timeZone, size: min(row * 0.6, 46 * k))
                    }
                    .frame(height: row)
                    .overlay(alignment: .top) {
                        if index > 0 { Rectangle().fill(.white.opacity(0.14)).frame(height: 1 / 2) }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(city.name), \(date.formatted(Date.FormatStyle(time: .shortened, timeZone: city.timeZone)))")
                }
            }
        }
    }
}

/// The time there in large light digits, AM or PM smaller in the same weight where the Mac uses a
/// 12-hour clock, as Clock's World Clock list writes it.
private struct DigitalTime: View {
    let date: Date
    let timeZone: TimeZone
    let size: CGFloat

    var body: some View {
        let style = Date.FormatStyle(timeZone: timeZone)
        let digits = Text(date.formatted(style.hour(.defaultDigits(amPM: .omitted)).minute()))
            .font(.system(size: size, weight: .light).monospacedDigit())
        let half = Text(Self.twelveHour ? date.formatted(style.hour(.defaultDigits(amPM: .abbreviated))).filter(\.isLetter) : "")
            .font(.system(size: size * 0.5, weight: .light))
        Text("\(digits)\(Text(Self.twelveHour ? "\u{2009}" : ""))\(half)")
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize()
            .contentTransition(.numericText())
    }

    private static let twelveHour = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current)?.contains("a") ?? false
}

/// An analog face as macOS's Clock draws it, measured from Clock on macOS 27 at 2x: numerals near the rim,
/// thin hands with round ends, a ring at the centre in the hands' colour holding the orange second hand's
/// dot, and the second hand a hairline with a short tail. White in the city's daytime; at night grey,
/// since Clock's black face would vanish on the black island.
private struct ClockFace: View {
    let date: Date
    let timeZone: TimeZone

    /// Clock's second hand, measured.
    private static let orange = Color(red: 0.957, green: 0.655, blue: 0.349)

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
                // Digits sit a little high in their line, so the centre moves down to centre them optically.
                let at = CGPoint(x: c.x + sin(angle) * r * 0.79, y: c.y - cos(angle) * r * 0.79 + r * 0.015)
                context.draw(Text("\(n)").font(.system(size: r * 0.27, weight: .semibold)).foregroundStyle(ink), at: at)
            }

            func point(_ fraction: Double, _ length: CGFloat) -> CGPoint {
                let angle = fraction * 2 * .pi
                return CGPoint(x: c.x + sin(angle) * length, y: c.y - cos(angle) * length)
            }
            func hand(_ fraction: Double, length: CGFloat, width: CGFloat) {
                var line = Path()
                line.move(to: c)
                line.addLine(to: point(fraction, length))
                context.stroke(line, with: .color(ink), style: StrokeStyle(lineWidth: width, lineCap: .round))
            }
            hand((hour.truncatingRemainder(dividingBy: 12) + minute / 60) / 12, length: r * 0.5, width: r * 0.045)
            hand((minute + second / 60) / 60, length: r * 0.9, width: r * 0.038)
            context.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.05, y: c.y - r * 0.05, width: r * 0.1, height: r * 0.1)), with: .color(ink))

            var seconds = Path()
            seconds.move(to: point(second / 60 + 0.5, r * 0.11))
            seconds.addLine(to: point(second / 60, r * 0.9))
            context.stroke(seconds, with: .color(Self.orange), style: StrokeStyle(lineWidth: max(r * 0.017, 1), lineCap: .butt))
            context.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.026, y: c.y - r * 0.026, width: r * 0.052, height: r * 0.052)), with: .color(Self.orange))
        }
    }
}
