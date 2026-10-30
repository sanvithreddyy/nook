import AppKit
import SwiftUI

/// Keyboard shortcuts that work from any app. None are set to begin with.
struct ShortcutsPane: View {
    var body: some View {
        SettingsPage(title: "Keyboard Shortcuts", area: Prefs.shortcutsArea) {
            SettingsSection(footer: "Click a shortcut, then press the keys. Escape cancels; Delete clears it. A shortcut another app already uses won't fire.") {
                ForEach(ShortcutAction.allCases) { action in
                    SettingsRow(action.title) { ShortcutRecorder(action: action) }
                }
            }
        }
    }
}

/// Shows a shortcut and records a new one: click, then press the keys.
private struct ShortcutRecorder: View {
    let action: ShortcutAction
    @AppStorage private var stored: String
    @State private var recording = false
    @State private var monitor: Any?

    init(action: ShortcutAction) {
        self.action = action
        _stored = AppStorage(wrappedValue: "", action.key)
    }

    var body: some View {
        HStack(spacing: 6) {
            Button { recording ? stop() : record() } label: {
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
        .onDisappear { stop() }
    }

    private func record() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modified = !event.modifierFlags.intersection([.command, .option, .control]).isEmpty
            if event.keyCode == 53 {
                stop()
            } else if (event.keyCode == 51 || event.keyCode == 117) && !modified {
                stored = ""
                stop()
            } else if let shortcut = Shortcut(event: event) {
                // One shortcut does one thing: whatever had it lets it go.
                for other in ShortcutAction.allCases where other != action && Shortcut.saved(other) == shortcut {
                    UserDefaults.standard.set("", forKey: other.key)
                }
                stored = shortcut.stored
                stop()
            }
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
