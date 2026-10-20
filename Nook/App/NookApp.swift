import SwiftUI

@main
struct NookApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Nook is a menu bar agent; its windows are managed by AppDelegate.
        Settings { EmptyView() }
    }
}
