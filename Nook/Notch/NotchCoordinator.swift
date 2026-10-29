import AppKit
import SwiftUI

/// Wires system events into the island: picks the live activity, posts notifications,
/// keeps the panel on the right screen and out of the way of fullscreen apps.
final class NotchCoordinator {
    let model = NotchModel()
    let nowPlaying = NowPlayingModel()
    let calendar = CalendarModel()
    let shelf = ShelfModel()
    #if DEBUG
    /// Preview timers live in their own store, so a test timer never shows up in the real app.
    let timer = TimerModel(defaults: CommandLine.arguments.contains("-preview-timer") ? .preview : .standard)
    #else
    let timer = TimerModel()
    #endif

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

        timer.onChange = { [weak self] in self?.refreshActivity() }
        timer.onDone = { [weak self] in self?.timerDone() }

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
            self?.lastConnect = (device.name, .now)
            self?.model.post(.device(name: device.name, symbol: device.symbol, battery: nil), for: .seconds(3))
        }
        volume.onOutputChange = { [weak self] symbol, name in self?.outputChanged(to: symbol, name: name) }
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
            // Nook's panel isn't drawn on the lock screen or while suppressed, and an open card has no
            // room for the level, so the system's own HUD shows instead.
            guard let self, !self.model.isSuppressed, !self.model.isExpanded, self.lock.state != .locked else { return false }
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
            self.model.expand(card: .shelf)
        }
        fileDrags.onActiveChange = { [weak self] active in self?.model.setDraggingFile(active) }
        fileDrags.start()
        observeShelf()

        #if DEBUG
        if DebugTour.isRequested { DebugTour.run(self) }
        if CommandLine.arguments.contains("-preview-playing") {
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                nowPlaying.previewPlaying()
                debugRefresh()
                let args = CommandLine.arguments
                if args.contains("-preview-calendar") { calendar.debugPreview(meetingSoon: args.contains("-preview-meeting")) }
                // -preview-silent: what the island shows when nothing is playing.
                if args.contains("-preview-silent") {
                    nowPlaying.debugClear()
                    nowPlayingVisible = false
                    refreshActivity()
                }
                if args.contains("-preview-drag") { model.setDraggingFile(true) }
                if args.contains("-preview-timer") {
                    // -later: the drop splits off after a pause and merges back, for recording the motion.
                    if args.contains("-short") {
                        timer.debugStart(seconds: 4)
                    } else if args.contains("-later") {
                        try? await Task.sleep(for: .seconds(2))
                        timer.start(minutes: 5)
                        try? await Task.sleep(for: .seconds(2.5))
                        timer.cancel()
                    } else {
                        timer.start(minutes: 5)
                    }
                }
                if args.contains("-preview-shelf") {
                    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                    shelf.debugPreview(["scripts/build.sh", "project.yml", "Nook/Info.plist"].map { root.appendingPathComponent($0) })
                }
                if args.contains("-expand") {
                    model.expand(card: args.contains("-shelf") ? .shelf : args.contains("-timer-card") ? .timer : nil)
                }
                // -expand-later: open from the closed island after a pause, then close, for recording the motion.
                if args.contains("-expand-later") {
                    try? await Task.sleep(for: .seconds(2))
                    model.expand()
                    try? await Task.sleep(for: .seconds(2))
                    model.collapse()
                }
                if CommandLine.arguments.contains("-peek") { model.showPeek(.track, for: nil) }
                if CommandLine.arguments.contains("-hud") {
                    try? await Task.sleep(for: .seconds(1))
                    model.post(.volume(level: 0.62, muted: false, output: nil), for: .seconds(30))
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
                .environment(timer)
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
        defaultsObserver = center.addObserver(forName: UserDefaults.didChangeNotification, object: UserDefaults.standard, queue: .main) { [weak self] _ in
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
        let style = HUDStyle.current
        if model.hudStyle != style { model.hudStyle = style }
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

    /// What's going on, most important first: music the island is showing, a timer, a meeting about
    /// to start. The first is the island's own activity; the next becomes the drop beside it.
    private func liveActivities() -> [LiveActivity] {
        var live: [LiveActivity] = []
        if Prefs.bool(Prefs.nowPlaying), nowPlaying.hasTrack, nowPlayingVisible { live.append(.nowPlaying) }
        var timed: [(activity: LiveActivity, due: Date)] = []
        if timer.isActive { timed.append((.timer, .now.addingTimeInterval(timer.remaining()))) }
        if Prefs.bool(Prefs.calendar), let meeting = calendar.eventForLiveActivity() { timed.append((.calendar(id: meeting.id), meeting.start)) }
        // Of a timer and a meeting, whichever comes due first sits nearer the island.
        live += timed.sorted { $0.due < $1.due }.map(\.activity)
        return live
    }

    private func refreshActivity() {
        let live = liveActivities()
        let activity: LiveActivity?
        switch lock.state {
        case .locked where Prefs.bool(Prefs.lockActivity):
            activity = .locked
        case .justUnlocked where Prefs.bool(Prefs.lockActivity):
            activity = .unlocked
        default:
            activity = live.first
        }
        let hours = timer.remaining() >= 3600
        if model.timerShowsHours != hours { withAnimation(Motion.activityIn) { model.timerShowsHours = hours } }
        model.setLiveActivity(activity)
        // The next thing going on gets its own drop beside the island.
        model.setCompanion(activity == live.first && Prefs.bool(Prefs.showCompanion) ? live.dropFirst().first : nil)
        if activity != .nowPlaying, model.peek == .track { model.hidePeek() }
        refreshCards(live: live)
    }

    /// Runs on every calendar change and on the 30 s tick too, so a meeting that starts or the last
    /// event ending changes what the island opens to.
    private func refreshCards(live: [LiveActivity]? = nil) {
        let calendarOn = Prefs.bool(Prefs.calendar)
        let needsAccess = calendar.access != .granted
        let hasFiles = !shelf.isEmpty
        if model.calendarNeedsAccess != needsAccess || model.shelfHasFiles != hasFiles {
            withAnimation(model.isExpanded ? Motion.expand : nil) {
                model.calendarNeedsAccess = needsAccess
                model.shelfHasFiles = hasFiles
            }
        }
        model.setCards(IslandCard.available(
            live: (live ?? liveActivities()).compactMap(\.card),
            music: Prefs.bool(Prefs.nowPlaying) && nowPlaying.hasTrack,
            agenda: calendarOn && (needsAccess || !calendar.upcoming().isEmpty),
            shelf: Prefs.bool(Prefs.shelf)))
    }

    private func observeShelf() {
        withObservationTracking {
            _ = shelf.isEmpty
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.refreshCards()
                self?.observeShelf()
            }
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

    // MARK: Audio output

    /// The last Bluetooth device to connect, so its own connection view isn't followed by a switch view.
    private var lastConnect: (name: String, at: Date)?

    /// Sound moved to headphones that were already connected: AirPods' automatic switching, or a pick
    /// in Control Center. A device that just connected already showed its connection instead.
    private func outputChanged(to symbol: String?, name: String) {
        guard Prefs.bool(Prefs.connectivity), let symbol else { return }
        if let last = lastConnect, last.name == name, Date.now.timeIntervalSince(last.at) < 8 { return }
        model.post(.audioSwitched(symbol: symbol), for: .seconds(2.6))
    }

    // MARK: Timer

    private var doneTask: Task<Void, Never>?

    /// Like a ringing timer on iPhone: a sound, the island opens on the finished timer for a few
    /// seconds, then the notch keeps showing "Done" until it's stopped (or for ten minutes).
    private func timerDone() {
        #if DEBUG
        let previewing = CommandLine.arguments.contains("-preview-timer")
        #else
        let previewing = false
        #endif
        // Preview timers stay quiet, so testing doesn't chime on the Mac.
        let sound = UserDefaults.standard.string(forKey: Prefs.timerSound) ?? ""
        if !previewing, !sound.isEmpty { NSSound(named: sound)?.play() }
        Haptics.tap()
        // A file drag holding the shelf open keeps it; the notch shows "Done" until it's stopped.
        if !model.isSuppressed, !model.isDraggingFile { model.expand(card: .timer) }
        doneTask?.cancel()
        doneTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard let self, !Task.isCancelled else { return }
            if self.model.isExpanded, self.model.card == .timer, !self.model.isHovering { self.model.collapse() }
            try? await Task.sleep(for: .seconds(10 * 60 - 8))
            guard !Task.isCancelled, self.timer.state == .done else { return }
            self.timer.cancel()
        }
    }

    // MARK: Input

    /// Sideways on the open island turns cards; on the closed island it skips tracks.
    private func swiped(_ direction: SwipeDirection) {
        if model.isExpanded {
            switch direction {
            case .left: model.page(1)
            case .right: model.page(-1)
            default: break
            }
            return
        }
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
            let up = key == .volumeUp
            let before = volume.volume
            let result = volume.step(up: up, fine: fine)
            bumpIfAtEnd(kind: "volume", before: before, after: result.level, up: up)
            model.post(.volume(level: result.level, muted: result.muted, output: volume.headphones), for: .seconds(1.6))
        case .mute:
            let result = volume.toggleMute()
            model.post(.volume(level: result.level, muted: result.muted, output: volume.headphones), for: .seconds(1.6))
        case .brightnessUp, .brightnessDown:
            let up = key == .brightnessUp
            let before = brightness.level
            let level = brightness.step(up: up, fine: fine)
            bumpIfAtEnd(kind: "brightness", before: before, after: level, up: up)
            model.post(.brightness(level: level), for: .seconds(1.6))
        }
    }

    /// Pressing on at the top or bottom stretches the bar that's already showing, instead of nothing.
    /// Only that HUD's own bar (brightness showing doesn't stretch for a volume press), and with a
    /// little slack, since a display can read back a hair off 1.
    private func bumpIfAtEnd(kind: String, before: Float, after: Float, up: Bool) {
        let end: Float = up ? 1 : 0
        guard model.notification?.kind == kind, abs(after - before) < 0.001, abs(after - end) < 0.001 else { return }
        model.bumpHUD(up: up)
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

#if DEBUG
private extension UserDefaults {
    static let preview: UserDefaults = {
        let suite = "com.sanvith.nook.preview"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }()
}
#endif
