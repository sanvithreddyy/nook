import AppKit
import SwiftUI

/// Wires system events into the island: picks the live activity, posts notifications,
/// keeps the panel on the right screen and out of the way of fullscreen apps.
final class NotchCoordinator {
    let model = NotchModel()
    let nowPlaying = NowPlayingModel()
    let calendar = CalendarModel()
    let shelf = ShelfModel()

    private let lock = LockMonitor()
    private let battery = BatteryMonitor()
    private let bluetooth = BluetoothMonitor()
    private let volume = VolumeService()
    private let brightness = BrightnessService()
    private let keys = MediaKeyTap()
    private let fileDrags = FileDragWatcher()

    private var window: NotchWindowController?
    private var observers: [NSObjectProtocol] = []
    private var defaultsObserver: NSObjectProtocol?
    private var pauseGraceTask: Task<Void, Never>?
    private var permissionTask: Task<Void, Never>?
    private var nowPlayingVisible = false
    /// A low-battery warning raised while the island was hidden, shown once it's back.
    private var pendingLowBattery: Int?

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
            guard let self, Prefs.bool(Prefs.battery) else { return }
            if self.model.isSuppressed {
                self.pendingLowBattery = reading.level
            } else {
                self.model.post(.lowBattery(level: reading.level), for: .seconds(4))
            }
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

        // Swallow a key only when Nook can both act on it and show the result;
        // otherwise the system handles it as usual.
        keys.handles = { [weak self] key in
            // Nook's panel isn't drawn on the lock screen or while suppressed.
            guard let self, !self.model.isSuppressed, self.lock.state != .locked else { return false }
            switch key {
            case .volumeUp, .volumeDown: return Prefs.bool(Prefs.volumeHUD) && self.volume.canSetVolume
            case .mute: return Prefs.bool(Prefs.volumeHUD) && self.volume.canMute
            case .brightnessUp, .brightnessDown: return Prefs.bool(Prefs.brightnessHUD) && self.brightness.isAvailable
            }
        }
        keys.onKey = { [weak self] key, fine in self?.mediaKey(key, fine: fine) }
        // Accessibility revoked mid-session: wait for it to come back.
        keys.onRevoked = { [weak self] in self?.watchPermissions() }

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

        // Dragging a file to the notch opens the shelf as a drop target.
        fileDrags.onEnterNotch = { [weak self] in
            guard let self, Prefs.bool(Prefs.shelf), !self.model.isSuppressed else { return }
            self.model.expand(tab: .shelf)
        }
        fileDrags.start()

