import Foundation
import Testing

/// The World Clock's lines under each face, and the cities it shows.
struct ClockCityTests {
    private let chicago = TimeZone(identifier: "America/Chicago")!
    /// Oct 30, 2026, 9 PM in Chicago: already tomorrow in Tokyo, still today in Los Angeles.
    private let evening = ISO8601DateFormatter().date(from: "2026-10-31T02:00:00Z")!

    @Test func offsetsReadAsTheWidgetWritesThem() {
        #expect(ClockCity(timeZone: chicago).offset(at: evening, from: chicago) == "+0HRS")
        #expect(ClockCity(timeZone: TimeZone(identifier: "Asia/Tokyo")!).offset(at: evening, from: chicago) == "+14HRS")
        #expect(ClockCity(timeZone: TimeZone(identifier: "America/Los_Angeles")!).offset(at: evening, from: chicago) == "−2HRS")
        #expect(ClockCity(timeZone: TimeZone(identifier: "Asia/Kolkata")!).offset(at: evening, from: chicago) == "+10:30HRS")
    }

    @Test func theDayFollowsTheCity() {
        #expect(ClockCity(timeZone: TimeZone(identifier: "Asia/Tokyo")!).day(at: evening, from: chicago) == "Tomorrow")
        #expect(ClockCity(timeZone: TimeZone(identifier: "America/Los_Angeles")!).day(at: evening, from: chicago) == "Today")
        #expect(ClockCity(timeZone: chicago).day(at: evening, from: chicago) == "Today")
    }

    /// Untouched, the clock shows here and three more; once edited it shows exactly what was picked.
    @Test func citiesComeFromSettings() {
        #expect(ClockCity.saved("").count == 4)
        #expect(ClockCity.saved("[]").isEmpty)
        let paris = Place(name: "Paris", latitude: 48.86, longitude: 2.35, timeZoneID: "Europe/Paris")
        let json = Place.json([paris])
        #expect(Place.list(from: json) == [paris])
        #expect(ClockCity.saved(json).map(\.name) == ["Paris"])
        #expect(ClockCity(timeZone: TimeZone(identifier: "America/New_York")!).name == "New York")
    }
}

/// An Open-Meteo forecast turned into the Weather widget's lines.
struct WeatherReportTests {
    private let forecast = #"""
        {"timezone": "America/Chicago", "utc_offset_seconds": -18000,
         "current": {"temperature_2m": 71.6, "weather_code": 2, "is_day": 1},
         "hourly": {"time": ["2026-10-30T15:00", "2026-10-30T16:00", "2026-10-30T17:00", "2026-10-30T18:00", "2026-10-30T19:00",
                             "2026-10-30T20:00", "2026-10-30T21:00", "2026-10-30T22:00"],
                    "temperature_2m": [70.2, 71.5, 69.4, 66.0, 63.8, 61.1, 59.9, 58.4],
                    "weather_code": [0, 1, 2, 3, 61, 0, 95, 71],
                    "is_day": [1, 1, 1, 1, 0, 0, 0, 0]},
         "daily": {"temperature_2m_max": [74.4, 70.0], "temperature_2m_min": [56.6, 50.0]}}
        """#

    @Test func readsNowTodayAndTheNextHours() throws {
        // 3:40 PM in Chicago: the hours start at 4 PM.
        let now = ISO8601DateFormatter().date(from: "2026-10-30T20:40:00Z")!
        let report = try #require(WeatherModel.report(from: Data(forecast.utf8), city: "Chicago", isCurrentLocation: true, now: now))
        #expect(report.temperature == 72)
        #expect(report.condition == "Partly Cloudy")
        #expect(report.symbol == "cloud.sun.fill")
        #expect(report.high == 74 && report.low == 57)
        #expect(report.timeZone.identifier == "America/Chicago")
        #expect(report.hours.count == 6)
        #expect(report.hours.map(\.temperature) == [72, 69, 66, 64, 61, 60])
        #expect(report.hours[3].symbol == "cloud.rain.fill")
        #expect(report.hours[4].symbol == "moon.stars.fill")
    }

    @Test func somethingElseIsNotAForecast() {
        #expect(WeatherModel.report(from: Data("{}".utf8), city: "X", isCurrentLocation: false) == nil)
    }

    @Test func skiesAreNamedAsWeatherNamesThem() {
        #expect(WeatherModel.sky(code: 0, isDay: false) == ("moon.stars.fill", "Clear"))
        #expect(WeatherModel.sky(code: 65, isDay: true) == ("cloud.heavyrain.fill", "Heavy Rain"))
        #expect(WeatherModel.sky(code: 95, isDay: true).condition == "Thunderstorms")
    }
}

/// The Shortcuts module shows the picked shortcuts that still exist, or the first four.
struct ShortcutsPickTests {
    let all = ["A", "B", "C", "D", "E, with a comma"]

    @Test func noPicksShowsTheFirstFour() {
        #expect(ShortcutsModel.shown(names: all, picked: []) == ["A", "B", "C", "D"])
    }

    @Test func picksKeepTheirOrderAndDropMissingOnes() {
        #expect(ShortcutsModel.shown(names: all, picked: ["E, with a comma", "Gone", "B"]) == ["E, with a comma", "B"])
        #expect(ShortcutsModel.shown(names: all, picked: ["Gone"]) == ["A", "B", "C", "D"])
    }

    @Test func picksRoundTripThroughJSON() {
        let picks = ["E, with a comma", "A"]
        #expect(ShortcutsModel.picks(from: ShortcutsModel.json(picks)) == picks)
        #expect(ShortcutsModel.json([]) == "")
        #expect(ShortcutsModel.picks(from: "").isEmpty)
    }
}
