import SwiftUI

/// Apple's Batteries widget on the notch: a ring per device with its glyph inside and its level under
/// it, empty rings holding the places of devices that aren't there. Green as Apple draws it (white when
/// Settings asks for white), yellow in Low Power Mode, red at 20% and below; a bolt set into the top of
/// the ring while charging.
struct BatteriesModule: View {
    @Environment(DeviceBatteries.self) private var batteries
    @Environment(\.homeScale) private var k
    /// Its own width, or the whole page's when the page is wider: the places spread out evenly across
    /// it, as the widget's do, and the rings grow into the height.
    let width: CGFloat

    var body: some View {
        let devices = batteries.devices
        let cell = width / CGFloat(max(devices.count, HomeMetrics.batterySlots))
        let diameter = min(cell * DeviceRing.widthShare, DeviceRing.widgetDiameter * DeviceRing.maxGrowth * k)
        HStack(spacing: 0) {
            ForEach(devices) { device in
                DeviceRing(device: device, diameter: diameter)
                    .frame(width: cell)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
            ForEach(devices.count..<max(devices.count, HomeMetrics.batterySlots), id: \.self) { _ in
                DeviceRing(device: nil, diameter: diameter)
                    .frame(width: cell)
            }
        }
        .animation(Motion.content, value: devices.map(\.id))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One device, or an empty place: the track ring alone. Measured from the widget, where a 58 pt ring
/// sits in a 76 pt place with a 6 pt line, a 22 pt glyph and its level in 15 pt; every part keeps
/// that proportion to the ring.
private struct DeviceRing: View {
    let device: DeviceBattery?
    let diameter: CGFloat

    static let widgetDiameter: CGFloat = 58
    /// The ring's share of its place's width.
    static let widthShare: CGFloat = 58 / 76
    /// Grown any further, ring and level fill the module's height and crowd the notch.
    static let maxGrowth: CGFloat = 1.5

    var body: some View {
        let s = diameter / Self.widgetDiameter
        let level = device.map { CGFloat(min(max($0.level, 0), 100)) / 100 } ?? 0
        let charging = device?.isCharging == true
        let low = device.map { $0.level <= 20 && !$0.isCharging } ?? false
        let color: Color = low ? .red : device?.isLowPower == true ? Color.status(.yellow) : Color.status(.green)
        let line = 6 * s
        VStack(spacing: 9 * s) {
            ZStack {
                RingArc(fraction: 1, gap: charging).stroke(.white.opacity(0.16), lineWidth: line)
                if device != nil {
                    RingArc(fraction: level, gap: charging)
                        .stroke(color, style: StrokeStyle(lineWidth: line, lineCap: .round))
                }
                if charging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 10 * s, weight: .bold))
                        .foregroundStyle(color)
                        .offset(y: -diameter / 2)
                }
                if let device {
                    // Two tones, as the widget draws them: the AirPods' tips and the Mac's screen softer.
                    Image(systemName: device.symbol)
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 22 * s))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: diameter, height: diameter)
            Text(device.map { "\($0.level)%" } ?? " ")
                .font(.system(size: 15 * s).monospacedDigit())
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
