import AppKit
import SwiftUI

/// Wires system events into the island: picks the live activity, posts notifications,
/// keeps the panel on the right screen and out of the way of fullscreen apps.
/// With "All displays" every screen has its own island: each opens, hovers and hides for full screen
/// on its own, and everything they show (notices, activities, the home) goes to all of them.
final class NotchCoordinator {
    /// The island on the chosen display, or on the built-in one with all displays.
    let model = NotchModel()
    let nowPlaying = NowPlayingModel()
    let calendar = CalendarModel()
    let shelf = ShelfModel()
    let batteries = DeviceBatteries()
    let weather = WeatherModel()
    let reminders = RemindersModel()
    let shortcuts = ShortcutsModel()
    let outputs = AudioOutputs()
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
    private let hotKeys = HotKeys.shared
    private let brightness = BrightnessService()
    private let keys = MediaKeyTap()
    private let fileDrags = FileDragWatcher()

    private var window: NotchWindowController?
    /// With all displays, the islands on the other screens.
    private var others: [(model: NotchModel, window: NotchWindowController)] = []
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
        // The playing app can arrive after its track; what the island shows and hides depends on it.
        nowPlaying.onSourceChange = { [weak self] in
            self?.refreshActivity()
            self?.updateFullscreen()
        }
        nowPlaying.start()

        lock.onChange = { [weak self] in self?.refreshActivity() }
        lock.start()

        calendar.onChange = { [weak self] in
            self?.refreshActivity()
            self?.scheduleEventStart()
        }

        hotKeys.onPress = { [weak self] action in self?.shortcut(action) }
        timer.onChange = { [weak self] in self?.refreshActivity() }
        timer.onDone = { [weak self] in self?.timerDone() }

        battery.onReadingChange = { [weak self] reading, lowPower in self?.batteries.updateMac(reading, lowPower: lowPower) }
        battery.onPowerSourceChange = { [weak self] reading in
            guard Prefs.bool(Prefs.battery) else { return }
            self?.everyIsland { $0.post(reading.onAC ? .charging(level: reading.level) : .onBattery(level: reading.level),
                                        for: .seconds(Prefs.double(Prefs.batteryNoticeDuration))) }
        }
        battery.onLowBattery = { [weak self] reading in
            guard let self, Prefs.bool(Prefs.battery), Prefs.bool(Prefs.lowBatteryWarning) else { return }
            if self.islands.allSatisfy(\.model.isSuppressed) {
                self.pendingLowBattery = reading.level
            } else {
                self.warnLowBattery(reading.level)
            }
        }
        battery.onLowPowerModeChange = { [weak self] on in
            guard Prefs.bool(Prefs.battery), Prefs.bool(Prefs.lowPowerNotice) else { return }
            let level = self?.battery.reading?.level ?? 100
            self?.everyIsland { $0.post(.lowPowerMode(on: on, level: level), for: .seconds(2.2)) }
        }
        battery.start()

        bluetooth.onConnect = { [weak self] device, level in
            guard let self, Prefs.bool(Prefs.connectivity) else { return }
            self.everyIsland { $0.post(.device(name: device.name, symbol: device.symbol, battery: level),
                                       for: .seconds(Prefs.double(Prefs.deviceNoticeDuration))) }
            self.batteries.refresh(force: true)
        }
        volume.onOutputChange = { [weak self] symbol, name in self?.outputChanged(to: symbol, name: name) }
        if Prefs.bool(Prefs.connectivity) { bluetooth.start() }
        batteries.refresh(force: true)

