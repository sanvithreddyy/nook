import Foundation
import Observation

/// A countdown kept in the notch. Started from the island's right-click menu; it shows as the
/// compact view when nothing else is going on, as a drop beside the island while music plays,
/// and as a card when the island opens. A running timer survives quitting Nook.
@Observable
final class TimerModel {
    enum State: Equatable {
        case idle
        case running(end: Date)
        case paused(remaining: TimeInterval)
        /// Reached zero and not yet stopped.
        case done
    }

    private(set) var state: State = .idle
    /// The length it was started with, grown by the dial; the ring drains against it.
    private(set) var total: TimeInterval = 0
    /// The length last started, kept after it stops and across launches: what Start and the
    /// shortcut begin next.
    private(set) var lastMinutes = 5

    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored var onDone: (() -> Void)?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let defaults: UserDefaults

    static let presets = [1, 3, 5, 10, 15, 25, 45, 60]
    /// The dial never takes a running timer below this.
    static let minimum: TimeInterval = 10

    /// Its own store: the app re-reads its settings whenever the standard defaults change, and a
    /// timer saves on every dial detent.
    static let store = UserDefaults(suiteName: "com.sanvith.nook.timer") ?? .standard

    init(defaults: UserDefaults = TimerModel.store) {
        self.defaults = defaults
        restore()
    }

    var isActive: Bool { state != .idle }
    var isRunning: Bool { if case .running = state { true } else { false } }

    func remaining(at date: Date = .now) -> TimeInterval {
        switch state {
        case .idle, .done: 0
        case .running(let end): max(end.timeIntervalSince(date), 0)
        case .paused(let remaining): remaining
        }
    }

    /// What's left as a fraction of the whole, for the draining ring.
    func fraction(at date: Date = .now) -> Double {
        total > 0 ? min(max(remaining(at: date) / total, 0), 1) : 0
    }

    // MARK: Actions

    func start(minutes: Int) {
        total = TimeInterval(minutes * 60)
        lastMinutes = minutes
        defaults.set(minutes, forKey: Key.lastMinutes)
        set(.running(end: .now.addingTimeInterval(total)))
    }

    #if DEBUG
    func debugStart(seconds: TimeInterval) {
        total = seconds
        set(.running(end: .now.addingTimeInterval(seconds)))
    }
    #endif

    func pause() {
        // At zero the finish is a moment away; pausing then would hold a timer with nothing left.
        guard case .running = state, remaining() > 0.5 else { return }
        set(.paused(remaining: remaining()))
    }

    func resume() {
        guard case .paused(let remaining) = state else { return }
        set(.running(end: .now.addingTimeInterval(remaining)))
    }

    func toggle() {
        if isRunning { pause() } else { resume() }
    }

    /// Stop: a running, paused or finished timer goes away.
    func cancel() {
        total = 0
        set(.idle)
    }

    /// Starts the same length again after it finished.
    func repeatLast() {
        guard total > 0 else { return }
        set(.running(end: .now.addingTimeInterval(total)))
    }

    /// The dial and "+1 Min": whole minutes on or off what's left, never below ten seconds.
    /// Returns whether anything changed (an idle or finished timer has nothing to adjust).
    @discardableResult
    func adjust(minutes: Int) -> Bool {
        guard isRunning || { if case .paused = state { true } else { false } }() else { return false }
        let left = max(remaining() + TimeInterval(minutes * 60), Self.minimum)
        switch state {
        case .running:
            total = max(total + TimeInterval(minutes * 60), left)
            set(.running(end: .now.addingTimeInterval(left)))
        case .paused:
            total = max(total + TimeInterval(minutes * 60), left)
            set(.paused(remaining: left))
        case .idle, .done:
            break
        }
        return true
    }

    // MARK: State

    private func set(_ new: State) {
        state = new
        schedule()
        save()
        onChange?()
    }

    private func schedule() {
        task?.cancel()
        guard case .running(let end) = state else { return }
        task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(end.timeIntervalSinceNow, 0)))
            guard !Task.isCancelled, let self, case .running(let current) = self.state, current == end else { return }
            self.state = .done
            self.save()
            self.onChange?()
            self.onDone?()
        }
    }

    private enum Key {
        static let end = "timerEnd"
        static let paused = "timerPausedRemaining"
        static let total = "timerTotal"
        static let lastMinutes = "timerLastMinutes"
    }

    private func save() {
        defaults.removeObject(forKey: Key.end)
        defaults.removeObject(forKey: Key.paused)
        switch state {
        case .running(let end): defaults.set(end.timeIntervalSince1970, forKey: Key.end)
        case .paused(let remaining): defaults.set(remaining, forKey: Key.paused)
        case .idle, .done: break
        }
        defaults.set(state == .idle ? 0 : total, forKey: Key.total)
    }

    /// A timer that was running when Nook quit carries on; one that ran out meanwhile is dropped
    /// rather than ringing late.
    private func restore() {
        let last = defaults.integer(forKey: Key.lastMinutes)
        lastMinutes = last > 0 ? last : 5
        total = defaults.double(forKey: Key.total)
        let end = defaults.double(forKey: Key.end)
        let paused = defaults.double(forKey: Key.paused)
        if end > 0, Date(timeIntervalSince1970: end) > .now {
            state = .running(end: Date(timeIntervalSince1970: end))
            schedule()
        } else if paused > 0 {
            state = .paused(remaining: paused)
        } else {
            total = 0
            state = .idle
            save()
        }
    }
}

extension TimeInterval {
    /// "4:05", "1:02:05": a countdown, rounded up so it never shows 0:00 while time is left.
    var countdown: String {
        let total = Int(self.rounded(.up))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
