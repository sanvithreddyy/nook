import AppKit
import SwiftUI

/// Keyboard shortcuts that work from any app. None are set to begin with.
struct ShortcutsPane: View {
    var body: some View {
        SettingsPage(title: "Keyboard Shortcuts", area: Prefs.shortcutsArea) {
            SettingsSection(footer: "Click a shortcut, then press the keys. Each one needs Control, or Option with Command, so it never takes over an app's own shortcuts or a typed character. Escape cancels; Delete clears it. One another app has already claimed won't work.") {
                ForEach(ShortcutAction.allCases) { action in
                    SettingsRow(action.title) { ShortcutRecorder(action: action) }
                }
            }
        }
        .onDisappear { ShortcutRecording.shared.stop() }
    }
}

/// Shows a shortcut and records a new one: click, then press the keys.
private struct ShortcutRecorder: View {
    let action: ShortcutAction
    @AppStorage private var stored: String
    private var recording: Bool { ShortcutRecording.shared.action == action }

    init(action: ShortcutAction) {
        self.action = action
        _stored = AppStorage(wrappedValue: "", action.key)
    }

    var body: some View {
        HStack(spacing: 6) {
            Button {
                if recording { ShortcutRecording.shared.stop() } else { ShortcutRecording.shared.start(action) }
            } label: {
                Text(recording ? "Press keys…" : (Shortcut(stored: stored)?.label ?? "Record Shortcut"))
                    .foregroundStyle(stored.isEmpty || recording ? .secondary : .primary)
                    .frame(minWidth: 110)
            }
            if !stored.isEmpty, !recording {
                Button { stored = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Clear \(action.title)")
            }
        }
    }
}

/// The one shortcut being recorded, if any. Nook's own shortcuts pause meanwhile, and recording stops
/// when Settings closes, loses focus or Nook goes to the background, since a SwiftUI page doesn't
/// hear its window close.
@Observable
final class ShortcutRecording {
    static let shared = ShortcutRecording()
    private(set) var action: ShortcutAction?
    @ObservationIgnored private var monitor: Any?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    func start(_ action: ShortcutAction) {
        stop()
        self.action = action
        HotKeys.shared.isSuspended = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event) ?? event
        }
        let center = NotificationCenter.default
        observers = [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification, NSApplication.didResignActiveNotification].map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.stop() }
            }
        }
    }

    func stop() {
        guard action != nil || monitor != nil else { return }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        action = nil
        HotKeys.shared.isSuspended = false
    }

    /// The key press, or nil when recording took it.
    private func handle(_ event: NSEvent) -> NSEvent? {
        guard let action else { return event }
        let modified = !event.modifierFlags.intersection([.command, .option, .control]).isEmpty
        if event.keyCode == 53 {
            stop()
            return nil
        }
        if (event.keyCode == 51 || event.keyCode == 117) && !modified {
            UserDefaults.standard.set("", forKey: action.key)
            stop()
            return nil
        }
        if let shortcut = Shortcut(event: event) {
            // One shortcut does one thing: whatever had it lets it go.
            for other in ShortcutAction.allCases where other != action && Shortcut.saved(other) == shortcut {
                UserDefaults.standard.set("", forKey: other.key)
            }
            UserDefaults.standard.set(shortcut.stored, forKey: action.key)
            stop()
            return nil
        }
        // Command with a key is the app's (Close, Quit): stop recording and let it through.
        if event.modifierFlags.contains(.command) {
            stop()
            return event
        }
        return nil
    }
}
