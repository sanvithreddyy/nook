import SwiftUI

struct NowPlayingPane: View {
    @AppStorage(Prefs.nowPlaying) private var enabled = true
    @AppStorage(Prefs.peekOnTrackChange) private var peekOnTrackChange = true
    @AppStorage(Prefs.peekOnHover) private var peekOnHover = true
    @AppStorage(Prefs.expandOnHover) private var expandOnHover = true
    @AppStorage(Prefs.showWaveform) private var showWaveform = true
    @AppStorage(Prefs.tintWaveform) private var tintWaveform = true

    var body: some View {
        SettingsPage(title: "Now Playing") {
            SettingsSection {
                SettingsToggle("Show what's playing", isOn: $enabled)
            }
            SettingsSection("Closed island") {
                SettingsToggle("Waveform", isOn: $showWaveform)
                SettingsToggle("Color the waveform from the artwork", isOn: $tintWaveform)
                    .disabled(!showWaveform)
                SettingsToggle("Show the title when the track changes", isOn: $peekOnTrackChange)
                SettingsToggle("Show the title on hover",
                               description: expandOnHover ? "Hovering opens the island instead. Turn off \"Open when the pointer rests on it\" in General to use this." : nil,
                               isOn: $peekOnHover)
                    .disabled(expandOnHover)
            }
            .disabled(!enabled)
        }
    }
}
