import SwiftUI

struct ConnectivityPane: View {
    @AppStorage(Prefs.connectivity) private var enabled = true
    @AppStorage(Prefs.deviceNoticeDuration) private var duration = 2.5

    var body: some View {
        SettingsPage(title: "Connectivity", area: Prefs.connectivityArea, preview: "Shows AirPods connecting, as a sample, on the notch.") {
            SettingsSection {
                SettingsToggle("Show when Bluetooth devices connect",
                               description: "AirPods and other headphones show their battery when macOS reports it, and sound switching to them shows too.",
                               isOn: $enabled)
                SettingsRow("Stays for", value: String(format: "%.1f s", duration), wide: true) {
                    Slider(value: $duration, in: 1.5...6, step: 0.5)
                }
                .disabled(!enabled)
            }
        }
    }
}
