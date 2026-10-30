import SwiftUI

/// Apple's Weather widget (medium) on the notch: the place and the temperature now on the left, the
/// sky and today's high and low on the right, the next six hours along the bottom. The symbols keep
/// Apple's own colours, as the widget draws them.
struct WeatherModule: View {
    @Environment(WeatherModel.self) private var weather
    @Environment(\.homeScale) private var k

    var body: some View {
        if let report = weather.report {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 8 * k) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 4 * k) {
                            Text(report.city)
                                .font(.system(size: 14 * k, weight: .semibold))
                                .lineLimit(1)
                            Image(systemName: "location.fill")
                                .font(.system(size: 9 * k, weight: .semibold))
                        }
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
                    ForEach(Array(report.hours.prefix(6).enumerated()), id: \.element.id) { index, hour in
                        VStack(spacing: 6 * k) {
                            // "4PM", as the widget writes it.
                            Text(index == 0 ? "Now" : hour.time.formatted(.dateTime.hour()).replacing(/\s/, with: ""))
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
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(report.city), \(report.temperature) degrees, \(report.condition), high \(report.high), low \(report.low)")
        }
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
