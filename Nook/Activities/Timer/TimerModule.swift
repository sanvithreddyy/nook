import SwiftUI

/// The Mac's Clock app Timer on the notch: the time in large thin digits under small min and sec
/// labels (hr too past an hour), and Cancel beside Start, Pause or Resume as capsules under it, as in
/// Clock's Timers. Scroll over the digits to set the minutes, or to add or take off minutes while it runs.
struct TimerModule: View {
    @Environment(TimerModel.self) private var timer
    @Environment(\.homeScale) private var k
    /// The length Start begins, before a timer runs.
    @State private var minutes = 5

    var body: some View {
        VStack(spacing: 14 * k) {
            // Once a second, reading the clock itself, as the timer's drop does.
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                TimerDigits(seconds: timer.isActive ? timer.remaining(at: .now).rounded(.up) : TimeInterval(minutes * 60))
                    .opacity(isPaused ? 0.55 : 1)
            }
            .overlay {
                ScrollDial { step in
                    guard !timer.isActive else { return timer.adjust(minutes: step) }
                    let next = min(max(minutes + step, 1), 23 * 60 + 59)
                    defer { minutes = next }
                    return next != minutes
                }
            }
            .help(timer.isActive ? "Scroll to add or take off minutes" : "Scroll to set the minutes")
            HStack(spacing: 12 * k) {
                switch timer.state {
                case .idle:
                    CapsuleButton(title: "Cancel", fill: .white.opacity(0.14)) {}
                        .disabled(true)
                    CapsuleButton(title: "Start", fill: .green) { timer.start(minutes: minutes) }
                case .done:
                    CapsuleButton(title: "Repeat", fill: .white.opacity(0.14)) { timer.repeatLast() }
                    CapsuleButton(title: "Stop", fill: .orange) { timer.cancel() }
                case .running, .paused:
                    CapsuleButton(title: "Cancel", fill: .white.opacity(0.14)) { timer.cancel() }
                    CapsuleButton(title: isPaused ? "Resume" : "Pause", fill: isPaused ? .green : .orange) { timer.toggle() }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(Motion.content, value: timer.state)
    }

    private var isPaused: Bool { if case .paused = timer.state { true } else { false } }
}

/// "05:00" as the Clock app sets it: two-digit groups in thin digits, each under its unit.
private struct TimerDigits: View {
    @Environment(\.homeScale) private var k
    let seconds: TimeInterval

    var body: some View {
        let total = max(Int(seconds), 0)
        let groups: [(unit: String, value: Int)] = total >= 3600
            ? [("hr", total / 3600), ("min", total % 3600 / 60), ("sec", total % 60)]
            : [("min", total / 60), ("sec", total % 60)]
        HStack(alignment: .lastTextBaseline, spacing: 0) {
            ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                if index > 0 {
                    Text(":").font(.system(size: 50 * k, weight: .thin))
                }
                VStack(spacing: 2 * k) {
                    Text(group.unit)
                        .font(.system(size: 11 * k, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                    Text(String(format: "%02d", group.value))
                        .font(.system(size: 50 * k, weight: .thin).monospacedDigit())
                        .contentTransition(.numericText(countsDown: true))
                }
            }
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Duration.seconds(total).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide)))
    }
}

/// The Clock app's capsule buttons: white words on a filled capsule.
private struct CapsuleButton: View {
    @Environment(\.homeScale) private var k
    @Environment(\.isEnabled) private var isEnabled
    let title: String
    let fill: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13 * k, weight: .medium))
                .foregroundStyle(.white.opacity(isEnabled ? 1 : 0.35))
                .frame(width: 92 * k, height: 28 * k)
                .background(Capsule().fill(fill.opacity(isEnabled ? 1 : 0.6)))
                .contentShape(Capsule())
        }
        .buttonStyle(CapsulePress())
    }
}

private struct CapsulePress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? ButtonFeedback.pressed : 1)
            .animation(ButtonFeedback.press, value: configuration.isPressed)
    }
}
