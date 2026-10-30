import AppKit
import SwiftUI

struct BatteryPane: View {
    @AppStorage(Prefs.battery) private var enabled = true
    @AppStorage(Prefs.lowBatteryThreshold) private var threshold = 20
    @AppStorage(Prefs.batteryNoticeDuration) private var duration = 2.5
    @AppStorage(Prefs.lowBatteryWarning) private var warn = true
    @AppStorage(Prefs.lowBatterySound) private var sound = ""
    @AppStorage(Prefs.lowPowerNotice) private var lowPower = true

    var body: some View {
        SettingsPage(title: "Battery", area: Prefs.batteryArea, preview: "Shows the battery notice on the notch while you change things here.") {
            SettingsSection {
                SettingsToggle("Charging and battery notices", isOn: $enabled)
                Group {
                    SettingsRow("Plugging in shows for", value: String(format: "%.1f s", duration), wide: true) {
                        Slider(value: $duration, in: 1.5...5, step: 0.5)
                    }
                    SettingsToggle("Low Power Mode on and off", isOn: $lowPower)
                }
                .disabled(!enabled)
            }
            SettingsSection("Low battery") {
                SettingsToggle("Warn when the battery runs low", isOn: $warn)
                Group {
                    SettingsRow("Warn at") {
                        Picker("Warn at", selection: $threshold) {
                            ForEach([10, 15, 20, 25, 30], id: \.self) { Text("\($0)%").tag($0) }
                        }
                        .menuStyle()
                    }
                    SettingsRow("Sound") {
                        Picker("Sound", selection: $sound) {
                            Text("None").tag("")
                            Divider()
                            ForEach(TimerPane.sounds, id: \.self) { Text($0).tag($0) }
                        }
                        .menuStyle()
                        .onChange(of: sound) { _, new in
                            if !new.isEmpty { NSSound(named: new)?.play() }
                        }
                    }
                }
                .disabled(!warn)
            }
            .disabled(!enabled)
        }
    }
}
