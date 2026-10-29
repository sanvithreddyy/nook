import Foundation
import Testing

/// The timer's arithmetic: pausing holds the time, the dial never goes below ten seconds,
/// and a timer survives a relaunch unless it ran out meanwhile.
@MainActor
struct TimerModelTests {
    let defaults: UserDefaults

    init() {
        let suite = "nook-timer-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
    }

    @Test func pausingHoldsTheTimeLeft() {
        let timer = TimerModel(defaults: defaults)
        timer.start(minutes: 5)
        timer.pause()
        let held = timer.remaining()
        #expect(held > 299 && held <= 300)
        #expect(timer.remaining(at: .now.addingTimeInterval(120)) == held)
        timer.resume()
        #expect(timer.isRunning)
    }

    @Test func theDialAddsMinutesAndStopsAtTenSeconds() {
        let timer = TimerModel(defaults: defaults)
        timer.start(minutes: 1)
        timer.adjust(minutes: 2)
        #expect(timer.remaining() > 179 && timer.remaining() <= 180)
        #expect(timer.total >= 180)
        timer.adjust(minutes: -10)
        #expect(timer.remaining() > 9 && timer.remaining() <= TimerModel.minimum)
    }

    @Test func aRunningTimerSurvivesARelaunch() {
        let first = TimerModel(defaults: defaults)
        first.start(minutes: 10)
        let second = TimerModel(defaults: defaults)
        #expect(second.isRunning)
        #expect(second.remaining() > 590)
        first.cancel()
        let third = TimerModel(defaults: defaults)
        #expect(third.state == .idle)
    }

    @Test func cancellingClearsEverything() {
        let timer = TimerModel(defaults: defaults)
        timer.start(minutes: 3)
        timer.cancel()
        #expect(timer.state == .idle)
        #expect(timer.total == 0)
        #expect(timer.fraction() == 0)
    }
}