        #if DEBUG
        if DebugTour.isRequested { DebugTour.run(self) }
        if CommandLine.arguments.contains("-preview-playing") {
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                nowPlaying.previewPlaying()
                debugRefresh()
                let args = CommandLine.arguments
                if args.contains("-preview-calendar") { calendar.debugPreview() }
                // -preview-silent: what the island shows when nothing is playing.
                if args.contains("-preview-silent") {
                    nowPlaying.debugClear()
                    model.hasPlayer = false
                    nowPlayingVisible = false
                    refreshActivity()
                }
                if args.contains("-preview-shelf") {
                    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                    shelf.debugPreview(["scripts/build.sh", "project.yml", "Nook/Info.plist"].map { root.appendingPathComponent($0) })
                }
                if args.contains("-expand") { model.expand(tab: args.contains("-shelf") ? .shelf : .home) }
                if CommandLine.arguments.contains("-peek") { model.showPeek(.track, for: nil) }
                if CommandLine.arguments.contains("-hud") {
                    try? await Task.sleep(for: .seconds(1))
                    model.post(.volume(level: 0.62, muted: false), for: .seconds(30))
                }
            }
        }
        #endif
    }

    func stop() {
        nowPlaying.stop()
        keys.stop()
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
                .environment(shelf)
        }
        fileDrags.isInsideNotch = { [weak window] point in window?.catchesDrag(at: point) ?? false }
        window.isFileDragActive = { [weak self] in self?.fileDrags.isActive ?? false }
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
                    try? await Task.sleep(for: .milliseconds(800))
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
        }
        let connectivityEnabled = Prefs.bool(Prefs.connectivity)
        if connectivityEnabled != lastConnectivityEnabled {
            if lastConnectivityEnabled != nil {
                if connectivityEnabled { bluetooth.start() } else { bluetooth.stop() }
            }
            lastConnectivityEnabled = connectivityEnabled
        }
        if wantsKeyTap {
            keys.start()
        } else {
            keys.stop()
        }
        let hasPlayer = Prefs.bool(Prefs.nowPlaying) && nowPlaying.hasTrack
        if model.hasPlayer != hasPlayer { model.hasPlayer = hasPlayer }
        watchPermissions()
        updateFullscreen()
        refreshActivity()
    }

    private var wantsKeyTap: Bool { Prefs.bool(Prefs.volumeHUD) || Prefs.bool(Prefs.brightnessHUD) }

    /// Accessibility is granted in System Settings while Nook isn't frontmost, after the user turned
    /// a HUD on; poll quietly until it arrives, then stop. (Calendar access is re-checked when the
    /// island opens instead, so nobody who skips it gets a poll forever.)
    private func watchPermissions() {
        let keysPending = wantsKeyTap && !keys.isRunning
        guard keysPending else {
            permissionTask?.cancel()
            permissionTask = nil
            return
        }
        guard permissionTask == nil else { return }
        permissionTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self else { return }
                if self.wantsKeyTap, !self.keys.isRunning { self.keys.start() }
                if !(self.wantsKeyTap && !self.keys.isRunning) {
                    self.permissionTask = nil
                    return
                }
            }
        }
    }

    private func updateFullscreen() {
        guard let screen = window?.screen else { return }
        let hide = Prefs.bool(Prefs.hideInFullscreen) && FullscreenDetector.isFullscreen(on: screen)
        guard hide != model.isSuppressed else { return }
        model.isSuppressed = hide
        if hide { model.collapse() }
        window?.setSuppressed(hide)
        if !hide, let level = pendingLowBattery {
            pendingLowBattery = nil
            // Skip it if the Mac was plugged in while the island was hidden.
            if battery.reading?.onAC == false {
                model.post(.lowBattery(level: level), for: .seconds(4))
            }
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

        // Runs on every calendar change and on the 30 s tick, so the last event ending shrinks the island.
        let agenda = Prefs.bool(Prefs.calendar) && (calendar.access != .granted || !calendar.upcoming().isEmpty)
        if model.showsAgenda != agenda {
            withAnimation(model.isExpanded ? Motion.expand : nil) { model.showsAgenda = agenda }
        }
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
        let hasPlayer = Prefs.bool(Prefs.nowPlaying) && nowPlaying.hasTrack
        if model.hasPlayer != hasPlayer {
            withAnimation(model.isExpanded ? Motion.expand : nil) { model.hasPlayer = hasPlayer }
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
        guard Prefs.bool(Prefs.nowPlaying), nowPlaying.hasTrack else { return }
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
    /// A fullscreen space has no menu bar window on that display (unless the pointer reveals it)
    /// and another app's window spans the screen's full width from the top of the usable area.
    /// Both must hold, so an auto-hidden menu bar or a zoomed window alone doesn't hide the island.
    static func isFullscreen(on screen: NSScreen) -> Bool {
        guard let primary = NSScreen.screens.first,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return false }
        // CoreGraphics window bounds use a top-left origin on the primary display.
        let target = CGRect(x: screen.frame.minX,
                            y: primary.frame.maxY - screen.frame.maxY,
                            width: screen.frame.width,
                            height: screen.frame.height)
        let me = ProcessInfo.processInfo.processIdentifier
        var menuBarVisible = false
        var coveringWindow = false
        for info in windows {
            guard let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  bounds.intersects(target)
            else { continue }
            let layer = info[kCGWindowLayer as String] as? Int ?? 0
            let owner = info[kCGWindowOwnerName as String] as? String
            if layer == Int(CGWindowLevelForKey(.mainMenuWindow)), owner == "Window Server", abs(bounds.minY - target.minY) < 1 {
                menuBarVisible = true
            }
            if layer == 0, (info[kCGWindowOwnerPID as String] as? pid_t) != me,
               abs(bounds.width - target.width) < 1,
               // A maximized window starts under the menu bar (33 pt on a 14" MBP, notch 32 pt);
               // a fullscreen one starts at or above the notch line.
               bounds.minY - target.minY <= screen.safeAreaInsets.top,
               abs(bounds.maxY - target.maxY) < 1 {
                coveringWindow = true
            }
        }
        return coveringWindow && !menuBarVisible
    }
}
