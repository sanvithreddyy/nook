import AppKit
import ServiceManagement
import SwiftUI

struct GeneralPane: View {
    @AppStorage(Prefs.display) private var display = DisplayChoice.builtIn.rawValue
    @AppStorage(Prefs.closedHeight) private var closedHeight = ClosedHeight.notch
    @AppStorage(Prefs.closedHeightCustom) private var customHeight = 32.0
    @AppStorage(Prefs.notchlessStyle) private var notchless = NotchlessStyle.notch
    @AppStorage(Prefs.hideInFullscreen) private var hideInFullscreen = false
    @AppStorage(Prefs.fullscreenMediaOnly) private var fullscreenMediaOnly = false
    @AppStorage(Prefs.openTo) private var openTo = OpenTo.whatsHappening
    @AppStorage(Prefs.expandOnHover) private var expandOnHover = true
    @AppStorage(Prefs.hoverDelay) private var hoverDelay = 0.18
    @AppStorage(Prefs.swipeGestures) private var swipeGestures = true
    @AppStorage(Prefs.swipeOpenClose) private var swipeOpenClose = true
    @AppStorage(Prefs.swipeSideways) private var swipeSideways = true
    @AppStorage(Prefs.swipeReversed) private var swipeReversed = false
    @AppStorage(Prefs.swipeSensitivity) private var swipeSensitivity = SwipeSensitivity.medium
    @AppStorage(Prefs.enableHaptics) private var haptics = true
    @AppStorage(Prefs.hideMenuBarIcon) private var hideMenuBarIcon = false
    @AppStorage(Prefs.statusColors) private var statusColors = true
    @AppStorage(Prefs.showCompanion) private var showCompanion = true
    @AppStorage(Prefs.islandShadow) private var shadow = true
    @AppStorage(Prefs.islandOutline) private var outline = false
    @AppStorage(Prefs.hideFromCapture) private var hideFromCapture = false
    @AppStorage(Prefs.settingsAppearance) private var appearance = SettingsAppearance.light
    @State private var loginError: String?

    var body: some View {
        SettingsPage(title: "General", area: Prefs.generalArea) {
            SettingsSection("Island") {
                SettingsRow("Show on") {
                    Picker("Show on", selection: $display) {
                        ForEach(DisplayChoice.choices(keeping: display)) { Text($0.label).tag($0.rawValue) }
                    }
                    .menuStyle()
                }
                SettingsRow("Closed height", description: closedHeight == .notch ? nil : "Never shorter than a real notch.") {
                    Picker("Closed height", selection: $closedHeight) {
                        ForEach(ClosedHeight.allCases) { Text($0.title).tag($0) }
                    }
                    .segmentedStyle()
                }
                if closedHeight == .custom {
                    SettingsRow("Height", value: "\(Int(customHeight)) pt", wide: true) {
                        Slider(value: $customHeight, in: 24...44, step: 1)
                            .accessibilityLabel("Height")
                    }
                }
                SettingsRow("Without a notch", description: "On screens that have none: a drawn notch, a pill like Apple's own island, or nothing until there's something to show.") {
                    Picker("Without a notch", selection: $notchless) {
                        ForEach(NotchlessStyle.allCases) { Text($0.title).tag($0) }
                    }
                    .segmentedStyle()
                }
                SettingsToggle("Open when the pointer rests on it", isOn: $expandOnHover)
                SettingsRow("Opens to", description: openTo == .whatsHappening ? "The page for what the closed island shows: the music, a meeting, a timer." : nil) {
                    Picker("Opens to", selection: $openTo) {
                        ForEach(OpenTo.allCases) { Text($0.title).tag($0) }
                    }
                    .menuStyle()
                }
                SettingsRow("Rest before it responds", value: String(format: "%.2f s", hoverDelay), wide: true) {
                    // Not quite zero: a pointer sweeping across the menu bar would open the island on the way past.
                    Slider(value: $hoverDelay, in: 0.05...0.6, step: 0.05)
                        .accessibilityLabel("Rest before it responds")
                }
                SettingsToggle("Haptic feedback", isOn: $haptics)
                SettingsToggle("Hide when an app is full screen", isOn: $hideInFullscreen)
                SettingsToggle("Only when it's the app that's playing", description: "A video full screen hides the island; other full-screen apps keep it.",
                               isOn: $fullscreenMediaOnly)
                    .disabled(!hideInFullscreen)
            }
            SettingsSection("Gestures") {
                SettingsToggle("Swipe gestures", description: "Two fingers on the trackpad, with the pointer on the island.",
                               isOn: $swipeGestures)
                Group {
                    SettingsToggle(swipeReversed ? "Up to open, down to close" : "Down to open, up to close", isOn: $swipeOpenClose)
                    SettingsToggle("Sideways to skip tracks or turn pages", isOn: $swipeSideways)
                    SettingsToggle("Reverse direction", isOn: $swipeReversed)
                    SettingsRow("Sensitivity") {
                        Picker("Sensitivity", selection: $swipeSensitivity) {
                            ForEach(SwipeSensitivity.allCases) { Text($0.title).tag($0) }
                        }
                        .segmentedStyle()
                    }
                }
                .disabled(!swipeGestures)
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
                SettingsToggle("Shadow under the open island", isOn: $shadow)
                SettingsToggle("Hairline outline", description: "So the island shows against a black menu bar or a dark wallpaper.",
                               isOn: $outline)
                SettingsToggle("Hide from screenshots and recordings", isOn: $hideFromCapture)
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
