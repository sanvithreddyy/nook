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

/// Records display-link intervals on the main thread. Late callbacks mean the main thread
/// (where SwiftUI runs springs) was busy and a frame was missed.
final class FrameProbe: NSObject {
    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0
    private var intervals: [Double] = []

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
        last = 0
    }

    @objc private func tick(_ link: CADisplayLink) {
        if last > 0 { intervals.append(link.timestamp - last) }
        last = link.timestamp
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
