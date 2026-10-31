import SwiftUI

@main
struct NookApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Nook is a menu bar agent; its windows are managed by AppDelegate.
        Settings { EmptyView() }
            // The menu bar shows while Settings is open: Settings… opens Nook's own window, and there's
            // no Help book to offer.
            .commands {
                CommandGroup(replacing: .appSettings) {
                    Button("Settings…") { SettingsWindowController.shared.show() }
                        .keyboardShortcut(",")
                }
                // File holds only Close (Command-W), in place of the system's save and close group.
                CommandGroup(replacing: .saveItem) {
                    Button("Close") { NSApp.keyWindow?.performClose(nil) }
                        .keyboardShortcut("w")
                }
                CommandGroup(replacing: .help) {}
            }
    }
}
