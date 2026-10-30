import SwiftUI

/// Apple's Batteries widget on the notch: a ring per device with its glyph inside and its level under
/// it, empty rings holding the places of devices that aren't there. Green as Apple draws it (white when
/// Settings asks for white), yellow in Low Power Mode, red at 20% and below; a bolt set into the top of
/// the ring while charging.
struct BatteriesModule: View {
    @Environment(DeviceBatteries.self) private var batteries
    @Environment(\.homeScale) private var k

    var body: some View {
        let devices = batteries.devices
        HStack(spacing: 0) {
            ForEach(devices) { device in
                DeviceRing(device: device)
                    .frame(width: HomeMetrics.batteryCell * k)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
            ForEach(devices.count..<max(devices.count, HomeMetrics.batterySlots), id: \.self) { _ in
                DeviceRing(device: nil)
                    .frame(width: HomeMetrics.batteryCell * k)
            }
        }
        .animation(Motion.content, value: devices.map(\.id))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One device, or an empty place: the track ring alone.
private struct DeviceRing: View {
    @Environment(\.homeScale) private var k
    let device: DeviceBattery?

    var body: some View {
        let level = device.map { CGFloat(min(max($0.level, 0), 100)) / 100 } ?? 0
        let charging = device?.isCharging == true
        let low = device.map { $0.level <= 20 && !$0.isCharging } ?? false
        let color: Color = low ? .red : device?.isLowPower == true ? Color.status(.yellow) : Color.status(.green)
        let diameter = 58 * k
        let line = 6 * k
        VStack(spacing: 9 * k) {
            ZStack {
                RingArc(fraction: 1, gap: charging).stroke(.white.opacity(0.16), lineWidth: line)
                if device != nil {
                    RingArc(fraction: level, gap: charging)
                        .stroke(color, style: StrokeStyle(lineWidth: line, lineCap: .round))
                }
                if charging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 10 * k, weight: .bold))
                        .foregroundStyle(color)
                        .offset(y: -diameter / 2)
                }
                if let device {
                    Image(systemName: device.symbol)
                        .symbolRenderingMode(.monochrome)
                        .font(.system(size: 22 * k))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: diameter, height: diameter)
            Text(device.map { "\($0.level)%" } ?? " ")
                .font(.system(size: 15 * k).monospacedDigit())
                .foregroundStyle(low ? .red : .white)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(device.map { "\($0.name), \($0.level) percent\($0.isCharging ? ", charging" : "")" } ?? "")
        .accessibilityHidden(device == nil)
    }
}

/// A ring from twelve o'clock clockwise. While charging, a gap at the top holds the bolt.
nonisolated private struct RingArc: Shape {
    var fraction: CGFloat
    let gap: Bool

    var animatableData: CGFloat {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let open = gap ? 0.045 : 0
        let start = open
        let end = open + (1 - open * 2) * min(max(fraction, 0), 1)
        return Circle()
            .trim(from: start, to: end)
            .rotation(.degrees(-90))
            .path(in: rect)
    }
}
