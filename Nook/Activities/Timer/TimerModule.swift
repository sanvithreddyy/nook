import SwiftUI

/// The Timer module: Clock's timer as the iPhone draws it, filling the module.
struct TimerModule: View {
    @Environment(TimerModel.self) private var timer
    @Environment(\.homeScale) private var k
    /// The length Start begins, before a timer runs: the last one started, until the dial changes it.
    @State private var minutes: Int?

    var body: some View {
        GeometryReader { geometry in
            TimerFace(length: length, size: geometry.size, button: 58 * k) { step in
                let next = min(max(length + step, 1), 23 * 60 + 59)
                defer { minutes = next }
                return next != length
            }
        }
    }

    private var length: Int { minutes ?? timer.lastMinutes }
}

/// Clock's timer on the iPhone, laid across: an orange ring draining around the time left in thin
/// digits, with a bell and when it ends under them, Cancel to its left and Start, Pause or Resume to its
/// right as round buttons. Before a timer runs the ring is grey and scrolling over it sets the minutes;
/// while it runs scrolling adds or takes some off. Shared by the module and the open timer's page.
struct TimerFace: View {
    @Environment(TimerModel.self) private var timer
    /// The length Start begins.
    let length: Int
    let size: CGSize
    let button: CGFloat
    /// A scroll over the ring before a timer runs; returns whether the length changed.
    let setLength: (Int) -> Bool
    /// After Cancel or Stop, for the open page to close.
    var stopped: () -> Void = {}

    var body: some View {
        let gap = button * 0.3
        let ring = max(min(size.height, size.width - (button + gap) * 2), 0)
        HStack(spacing: gap) {
            left
            TimerRing(length: length, diameter: ring)
                .overlay { ScrollDial { step in timer.isActive ? timer.adjust(minutes: step) : setLength(step) } }
                .help(timer.isActive ? "Scroll to add or take off minutes" : "Scroll to set the minutes")
            right
        }
        .frame(width: size.width, height: size.height)
        .animation(Motion.content, value: timer.state)
    }

    @ViewBuilder private var left: some View {
        switch timer.state {
        case .idle:
            RoundTimerButton(title: "Cancel", tint: .white, size: button) {}
                .disabled(true)
        case .done:
            RoundTimerButton(title: "Stop", tint: .white, size: button) {
                timer.cancel()
                stopped()
            }
        case .running, .paused:
            RoundTimerButton(title: "Cancel", tint: .white, size: button) {
                timer.cancel()
                stopped()
            }
        }
    }

    @ViewBuilder private var right: some View {
        switch timer.state {
        case .idle: RoundTimerButton(title: "Start", tint: .green, size: button) { timer.start(minutes: length) }
        case .running: RoundTimerButton(title: "Pause", tint: .orange, size: button) { timer.toggle() }
        case .paused: RoundTimerButton(title: "Resume", tint: .green, size: button) { timer.toggle() }
        case .done: RoundTimerButton(title: "Repeat", tint: .green, size: button) { timer.repeatLast() }
        }
    }
}

/// The ring and the time inside it. The ring drains clockwise from twelve, smoothly between the
/// once-a-second redraws; paused, it and the time dim.
private struct TimerRing: View {
    @Environment(TimerModel.self) private var timer
    let length: Int
    let diameter: CGFloat

    var body: some View {
        // Once a second, reading the clock itself, as the timer's drop does.
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let now = Date.now
            let left = timer.isActive ? timer.remaining(at: now).rounded(.up) : TimeInterval(length * 60)
            let fraction = timer.isActive ? timer.fraction(at: now) : 1
            let paused = { if case .paused = timer.state { true } else { false } }()
            let line = max(diameter * 0.045, 3)
            ZStack {
                Circle().stroke(Color.white.opacity(0.12), lineWidth: line)
                if timer.isActive {
                    Circle()
                        .trim(from: 1 - fraction, to: 1)
                        .stroke(Color.orange.opacity(paused ? 0.45 : 1), style: StrokeStyle(lineWidth: line, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(timer.isRunning ? .linear(duration: 1) : Motion.content, value: fraction)
                }
                VStack(spacing: diameter * 0.03) {
                    Text(timer.state == .done ? "0:00" : left.countdown)
                        .font(.system(size: diameter * 0.22, weight: .light).monospacedDigit())
                        .foregroundStyle(.white.opacity(paused ? 0.55 : 1))
                        .contentTransition(.numericText(countsDown: true))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if case .running(let end) = timer.state {
                        Label(end.formatted(date: .omitted, time: .shortened), systemImage: "bell.fill")
                            .font(.system(size: max(diameter * 0.085, 10)).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.5))
                            .labelStyle(BellLabelStyle())
                    }
                }
                .padding(line * 2)
            }
            .frame(width: diameter, height: diameter)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(timer.isActive ? "Timer, \(timer.remaining().countdown) left" : "Timer, \(length) minutes")
    }
}

/// Bell and time close together, as Clock writes when a timer ends.
private struct BellLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon.imageScale(.small)
            configuration.title
        }
    }
}

/// Clock's round timer buttons: the word in the tint on a dim disc of it, ringed by a thin line of the
/// same with a gap between.
private struct RoundTimerButton: View {
    @Environment(\.isEnabled) private var isEnabled
    let title: String
    let tint: Color
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        let fill = tint.opacity(tint == .white ? 0.16 : 0.24)
        Button(action: action) {
            ZStack {
                Circle().fill(fill).padding(size * 0.06)
                Circle().strokeBorder(fill, lineWidth: max(size * 0.03, 1.5))
                Text(title)
                    .font(.system(size: size * 0.24))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(size * 0.1)
            }
            .frame(width: size, height: size)
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(Circle())
        }
        .buttonStyle(RoundPress())
    }
}

private struct RoundPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? ButtonFeedback.pressed : 1)
            .animation(ButtonFeedback.press, value: configuration.isPressed)
    }
}
