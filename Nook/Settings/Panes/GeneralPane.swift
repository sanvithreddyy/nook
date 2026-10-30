import AppKit
import ServiceManagement
import SwiftUI

struct GeneralPane: View {
    @AppStorage(Prefs.display) private var display = DisplayChoice.builtIn.rawValue
    @AppStorage(Prefs.hideInFullscreen) private var hideInFullscreen = false
    @AppStorage(Prefs.expandOnHover) private var expandOnHover = true
    @AppStorage(Prefs.swipeGestures) private var swipeGestures = true
    @AppStorage(Prefs.enableHaptics) private var haptics = true
    @AppStorage(Prefs.hideMenuBarIcon) private var hideMenuBarIcon = false
    @AppStorage(Prefs.statusColors) private var statusColors = true
    @AppStorage(Prefs.showCompanion) private var showCompanion = true
    @AppStorage(Prefs.settingsAppearance) private var appearance = SettingsAppearance.light
    @State private var loginError: String?

    var body: some View {
        SettingsPage(title: "General") {
            SettingsSection("Island") {
                SettingsRow("Show on") {
                    Picker("Show on", selection: $display) {
                        ForEach(DisplayChoice.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    .menuStyle()
                }
                SettingsToggle("Open when the pointer rests on it", isOn: $expandOnHover)
                SettingsToggle("Swipe gestures", description: "Two fingers down opens and up closes. Sideways skips tracks, or turns cards when the island is open.",
                               isOn: $swipeGestures)
                SettingsToggle("Haptic feedback", isOn: $haptics)
                SettingsToggle("Hide when an app is full screen", isOn: $hideInFullscreen)
            }
            SettingsSection("Appearance") {
                SettingsRow("Theme", description: "For this window. The island is always black.") {
                    Picker("Theme", selection: $appearance) {
                        ForEach(SettingsAppearance.allCases) { Text($0.title).tag($0) }
                    }
                    .segmentedStyle()
                    .onChange(of: appearance) { _, _ in SettingsWindowController.shared.applyAppearance() }
                }
                SettingsRow("Status colors", description: "Green for charging and AirPods, orange for timers, blue when sound switches. Low battery is red either way.") {
                    Picker("Status colors", selection: $statusColors) {
                        Text("Apple's").tag(true)
                        Text("White").tag(false)
                    }
                    .segmentedStyle()
                }
                SettingsToggle("Second activity beside the island", description: "A timer while music plays, or a meeting about to start, gets its own drop.",
                               isOn: $showCompanion)
            }
            SettingsSection("App") {
                SettingsRow("Open at login", description: loginError) {
                    Toggle("Open at login", isOn: launchAtLogin).toggleStyle(.switch).labelsHidden()
                }
                SettingsToggle("Hide the menu bar icon",
                               description: hideMenuBarIcon ? "Open Nook again from Finder or Spotlight to get back here." : nil,
                               isOn: $hideMenuBarIcon)
            }
        }
    }

    private var launchAtLogin: Binding<Bool> {
        Binding(
            get: { SMAppService.mainApp.status == .enabled },
            set: { enabled in
                do {
                    if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    loginError = nil
                } catch {
                    loginError = "Couldn't change: \(error.localizedDescription)"
                }
            }
        )
    }
}
