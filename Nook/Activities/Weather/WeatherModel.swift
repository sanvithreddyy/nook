import CoreLocation
import Foundation
import Observation

/// What the Weather module shows for one place: the weather now, today's high and low, the next hours.
struct WeatherReport: Equatable, Sendable {
    struct Hour: Equatable, Sendable, Identifiable {
        let time: Date
        let symbol: String
        let temperature: Int
        var id: Date { time }
    }

    let city: String
    /// Marked with the location arrow, as Weather marks My Location.
    var isCurrentLocation = false
    /// The place's own clock, which its hours are told in.
    var timeZone: TimeZone = .current
    let temperature: Int
    let symbol: String
    let condition: String
    let high: Int
    let low: Int
    let hours: [Hour]
}

/// The weather for the places Settings lists: this Mac's location first when it's on, then the cities
/// added. Forecasts come from Open-Meteo (free, no account), read when the island opens and the last
/// read is a quarter of an hour old; nothing runs in between. Asks for the location only from the
/// module's button.
@Observable
final class WeatherModel: NSObject {
    enum LocationAccess { case notDetermined, granted, denied }

    private(set) var reports: [WeatherReport] = []
    private(set) var selected = 0
    private(set) var locationAccess: LocationAccess = .notDetermined
    /// The last read found nothing, though there are places to read.
    private(set) var failed = false

