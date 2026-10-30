import SwiftUI

struct AboutPane: View {
    var body: some View {
        SettingsPage(title: "About") {
            SettingsSection {
                SettingsRow("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
            }
            SettingsSection("Acknowledgements") {
                Text("Now playing uses mediaremote-adapter by Jonas van den Berg, BSD 3-Clause License.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 11)
            }
        }
    }
}

/// Volume and brightness styles as thumbnails, like macOS's own appearance picker.
