import SwiftUI

struct ConnectivityPane: View {
    @AppStorage(Prefs.connectivity) private var enabled = true

    var body: some View {
        SettingsPage(title: "Connectivity", area: Prefs.connectivityArea, preview: "Shows AirPods connecting, as a sample, on the notch.") {
            SettingsSection {
                SettingsToggle("Show when Bluetooth devices connect",
                               description: "AirPods and other headphones show their battery when macOS reports it, and sound switching to them shows too.",
                               isOn: $enabled)
            }
        }
    }
}