    var report: WeatherReport? { reports.isEmpty ? nil : reports[min(selected, reports.count - 1)] }
    var hasPlaces: Bool { usesLocation || !places.isEmpty }
    /// Waiting on the location: asked for, or turned down.
    var needsLocation: Bool { usesLocation && locationAccess != .granted && places.isEmpty }

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var location: CLLocation?
    @ObservationIgnored private var lastRead: Date?
    @ObservationIgnored private var reading = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        locationAccess = Self.access(manager.authorizationStatus)
    }

    private var usesLocation: Bool { Prefs.bool(Prefs.weatherCurrentLocation) }
    private var places: [Place] { Place.list(from: Prefs.string(Prefs.weatherPlaces)) }

    /// Reads again if the last read is old, or straight away after Settings changes the places.
    func refresh(force: Bool = false) {
        if !force, let lastRead, Date.now.timeIntervalSince(lastRead) < 15 * 60 { return }
        if usesLocation, locationAccess == .granted {
            // The read follows once the location arrives (or fails).
            manager.requestLocation()
        } else {
            read()
        }
    }

    func requestLocation() {
        manager.requestWhenInUseAuthorization()
    }

    /// The next place, after the last back to the first.
    func showNext() {
        guard reports.count > 1 else { return }
        selected = (selected + 1) % reports.count
    }

    private func read() {
        guard !reading else { return }
        var targets: [(name: String?, latitude: Double, longitude: Double)] = []
        if usesLocation, let location {
            targets.append((nil, location.coordinate.latitude, location.coordinate.longitude))
        }
        targets += places.map { ($0.name, $0.latitude, $0.longitude) }
        guard !targets.isEmpty else {
            reports = []
            return
        }
        reading = true
        let fahrenheit = Self.usesFahrenheit
        Task {
            var found: [WeatherReport] = []
            for target in targets {
                guard let data = await Self.forecast(latitude: target.latitude, longitude: target.longitude, fahrenheit: fahrenheit) else { continue }
                var city = target.name
                if city == nil, let location { city = await Self.cityName(at: location) }
                if let report = Self.report(from: data, city: city ?? "My Location", isCurrentLocation: target.name == nil) {
                    found.append(report)
                }
            }
            reading = false
            failed = found.isEmpty
            // A read that found nothing (offline) keeps what was there.
            guard !found.isEmpty else { return }
            reports = found
            selected = min(selected, found.count - 1)
            lastRead = .now
        }
    }

    // MARK: Reading

    /// Fahrenheit or Celsius as Settings picks, or by default as the Mac is set (Language & Region),
    /// as Weather follows it.
    nonisolated static var usesFahrenheit: Bool {
        switch TemperatureUnit(rawValue: UserDefaults.standard.string(forKey: Prefs.weatherUnit) ?? "") ?? .auto {
        case .fahrenheit: return true
        case .celsius: return false
        case .auto:
            if let unit = UserDefaults.standard.string(forKey: "AppleTemperatureUnit") { return unit == "Fahrenheit" }
            return Locale.current.measurementSystem == .us
        }
    }

    nonisolated private static func forecast(latitude: Double, longitude: Double, fahrenheit: Bool) async -> Data? {
        var url = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        url.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.3f", latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.3f", longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "hourly", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "temperature_unit", value: fahrenheit ? "fahrenheit" : "celsius"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "2"),
        ]
        guard let (data, response) = try? await URLSession.shared.data(from: url.url!),
              (response as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        return data
    }

    nonisolated private static func cityName(at location: CLLocation) async -> String? {
        (try? await CLGeocoder().reverseGeocodeLocation(location))?.first?.locality
    }

    nonisolated private struct Forecast: Decodable {
        struct Current: Decodable {
            let temperature_2m: Double
            let weather_code: Int
            let is_day: Int
        }

        struct Hourly: Decodable {
            let time: [String]
            let temperature_2m: [Double]
            let weather_code: [Int]
            let is_day: [Int]
        }

        struct Daily: Decodable {
            let temperature_2m_max: [Double]
            let temperature_2m_min: [Double]
        }

        let timezone: String
        let utc_offset_seconds: Int
        let current: Current
        let hourly: Hourly
        let daily: Daily
    }

    /// An Open-Meteo forecast as the widget shows it: hours from the next whole hour, six of them.
    nonisolated static func report(from data: Data, city: String, isCurrentLocation: Bool, now: Date = .now) -> WeatherReport? {
        guard let forecast = try? JSONDecoder().decode(Forecast.self, from: data),
              let high = forecast.daily.temperature_2m_max.first, let low = forecast.daily.temperature_2m_min.first
        else { return nil }
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd'T'HH:mm"
        parser.timeZone = TimeZone(secondsFromGMT: forecast.utc_offset_seconds)
        let hourly = forecast.hourly
        let count = min(hourly.time.count, hourly.temperature_2m.count, hourly.weather_code.count, hourly.is_day.count)
        let hours = (0..<count).compactMap { i -> WeatherReport.Hour? in
            guard let time = parser.date(from: hourly.time[i]), time > now else { return nil }
            return WeatherReport.Hour(time: time, symbol: sky(code: hourly.weather_code[i], isDay: hourly.is_day[i] == 1).symbol,
                                      temperature: Int(hourly.temperature_2m[i].rounded()))
        }
        let now = sky(code: forecast.current.weather_code, isDay: forecast.current.is_day == 1)
        return WeatherReport(city: city, isCurrentLocation: isCurrentLocation,
                             timeZone: TimeZone(identifier: forecast.timezone) ?? TimeZone(secondsFromGMT: forecast.utc_offset_seconds) ?? .current,
                             temperature: Int(forecast.current.temperature_2m.rounded()), symbol: now.symbol, condition: now.condition,
                             high: Int(high.rounded()), low: Int(low.rounded()), hours: Array(hours.prefix(6)))
    }

    /// A WMO weather code as Weather names and draws it.
    nonisolated static func sky(code: Int, isDay: Bool) -> (symbol: String, condition: String) {
        switch code {
        case 0: isDay ? ("sun.max.fill", "Sunny") : ("moon.stars.fill", "Clear")
        case 1: isDay ? ("sun.max.fill", "Mostly Sunny") : ("moon.stars.fill", "Mostly Clear")
        case 2: isDay ? ("cloud.sun.fill", "Partly Cloudy") : ("cloud.moon.fill", "Partly Cloudy")
        case 45, 48: ("cloud.fog.fill", "Foggy")
        case 51, 53, 55: ("cloud.drizzle.fill", "Drizzle")
        case 56, 57, 66, 67: ("cloud.sleet.fill", "Freezing Rain")
        case 61, 63, 80, 81: ("cloud.rain.fill", "Rain")
        case 65, 82: ("cloud.heavyrain.fill", "Heavy Rain")
        case 71, 73, 77, 85: ("cloud.snow.fill", "Snow")
        case 75, 86: ("snowflake", "Heavy Snow")
        case 95, 96, 99: ("cloud.bolt.rain.fill", "Thunderstorms")
        default: ("cloud.fill", "Cloudy")
        }
    }

    nonisolated private static func access(_ status: CLAuthorizationStatus) -> LocationAccess {
        switch status {
        case .notDetermined: .notDetermined
        case .denied, .restricted: .denied
        default: .granted
        }
    }

    #if DEBUG
    /// A mild afternoon, for designing and capturing the module.
    func debugPreview() {
        let hour = (Calendar.current.dateInterval(of: .hour, for: .now)?.start ?? .now).addingTimeInterval(3600)
        let hours = zip([73, 74, 74, 72, 69, 66], ["sun.max.fill", "sun.max.fill", "cloud.sun.fill", "cloud.sun.fill", "cloud.fill", "cloud.moon.fill"])
            .enumerated()
            .map { WeatherReport.Hour(time: hour.addingTimeInterval(Double($0.offset) * 3600), symbol: $0.element.1, temperature: $0.element.0) }
        reports = [WeatherReport(city: "Cupertino", isCurrentLocation: true, temperature: 72, symbol: "sun.max.fill", condition: "Sunny",
                                 high: 75, low: 58, hours: hours)]
        lastRead = .distantFuture
    }
    #endif
}

extension WeatherModel: @preconcurrency CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        locationAccess = Self.access(manager.authorizationStatus)
        if locationAccess == .granted, usesLocation { manager.requestLocation() } else { read() }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        location = locations.last
        read()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        // The cities still read; a later open asks for the location again.
        read()
    }
}

/// The weather's unit: as the Mac is set, or always one.
nonisolated enum TemperatureUnit: String, CaseIterable, Identifiable {
    case auto, fahrenheit, celsius

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: "Auto"
        case .fahrenheit: "°F"
        case .celsius: "°C"
        }
    }
}
