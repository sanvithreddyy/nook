import AppKit
import SwiftUI

/// Apple's Weather widget (medium) on the notch: the place and the temperature now on the left, the
/// sky and today's high and low on the right, the next six hours along the bottom, from the next whole
/// hour and on the place's own clock, as the widget starts them. The symbols keep Apple's own colours.
/// With more than one place, clicking the name moves to the next.
struct WeatherModule: View {
    @Environment(WeatherModel.self) private var weather
    @Environment(\.homeScale) private var k

    var body: some View {
        if let report = weather.report {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 8 * k) {
                    VStack(alignment: .leading, spacing: 0) {
                        Button { withAnimation(Motion.content) { weather.showNext() } } label: {
                            HStack(spacing: 4 * k) {
                                Text(report.city)
                                    .font(.system(size: 14 * k, weight: .semibold))
                                    .lineLimit(1)
                                if report.isCurrentLocation {
                                    Image(systemName: "location.fill")
                                        .font(.system(size: 9 * k, weight: .semibold))
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(weather.reports.count < 2)
                        .help(weather.reports.count > 1 ? "Next place" : "")
                        Text("\(report.temperature)°")
                            .font(.system(size: 44 * k, weight: .light))
                            .tracking(-1 * k)
                            .contentTransition(.numericText(value: Double(report.temperature)))
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 1 * k) {
                        SkySymbol(name: report.symbol, size: 15 * k)
                            .padding(.bottom, 3 * k)
                        Text(report.condition)
                        Text("H:\(report.high)° L:\(report.low)°")
                    }
                    .font(.system(size: 13 * k, weight: .semibold))
                    .lineLimit(1)
                    .padding(.top, 2 * k)
                }
                Spacer(minLength: 0)
                HStack(spacing: 0) {
                    ForEach(report.hours.prefix(6)) { hour in
                        VStack(spacing: 6 * k) {
                            Text(hour.time.formatted(Date.FormatStyle(timeZone: report.timeZone).hour()))
                                .font(.system(size: 11 * k, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.7))
                            SkySymbol(name: hour.symbol, size: 16 * k)
                                .frame(height: 18 * k)
                            Text("\(hour.temperature)°")
                                .font(.system(size: 13 * k, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .foregroundStyle(.white)
            .padding(.vertical, 2 * k)
            .id(report.city)
            .transition(.opacity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(report.city), \(report.temperature) degrees, \(report.condition), high \(report.high), low \(report.low)")
        } else {
            WeatherAsk()
        }
    }
}

/// Before there's weather to show: a city to add or the location to allow, as one button. Otherwise
/// quiet, or a line when the forecast couldn't be read.
private struct WeatherAsk: View {
    @Environment(WeatherModel.self) private var weather
    @Environment(\.homeScale) private var k

    var body: some View {
        Group {
            if !weather.hasPlaces {
                ask("Add a City") { SettingsWindowController.shared.show(pane: .home) }
            } else if weather.needsLocation {
                if weather.locationAccess == .denied {
                    ask("Allow Location in Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!)
                    }
                } else {
                    ask("Use My Location") { weather.requestLocation() }
                }
            } else if weather.failed {
                Text("Weather isn't available right now")
                    .font(.system(size: 13 * k, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func ask(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12 * k, weight: .semibold))
                .padding(.horizontal, 12 * k)
                .frame(height: 26 * k)
        }
        .buttonStyle(CardButtonStyle(style: .primary))
    }
}

/// A weather symbol in Apple's colours: yellow sun, white cloud, blue rain.
private struct SkySymbol: View {
    let name: String
    let size: CGFloat

    var body: some View {
        Image(systemName: name)
            .symbolRenderingMode(.multicolor)
            .font(.system(size: size))
    }
}
