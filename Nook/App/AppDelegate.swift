import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: NotchCoordinator?
    private var statusItem: NSStatusItem?
    private var hideIconObserver: NSKeyValueObservation?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Prefs.registerDefaults()
        let coordinator = NotchCoordinator()
        coordinator.start()
        self.coordinator = coordinator
        installStatusItem()
        hideIconObserver = UserDefaults.standard.observe(\.hideMenuBarIcon, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.installStatusItem() }
        }
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
        item.button?.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "Nook")
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
