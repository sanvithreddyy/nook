import SwiftUI

/// One side of a transient notification beside the notch.
struct NotificationSide: View {
    let note: NotchNotification
    let edge: HorizontalEdge

    var body: some View {
        Group {
            switch note {
            case .volume(let level, let muted):
                if edge == .leading {
                    Image(systemName: muted || level == 0 ? "speaker.slash.fill" : "speaker.wave.3.fill", variableValue: Double(level))
                        .contentTransition(.symbolEffect(.replace))
                        .hudGlyph()
                } else {
                    LevelBar(level: muted ? 0 : level)
                }
            case .brightness(let level):
                if edge == .leading {
                    Image(systemName: level < 0.5 ? "sun.min.fill" : "sun.max.fill")
                        .contentTransition(.symbolEffect(.replace))
                        .hudGlyph()
                } else {
                    LevelBar(level: level)
                }
            case .charging(let level):
                sides(label: "Charging", level: level, style: .charging)
            case .onBattery(let level):
                sides(label: "On battery", level: level, style: .normal)
            case .lowBattery(let level):
                sides(label: "Low battery", level: level, style: .low)
            case .lowPowerMode(let on):
                if edge == .leading {
                    label("Low Power")
                } else {
                    Text(on ? "On" : "Off")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(on ? Color.yellow : .white.opacity(0.6))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, 14)
                }
            case .device(let name, let symbol, let battery):
                if edge == .leading {
                    HStack(spacing: 7) {
                        Image(systemName: symbol)
                            .font(.system(size: 14, weight: .medium))
                        Text(name)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 14)
                } else if let battery {
                    HStack(spacing: 6) {
                        Text("\(battery)%")
                            .font(.system(size: 12, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.white)
                        BatteryRing(level: Double(battery) / 100)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 14)
                } else {
                    Text("Connected")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, 14)
                }
            }
        }
    }

    @ViewBuilder
    private func sides(label text: String, level: Int, style: BatteryGlyph.Style) -> some View {
        if edge == .leading {
            label(text)
        } else {
            HStack(spacing: 6) {
                Text("\(level)%")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .contentTransition(.numericText(value: Double(level)))
                BatteryGlyph(level: Double(level) / 100, style: style)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 14)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 14)
    }
}

private extension View {
    func hudGlyph() -> some View {
        font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 16)
    }
}

/// Thin level bar for volume and brightness.
struct LevelBar: View {
    let level: Float

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.18))
                Capsule().fill(.white).frame(width: geo.size.width * CGFloat(min(max(level, 0), 1)))
            }
        }
        .frame(height: 4)
        .padding(.leading, 6)
        .padding(.trailing, 16)
    }
}

struct BatteryGlyph: View {
    enum Style { case normal, charging, low, lowPower }
    let level: Double
    let style: Style

    private var fill: Color {
        switch style {
        case .charging: .green
        case .low: .red
        case .lowPower: .yellow
        case .normal: level <= 0.2 ? .red : .white
        }
    }

    var body: some View {
        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .stroke(.white.opacity(0.4), lineWidth: 1)
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(fill)
                    .frame(width: max(18 * min(max(level, 0), 1), 2))
                    .padding(2)
            }
            .frame(width: 24, height: 12)
            RoundedRectangle(cornerRadius: 1)
                .fill(.white.opacity(0.4))
                .frame(width: 1.5, height: 4)
        }
        .overlay {
            if style == .charging {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 1)
                    .offset(x: -1)
            }
        }
    }
}

struct BatteryRing: View {
    let level: Double

    var body: some View {
        ZStack {
            Circle().stroke(Color.green.opacity(0.3), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: min(max(level, 0), 1))
                .stroke(Color.green, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 15, height: 15)
    }
}
