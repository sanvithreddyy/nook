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
    case general, home, nowPlaying, calendar, timer, shelf, huds, battery, connectivity, lock, about
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
                    ForEach([SettingsPane.home, .nowPlaying, .calendar, .timer, .shelf]) { Text($0.title).tag($0) }
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
                case .home: HomePane()
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
        }
        .frame(minWidth: 760, minHeight: 520)
        // Otherwise a solid bar sits behind the toolbar once the sidebar is toggled or the window is inactive.
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
    }
}
