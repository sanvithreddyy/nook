#if DEBUG
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
            ("volume", { m.post(.volume(level: 0.56, muted: false), for: .seconds(2.4)) }),
            ("volume-up", { m.post(.volume(level: 0.62, muted: false), for: .seconds(1.6)) }),
            ("brightness", { m.post(.brightness(level: 0.75), for: .seconds(2.2)) }),
            ("charging", { m.post(.charging(level: 84), for: .seconds(2.4)) }),
            ("device", { m.post(.device(name: "AirPods Pro", symbol: "airpodspro", battery: 82), for: .seconds(2.4)) }),
            ("lowBattery", { m.post(.lowBattery(level: 12), for: .seconds(2.4)) }),
            ("expanded2", { m.expand() }),
            ("collapsed2", { m.collapse() }),
            ("paused", { c.nowPlaying.previewPaused() }),
            ("end", {}),
        ]
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            for (name, action) in steps {
                print("TOUR \(name) \(Date().timeIntervalSince1970)")
                fflush(stdout)
                action()
                try? await Task.sleep(for: .seconds(2.5))
            }
        }
    }
}
#endif
