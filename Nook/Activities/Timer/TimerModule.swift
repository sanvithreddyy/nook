import SwiftUI

/// The Clock app's Timer on the notch. Idle, it lists lengths to start with a green play button, as
/// Timer's Recents do; running, the time left sits in an orange ring that drains, with the end time
/// under it and Cancel and Pause as round buttons beside it.
struct TimerModule: View {
    @Environment(TimerModel.self) private var timer

    var body: some View {
        if timer.isActive {
            TimerRunning()
                .transition(.opacity)
        } else {
            TimerRecents()
                .transition(.opacity)
        }
    }
}

/// Lengths to start, as Timer's Recents list them: three down a narrow module, six in two rows of
/// three when the module has the page to itself.
private struct TimerRecents: View {
    @Environment(\.homeScale) private var k

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ModuleHeading(text: "Timer", color: .orange)
                .padding(.bottom, 4 * k)
            ViewThatFits(in: .horizontal) {
                Grid(horizontalSpacing: 24 * k, verticalSpacing: 0) {
                    ForEach([[1, 3, 5], [10, 15, 25]], id: \.self) { row in
                        GridRow {
                            ForEach(row, id: \.self) { minutes in
                                RecentRow(minutes: minutes, separated: row.first != 1)
                            }
                        }
                    }
                }
                .frame(minWidth: 480 * k)
                VStack(spacing: 0) {
                    ForEach([5, 10, 25], id: \.self) { minutes in
                        RecentRow(minutes: minutes, separated: minutes != 5)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// A length with its green start button, under a hairline when it isn't the first.
private struct RecentRow: View {
    @Environment(TimerModel.self) private var timer
    @Environment(\.homeScale) private var k
    let minutes: Int
    let separated: Bool

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(minutes):00")
                    .font(.system(size: 24 * k, weight: .light).monospacedDigit())
                    .foregroundStyle(.white)
                Text("\(minutes) min")
                    .font(.system(size: 11 * k))
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer(minLength: 8 * k)
            Button { withAnimation(Motion.content) { timer.start(minutes: minutes) } } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 12 * k, weight: .bold))
                    .foregroundStyle(.green)
                    .frame(width: 30 * k, height: 30 * k)
                    .background(Circle().fill(.green.opacity(0.22)))
            }
            .buttonStyle(IslandButtonStyle())
            .accessibilityLabel("Start a \(minutes) minute timer")
        }
        .frame(height: 42 * k)
        .overlay(alignment: .top) {
            if separated {
                Rectangle().fill(.white.opacity(0.12)).frame(height: 1)
            }
        }
    }
}

private struct TimerRunning: View {
    @Environment(TimerModel.self) private var timer
    @Environment(\.homeScale) private var k

    var body: some View {
        // Ring and buttons stay together in the middle, however wide the module is.
        HStack(spacing: 28 * k) {
            // Once a second, reading the clock itself, as the timer's drop does.
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                let now = Date.now
                ZStack {
                    Circle().stroke(Color.orange.opacity(0.25), lineWidth: 5 * k)
                    Circle()
                        .trim(from: 0, to: timer.state == .done ? 1 : timer.fraction(at: now))
                        .stroke(Color.orange, style: StrokeStyle(lineWidth: 5 * k, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 2 * k) {
                        TimerText(size: 26 * k, weight: .light, color: .white)
                        if case .running(let end) = timer.state {
                            Label(end.formatted(date: .omitted, time: .shortened), systemImage: "bell.fill")
                                .font(.system(size: 11 * k, weight: .medium))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }
                }
                .frame(width: 126 * k, height: 126 * k)
            }
            HStack(spacing: 12 * k) {
                if timer.state == .done {
                    WordButton(title: "Repeat", tint: .white) { timer.repeatLast() }
                    WordButton(title: "Stop", tint: .orange) { withAnimation(Motion.content) { timer.cancel() } }
                } else {
                    WordButton(title: "Cancel", tint: .white) { withAnimation(Motion.content) { timer.cancel() } }
                    WordButton(title: timer.isRunning ? "Pause" : "Resume", tint: timer.isRunning ? .orange : .green) { timer.toggle() }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The Clock app's round timer buttons: the word in the tint on a dim disc of it.
private struct WordButton: View {
    @Environment(\.homeScale) private var k
    let title: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13 * k, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 58 * k, height: 58 * k)
                .background(Circle().fill(tint.opacity(tint == .white ? 0.16 : 0.22)))
        }
        .buttonStyle(IslandButtonStyle())
    }
}
