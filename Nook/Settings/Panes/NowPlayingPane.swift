import AppKit
import SwiftUI

struct NowPlayingPane: View {
    @AppStorage(Prefs.nowPlaying) private var enabled = true
    @AppStorage(Prefs.peekOnTrackChange) private var peekOnTrackChange = true
    @AppStorage(Prefs.peekOnHover) private var peekOnHover = true
    @AppStorage(Prefs.expandOnHover) private var expandOnHover = true
    @AppStorage(Prefs.showWaveform) private var showWaveform = true
    @AppStorage(Prefs.tintWaveform) private var tintWaveform = true
    @AppStorage(Prefs.artworkFlip) private var artworkFlip = true
    @AppStorage(Prefs.pausedLinger) private var pausedLinger = 5
    @AppStorage(Prefs.peekDuration) private var peekDuration = 3.0
    @AppStorage(Prefs.hideWhenPlayerFront) private var hideWhenPlayerFront = true
    @AppStorage(Prefs.mediaIgnoredApps) private var ignoredText = ""
    /// Read here so an app that starts playing while Settings is open joins the list.
    @AppStorage(Prefs.mediaSeenApps) private var seenText = ""

    var body: some View {
        SettingsPage(title: "Now Playing", area: Prefs.mediaArea, preview: "Opens the player on the notch while you change things here.") {
            SettingsSection {
                SettingsToggle("Show what's playing", isOn: $enabled)
                SettingsRow("Keep a paused player") {
                    Picker("Keep a paused player", selection: $pausedLinger) {
                        Text("5 seconds").tag(5)
                        Text("30 seconds").tag(30)
                        Text("1 minute").tag(60)
                        Text("5 minutes").tag(300)
                        Text("Until the player stops").tag(-1)
                    }
                    .menuStyle()
                }
                .disabled(!enabled)
                SettingsToggle("Hide while the player is in front", description: "The closed island leaves out what's playing while its app is in front, as when you watch a video. The open island still shows the player.",
                               isOn: $hideWhenPlayerFront)
                    .disabled(!enabled)
            }
            SettingsSection("Closed island") {
                SettingsToggle("Waveform", isOn: $showWaveform)
                SettingsToggle("Color the waveform from the artwork", isOn: $tintWaveform)
                    .disabled(!showWaveform)
                SettingsToggle("Show the title when the track changes", isOn: $peekOnTrackChange)
                SettingsRow("Show it for", value: String(format: "%.0f s", peekDuration), wide: true) {
                    Slider(value: $peekDuration, in: 1...6, step: 1)
                        .accessibilityLabel("Show the title for")
                }
                .disabled(!peekOnTrackChange)
                SettingsToggle("Show the title on hover",
                               description: expandOnHover ? "Hovering opens the island instead. Turn off \"Open when the pointer rests on it\" in General to use this." : nil,
                               isOn: $peekOnHover)
                    .disabled(expandOnHover)
            }
            .disabled(!enabled)
            SettingsSection("Artwork") {
                SettingsToggle("Flip the artwork when the track changes", isOn: $artworkFlip)
            }
            .disabled(!enabled)
            SettingsSection("Apps", footer: "Turn an app off and what it plays stays off the island: a browser's videos, say.") {
                let seen = seenText.split(separator: ",").map(String.init)
                if seen.isEmpty {
                    Text("Apps show here once they've played something.")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 11)
                }
                ForEach(seen, id: \.self) { app in
                    SettingsToggle(Self.name(of: app), isOn: following(app))
                }
            }
            .disabled(!enabled)
        }
    }

    /// On while the island follows the app; reads the ignored list so the switch updates with it.
    private func following(_ app: String) -> Binding<Bool> {
        Binding(
            get: { !ignoredText.split(separator: ",").contains(Substring(app)) },
            set: { MediaSources.setIgnored(app, !$0) }
        )
    }

    private static func name(of app: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app) else { return app }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}
