import AppKit
import SwiftUI

final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?
    /// The app in front before Settings opened, given the front back when it closes.
    private var previousApp: NSRunningApplication?

    func show(activate: Bool = true, pane: SettingsPane? = nil) {
        if let pane {
            SettingsNavigation.shared.pane = pane
            // Straight away, so a preview turned on with it shows this page, not the last one.
            IslandPreview.shared.pane = pane
        }
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
            // The preview holds the island only while Settings is there to change it: closed, minimized,
            // or Nook sent to the background (Command-Tab, hidden), it ends.
            let center = NotificationCenter.default
            for name in [NSWindow.willCloseNotification, NSWindow.willMiniaturizeNotification] {
                center.addObserver(forName: name, object: window, queue: .main) { _ in
                    MainActor.assumeIsolated { IslandPreview.shared.isOn = false }
                }
            }
            center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.becomeMenuBarApp() }
            }
            center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { IslandPreview.shared.isOn = false }
            }
            self.window = window
            applyAppearance()
        }
        if activate {
            // A menu bar app has no menus, and macOS hides the menu bar while one is in front. While
            // Settings is open Nook is a regular app, so the menu bar stays (and it's in the Dock and
            // Command-Tab, like any app with a window).
            if NSApp.activationPolicy() != .regular {
                previousApp = NSWorkspace.shared.frontmostApplication.flatMap { $0 == .current ? nil : $0 }
                NSApp.setActivationPolicy(.regular)
                // SwiftUI leaves a View menu with nothing in it for a window without a toolbar.
                if let menu = NSApp.mainMenu, let view = menu.items.first(where: { $0.title == "View" }), view.submenu?.items.isEmpty ?? true {
                    menu.removeItem(view)
                }
            }
            NSApp.activate()
            window?.makeKeyAndOrderFront(nil)
        } else {
            window?.orderFrontRegardless()
        }
        lockSidebar()
    }

    /// The sidebar stays at one width, as in System Settings. SwiftUI's hide and show slid it in empty,
    /// then its contents popped in and the page jumped; dragging the divider to the edge hid it the same
    /// way. Without the toggle there's no toolbar, and SwiftUI then sizes the sidebar narrower than it's
    /// asked to and makes it collapsible again on every update, so the split view item underneath is
    /// held, and put back whenever SwiftUI changes it.
    private func lockSidebar() {
        guard let item = splitController()?.splitViewItems.first, item !== sidebarLock?.item else { return }
        sidebarLock = SidebarLock(item: item, width: SettingsView.sidebarWidth)
    }

    private var sidebarLock: SidebarLock?

    private func splitController() -> NSSplitViewController? {
        func find(_ view: NSView) -> NSSplitViewController? {
            ((view as? NSSplitView)?.delegate as? NSSplitViewController) ?? view.subviews.lazy.compactMap(find).first
        }
        return window?.contentView.flatMap(find)
    }

    /// Settings closed: back to a menu bar app, and the app that was in front before it gets the front again,
    /// so the menu bar isn't left empty.
    private func becomeMenuBarApp() {
        guard NSApp.activationPolicy() != .accessory else { return }
        NSApp.setActivationPolicy(.accessory)
        if let previousApp, !previousApp.isTerminated { previousApp.activate() }
        previousApp = nil
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
                // -capture-end: the same page scrolled to its end, for pages longer than the window;
                // -capture-middle: halfway, for pages longer than two windows.
                if CommandLine.arguments.contains("-capture-end"), let page = pageScroller(), page.documentView?.frame.height ?? 0 > page.contentView.bounds.height {
                    let doc = page.documentView?.frame.height ?? 0
                    let bottom = doc - page.contentView.bounds.height
                    let end = (page.documentView?.isFlipped ?? true) ? (CommandLine.arguments.contains("-capture-middle") ? bottom / 2 : bottom) : 0
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

    /// -settings-sidebar: Settings without focus, then every way its sidebar could collapse (the divider
    /// dragged to the edge, Hide Sidebar), printing the sidebar's width after each.
    func runSidebarProbe() {
        show(activate: false)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            @MainActor func report(_ step: String) {
                let item = splitController()?.splitViewItems.first
                print("SIDEBAR \(step): width \(item?.viewController.view.frame.width ?? -1) min \(item?.minimumThickness ?? -1) max \(item?.maximumThickness ?? -1) collapsed \(item?.isCollapsed ?? false)")
                fflush(stdout)
            }
            print("TOOLBAR " + (window?.toolbar?.items.map(\.itemIdentifier.rawValue).joined(separator: ", ") ?? "none"))
            report("start")
            for pane in [SettingsPane.home, .huds, .about, .general] {
                SettingsNavigation.shared.pane = pane
                try? await Task.sleep(for: .seconds(0.6))
                report("on \(pane.rawValue)")
            }
            Updates.shared.previewFound()
            try? await Task.sleep(for: .seconds(0.6))
            report("with the update row")
            (splitController()?.splitView).map { $0.setPosition(0, ofDividerAt: 0) }
            try? await Task.sleep(for: .seconds(1))
            report("after the divider is dragged to the edge")
            splitController()?.toggleSidebar(nil)
            try? await Task.sleep(for: .seconds(1))
            report("after Hide Sidebar")
            NSApp.terminate(nil)
        }
    }

    /// The page scrolled to its end, for stills of what's at the bottom.
    func scrollPageToEnd() {
        guard let page = pageScroller(), let doc = page.documentView else { return }
        let bottom = doc.frame.height - page.contentView.bounds.height
        page.contentView.scroll(to: NSPoint(x: 0, y: doc.isFlipped ? max(bottom, 0) : 0))
        page.reflectScrolledClipView(page.contentView)
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

extension SettingsPane {
    /// Pages with part of the island to show on the notch while they're open.
    var hasPreview: Bool {
        switch self {
        case .home, .nowPlaying, .calendar, .timer, .shelf, .huds, .battery, .connectivity: true
        case .general, .lock, .shortcuts, .advanced, .about, .update: false
        }
    }
}

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, home, nowPlaying, calendar, timer, shelf, huds, battery, connectivity, lock, shortcuts, advanced, about, update
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
        case .shortcuts: "Keyboard Shortcuts"
        case .advanced: "Advanced"
        case .about: "About"
        case .update: "Software Update"
        }
    }

    /// Every row label on the page, and a few words people might search for instead.
    /// A test checks each row label in Settings/Panes is listed here.
    var keywords: [String] {
        switch self {
        case .general: ["Island", "Show on", "Display", "Screen", "Monitor", "Closed height", "Notch", "Menu Bar", "Custom", "Height",
                        "Without a notch", "Pill", "Hidden", "All Displays", "Open when the pointer rests on it", "Hover",
                        "Opens to", "What's happening", "Last page", "Only when it's the app that's playing", "Full screen",
                        "Video",
                        "Rest before it responds", "Hover delay", "Gestures", "Swipe gestures", "Swipe down to open", "Swipe up to close",
                        "Swipe up to open", "Swipe down to close",
                        "Sideways to skip tracks or turn pages", "Pages", "Follow fingers", "Turn at once", "Reverse direction", "Sensitivity", "Trackpad",
                        "Haptic feedback", "Strength", "Medium", "Strong", "Hide when an app is full screen", "Appearance", "Theme", "Dark", "Light",
                        "Status colors", "Second activity beside the island", "Shadow under the open island", "Shadow",
                        "Hairline outline", "Outline", "Border", "Hide from screenshots and recordings", "Screen recording",
                        "Screenshot", "App", "Open at login", "Hide the menu bar icon", "Quit Nook", "Quit"]
        case .home: ["Preview on the notch", "Layout", "Side by Side", "One at a Time", "Modules side by side", "Size",
                     "Modules", "Order", "Pages", "Page", "New Page", "Group", "Home page", "Shelf", "AirDrop", "Music", "Left button", "Right button", "Favorite", "Output", "Shuffle", "Repeat",
                     "Back 15 seconds", "Forward 15 seconds", "Time after the bar", "Time left", "Length", "Remaining", "Calendar", "Week starts on",
                     "Mark days with events", "Weekends in gray", "Batteries", "Include this Mac", "Weather", "Temperature", "Fahrenheit", "Celsius", "Auto", "My Location",
                     "Add City", "Reminders", "List", "World Clock", "Time zones", "Cities", "Style", "Analog", "Digital", "Shortcuts", "Add Shortcut", "Timer"]
        case .nowPlaying: ["Preview on the notch", "Show what's playing", "Closed island", "Waveform", "Color the waveform from the artwork",
                           "Show the title when the track changes", "Show the title on hover", "Artwork", "Keep a paused player",
                           "Paused", "Hide while the player is full screen", "Show it for", "Peek", "Apps", "Sources", "Browser",
                           "Flip the artwork when the track changes", "Album art", "Music", "Media"]
        case .calendar: ["Preview on the notch", "Show upcoming events", "Show a meeting in the notch", "Access", "Calendar access", "Events",
                         "Once it starts", "Leave the notch", "Stay until it ends", "When an event starts",
                         "Show its title under the island", "Sound", "Chime", "Hide all-day events", "All-day",
                         "Calendars", "Calendar colors"]
        case .timer: ["Preview on the notch", "Sound when it ends", "Alarm"]
        case .shelf: ["Preview on the notch", "Open the shelf when a file is dragged to the notch", "Files", "Drop", "AirDrop", "Catch area",
                      "Tight", "Wide", "Remove files that are gone", "Share"]
        case .huds: ["Preview on the notch", "Replace the volume HUD", "Replace the brightness HUD", "Accessibility access", "Style",
                     "Ledge", "Slider", "Steps", "Outline", "Show the level as a number", "Percentage", "Stays for",
                     "Duration"]
        case .battery: ["Preview on the notch", "Charging and battery notices", "Warn at", "Low battery", "Plugging in and unplugging show for",
                        "Low Power Mode on and off", "Warn when the battery runs low", "Sound"]
        case .connectivity: ["Preview on the notch", "Show when Bluetooth devices connect", "AirPods", "Headphones", "Stays for"]
        case .lock: ["Show lock and unlock"]
        case .shortcuts: ["Shortcut", "Keyboard", "Hotkey", "Record Shortcut"] + ShortcutAction.allCases.map(\.title)
        case .advanced: ["Export Settings", "Import Settings", "Reset All Settings", "Backup"]
        case .about: ["Version", "Acknowledgements", "Check for updates automatically", "Updates"]
        case .update: ["Update", "Update Now", "New version"]
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

/// Shows the part of the island the settings page is about on the real notch while it's open (the
/// home, the player, a volume HUD at the real level), so changes show as they're made.
@Observable
final class IslandPreview {
    static let shared = IslandPreview()
    var isOn = false
    /// Follows the page Settings shows.
    var pane: SettingsPane = .general
}

struct SettingsView: View {
    static let sidebarWidth: CGFloat = 190
    @Bindable private var navigation = SettingsNavigation.shared
    @State private var query = ""
    private let updates = Updates.shared
    private var pane: SettingsPane { navigation.pane }

    var body: some View {
        NavigationSplitView {
            // Plain names in groups; while searching, the pages that match, each with what matched.
            List(selection: $navigation.pane) {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    if updates.release != nil { UpdateSidebarRow().tag(SettingsPane.update) }
                    Text(SettingsPane.general.title).tag(SettingsPane.general)
                    Section("Island") {
                        ForEach([SettingsPane.home, .nowPlaying, .calendar, .timer, .shelf]) { Text($0.title).tag($0) }
                    }
                    Section("Notices") {
                        ForEach([SettingsPane.huds, .battery, .connectivity, .lock]) { Text($0.title).tag($0) }
                    }
                    Section("Nook") {
                        ForEach([SettingsPane.shortcuts, .advanced, .about]) { Text($0.title).tag($0) }
                    }
                } else {
                    ForEach(SettingsPane.allCases.filter { $0.match(query) != nil && (updates.release != nil || $0 != .update) }) { pane in
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
            .navigationSplitViewColumnWidth(Self.sidebarWidth)
            // The sidebar stays (see lockSidebar).
            .toolbar(removing: .sidebarToggle)
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
                case .shortcuts: ShortcutsPane()
                case .advanced: AdvancedPane()
                case .about: AboutPane()
                case .update: UpdatePane()
                }
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .onChange(of: navigation.pane, initial: true) { _, pane in IslandPreview.shared.pane = pane }
        // Installed or gone: the update's page goes, About shows the version.
        .onChange(of: updates.release == nil) { _, gone in
            if gone, navigation.pane == .update { navigation.pane = .about }
        }
        // Otherwise a solid bar sits behind the toolbar once the sidebar is toggled or the window is inactive.
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        #if DEBUG
        .modifier(StillAppearance())
        #endif
    }
}

#if DEBUG
/// A still is taken without focus; draw the controls as the front window has them.
private struct StillAppearance: ViewModifier {
    func body(content: Content) -> some View {
        if CommandLine.arguments.contains("-settings-still") {
            content.environment(\.controlActiveState, .key)
        } else {
            content
        }
    }
}
#endif

/// Keeps a split view's sidebar item open at one width, and puts that back the moment anything changes it.
private final class SidebarLock {
    let item: NSSplitViewItem
    private var observations: [NSKeyValueObservation] = []

    init(item: NSSplitViewItem, width: CGFloat) {
        self.item = item
        let hold = { (item: NSSplitViewItem) in
            if item.canCollapse { item.canCollapse = false }
            if item.minimumThickness != width { item.minimumThickness = width }
            if item.maximumThickness != width { item.maximumThickness = width }
            if item.isCollapsed { item.isCollapsed = false }
        }
        hold(item)
        let reapply: (NSSplitViewItem, Any) -> Void = { item, _ in MainActor.assumeIsolated { hold(item) } }
        observations = [
            item.observe(\.canCollapse, changeHandler: reapply),
            item.observe(\.minimumThickness, changeHandler: reapply),
            item.observe(\.maximumThickness, changeHandler: reapply),
            item.observe(\.isCollapsed, changeHandler: reapply),
        ]
    }
}
