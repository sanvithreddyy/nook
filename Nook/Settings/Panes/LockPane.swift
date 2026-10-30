import SwiftUI

struct LockPane: View {
    @AppStorage(Prefs.lockActivity) private var enabled = true

    var body: some View {
        SettingsPage(title: "Lock Screen") {
            SettingsSection {
                SettingsToggle("Show lock and unlock", isOn: $enabled)
            }
        }
    }
}
