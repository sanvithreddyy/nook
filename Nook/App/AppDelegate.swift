import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: NotchCoordinator?
    private var statusItem: NSStatusItem?
    private var hideIconObserver: NSKeyValueObservation?
    private var terminationSource: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Prefs.registerDefaults()
        let coordinator = NotchCoordinator()
        coordinator.start()
        self.coordinator = coordinator
        // `kill` and logout send SIGTERM, which skips applicationWillTerminate; stop the adapter first.
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.coordinator?.stop() }
            exit(0)
        }
        source.resume()
        terminationSource = source
        installStatusItem()
        Updates.shared.start()
        if Updates.shared.takeReopenRequest() { SettingsWindowController.shared.show(pane: .about) }
        #if DEBUG
        if CommandLine.arguments.contains("-settings-capture") { SettingsWindowController.shared.runCapture() }
        if CommandLine.arguments.contains("-settings-sidebar") { SettingsWindowController.shared.runSidebarProbe() }
        // -settings-show <pane>: Settings on that page without focus, left open, for recordings.
        if let i = CommandLine.arguments.firstIndex(of: "-settings-show"), i + 1 < CommandLine.arguments.count,
           let pane = SettingsPane(rawValue: CommandLine.arguments[i + 1]) {
            SettingsWindowController.shared.show(activate: false, pane: pane)
        }
        // -settings-still <pane>: Settings on that page without focus, its window number printed, for a still.
        if let i = CommandLine.arguments.firstIndex(of: "-settings-still"), i + 1 < CommandLine.arguments.count,
           let pane = SettingsPane(rawValue: CommandLine.arguments[i + 1]) {
            SettingsWindowController.shared.show(activate: false, pane: pane)
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.5))
                print("STILL \(NSApp.windows.first { $0.title == "Nook" }?.windowNumber ?? 0)")
                fflush(stdout)
                try? await Task.sleep(for: .seconds(3))
                NSApp.terminate(nil)
            }
        }
        // -settings-preview <pane>: Settings on that page with "Preview on the notch" on, for captures.
        let args = CommandLine.arguments
        // -settings-open: Settings in front as a click on Settings… opens it, then the menu bar's menus
        // printed, to check them.
        if args.contains("-settings-open") {
            SettingsWindowController.shared.show()
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.5))
                for item in NSApp.mainMenu?.items ?? [] {
                    print("\(item.title): " + (item.submenu?.items.map(\.title).filter { !$0.isEmpty }.joined(separator: ", ") ?? ""))
                }
                fflush(stdout)
            }
        }
        if let i = args.firstIndex(of: "-settings-preview"), i + 1 < args.count, let pane = SettingsPane(rawValue: args[i + 1]) {
            SettingsWindowController.shared.show(activate: false, pane: pane)
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                IslandPreview.shared.isOn = true
            }
        }
        #endif
        hideIconObserver = UserDefaults.standard.observe(\.hideMenuBarIcon, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.installStatusItem() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Launching Nook again from Finder or Spotlight is the way back to settings when the icon is hidden.
        SettingsWindowController.shared.show()
        return false
    }

    private func installStatusItem() {
        if UserDefaults.standard.bool(forKey: Prefs.hideMenuBarIcon) {
            if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
            statusItem = nil
            return
        }
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(named: "MenuBarIcon")
        image?.accessibilityDescription = "Nook"
        item.button?.image = image
        let menu = NSMenu()
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Nook", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }
}

extension UserDefaults {
    @objc dynamic var hideMenuBarIcon: Bool { bool(forKey: Prefs.hideMenuBarIcon) }
}
