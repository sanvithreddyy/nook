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
                .foregroundStyle(Color.status(.orange))
                .concentric(.leading, height: model.notch.size.height)
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
        // Redraws once a second, reading the clock itself: a tick's own date can trail the real time
        // by up to a second, which would show a second too many.
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let now = Date.now
            let left = timer.remaining(at: now)
            ZStack {
                Circle().stroke(Color.orange.opacity(0.28), lineWidth: 2.4)
                Circle()
                    .trim(from: 0, to: timer.state == .done ? 1 : timer.fraction(at: now))
                    .stroke(Color.orange, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Group {
                    if timer.state == .done {
                        Image(systemName: "bell.fill").font(.system(size: 9, weight: .bold))
                    } else {
                        // Hours, minutes or seconds, whichever fits three characters.
                        Text(left >= 3600 ? "\(Int(left / 3600))h" : left >= 60 ? "\(Int((left / 60).rounded(.up)))" : "\(Int(left.rounded(.up)))")
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

/// The open timer's page: the timer's glyph beside the notch, then the Timer module's face, larger.
struct TimerCard: View {
    @Environment(TimerModel.self) private var timer
    @Environment(NotchModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardGlyph(symbol: "timer", tint: .orange)
            GeometryReader { geometry in
                // Only open while a timer is going, so there's no length to set here.
                TimerFace(length: timer.lastMinutes, size: geometry.size, button: 62, setLength: { _ in false }) {
                    model.collapse()
                }
            }
            .padding(.bottom, Card.inset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contextMenu {
            TimerMenu()
            Divider()
            SettingsMenuItem(pane: .timer)
        }
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
    /// Returns whether the step did anything; only those get a detent.
    let onStep: (Int) -> Bool

    func makeNSView(context: Context) -> DialView {
        let view = DialView()
        view.onStep = onStep
        return view
    }

    func updateNSView(_ view: DialView, context: Context) {
        view.onStep = onStep
    }

    final class DialView: NSView {
        var onStep: ((Int) -> Bool)?
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
                if onStep?(step) == true { Haptics.detent() }
            }
        }
    }
}
