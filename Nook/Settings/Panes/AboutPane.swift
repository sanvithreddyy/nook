import SwiftUI

struct AboutPane: View {
    @Bindable private var updates = Updates.shared

    var body: some View {
        SettingsPage(title: "About") {
            SettingsSection {
                SettingsRow("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                SettingsRow("Updates", description: updateStatus) {
                    if updates.release != nil {
                        Button("Show Update") { updates.checkNow() }
                    } else {
                        Button("Check Now") { updates.checkNow() }
                            .disabled(!updates.canCheck || updates.check == .checking)
                    }
                }
                SettingsToggle("Check for updates automatically", description: "Once a day.",
                               isOn: $updates.checksAutomatically)
            }
            SettingsSection("Acknowledgements") {
                ForEach(["Now playing uses mediaremote-adapter by Jonas van den Berg, BSD 3-Clause License.",
                         "Updates use Sparkle, MIT License."], id: \.self) { credit in
                    Text(credit)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 11)
                }
            }
        }
        .onAppear { updates.refreshLastChecked() }
    }

    private var updateStatus: String? {
        if let release = updates.release { return "Nook \(release.version) is available." }
        switch updates.check {
        case .checking: return "Checking…"
        case .upToDate: return "Nook is up to date."
        case .failed: return "Couldn't check. Try again in a moment."
        case .idle:
            guard let date = updates.lastChecked else { return nil }
            return "Last checked \(date.formatted(.relative(presentation: .named)))."
        }
    }
}

/// Volume and brightness styles as thumbnails, like macOS's own appearance picker.
