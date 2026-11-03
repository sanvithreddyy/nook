#if DEBUG
import QuartzCore
import SwiftUI

/// Launch with `-tour` to step through every island state on a fixed schedule,
/// so scripts/tour.sh can record each one without touching real playback or hardware.
enum DebugTour {
    static var isRequested: Bool { CommandLine.arguments.contains("-tour") }

    static func run(_ c: NotchCoordinator) {
        let m = c.model
        let steps: [(String, () -> Void)] = [
            ("idle", {}),
            ("hover", { m.setHovering(true) }),
            ("unhover", { m.setHovering(false) }),
            ("nowPlaying", { c.nowPlaying.previewPlaying(); c.debugRefresh() }),
            ("peek", { m.showPeek(.track, for: nil) }),
            ("unpeek", { m.hidePeek() }),
            ("expanded", { m.expand() }),
            ("collapsed", { m.collapse() }),
            ("volume", { m.post(.volume(level: 0.56, muted: false, output: nil), for: .seconds(2.4)) }),
            ("volume-up", { m.post(.volume(level: 0.62, muted: false, output: nil), for: .seconds(1.6)) }),
            ("brightness", { m.post(.brightness(level: 0.75), for: .seconds(2.2)) }),
            ("charging", { m.post(.charging(level: 84), for: .seconds(2.4)) }),
            ("device", { m.post(.device(name: "AirPods Pro", symbol: "airpodspro", battery: 82), for: .seconds(2.4)) }),
            ("lowBattery", { m.post(.lowBattery(level: 12), for: .seconds(2.4)) }),
            ("expanded2", { m.expand() }),
            ("collapsed2", { m.collapse() }),
            ("paused", { c.nowPlaying.previewPaused() }),
            ("end", {}),
        ]
        let probe = FrameProbe()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            probe.start(on: NSScreen.target(for: .builtIn) ?? NSScreen.screens[0])
            for (name, action) in steps {
                print("TOUR \(name) \(Date().timeIntervalSince1970)")
                probe.reset()
                action()
                // Measure the first second after the change, where the springs run.
                try? await Task.sleep(for: .seconds(1))
                print("PROBE \(name) \(probe.report())")
                fflush(stdout)
                try? await Task.sleep(for: .seconds(1.5))
            }
            probe.stop()
        }
    }
}

/// -probe-swipes: the frames each two-finger page swipe missed, real or scripted (-gesture-fuzz), printed as
/// GESTURE lines: the late frames as when each ended and how long it took (ms after the touch), beside the
/// moments the page was picked up, let go and landed.
enum GestureProbe {
    static let isOn = CommandLine.arguments.contains("-probe-swipes")
    private static var probe: FrameProbe?
    private static var count = 0
    private static var startedAt: TimeInterval = 0

    static func began() {
        guard isOn else { return }
        if probe == nil {
            let new = FrameProbe()
            new.start(on: NSScreen.target(for: .builtIn) ?? NSScreen.screens[0])
            probe = new
        }
        probe?.reset()
        marks = []
        startedAt = Date().timeIntervalSince1970
    }

    private static var marks: [(String, CFTimeInterval)] = []

    /// A moment in the swipe (the page picked up, let go, landed), printed beside the late frames.
    static func mark(_ name: String) {
        guard isOn, probe != nil else { return }
        marks.append((name, CACurrentMediaTime()))
    }

    static func ended() {
        guard isOn, let probe else { return }
        let started = startedAt
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.8))
            count += 1
            print("GESTURE \(count) \(probe.report()) began=\(String(format: "%.3f", started)) lateAt=[\(probe.lateFrames())] marks=[\(marks.map { String(format: "%@:%.0f", $0.0, ($0.1 - probe.firstFrame) * 1000) }.joined(separator: " "))]")
            fflush(stdout)
        }
    }
}

/// Records display-link intervals on the main thread. Late callbacks mean the main thread
/// (where SwiftUI runs springs) was busy and a frame was missed.
final class FrameProbe: NSObject {
    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0
    private var first: CFTimeInterval = 0
    private var intervals: [Double] = []
    private var stamps: [CFTimeInterval] = []

    func start(on screen: NSScreen) {
        let link = screen.displayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 120, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    func reset() {
        intervals.removeAll()
        stamps.removeAll()
        last = 0
    }

    @objc private func tick(_ link: CADisplayLink) {
        if last > 0 { intervals.append(link.timestamp - last) } else { first = link.timestamp }
        last = link.timestamp
        stamps.append(link.timestamp)
    }

    var firstFrame: CFTimeInterval { first }

    /// The late frames, as when each ended (ms after the first frame) and how long it took.
    func lateFrames() -> String {
        guard !intervals.isEmpty else { return "" }
        let median = intervals.sorted()[intervals.count / 2]
        return intervals.indices.filter { intervals[$0] > median * 1.5 }
            .map { String(format: "%.0f:%.0f", (stamps[$0 + 1] - first) * 1000, intervals[$0] * 1000) }
            .joined(separator: " ")
    }

    func report() -> String {
        guard !intervals.isEmpty else { return "frames=0" }
        let sorted = intervals.sorted()
        let median = sorted[sorted.count / 2]
        let late = intervals.filter { $0 > median * 1.5 }.count
        let maxMs = (sorted.last ?? 0) * 1000
        return String(format: "frames=%d median=%.2fms max=%.2fms late=%d", intervals.count, median * 1000, maxMs, late)
    }
}
#endif