        // Swallow a key only when Nook can both act on it and show the result;
        // otherwise the system handles it as usual.
        keys.handles = { [weak self] key in
            // Nook's panel isn't drawn on the lock screen or while suppressed, and an open card has no
            // room for the level, so the system's own HUD shows instead.
            // The island looked at is the one under the pointer.
            guard let self, !self.activeModel.isSuppressed, !self.activeModel.isExpanded, self.lock.state != .locked else { return false }
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
        fileDrags.isInsideNotch = { [weak self] point in
            self?.islands.contains { $0.window.catchesDrag(at: point) } ?? false
        }
        fileDrags.onEnterNotch = { [weak self] in
            guard let self, Prefs.bool(Prefs.shelf),
                  let island = self.islands.first(where: { $0.window.catchesDrag(at: NSEvent.mouseLocation) }),
                  !island.model.isSuppressed else { return }
            island.model.expand(card: .shelf)
        }
        fileDrags.onActiveChange = { [weak self] active in self?.everyIsland { $0.setDraggingFile(active) } }
        fileDrags.start()
        observeShelf()
        observeModuleData()
        observePreview()
        shortcuts.refresh()

        #if DEBUG
        if DebugTour.isRequested { DebugTour.run(self) }
        if CommandLine.arguments.contains("-preview-playing") {
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                nowPlaying.previewPlaying()
                debugRefresh()
                let args = CommandLine.arguments
                // -preview-meeting-in <s>: the sample meeting starts that many seconds after launch.
                let startsIn = args.firstIndex(of: "-preview-meeting-in").flatMap { args.indices.contains($0 + 1) ? Double(args[$0 + 1]) : nil }
                if args.contains("-preview-calendar") { calendar.debugPreview(meetingSoon: args.contains("-preview-meeting"), startsIn: startsIn) }
                if args.contains("-preview-batteries") { batteries.debugPreview() }
                // -preview-places: real weather for Chicago and Tokyo and four clock cities, for this run
                // only (nothing is saved).
                if args.contains("-preview-places") {
                    let place = { (name: String, lat: Double, lon: Double, zone: String) in Place(name: name, latitude: lat, longitude: lon, timeZoneID: zone) }
                    UserDefaults.standard.setVolatileDomain([
                        Prefs.weatherCurrentLocation: false,
                        Prefs.weatherPlaces: Place.json([place("Chicago", 41.878, -87.63, "America/Chicago"), place("Tokyo", 35.68, 139.69, "Asia/Tokyo")]),
                        Prefs.clockPlaces: Place.json([place("Chicago", 0, 0, "America/Chicago"), place("Hyderabad", 0, 0, "Asia/Kolkata"),
                                                       place("London", 0, 0, "Europe/London"), place("Tokyo", 0, 0, "Asia/Tokyo")]),
                        // -preview-digital: the clock in digits.
                        Prefs.clockStyle: args.contains("-preview-digital") ? ClockStyle.digital.rawValue : ClockStyle.analog.rawValue,
                    ], forName: UserDefaults.argumentDomain)
                    weather.refresh(force: true)
                }
                // -preview-modules: sample weather, reminders and shortcuts, for designing those modules.
                if args.contains("-preview-modules") {
                    weather.debugPreview()
                    reminders.debugPreview()
                    shortcuts.debugPreview()
                }
                // -home-one, -home-three, -home-small, -home-large: a home layout for this run only.
                if args.contains("-home-one") { debugHome.layout = .oneAtATime }
                if args.contains("-home-three") { debugHome.columns = 3 }
                if args.contains("-home-small") { debugHome.size = .small }
                if args.contains("-home-large") { debugHome.size = .large }
                applyPreferences()
                // -preview-silent: what the island shows when nothing is playing.
                if args.contains("-preview-silent") {
                    nowPlaying.debugClear()
                    nowPlayingVisible = false
                    refreshActivity()
                }
                if args.contains("-preview-drag") { model.setDraggingFile(true) }
                // -preview-next-in <s>: the sample track changes that many seconds later.
                if let i = args.firstIndex(of: "-preview-next-in"), args.indices.contains(i + 1), let delay = Double(args[i + 1]) {
                    Task {
                        try? await Task.sleep(for: .seconds(delay))
                        nowPlaying.debugNextTrack()
                    }
                }
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
                    // -preview-shelf-full: more files than the row has places, for the stack.
                    let files = args.contains("-preview-shelf-full")
                        ? ["project.yml", "scripts/build.sh", "Nook/Info.plist", "scripts/tour.sh", "scripts/capture.sh", "scripts/cpu.sh", "scripts/test.sh", "scripts/snapshots.sh"]
                        : ["project.yml", "scripts/build.sh", "Nook/Info.plist"]
                    shelf.debugPreview(files.map { root.appendingPathComponent($0) })
                }
                if args.contains("-expand") {
                    // -page <n>: the nth page, to capture each page.
                    let page = args.firstIndex(of: "-page").flatMap { args.indices.contains($0 + 1) ? Int(args[$0 + 1]) : nil }
                        .flatMap { model.cards.indices.contains($0) ? model.cards[$0] : nil }
                    model.expand(card: args.contains("-shelf") ? .shelf : args.contains("-timer-card") ? .timer : page)
                }
                // -expand-later: open from the closed island after a pause, then close, for recording the motion.
                if args.contains("-expand-later") {
                    try? await Task.sleep(for: .seconds(2))
                    model.expand()
                    try? await Task.sleep(for: .seconds(2))
                    model.collapse()
                }
                if CommandLine.arguments.contains("-peek") { model.showPeek(.track, for: nil) }
                // -preview-note low|airpods|switch|charging: one closed notice, held for capturing.
                if let i = args.firstIndex(of: "-preview-note"), i + 1 < args.count {
                    try? await Task.sleep(for: .seconds(0.5))
                    switch args[i + 1] {
                    case "low": model.post(.lowBattery(level: 20), for: .seconds(30))
                    case "charging": model.post(.charging(level: 84), for: .seconds(30))
                    // lowpower: on, then off in place a moment later, for recording the switch.
                    case "lowpower":
                        model.post(.lowPowerMode(on: true, level: 62), for: .seconds(2.2))
                        try? await Task.sleep(for: .seconds(1.4))
                        model.post(.lowPowerMode(on: false, level: 62), for: .seconds(2.2))
                    case "switch": model.post(.audioSwitched(symbol: "airpods.pro.gen1"), for: .seconds(30))
                    default: model.post(.device(name: "AirPods Pro", symbol: "airpods.pro.gen1", battery: 87), for: .seconds(30))
                    }
                }
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
    /// A home layout set from the command line for captures, without touching saved settings.
    private var debugHome = HomeConfig.current

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
        } else {
            window = makeWindow(on: screen, model: model)
        }
        // All displays: an island on each other screen, kept as screens come and go.
        let rest = choice == .all ? NSScreen.screens.filter { $0.displayID != screen.displayID } : []
        others.removeAll { other in
            guard !rest.contains(where: { $0.displayID == other.window.screen.displayID }) else { return false }
            other.window.tearDown()
            return true
        }
        var added = false
        for screen in rest {
            if let other = others.first(where: { $0.window.screen.displayID == screen.displayID }) {
                other.window.place(on: screen)
            } else {
                let island = NotchModel()
                // What the other islands already show; refreshActivity fills in the rest.
                island.home = model.home
                island.hudStyle = model.hudStyle
                island.openTo = model.openTo
                island.shelfItems = model.shelfItems
                island.batteryCount = model.batteryCount
                island.timerShowsHours = model.timerShowsHours
                others.append((island, makeWindow(on: screen, model: island)))
                added = true
            }
        }
        if added { refreshActivity() }
    }

    private func makeWindow(on screen: NSScreen, model: NotchModel) -> NotchWindowController {
        let window = NotchWindowController(screen: screen, model: model) {
            NotchRootView()
                .environment(model)
                .environment(nowPlaying)
                .environment(calendar)
                .environment(shelf)
                .environment(timer)
                .environment(batteries)
                .environment(weather)
                .environment(reminders)
                .environment(shortcuts)
                .environment(outputs)
        }
        window.isFileDragActive = { [weak self] in self?.fileDrags.isActive ?? false }
        window.onSwipe = { [weak self, weak model] direction in
            guard let model else { return }
            self?.swiped(direction, on: model)
        }
        window.panel.sharingType = Prefs.bool(Prefs.hideFromCapture) ? .none : .readOnly
        return window
    }

    /// Every island with its window: the chosen display's, then the others.
    private var islands: [(model: NotchModel, window: NotchWindowController)] {
        (window.map { [(model, $0)] } ?? []) + others
    }

    /// What every island shows alike.
    private func everyIsland(_ change: (NotchModel) -> Void) {
        change(model)
        others.forEach { change($0.model) }
    }

    /// The island on the screen with the pointer, for what one island does: a shortcut, a finished timer.
    private var activeModel: NotchModel {
        let pointer = NSEvent.mouseLocation
        return others.first { $0.window.screen.frame.contains(pointer) }?.model ?? model
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
                    // The player's app may have come to the front, or left it.
                    self?.refreshActivity()
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
        // Where the island goes and its shape there.
        let display = [Prefs.display, Prefs.closedHeight, Prefs.closedHeightCustom, Prefs.notchlessStyle]
            .map { "\(UserDefaults.standard.object(forKey: $0) ?? "")" }.joined(separator: "|")
        if display != lastAppliedDisplay {
            lastAppliedDisplay = display
            buildWindow()
        }
        let calendarEnabled = Prefs.bool(Prefs.calendar)
        if calendarEnabled != lastCalendarEnabled {
            lastCalendarEnabled = calendarEnabled
            calendar.update()
        }
        let calendarFilter = Prefs.string(Prefs.calendarHidden) + "|\(Prefs.bool(Prefs.calendarHideAllDay))"
        if calendarFilter != lastCalendarFilter {
            if lastCalendarFilter != nil { calendar.reloadIfRunning() }
            lastCalendarFilter = calendarFilter
        }
        // The weather's places and the reminders' list, read again only when they change.
        let weatherPlaces = "\(Prefs.bool(Prefs.weatherCurrentLocation))|" + Prefs.string(Prefs.weatherPlaces)
        if weatherPlaces != lastWeatherPlaces {
            lastWeatherPlaces = weatherPlaces
            weather.refresh(force: true)
        }
        let remindersList = Prefs.string(Prefs.remindersList) + "|\(model.home.modules.contains(.reminders))"
        if remindersList != lastRemindersList {
            lastRemindersList = remindersList
            reminders.update()
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
        everyIsland { if $0.hudStyle != style { $0.hudStyle = style } }
        let openTo = OpenTo.current
        everyIsland { if $0.openTo != openTo { $0.openTo = openTo } }
        hotKeys.update()
        let ignored = MediaSources.ignored
        if nowPlaying.ignoredApps != ignored {
            nowPlaying.ignoredApps = ignored
            refreshActivity()
        }
        for island in islands { island.window.panel.sharingType = Prefs.bool(Prefs.hideFromCapture) ? .none : .readOnly }
        var home = HomeConfig.current
        #if DEBUG
        if CommandLine.arguments.contains(where: { $0.hasPrefix("-home-") }) { home = debugHome }
        #endif
        everyIsland { island in
            if island.home != home {
                withAnimation(island.isExpanded ? Motion.reshape : nil) { island.home = home }
            }
        }
        batteries.publish()
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

    /// Each island hides for a full-screen app on its own screen.
    private func updateFullscreen() {
        var shown = false
        for island in islands {
            var hide = false
            if Prefs.bool(Prefs.hideInFullscreen), let owner = FullscreenDetector.fullscreenApp(on: island.window.screen) {
                // Only the app that's playing, if asked: a video full screen, not a full-screen editor. An app
                // left out of the island under Apps still counts: its video is still what's playing.
                hide = !Prefs.bool(Prefs.fullscreenMediaOnly)
                    || (!nowPlaying.title.isEmpty && NSRunningApplication(processIdentifier: owner)?.bundleIdentifier == nowPlaying.bundleIdentifier)
            }
            guard hide != island.model.isSuppressed else { continue }
            island.model.isSuppressed = hide
            if hide { island.model.collapse() }
            island.window.setSuppressed(hide)
            if !hide { shown = true }
        }
        if shown, let level = pendingLowBattery {
            pendingLowBattery = nil
            // Skip it if the Mac was plugged in, or the warning turned off, while the island was hidden.
            if battery.reading?.onAC == false, Prefs.bool(Prefs.battery), Prefs.bool(Prefs.lowBatteryWarning) {
                warnLowBattery(level)
            }
        }
    }

    private func warnLowBattery(_ level: Int) {
        everyIsland { $0.post(.lowBattery(level: level), for: .seconds(4)) }
        let sound = Prefs.string(Prefs.lowBatterySound)
        if !sound.isEmpty { NSSound(named: sound)?.play() }
    }

    // MARK: Shortcuts

    private func shortcut(_ action: ShortcutAction) {
        switch action {
        case .toggleIsland:
            let island = activeModel
            if island.isExpanded { island.collapse() } else if !island.isSuppressed { island.expand() }
        case .playPause:
            nowPlaying.togglePlayPause()
        case .nextTrack:
            nowPlaying.next()
        case .previousTrack:
            nowPlaying.previous()
        case .timer:
            // Pauses or resumes one that's going; otherwise starts the last length again.
            switch timer.state {
            case .running, .paused: timer.toggle()
            case .idle, .done: timer.start(minutes: timer.lastMinutes)
            }
        case .shelf:
            let island = activeModel
            if Prefs.bool(Prefs.shelf), !island.isSuppressed { island.expand(card: .shelf) }
        case .settings:
            SettingsWindowController.shared.show()
        }
    }

    // MARK: Events starting

    private var lastWeatherPlaces: String?
    private var lastRemindersList: String?
    private var lastCalendarFilter: String?
    private var eventStartTask: Task<Void, Never>?
    /// Events already marked as they started, so a recheck doesn't chime twice.
    private var startedEvents: Set<String> = []

    /// Waits for the next timed event to start, for its sound and its title under the island.
    private func scheduleEventStart() {
        eventStartTask?.cancel()
        let now = Date()
        // A start a moment ago still counts: the 30 s recheck can land just after it.
        guard Prefs.bool(Prefs.calendar),
              let next = calendar.upcoming(now: now).first(where: {
                  $0.start > now.addingTimeInterval(-2) && !startedEvents.contains($0.id) && !$0.isDeclined
              })
        else { return }
        let wait = max(next.start.timeIntervalSince(now), 0)
        eventStartTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled, let self else { return }
            // The wait runs on through sleep; a start that's long past (the lid was shut) passes quietly.
            if Date().timeIntervalSince(next.start) < 5 { self.eventStarted(next) }
            self.scheduleEventStart()
        }
    }

    private func eventStarted(_ event: CalendarEvent) {
        guard startedEvents.insert(event.id).inserted else { return }
        // "Leave the notch" takes it away as it starts, not at the next half-minute check.
        refreshActivity()
        guard !calendar.isDismissed(event.id) else { return }
        let sound = Prefs.string(Prefs.calendarChime)
        if !sound.isEmpty { NSSound(named: sound)?.play() }
        if Prefs.bool(Prefs.calendarPeekAtStart) {
            everyIsland { island in
                if !island.isExpanded, island.notification == nil { island.showPeek(.event(id: event.id)) }
            }
        }
    }

    // MARK: Live activity

    /// What's going on, most important first: music the island is showing, a timer, a meeting about
    /// to start. The first is the island's own activity; the next becomes the drop beside it.
    private func liveActivities() -> [LiveActivity] {
        var live: [LiveActivity] = []
        if Prefs.bool(Prefs.nowPlaying), nowPlaying.hasTrack, nowPlayingVisible, !playerInFront { live.append(.nowPlaying) }
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
        // The next thing going on gets its own drop beside the island.
        let companion = activity == live.first && Prefs.bool(Prefs.showCompanion) ? live.dropFirst().first : nil
        everyIsland { island in
            if island.timerShowsHours != hours { withAnimation(Motion.grow) { island.timerShowsHours = hours } }
            island.setLiveActivity(activity)
            island.setCompanion(companion)
            if activity != .nowPlaying, island.peek == .track { island.hidePeek() }
        }
        refreshCards(live: live)
    }

    /// Runs on every calendar change and on the 30 s tick too, so a meeting that starts changes what
    /// the island opens to. The home shows the modules that are on and have something to show.
    private func refreshCards(live: [LiveActivity]? = nil) {
        let items = shelf.items.count
        let devices = batteries.devices.count
        everyIsland { island in
            if island.shelfItems != items || island.batteryCount != devices {
                withAnimation(island.isExpanded ? Motion.reshape : nil) {
                    island.shelfItems = items
                    island.batteryCount = devices
                }
            }
        }
        let home = model.home
        let pages = home.arrangement.pages { module in
            guard !home.hidden.contains(module) else { return false }
            return switch module {
            case .music: Prefs.bool(Prefs.nowPlaying) && nowPlaying.hasTrack
            case .calendar: Prefs.bool(Prefs.calendar)
            case .batteries: devices > 0
            case .shortcuts: !shortcuts.names.isEmpty
            // Shown before there's anything in them, to hold the button that sets them up.
            case .weather, .reminders, .clock, .timer: true
            }
        }
        let available = IslandCard.available(live: live ?? liveActivities(), pages: pages, shelf: Prefs.bool(Prefs.shelf))
        everyIsland { $0.setCards(available.cards, opening: available.opening) }
    }

    private func observeShelf() {
        withObservationTracking {
            _ = shelf.items.count
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.refreshCards()
                self?.observeShelf()
            }
        }
    }

    /// Settings' "Preview on the notch", following the switch and the page Settings shows.
    private func observePreview() {
        withObservationTracking {
            _ = IslandPreview.shared.isOn
            _ = IslandPreview.shared.pane
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.showPreview()
                self?.observePreview()
            }
        }
    }

    /// The notice the preview put up, taken down when the preview moves on unless a real one replaced it.
    private var previewNotice: NotchNotification?
    /// The preview was showing something last time, so turning it off has something to undo.
    private var previewShowing = false

    /// Shows what the settings page is about: an open page for the island's own content, a closed
    /// notice for volume, battery and connections. Pages without a preview switch show nothing.
    private func showPreview() {
        let preview = IslandPreview.shared
        let active = preview.isOn && preview.pane.hasPreview && !model.isSuppressed
        if let note = previewNotice {
            previewNotice = nil
            if model.notification == note { model.dismissNotification() }
        }
        // Holds the island open only while it previews a page; a notice or a closed island lets go.
        model.isPreviewing = false
        guard active else {
            if previewShowing, !model.isHovering { model.collapse(remembering: false) }
            previewShowing = false
            return
        }
        previewShowing = true
        let cards = model.cards
        func page(with module: HomeModule) -> IslandCard? { cards.first { $0.modules.contains(module) } }
        func open(_ card: IslandCard?) {
            guard let card else {
                model.collapse(remembering: false)
                return
            }
            model.isPreviewing = true
            model.expand(card: card)
        }
        func notice(_ note: NotchNotification) {
            model.collapse(remembering: false)
            model.post(note, for: .seconds(3600))
            previewNotice = note
        }
        switch preview.pane {
        case .nowPlaying:
            open(page(with: .music))
        case .calendar:
            open(page(with: .calendar) ?? cards.first(where: { $0.settingsPane == .calendar }))
        case .timer:
            open(cards.contains(.timer) ? .timer : nil)
        case .shelf:
            open(cards.contains(.shelf) ? .shelf : nil)
        case .huds:
            notice(.volume(level: volume.volume, muted: volume.isMuted, output: volume.headphones))
        case .battery:
            if let reading = battery.reading {
                notice(reading.onAC ? .charging(level: reading.level) : .onBattery(level: reading.level))
            }
        case .connectivity:
            notice(.device(name: "AirPods Pro", symbol: "airpods.pro.gen1", battery: 80))
        default:
            open(cards.first { !$0.modules.isEmpty })
        }
    }

    /// Modules with nothing to show stay off the home: devices with a battery, shortcuts to run.
    private func observeModuleData() {
        withObservationTracking {
            _ = batteries.devices.count
            _ = shortcuts.names.isEmpty
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.refreshCards()
                self?.observeModuleData()
            }
        }
    }

    /// The player's own app is in front and Settings asks for the island to leave it alone then.
    private var playerInFront: Bool {
        Prefs.bool(Prefs.hideWhenPlayerFront) && nowPlaying.bundleIdentifier != nil
            && NSWorkspace.shared.frontmostApplication?.bundleIdentifier == nowPlaying.bundleIdentifier
    }

    private func playbackChanged() {
        pauseGraceTask?.cancel()
        // A video starting or stopping in a full-screen app changes whether "only the app that's playing" hides.
        updateFullscreen()
        if nowPlaying.isPlaying {
            nowPlayingVisible = true
            refreshActivity()
        } else {
            // A paused track lingers so a quick pause/resume doesn't flicker the island; as long as
            // Settings says, or until the player lets go of the track.
            let linger = Prefs.int(Prefs.pausedLinger)
            guard linger >= 0 else { return }
            pauseGraceTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(linger))
                guard !Task.isCancelled, let self else { return }
                if self.islands.contains(where: { $0.model.isHovering || $0.model.isExpanded }) {
                    self.playbackChanged()
                    return
                }
                self.nowPlayingVisible = false
                self.refreshActivity()
            }
        }
    }

    private func trackChanged() {
        // A player letting go of its track changes what "only the app that's playing" hides.
        updateFullscreen()
        guard nowPlaying.hasTrack, nowPlaying.isPlaying || nowPlayingVisible else {
            refreshActivity()
            return
        }
        nowPlayingVisible = true
        refreshActivity()
        guard Prefs.bool(Prefs.peekOnTrackChange) else { return }
        everyIsland { island in
            if island.liveActivity == .nowPlaying, !island.isExpanded, island.notification == nil {
                island.showPeek(.track, for: .seconds(Prefs.double(Prefs.peekDuration)))
            }
        }
    }

    // MARK: Audio output

    /// Sound moved to headphones that were already connected: AirPods' automatic switching, or a pick
    /// in Control Center. Sound follows a device that has just connected, which shows its own
    /// connection instead.
    private func outputChanged(to symbol: String?, name: String) {
        guard Prefs.bool(Prefs.connectivity), let symbol else { return }
        if let last = bluetooth.lastConnection, Date.now.timeIntervalSince(last) < 10 { return }
        everyIsland { $0.post(.audioSwitched(symbol: symbol), for: .seconds(Prefs.double(Prefs.deviceNoticeDuration))) }
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
        // On the screen in use. A file drag holding the shelf open keeps it; the notch shows "Done" until it's stopped.
        let island = activeModel
        if !island.isSuppressed, !island.isDraggingFile { island.expand(card: .timer) }
        doneTask?.cancel()
        doneTask = Task { [weak self, weak island] in
            try? await Task.sleep(for: .seconds(8))
            guard let self, !Task.isCancelled else { return }
            if let island, island.isExpanded, island.card == .timer, !island.isHovering { island.collapse() }
            try? await Task.sleep(for: .seconds(10 * 60 - 8))
            guard !Task.isCancelled, self.timer.state == .done else { return }
            self.timer.cancel()
        }
    }

    // MARK: Input

    /// Sideways on the open island turns cards; on the closed island it skips tracks.
    private func swiped(_ direction: SwipeDirection, on island: NotchModel) {
        if island.isExpanded {
            switch direction {
            case .left: island.page(1)
            case .right: island.page(-1)
            default: break
            }
            return
        }
        guard Prefs.bool(Prefs.nowPlaying), nowPlaying.hasTrack else { return }
        switch direction {
        case .left:
            nowPlaying.next()
        case .right:
            nowPlaying.previous()
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
            everyIsland { $0.post(.volume(level: result.level, muted: result.muted, output: volume.headphones), for: .seconds(Prefs.double(Prefs.hudDuration))) }
        case .mute:
            let result = volume.toggleMute()
            everyIsland { $0.post(.volume(level: result.level, muted: result.muted, output: volume.headphones), for: .seconds(Prefs.double(Prefs.hudDuration))) }
        case .brightnessUp, .brightnessDown:
            let up = key == .brightnessUp
            let before = brightness.level
            let level = brightness.step(up: up, fine: fine)
            bumpIfAtEnd(kind: "brightness", before: before, after: level, up: up)
            everyIsland { $0.post(.brightness(level: level), for: .seconds(Prefs.double(Prefs.hudDuration))) }
        }
    }

    /// Pressing on at the top or bottom stretches the bar that's already showing, instead of nothing.
    /// Only that HUD's own bar (brightness showing doesn't stretch for a volume press), and with a
    /// little slack, since a display can read back a hair off 1.
    private func bumpIfAtEnd(kind: String, before: Float, after: Float, up: Bool) {
        let end: Float = up ? 1 : 0
        guard abs(after - before) < 0.001, abs(after - end) < 0.001 else { return }
        everyIsland { if $0.notification?.kind == kind { $0.bumpHUD(up: up) } }
    }
}

