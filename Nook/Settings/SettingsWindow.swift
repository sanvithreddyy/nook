import AppKit
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
            // Each page carries its own title; the window's would float over the page as it scrolls.
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.toolbarStyle = .unified
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: SettingsView())
            window.setContentSize(NSSize(width: 820, height: 600))
            window.center()
            // The preview holds the island open only while Settings is there to change it.
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
                MainActor.assumeIsolated { IslandPreview.shared.isOn = false }
            }
            self.window = window
            applyAppearance()
        }
        if activate {
            NSApp.activate()
            window?.makeKeyAndOrderFront(nil)
        } else {
            window?.orderFrontRegardless()
        }
    }

    /// Only this window follows the Theme setting; the island and its menus keep their own look.
    func applyAppearance() {
        window?.appearance = switch SettingsAppearance.saved {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    #if DEBUG
    /// Steps through every pane without taking focus, printing the window number for screencapture.
    func runCapture() {
        show(activate: false)
        // -capture-tall: as tall as the screen allows, so a long page shows more of itself.
        if CommandLine.arguments.contains("-capture-tall"), let window, let screen = window.screen {
            // The hosting controller would size the window back to the content's preferred size.
            (window.contentViewController as? NSHostingController<SettingsView>)?.sizingOptions = []
            let area = screen.visibleFrame
            window.setFrame(NSRect(x: window.frame.minX, y: area.minY, width: window.frame.width, height: area.height), display: true)
        }
        Task { @MainActor in
            for pane in SettingsPane.allCases {
                SettingsNavigation.shared.pane = pane
                try? await Task.sleep(for: .milliseconds(900))
                print("PANE \(pane.rawValue) \(window?.windowNumber ?? 0)")
                fflush(stdout)
                try? await Task.sleep(for: .milliseconds(1500))
                // -capture-end: the same page scrolled to its end, for pages longer than the window.
                if CommandLine.arguments.contains("-capture-end"), let page = pageScroller(), page.documentView?.frame.height ?? 0 > page.contentView.bounds.height {
                    let doc = page.documentView?.frame.height ?? 0
                    let end = (page.documentView?.isFlipped ?? true) ? doc - page.contentView.bounds.height : 0
                    page.contentView.scroll(to: NSPoint(x: 0, y: end))
                    page.reflectScrolledClipView(page.contentView)
                    try? await Task.sleep(for: .milliseconds(400))
                    print("PANE \(pane.rawValue)-end \(window?.windowNumber ?? 0)")
                    fflush(stdout)
                    try? await Task.sleep(for: .milliseconds(1500))
                }
            }
            NSApp.terminate(nil)
        }
    }

    /// The page's scroll view: the rightmost one, the sidebar's being on the left.
    private func pageScroller() -> NSScrollView? {
        func all(in view: NSView) -> [NSScrollView] {
            view.subviews.flatMap { sub in (sub as? NSScrollView).map { [$0] } ?? all(in: sub) }
        }
        guard let root = window?.contentView else { return nil }
        return all(in: root).max { $0.convert($0.bounds, to: nil).minX < $1.convert($1.bounds, to: nil).minX }
    }
    #endif
}

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, home, nowPlaying, calendar, timer, shelf, huds, battery, connectivity, lock, advanced, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .home: "Home"
        case .nowPlaying: "Now Playing"
        case .huds: "Volume & Brightness"
        case .battery: "Battery"
        case .connectivity: "Connectivity"
        case .calendar: "Calendar"
        case .timer: "Timer"
        case .shelf: "Shelf"
        case .lock: "Lock Screen"
        case .advanced: "Advanced"
        case .about: "About"
        }
    }

    /// Every row label on the page, and a few words people might search for instead.
    /// A test checks each row label in Settings/Panes is listed here.
    var keywords: [String] {
        switch self {
        case .general: ["Island", "Show on", "Display", "Screen", "Monitor", "Open when the pointer rests on it", "Hover",
                        "Opens to", "What's happening", "Last page", "Only when it's the app that's playing", "Full screen",
                        "Video",
                        "Rest before it responds", "Hover delay", "Gestures", "Swipe gestures", "Down to open, up to close",
                        "Sideways to skip tracks or turn pages", "Reverse direction", "Sensitivity", "Trackpad",
                        "Haptic feedback", "Hide when an app is full screen", "Appearance", "Theme", "Dark", "Light",
                        "Status colors", "Second activity beside the island", "Shadow under the open island", "Shadow",
                        "Hairline outline", "Outline", "Border", "Hide from screenshots and recordings", "Screen recording",
                        "Screenshot", "App", "Open at login", "Hide the menu bar icon"]
        case .home: ["Preview on the notch", "Layout", "Side by Side", "One at a Time", "Modules side by side", "Size",
                     "Modules", "Order", "Music", "Left button", "Right button", "Favorite", "Output", "Shuffle", "Repeat",
                     "Back 15 seconds", "Forward 15 seconds", "Time after the bar", "Time left", "Length", "Remaining", "Calendar", "Week starts on",
                     "Mark days with events", "Weekends in gray", "Batteries", "Include this Mac"]
        case .nowPlaying: ["Show what's playing", "Closed island", "Waveform", "Color the waveform from the artwork",
                           "Show the title when the track changes", "Show the title on hover", "Artwork", "Keep a paused player",
                           "Paused", "Hide while the player is in front", "Show it for", "Peek", "Apps", "Sources", "Browser",
                           "Flip the artwork when the track changes", "Album art", "Music", "Media"]
        case .calendar: ["Show upcoming events", "Show a meeting in the notch", "Access", "Calendar access", "Events"]
        case .timer: ["Sound when it ends", "Alarm"]
        case .shelf: ["Open the shelf when a file is dragged to the notch", "Files", "Drop", "AirDrop"]
        case .huds: ["Replace the volume HUD", "Replace the brightness HUD", "Accessibility access", "Style",
                     "Ledge", "Slider", "Steps", "Outline"]
        case .battery: ["Charging and battery notices", "Warn at", "Low battery"]
        case .connectivity: ["Show when Bluetooth devices connect", "AirPods", "Headphones"]
        case .lock: ["Show lock and unlock"]
        case .advanced: ["Export Settings", "Import Settings", "Reset All Settings", "Backup"]
        case .about: ["Version", "Acknowledgements"]
        }
    }

    /// The label that matched a search, when it wasn't the page's own title.
    func match(_ query: String) -> String? {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return nil }
        if title.localizedCaseInsensitiveContains(query) { return title }
        return keywords.first { $0.localizedCaseInsensitiveContains(query) }
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
    @State private var query = ""
    private var pane: SettingsPane { navigation.pane }

    var body: some View {
        NavigationSplitView {
            // Plain names in groups; while searching, the pages that match, each with what matched.
            List(selection: $navigation.pane) {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text(SettingsPane.general.title).tag(SettingsPane.general)
                    Section("Island") {
                        ForEach([SettingsPane.home, .nowPlaying, .calendar, .timer, .shelf]) { Text($0.title).tag($0) }
                    }
                    Section("Notices") {
                        ForEach([SettingsPane.huds, .battery, .connectivity, .lock]) { Text($0.title).tag($0) }
                    }
                    Section("Nook") {
                        ForEach([SettingsPane.advanced, .about]) { Text($0.title).tag($0) }
                    }
                } else {
                    ForEach(SettingsPane.allCases.filter { $0.match(query) != nil }) { pane in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(pane.title)
                            if let hit = pane.match(query), hit != pane.title {
                                Text(hit).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        .tag(pane)
                    }
                }
            }
            .searchable(text: $query, placement: .sidebar, prompt: "Search")
            .onChange(of: query) { _, new in
                // The best match shows straight away, so typing a setting's name is enough to get to it.
                if let first = SettingsPane.allCases.first(where: { $0.match(new) != nil }), pane.match(new) == nil {
                    navigation.pane = first
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 230)
        } detail: {
            Group {
                switch pane {
                case .general: GeneralPane()
                case .home: HomePane()
                case .nowPlaying: NowPlayingPane()
                case .huds: HUDPane()
                case .battery: BatteryPane()
                case .connectivity: ConnectivityPane()
                case .calendar: CalendarPane()
                case .timer: TimerPane()
                case .shelf: ShelfPane()
                case .lock: LockPane()
                case .advanced: AdvancedPane()
                case .about: AboutPane()
                }
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        // Otherwise a solid bar sits behind the toolbar once the sidebar is toggled or the window is inactive.
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
    }
}
