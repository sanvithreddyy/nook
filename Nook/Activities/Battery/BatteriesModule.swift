import SwiftUI

/// Apple's Batteries widget on the notch: a ring per device with its glyph inside, the level and the
/// name under it. Green as Apple draws it (white when Settings asks for white), yellow in Low Power
/// Mode, red at 20% and below; a bolt while charging.
struct BatteriesModule: View {
    @Environment(DeviceBatteries.self) private var batteries
    @Environment(\.homeScale) private var k

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ModuleHeading(text: "Batteries", color: .white.opacity(0.45))
                .padding(.bottom, 16 * k)
            HStack(alignment: .top, spacing: 0) {
                ForEach(batteries.devices) { device in
                    DeviceRing(device: device)
                        .frame(width: HomeMetrics.batteryCell * k)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .animation(Motion.content, value: batteries.devices.map(\.id))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct DeviceRing: View {
    @Environment(\.homeScale) private var k
    let device: DeviceBattery

    var body: some View {
        let low = device.level <= 20 && !device.isCharging
        let color: Color = low ? .red : device.isLowPower ? Color.status(.yellow) : Color.status(.green)
        let fraction = CGFloat(min(max(device.level, 0), 100)) / 100
        VStack(spacing: 0) {
            ZStack {
                Circle().stroke(.white.opacity(0.16), lineWidth: 5 * k)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(color, style: StrokeStyle(lineWidth: 5 * k, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: device.symbol)
                    .font(.system(size: 18 * k, weight: .medium))
                    .foregroundStyle(.white)
            }
            .frame(width: 49 * k, height: 49 * k)
            .padding(2.5 * k)
            HStack(spacing: 2 * k) {
                if device.isCharging {
                    Image(systemName: "bolt.fill").font(.system(size: 10 * k, weight: .bold))
                }
                Text("\(device.level)%")
            }
            .font(.system(size: 13 * k, weight: .semibold).monospacedDigit())
            .foregroundStyle(low ? .red : .white)
            .padding(.top, 8 * k)
            Text(device.name)
                .font(.system(size: 11 * k))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 2 * k)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(device.name), \(device.level) percent\(device.isCharging ? ", charging" : "")")
    }
}