enum FullscreenDetector {
    /// A fullscreen space has no menu bar window on that display (unless the pointer reveals it)
    /// and another app's window spans the screen's full width from the top of the usable area.
    /// Both must hold, so an auto-hidden menu bar or a zoomed window alone doesn't hide the island.
    /// Returns the full-screen app's process, or nil when the screen isn't full screen.
    static func fullscreenApp(on screen: NSScreen) -> pid_t? {
        guard let primary = NSScreen.screens.first,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return nil }
        // CoreGraphics window bounds use a top-left origin on the primary display.
        let target = CGRect(x: screen.frame.minX,
                            y: primary.frame.maxY - screen.frame.maxY,
                            width: screen.frame.width,
                            height: screen.frame.height)
        let me = ProcessInfo.processInfo.processIdentifier
        var menuBarVisible = false
        var covering: pid_t?
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
            if layer == 0, covering == nil, let owner = info[kCGWindowOwnerPID as String] as? pid_t, owner != me,
               abs(bounds.width - target.width) < 1,
               // A maximized window starts under the menu bar (33 pt on a 14" MBP, notch 32 pt);
               // a fullscreen one starts at or above the notch line.
               bounds.minY - target.minY <= screen.safeAreaInsets.top,
               abs(bounds.maxY - target.maxY) < 1 {
                covering = owner
            }
        }
        return menuBarVisible ? nil : covering
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
