import AppKit
import Combine
import EventKit
import ServiceManagement
import SwiftUI

final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show(activate: Bool = true) {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 600),
                                  styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.title = "Nook"
            window.titlebarAppearsTransparent = true
            window.toolbarStyle = .unified
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: SettingsView())
            window.setContentSize(NSSize(width: 820, height: 600))
            window.center()
            self.window = window
        }
        if activate {
            NSApp.activate()
            window?.makeKeyAndOrderFront(nil)
        } else {
            window?.orderFrontRegardless()
        }
    }

    #if DEBUG
    /// Steps through every pane without taking focus, printing the window number for screencapture.
    func runCapture() {
        show(activate: false)
        Task { @MainActor in
            for pane in SettingsPane.allCases {
                SettingsNavigation.shared.pane = pane
                try? await Task.sleep(for: .milliseconds(900))
                print("PANE \(pane.rawValue) \(window?.windowNumber ?? 0)")
                fflush(stdout)
                try? await Task.sleep(for: .milliseconds(600))
            }
            NSApp.terminate(nil)
        }
    }
    #endif
}

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, nowPlaying, calendar, timer, shelf, huds, battery, connectivity, lock, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .nowPlaying: "Now Playing"
        case .huds: "Volume & Brightness"
        case .battery: "Battery"
        case .connectivity: "Connectivity"
        case .calendar: "Calendar"
        case .timer: "Timer"
        case .shelf: "Shelf"
        case .lock: "Lock Screen"
        case .about: "About"
        }
    }
}

/// Which settings pane is showing, so other parts of the app can open a specific one.
@Observable
final class SettingsNavigation {
    static let shared = SettingsNavigation()
    var pane: SettingsPane = .general
}

struct SettingsView: View {
    @Bindable private var navigation = SettingsNavigation.shared
    private var pane: SettingsPane { navigation.pane }

    var body: some View {
        NavigationSplitView {
            // Plain names in groups.
            List(selection: $navigation.pane) {
                Text(SettingsPane.general.title).tag(SettingsPane.general)
                Section("Island") {
                    ForEach([SettingsPane.nowPlaying, .calendar, .timer, .shelf]) { Text($0.title).tag($0) }
                }
                Section("Notices") {
                    ForEach([SettingsPane.huds, .battery, .connectivity, .lock]) { Text($0.title).tag($0) }
                }
                Section("Nook") {
                    Text(SettingsPane.about.title).tag(SettingsPane.about)
                }
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } detail: {
            Group {
                switch pane {
                case .general: GeneralPane()
                case .nowPlaying: NowPlayingPane()
                case .huds: HUDPane()
                case .battery: BatteryPane()
                case .connectivity: ConnectivityPane()
                case .calendar: CalendarPane()
                case .timer: TimerPane()
                case .shelf: ShelfPane()
                case .lock: LockPane()
                case .about: AboutPane()
                }
            }
            .formStyle(.grouped)
        }
        .frame(minWidth: 760, minHeight: 520)
        // Otherwise a solid bar sits behind the toolbar once the sidebar is toggled or the window is inactive.
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
    }
}

private struct GeneralPane: View {
    @AppStorage(Prefs.display) private var display = DisplayChoice.builtIn.rawValue
    @AppStorage(Prefs.hideInFullscreen) private var hideInFullscreen = false
    @AppStorage(Prefs.expandOnHover) private var expandOnHover = true
    @AppStorage(Prefs.swipeGestures) private var swipeGestures = true
    @AppStorage(Prefs.enableHaptics) private var haptics = true
    @AppStorage(Prefs.hideMenuBarIcon) private var hideMenuBarIcon = false
    @AppStorage(Prefs.statusColors) private var statusColors = true
    @AppStorage(Prefs.showCompanion) private var showCompanion = true
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
                Picker("Status colors", selection: $statusColors) {
                    Text("Apple's").tag(true)
                    Text("White").tag(false)
                }
                .pickerStyle(.segmented)
                Toggle("Show a second activity beside the island", isOn: $showCompanion)
            } footer: {
                Text("Green for charging and AirPods, orange for timers, blue when sound switches; low battery is always red. A second activity, like a timer while music plays, gets its own drop.")
            }
            Section {
                Toggle("Expand on hover", isOn: $expandOnHover)
                Toggle("Swipe gestures", isOn: $swipeGestures)
                    .help("Two fingers down opens, up closes. Sideways skips tracks, or turns cards when the island is open.")
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
    @AppStorage(Prefs.expandOnHover) private var expandOnHover = true
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
                    // Hovering opens the whole island instead.
                    .disabled(expandOnHover)
                    .help(expandOnHover ? "Turn off Expand on hover in General to use this." : "")
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
    @AppStorage(Prefs.hudStyle) private var style = HUDStyle.ledge.rawValue
    @State private var trusted = MediaKeyTap.isTrusted
    private let poll = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section("Style") {
                HUDStylePicker(selection: $style)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
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
        .onReceive(poll) { _ in trusted = MediaKeyTap.isTrusted }
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
    @AppStorage(Prefs.calendar) private var enabled = true
    @AppStorage(Prefs.calendarLeadMinutes) private var lead = 10
    @State private var status = EKEventStore.authorizationStatus(for: .event)
    private let poll = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                Toggle("Show upcoming events", isOn: $enabled)
                Picker("Show an event in the notch", selection: $lead) {
                    ForEach([5, 10, 15, 30], id: \.self) { Text("\($0) minutes before").tag($0) }
                }
                .disabled(!enabled)
            }
            if enabled {
                Section {
                    LabeledContent("Calendar access") {
                        switch status {
                        case .fullAccess:
                            Text("Allowed").foregroundStyle(.secondary)
                        case .notDetermined:
                            Button("Allow…") {
                                Task { _ = try? await EKEventStore().requestFullAccessToEvents() }
                            }
                        default:
                            Button("Open Privacy Settings…") {
                                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
                            }
                        }
                    }
                }
            }
        }
        .onReceive(poll) { _ in status = EKEventStore.authorizationStatus(for: .event) }
    }
}

