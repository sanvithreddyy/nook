import AppKit
import SwiftUI

/// Beside the notch, like the iPhone's timer: the orange timer glyph and the time left in orange.
struct TimerActivitySide: View {
    @Environment(TimerModel.self) private var timer
    @Environment(NotchModel.self) private var model
    let edge: HorizontalEdge

    var body: some View {
        if edge == .leading {
            Image(systemName: "timer")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: model.notch.size.height, height: model.notch.size.height)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            TimerText(size: Compact.fontSize)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, Compact.outer)
        }
    }
}

/// The time left, kept current by the system the way Live Activity timers are, so it costs nothing
/// per second. Paused, it holds and dims; finished, it says so.
struct TimerText: View {
    @Environment(TimerModel.self) private var timer
    let size: CGFloat
    var weight: Font.Weight = .semibold

    var body: some View {
        Group {
            switch timer.state {
            case .running(let end):
                Text(timerInterval: Date.now...max(end, .now), countsDown: true, showsHours: true)
            case .paused(let remaining):
                Text(remaining.countdown).opacity(0.55)
            case .done:
                Text("Done")
            case .idle:
                Text("0:00")
            }
        }
        .font(.system(size: size, weight: weight).monospacedDigit())
        .foregroundStyle(.orange)
        .lineLimit(1)
        .fixedSize()
    }
}

/// The timer in its drop beside the island: an orange ring that drains, with the minutes left in it
/// (seconds in the last minute).
struct TimerDropContent: View {
    @Environment(TimerModel.self) private var timer

    var body: some View {
        // Ticks on whole seconds from a date in the past, so the first frame draws straight away.
        TimelineView(.periodic(from: .distantPast, by: 1)) { context in
            let left = timer.remaining(at: context.date)
            ZStack {
                Circle().stroke(Color.orange.opacity(0.28), lineWidth: 2.4)
                Circle()
                    .trim(from: 0, to: timer.state == .done ? 1 : timer.fraction(at: context.date))
                    .stroke(Color.orange, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: timer.fraction(at: context.date))
                Group {
                    if timer.state == .done {
                        Image(systemName: "bell.fill").font(.system(size: 9, weight: .bold))
                    } else {
                        Text(left >= 60 ? "\(Int((left / 60).rounded(.up)))" : "\(Int(left.rounded(.up)))")
                            .font(.system(size: 10, weight: .bold).monospacedDigit())
                    }
                }
                .foregroundStyle(.orange)
                .opacity(timer.isRunning || timer.state == .done ? 1 : 0.55)
            }
            .frame(width: 21, height: 21)
        }
        .accessibilityLabel("Timer, \(timer.remaining().countdown) left")
    }
}

/// The open timer, like the iPhone's Timer Live Activity: the time left large in orange, then pause
/// and cancel as round buttons. Two-finger scrolling over the time adds or takes off minutes, one
/// detent per minute. Finished, the buttons become Repeat and Stop.
struct TimerCard: View {
    @Environment(TimerModel.self) private var timer
    @Environment(NotchModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: "timer")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.orange)
                .frame(height: model.notch.size.height)
                .accessibilityHidden(true)
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    TimerText(size: 34, weight: .medium)
                        .overlay { ScrollDial { step in timer.adjust(minutes: step) } }
                        .help("Scroll to add or take off minutes")
                    Text(caption)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer(minLength: 0)
                if timer.state == .done {
                    RoundButton(symbol: "arrow.counterclockwise", label: "Repeat", tint: .white) { timer.repeatLast() }
                    RoundButton(symbol: "xmark", label: "Stop", tint: .orange) {
                        timer.cancel()
                        model.collapse()
                    }
                } else {
                    RoundButton(symbol: timer.isRunning ? "pause.fill" : "play.fill",
                                label: timer.isRunning ? "Pause" : "Resume", tint: .orange) { timer.toggle() }
                    RoundButton(symbol: "xmark", label: "Cancel", tint: .white) {
                        timer.cancel()
                        model.collapse()
                    }
                }
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contextMenu {
            TimerMenu()
            Divider()
            SettingsMenuItem()
        }
    }

    private var caption: String {
        let length = timer.total >= 3600 ? "\(Int(timer.total / 3600)) hr \(Int(timer.total.truncatingRemainder(dividingBy: 3600) / 60)) min"
                                         : "\(Int((timer.total / 60).rounded())) min"
        switch timer.state {
        case .paused: return "Paused · \(length)"
        case .done: return "Timer · \(length)"
        default: return "Timer · \(length)"
        }
    }
}

/// A round control tinted like the iPhone's timer buttons: the glyph in the tint on a dim disc of it.
private struct RoundButton: View {
    let symbol: String
    let label: String
    let tint: Color
    let action: () -> Void
    @State private var clicks = 0

    var body: some View {
        Button {
            clicks += 1
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, options: .speed(1.5), value: clicks)
                .foregroundStyle(tint)
                .frame(width: 42, height: 42)
                .background(Circle().fill(tint.opacity(tint == .white ? 0.14 : 0.24)))
        }
        .buttonStyle(IslandButtonStyle())
        .accessibilityLabel(label)
    }
}

/// Timer items for the island's right-click menu.
struct TimerMenu: View {
    @Environment(TimerModel.self) private var timer

    var body: some View {
        switch timer.state {
        case .idle:
            Menu("Start Timer") {
                ForEach(TimerModel.presets, id: \.self) { minutes in
                    Button(Self.title(minutes)) { timer.start(minutes: minutes) }
                }
            }
        case .done:
            Button("Stop Timer") { timer.cancel() }
            Button("Repeat Timer") { timer.repeatLast() }
        case .running, .paused:
            Button(timer.isRunning ? "Pause Timer" : "Resume Timer") { timer.toggle() }
            Button("Add 1 Minute") { timer.adjust(minutes: 1) }
            Button("Cancel Timer") { timer.cancel() }
        }
    }

    static func title(_ minutes: Int) -> String {
        switch minutes {
        case 60: "1 Hour"
        case 1: "1 Minute"
        default: "\(minutes) Minutes"
        }
    }
}

/// Turns two-finger scrolling over a view into whole steps, with a trackpad detent for each,
/// like turning a crown. Fingers up adds; momentum is ignored so it stops where the fingers do.
struct ScrollDial: NSViewRepresentable {
    let onStep: (Int) -> Void

    func makeNSView(context: Context) -> DialView {
        let view = DialView()
        view.onStep = onStep
        return view
    }

    func updateNSView(_ view: DialView, context: Context) {
        view.onStep = onStep
    }

    final class DialView: NSView {
        var onStep: ((Int) -> Void)?
        private var travel: CGFloat = 0
        private static let detent: CGFloat = 16

        override func scrollWheel(with event: NSEvent) {
            guard event.momentumPhase.isEmpty else { return }
            if event.phase == .began || event.phase == .mayBegin { travel = 0 }
            // Positive means the fingers moved up, whichever scrolling direction is set.
            let fingers = event.scrollingDeltaY * (event.isDirectionInvertedFromDevice ? -1 : 1)
            travel += event.hasPreciseScrollingDeltas ? fingers : fingers * Self.detent
            while abs(travel) >= Self.detent {
                let step = travel > 0 ? 1 : -1
                travel -= CGFloat(step) * Self.detent
                onStep?(step)
                if Prefs.bool(Prefs.enableHaptics) {
                    NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
                }
            }
        }
    }
}
