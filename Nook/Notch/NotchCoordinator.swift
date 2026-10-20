import AppKit
import SwiftUI

/// Wires system events into the island: picks the live activity, posts notifications,
/// keeps the panel on the right screen and out of the way of fullscreen apps.
final class NotchCoordinator {
    let model = NotchModel()
    let nowPlaying = NowPlayingModel()
    let calendar = CalendarModel()

    private let lock = LockMonitor()
    private let battery = BatteryMonitor()
    private let bluetooth = BluetoothMonitor()
    private let volume = VolumeService()
    private let brightness = BrightnessService()
    private let keys = MediaKeyTap()

    private var window: NotchWindowController?
    private var observers: [NSObjectProtocol] = []
    private var defaultsObserver: NSObjectProtocol?
    private var pauseGraceTask: Task<Void, Never>?
    private var nowPlayingVisible = false

    func start() {
        nowPlaying.onTrackChange = { [weak self] in self?.trackChanged() }
        nowPlaying.onPlaybackChange = { [weak self] in self?.playbackChanged() }
        nowPlaying.start()

        lock.onChange = { [weak self] in self?.refreshActivity() }
        lock.start()

        calendar.onChange = { [weak self] in self?.refreshActivity() }

        battery.onPowerSourceChange = { [weak self] reading in
            guard Prefs.bool(Prefs.battery) else { return }
            self?.model.post(reading.onAC ? .charging(level: reading.level) : .onBattery(level: reading.level), for: .seconds(2.6))
        }
        battery.onLowBattery = { [weak self] reading in
            guard Prefs.bool(Prefs.battery) else { return }
            self?.model.post(.lowBattery(level: reading.level), for: .seconds(4))
        }
        battery.onLowPowerModeChange = { [weak self] on in
            guard Prefs.bool(Prefs.battery) else { return }
            self?.model.post(.lowPowerMode(on: on), for: .seconds(2.2))
        }
        battery.start()

        bluetooth.onConnect = { [weak self] device in
            guard Prefs.bool(Prefs.connectivity) else { return }
            self?.model.post(.device(name: device.name, symbol: device.symbol, battery: nil), for: .seconds(3))
        }
        bluetooth.onBattery = { [weak self] device, level in
            guard let self, Prefs.bool(Prefs.connectivity),
                  case .device(let name, _, _) = self.model.notification, name == device.name
            else { return }
            self.model.post(.device(name: device.name, symbol: device.symbol, battery: level), for: .seconds(2.5))
        }
        if Prefs.bool(Prefs.connectivity) { bluetooth.start() }

        keys.handles = { key in
            switch key {
            case .volumeUp, .volumeDown, .mute: Prefs.bool(Prefs.volumeHUD)
            case .brightnessUp, .brightnessDown: Prefs.bool(Prefs.brightnessHUD)
            }
        }
        keys.onKey = { [weak self] key, fine in self?.mediaKey(key, fine: fine) }

        #if DEBUG
        if let dir = SnapshotRenderer.outputDirectory {
            model.notch = (NSScreen.target(for: .builtIn) ?? NSScreen.screens[0]).notchMetrics
            SnapshotRenderer.run(self, into: dir)
            return
        }
        #endif

        buildWindow()
        observeSystem()
        applyPreferences()

        #if DEBUG
        if DebugTour.isRequested { DebugTour.run(self) }
        if CommandLine.arguments.contains("-preview-playing") {
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                nowPlaying.previewPlaying()
                debugRefresh()
                if CommandLine.arguments.contains("-expand") { model.expand() }
                if CommandLine.arguments.contains("-peek") { model.showPeek(.track, for: nil) }
            }
        }
        #endif
    }

    #if DEBUG
    func debugRefresh() {
        nowPlayingVisible = true
        refreshActivity()
    }
    #endif

    // MARK: Window

    private func buildWindow() {
        let choice = DisplayChoice(rawValue: UserDefaults.standard.string(forKey: Prefs.display) ?? "") ?? .builtIn
        guard let screen = NSScreen.target(for: choice) else { return }
        if let window {
            window.place(on: screen)
            return
        }
        let window = NotchWindowController(screen: screen, model: model) {
            NotchRootView()
                .environment(model)
                .environment(nowPlaying)
                .environment(calendar)
        }
        window.onSwipe = { [weak self] direction in self?.swiped(direction) }
        self.window = window
    }

    private func observeSystem() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.buildWindow()
                self?.updateFullscreen()
            }
        })
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    // Space switches finish animating after the notification; check again once settled.
                    self?.updateFullscreen()
                    try? await Task.sleep(for: .milliseconds(450))
                    self?.updateFullscreen()
                }
            })
        }
        defaultsObserver = center.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.applyPreferences() }
        }
    }

    private var lastAppliedDisplay: String?
    private var lastCalendarEnabled: Bool?
    private var lastConnectivityEnabled: Bool?

    /// Runs on every defaults change, so each step only acts when its own setting moved.
    private func applyPreferences() {
        let display = UserDefaults.standard.string(forKey: Prefs.display)
        if display != lastAppliedDisplay {
            lastAppliedDisplay = display
            buildWindow()
        }
        let calendarEnabled = Prefs.bool(Prefs.calendar)
        if calendarEnabled != lastCalendarEnabled {
            lastCalendarEnabled = calendarEnabled
            calendar.update()
            model.showsCalendarColumn = calendarEnabled
        }
        let connectivityEnabled = Prefs.bool(Prefs.connectivity)
        if connectivityEnabled != lastConnectivityEnabled {
            if lastConnectivityEnabled != nil {
                if connectivityEnabled { bluetooth.start() } else { bluetooth.stop() }
            }
            lastConnectivityEnabled = connectivityEnabled
        }
        if Prefs.bool(Prefs.volumeHUD) || Prefs.bool(Prefs.brightnessHUD) {
            keys.start()
        } else {
            keys.stop()
        }
        updateFullscreen()
        refreshActivity()
    }

    /// Re-check Accessibility after the user grants it in System Settings.
    func retryKeyTap() {
        applyPreferences()
    }

    private func updateFullscreen() {
        guard let screen = window?.screen else { return }
        let hide = Prefs.bool(Prefs.hideInFullscreen) && FullscreenDetector.hasFullscreenWindow(on: screen)
        if hide != model.isSuppressed {
            model.isSuppressed = hide
            if hide { model.collapse() }
            window?.pointerMoved()
        }
    }

    // MARK: Live activity

    private func refreshActivity() {
        let activity: LiveActivity?
        switch lock.state {
        case .locked where Prefs.bool(Prefs.lockActivity):
            activity = .locked
        case .justUnlocked where Prefs.bool(Prefs.lockActivity):
            activity = .unlocked
        default:
            if Prefs.bool(Prefs.nowPlaying), nowPlaying.hasTrack, nowPlayingVisible {
                activity = .nowPlaying
            } else if Prefs.bool(Prefs.calendar), let event = calendar.eventForLiveActivity() {
                activity = .calendar(id: event.id)
            } else {
                activity = nil
            }
        }
        model.setLiveActivity(activity)
        if activity != .nowPlaying, model.peek == .track { model.hidePeek() }
    }

    private func playbackChanged() {
        pauseGraceTask?.cancel()
        if nowPlaying.isPlaying {
            nowPlayingVisible = true
            refreshActivity()
        } else {
            // A paused track lingers briefly so a quick pause/resume doesn't flicker the island.
            pauseGraceTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, let self else { return }
                if self.model.isHovering || self.model.isExpanded {
                    self.playbackChanged()
                    return
                }
                self.nowPlayingVisible = false
                self.refreshActivity()
            }
        }
    }

    private func trackChanged() {
        if model.hasPlayer != nowPlaying.hasTrack {
            withAnimation(model.isExpanded ? Motion.expand : nil) { model.hasPlayer = nowPlaying.hasTrack }
        }
        guard nowPlaying.hasTrack, nowPlaying.isPlaying || nowPlayingVisible else {
            refreshActivity()
            return
        }
        nowPlayingVisible = true
        refreshActivity()
        if Prefs.bool(Prefs.peekOnTrackChange), model.liveActivity == .nowPlaying, !model.isExpanded, model.notification == nil {
            model.showPeek(.track)
        }
    }

    // MARK: Input

    private func swiped(_ direction: SwipeDirection) {
        guard nowPlaying.hasTrack else { return }
        switch direction {
        case .left:
            nowPlaying.next()
            Haptics.tap()
        case .right:
            nowPlaying.previous()
            Haptics.tap()
        default:
            break
        }
    }

    private func mediaKey(_ key: MediaKeyTap.Key, fine: Bool) {
        switch key {
        case .volumeUp, .volumeDown:
            let result = volume.step(up: key == .volumeUp, fine: fine)
            model.post(.volume(level: result.level, muted: result.muted), for: .seconds(1.6))
        case .mute:
            let result = volume.toggleMute()
            model.post(.volume(level: result.level, muted: result.muted), for: .seconds(1.6))
        case .brightnessUp, .brightnessDown:
            let level = brightness.step(up: key == .brightnessUp, fine: fine)
            model.post(.brightness(level: level), for: .seconds(1.6))
        }
    }
}

enum FullscreenDetector {
    /// True when another app's window covers the whole screen, which is how fullscreen spaces look.
    static func hasFullscreenWindow(on screen: NSScreen) -> Bool {
        guard let primary = NSScreen.screens.first,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return false }
        // CoreGraphics window bounds use a top-left origin on the primary display.
        let target = CGRect(x: screen.frame.minX,
                            y: primary.frame.maxY - screen.frame.maxY,
                            width: screen.frame.width,
                            height: screen.frame.height)
        let me = ProcessInfo.processInfo.processIdentifier
        for info in windows {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowOwnerPID as String] as? pid_t) != me,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
            else { continue }
            if abs(bounds.minX - target.minX) < 1, abs(bounds.minY - target.minY) < 1,
               abs(bounds.width - target.width) < 1, abs(bounds.height - target.height) < 1 {
                return true
            }
        }
        return false
    }
}
