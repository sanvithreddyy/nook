import Foundation
import Observation

/// What the Weather module shows: the place, the weather now, today's high and low, the next hours.
struct WeatherReport: Equatable, Sendable {
    struct Hour: Equatable, Sendable, Identifiable {
        let time: Date
        let symbol: String
        let temperature: Int
        var id: Date { time }
    }

    let city: String
    let temperature: Int
    let symbol: String
    let condition: String
    let high: Int
    let low: Int
    let hours: [Hour]
}

@Observable
final class WeatherModel {
    private(set) var report: WeatherReport?

    #if DEBUG
    /// A mild afternoon, for designing and capturing the module.
    func debugPreview() {
        let hour = (Calendar.current.dateInterval(of: .hour, for: .now)?.start ?? .now).addingTimeInterval(3600)
        let hours = zip([73, 74, 74, 72, 69, 66], ["sun.max.fill", "sun.max.fill", "cloud.sun.fill", "cloud.sun.fill", "cloud.fill", "cloud.moon.fill"])
            .enumerated()
            .map { WeatherReport.Hour(time: hour.addingTimeInterval(Double($0.offset) * 3600), symbol: $0.element.1, temperature: $0.element.0) }
        report = WeatherReport(city: "Cupertino", temperature: 72, symbol: "sun.max.fill", condition: "Sunny",
                               high: 75, low: 58, hours: hours)
    }
    #endif
}
