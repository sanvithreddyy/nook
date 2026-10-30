import SwiftUI

struct BatteryPane: View {
    @AppStorage(Prefs.battery) private var enabled = true
    @AppStorage(Prefs.lowBatteryThreshold) private var threshold = 20

    var body: some View {
        SettingsPage(title: "Battery", area: Prefs.batteryArea) {
            SettingsSection {
                SettingsToggle("Charging and battery notices", isOn: $enabled)
                SettingsRow("Warn at") {
                    Picker("Warn at", selection: $threshold) {
                        ForEach([10, 15, 20, 25, 30], id: \.self) { Text("\($0)%").tag($0) }
                    }
                    .menuStyle()
                }
                .disabled(!enabled)
            }
        }
    }
}