private struct ShelfPane: View {
    @AppStorage(Prefs.shelf) private var enabled = true

    var body: some View {
        Form {
            Section {
                Toggle("Open the shelf when a file is dragged to the notch", isOn: $enabled)
            } footer: {
                Text("Files stay where they are; the shelf keeps a reference. Dropped text, links and images are saved in Application Support/Nook/Shelf until you remove them.")
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

/// Volume and brightness styles as thumbnails, like macOS's own appearance picker.
private struct HUDStylePicker: View {
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 12) {
            ForEach(HUDStyle.allCases) { style in
                let selected = selection == style.rawValue
                Button { selection = style.rawValue } label: {
                    VStack(spacing: 6) {
                        HUDStyleThumbnail(style: style)
                            .frame(width: 118, height: 46)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: selected ? 3 : 1)
                            )
                        Text(style.title)
                            .font(.callout)
                            .foregroundStyle(selected ? .primary : .secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

/// One style drawn at real size on a sample island, scaled down.
private struct HUDStyleThumbnail: View {
    let style: HUDStyle

    var body: some View {
        let note = NotchNotification.volume(level: 0.62, muted: false, output: nil)
        let notch = NotchMetrics.simulated.size
        let side = notch.height + 4 + (style == .slider ? 13 : 8)
        let size = CGSize(width: notch.width + side * 2, height: notch.height + style.below)
        let layout = IslandLayout(size: size, topRadius: 6, bottomRadius: Compact.bottomRadius)
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(red: 0.27, green: 0.35, blue: 0.49), Color(red: 0.62, green: 0.69, blue: 0.81)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        if style.usesSides {
                            HUDGlyph(note: note)
                                .frame(width: side, alignment: .leading)
                                .padding(.leading, Compact.outer)
                            Spacer(minLength: 0)
                            HUDValue(note: note, style: style)
                                .frame(width: side - Compact.outer, alignment: .trailing)
                                .padding(.trailing, Compact.outer)
                        }
                    }
                    .frame(height: notch.height)
                    HUDBelow(note: note, style: style, bump: 0, bumpUp: true)
                        .padding(.horizontal, layout.topRadius + (style == .slider ? 4 : 12))
                }
                if style == .outline {
                    HUDOutline(level: 0.62, muted: false, layout: layout, notchHeight: notch.height)
                }
            }
            .frame(width: size.width, height: size.height, alignment: .top)
            .background(NotchShape(topRadius: layout.topRadius, bottomRadius: layout.bottomRadius).fill(.black))
            .scaleEffect(0.42, anchor: .top)
        }
        .environment(\.colorScheme, .dark)
        .accessibilityHidden(true)
    }
}

private struct TimerPane: View {
    @AppStorage(Prefs.timerSound) private var sound = "Glass"

    private static let sounds: [String] = {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: "/System/Library/Sounds")) ?? []
        return files.map { ($0 as NSString).deletingPathExtension }.sorted()
    }()

    var body: some View {
        Form {
            Section {
                Picker("Sound when it ends", selection: $sound) {
                    Text("None").tag("")
                    Divider()
                    ForEach(Self.sounds, id: \.self) { Text($0).tag($0) }
                }
                .onChange(of: sound) { _, new in
                    if !new.isEmpty { NSSound(named: new)?.play() }
                }
            } footer: {
                Text("Start a timer from the island's right-click menu. On the open timer, scroll over the time to add or take off minutes.")
            }
        }
    }
}

