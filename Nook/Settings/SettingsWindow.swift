import AppKit
import Combine
import EventKit
import ServiceManagement
import SwiftUI

final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 500),
                                  styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.title = "Nook"
            window.titlebarAppearsTransparent = true
            window.toolbarStyle = .unified
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: SettingsView())
            window.setContentSize(NSSize(width: 720, height: 500))
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, nowPlaying, huds, battery, connectivity, calendar, lock, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .nowPlaying: "Now Playing"
        case .huds: "Volume & Brightness"
        case .battery: "Battery"
        case .connectivity: "Connectivity"
        case .calendar: "Calendar"
        case .lock: "Lock Screen"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .nowPlaying: "play.circle"
        case .huds: "speaker.wave.2"
        case .battery: "battery.75percent"
        case .connectivity: "airpods"
        case .calendar: "calendar"
        case .lock: "lock"
        case .about: "info.circle"
        }
    }
}

struct SettingsView: View {
    @State private var pane: SettingsPane = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $pane) { pane in
                Label(pane.title, systemImage: pane.symbol).tag(pane)
            }
            .navigationSplitViewColumnWidth(196)
        } detail: {
            Group {
                switch pane {
                case .general: GeneralPane()
                case .nowPlaying: NowPlayingPane()
                case .huds: HUDPane()
                case .battery: BatteryPane()
                case .connectivity: ConnectivityPane()
                case .calendar: CalendarPane()
                case .lock: LockPane()
                case .about: AboutPane()
                }
            }
            .formStyle(.grouped)
            .navigationTitle(pane.title)
        }
        .frame(minWidth: 680, minHeight: 460)
    }
}

private struct GeneralPane: View {
    @AppStorage(Prefs.display) private var display = DisplayChoice.builtIn.rawValue
    @AppStorage(Prefs.hideInFullscreen) private var hideInFullscreen = true
    @AppStorage(Prefs.expandOnHover) private var expandOnHover = false
    @AppStorage(Prefs.swipeGestures) private var swipeGestures = true
    @AppStorage(Prefs.enableHaptics) private var haptics = true
    @AppStorage(Prefs.hideMenuBarIcon) private var hideMenuBarIcon = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section {
                Picker("Show on", selection: $display) {
                    ForEach(DisplayChoice.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Toggle("Hide when an app is fullscreen", isOn: $hideInFullscreen)
            }
            Section {
                Toggle("Expand on hover", isOn: $expandOnHover)
                Toggle("Swipe gestures", isOn: $swipeGestures)
                    .help("Two fingers down opens, up closes, left and right skip tracks.")
                Toggle("Haptic feedback", isOn: $haptics)
            }
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                Toggle("Hide menu bar icon", isOn: $hideMenuBarIcon)
            } footer: {
                if hideMenuBarIcon {
                    Text("Open Nook again from Finder or Spotlight to get back here.")
                }
            }
        }
    }
}

private struct NowPlayingPane: View {
    @AppStorage(Prefs.nowPlaying) private var enabled = true
    @AppStorage(Prefs.peekOnTrackChange) private var peekOnTrackChange = true
    @AppStorage(Prefs.peekOnHover) private var peekOnHover = true
    @AppStorage(Prefs.showWaveform) private var showWaveform = true
    @AppStorage(Prefs.tintWaveform) private var tintWaveform = true

    var body: some View {
        Form {
            Section {
                Toggle("Show what's playing", isOn: $enabled)
            }
            Section {
                Toggle("Show the title when the track changes", isOn: $peekOnTrackChange)
                Toggle("Show the title on hover", isOn: $peekOnHover)
                Toggle("Waveform", isOn: $showWaveform)
                Toggle("Color waveform from artwork", isOn: $tintWaveform)
                    .disabled(!showWaveform)
            }
            .disabled(!enabled)
        }
    }
}

private struct HUDPane: View {
    @AppStorage(Prefs.volumeHUD) private var volumeHUD = false
    @AppStorage(Prefs.brightnessHUD) private var brightnessHUD = false
    @State private var trusted = MediaKeyTap.isTrusted
    private let poll = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                Toggle("Replace the volume HUD", isOn: $volumeHUD)
                Toggle("Replace the brightness HUD", isOn: $brightnessHUD)
            } footer: {
                Text("Option-Shift with a key moves in quarter steps.")
            }
            if (volumeHUD || brightnessHUD) && !trusted {
                Section {
                    LabeledContent("Accessibility access") {
                        Button("Allow…") { MediaKeyTap.requestTrust() }
                    }
                } footer: {
                    Text("Nook needs Accessibility access to handle the volume and brightness keys. It only reads those keys.")
                }
            }
        }
        .onReceive(poll) { _ in
            let now = MediaKeyTap.isTrusted
            if now != trusted {
                trusted = now
                // Nudge the coordinator to start the key tap now that access exists.
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "accessibilityCheckedAt")
            }
        }
    }
}

private struct BatteryPane: View {
    @AppStorage(Prefs.battery) private var enabled = true
    @AppStorage(Prefs.lowBatteryThreshold) private var threshold = 20

    var body: some View {
        Form {
            Section {
                Toggle("Show charging and battery notices", isOn: $enabled)
                Picker("Warn at", selection: $threshold) {
                    ForEach([10, 15, 20, 25, 30], id: \.self) { Text("\($0)%").tag($0) }
                }
                .disabled(!enabled)
            }
        }
    }
}

private struct ConnectivityPane: View {
    @AppStorage(Prefs.connectivity) private var enabled = true

    var body: some View {
        Form {
            Section {
                Toggle("Show when Bluetooth devices connect", isOn: $enabled)
            } footer: {
                Text("AirPods and other headphones show their battery when macOS reports it.")
            }
        }
    }
}

private struct CalendarPane: View {
    @AppStorage(Prefs.calendar) private var enabled = false
    @AppStorage(Prefs.calendarLeadMinutes) private var lead = 10
    @State private var status = EKEventStore.authorizationStatus(for: .event)

    var body: some View {
        Form {
            Section {
                Toggle("Show upcoming events", isOn: $enabled)
                Picker("Show an event", selection: $lead) {
                    ForEach([5, 10, 15, 30], id: \.self) { Text("\($0) minutes before").tag($0) }
                }
                .disabled(!enabled)
            }
            if enabled, status == .denied || status == .restricted || status == .writeOnly {
                Section {
                    LabeledContent("Calendar access") {
                        Button("Open Privacy Settings…") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
                        }
                    }
                }
            }
        }
        .onChange(of: enabled) {
            Task {
                try? await Task.sleep(for: .seconds(1))
                status = EKEventStore.authorizationStatus(for: .event)
            }
        }
    }
}

private struct LockPane: View {
    @AppStorage(Prefs.lockActivity) private var enabled = true

    var body: some View {
        Form {
            Section {
                Toggle("Show lock and unlock", isOn: $enabled)
            }
        }
    }
}

private struct AboutPane: View {
    var body: some View {
        Form {
            Section {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
            }
            Section("Acknowledgements") {
                Text("Now playing uses mediaremote-adapter by Jonas van den Berg, BSD 3-Clause License.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
