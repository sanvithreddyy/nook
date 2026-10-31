#if DEBUG
import SwiftUI

/// Launch with `-snapshots <dir>` to render every island state over a system wallpaper
/// at 2x and quit. Used by scripts/snapshots.sh to review layout without a fullscreen app in the way.
enum SnapshotRenderer {
    static var outputDirectory: URL? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "-snapshots"), i + 1 < args.count else { return nil }
        return URL(fileURLWithPath: args[i + 1], isDirectory: true)
    }

    static func run(_ c: NotchCoordinator, into dir: URL) {
        Motion.isDisabled = true
        let m = c.model
        // No panel in this mode; the island is drawn on a canvas of this size instead.
        m.panelSize = size
        let wallpaper = NSImage(contentsOfFile: "/System/Library/Desktop Pictures/Sonoma.heic")
        let two = [("New York", "America/New_York"), ("Bengaluru", "Asia/Kolkata")]
        let four = [("Chicago", "America/Chicago"), ("Hyderabad", "Asia/Kolkata"), ("London", "Europe/London"), ("Tokyo", "Asia/Tokyo")]
        let states: [(String, () -> Void)] = [
            ("01-idle", {}),
            ("02-hover", { m.setHovering(true) }),
            ("03-now-playing", { c.nowPlaying.previewPlaying(); c.debugRefresh() }),
            ("04-peek", { c.nowPlaying.previewPlaying(); c.debugRefresh(); m.showPeek(.track, for: nil) }),
            ("05-expanded", { c.nowPlaying.previewPlaying(); c.debugRefresh(); m.expand() }),
            ("06-volume", { m.post(.volume(level: 0.56, muted: false, output: nil)) }),
            ("06a-volume-airpods", { m.post(.volume(level: 0.7, muted: false, output: "airpods.pro")) }),
            ("06b-volume-slider", { m.hudStyle = .slider; m.post(.volume(level: 0.62, muted: false, output: nil)) }),
            ("06c-volume-steps", { m.hudStyle = .segments; m.post(.volume(level: 0.62, muted: false, output: nil)) }),
            ("06d-volume-outline", { m.hudStyle = .outline; m.post(.volume(level: 0.62, muted: false, output: nil)) }),
            ("07-muted", { m.hudStyle = .ledge; m.post(.volume(level: 0.56, muted: true, output: nil)) }),
            ("08-brightness", { m.post(.brightness(level: 0.75)) }),
            ("09-charging", { m.post(.charging(level: 84)) }),
            ("10-on-battery", { m.post(.onBattery(level: 84)) }),
            ("11-low-battery", { m.post(.lowBattery(level: 20)) }),
            ("11a-low-power-on", { m.post(.lowPowerMode(on: true, level: 62)) }),
            ("11b-low-power-off", { m.post(.lowPowerMode(on: false, level: 62)) }),
            ("12a-device-no-level", { m.post(.device(name: "Magic Keyboard", symbol: "keyboard", battery: nil)) }),
            ("12-device", { m.post(.device(name: "AirPods Pro", symbol: "airpods.pro.gen1", battery: 87)) }),
            ("12b-audio-switched", { m.post(.audioSwitched(symbol: "airpods.pro.gen1")) }),
            ("13-locked", { m.debugSetActivity(.locked) }),
            ("14-unlocked", { m.debugSetActivity(.unlocked) }),
            ("15-up-next", { c.nowPlaying.debugClear(); c.calendar.debugPreview(); c.debugRefresh(); m.expand() }),
            ("16-meeting", { c.nowPlaying.debugClear(); c.calendar.debugPreview(meetingSoon: true); c.debugRefresh(); m.expand() }),
            ("17-shelf-drop", { c.shelf.debugPreview([]); c.debugRefresh(); m.setDraggingFile(true); m.expand(card: .shelf) }),
            ("18-shelf", { c.shelf.debugPreview(SnapshotRenderer.sampleFiles); c.debugRefresh(); m.expand(card: .shelf) }),
            ("19-shelf-empty", { c.shelf.debugPreview([]); c.debugRefresh(); m.expand(card: .shelf) }),
            ("20-batteries", { c.batteries.debugPreview(); c.debugRefresh(); m.expand(card: .home([.batteries])) }),
            ("21-timer", { c.nowPlaying.debugClear(); c.timer.debugShow(.running(end: .now.addingTimeInterval(297)), total: 300); m.expand(card: .timer) }),
            ("21a-timer-paused", { c.nowPlaying.debugClear(); c.timer.debugShow(.paused(remaining: 754), total: 900); m.expand(card: .timer) }),
            ("21b-timer-done", { c.nowPlaying.debugClear(); c.timer.debugShow(.done, total: 300); m.expand(card: .timer) }),
            ("22-meeting-under-way", { c.nowPlaying.debugClear(); c.timer.debugShow(.idle, total: 0); c.calendar.debugPreview(meetingSoon: true, startsIn: -240); c.debugRefresh(); m.expand() }),
            ("24-clock-two", { SnapshotRenderer.clock(two, .analog); c.nowPlaying.previewPlaying(); c.debugRefresh(); m.expand(card: .home([.clock])) }),
            ("24a-clock-four", { SnapshotRenderer.clock(four, .analog); c.debugRefresh(); m.expand(card: .home([.calendar, .clock])) }),
            ("24b-digital-two", { SnapshotRenderer.clock(two, .digital); c.debugRefresh(); m.expand(card: .home([.clock])) }),
            ("24c-digital-four", { SnapshotRenderer.clock(four, .digital); c.debugRefresh(); m.expand(card: .home([.calendar, .clock])) }),
            // Last: a screen without a notch, with the island as a pill.
            ("23-pill-idle", { m.notch = NotchMetrics(size: CGSize(width: 185, height: 32), isHardware: false, isPill: true) }),
            ("23a-pill-playing", { c.nowPlaying.previewPlaying(); c.timer.debugShow(.idle, total: 0); c.calendar.debugPreview(); c.debugRefresh() }),
            ("23b-pill-volume", { m.post(.volume(level: 0.56, muted: false, output: nil)) }),
            ("23c-pill-low-battery", { m.post(.lowBattery(level: 20)) }),
            ("23d-pill-open", { c.nowPlaying.previewPlaying(); c.debugRefresh(); m.expand() }),
        ]
        Task { @MainActor in
            // Let the now-playing stream deliver real metadata first.
            try? await Task.sleep(for: .seconds(1.5))
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for (name, setup) in states {
                m.debugReset()
                setup()
                try? await Task.sleep(for: .milliseconds(150))
                render(c, wallpaper: wallpaper, to: dir.appendingPathComponent("\(name).png"))
            }
            NSApp.terminate(nil)
        }
    }

    /// World Clock cities and style for this run only; nothing is saved.
    static func clock(_ cities: [(String, String)], _ style: ClockStyle) {
        UserDefaults.standard.setVolatileDomain([
            Prefs.clockPlaces: Place.json(cities.map { Place(name: $0.0, latitude: 0, longitude: 0, timeZoneID: $0.1) }),
            Prefs.clockStyle: style.rawValue,
        ], forName: UserDefaults.argumentDomain)
    }

    static var sampleFiles: [URL] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return ["project.yml", "scripts/build.sh", "scripts/tour.sh", "Nook/Info.plist"].map { root.appendingPathComponent($0) }
    }

    private static let size = CGSize(width: 820, height: 260)

    private static func render(_ c: NotchCoordinator, wallpaper: NSImage?, to url: URL) {
        let view = ZStack(alignment: .top) {
            if let wallpaper {
                Image(nsImage: wallpaper)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height, alignment: .top)
                    .clipped()
            }
            NotchRootView()
                .environment(c.model)
                .environment(c.nowPlaying)
                .environment(c.calendar)
                .environment(c.shelf)
                .environment(c.timer)
                .environment(c.batteries)
                .environment(c.weather)
                .environment(c.reminders)
                .environment(c.shortcuts)
                .environment(c.outputs)
        }
        .frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.cgImage else { return }
        let rep = NSBitmapImageRep(cgImage: image)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}

extension NotchModel {
    func debugReset() {
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            collapse()
            hidePeek()
            dismissNotification()
            setHovering(false)
            setDraggingFile(false)
        }
    }

    func debugSetActivity(_ activity: LiveActivity?) {
        setLiveActivity(activity)
    }
}
#endif
