import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Settings as a whole: save them to a file, bring them back (on this Mac or another), or start over.
struct AdvancedPane: View {
    @State private var confirmingReset = false
    @State private var status: String?

    var body: some View {
        SettingsPage(title: "Advanced") {
            SettingsSection("Settings", footer: status) {
                SettingsRow("Export Settings", description: "Saves every setting to a file.") {
                    Button("Export…") { export() }
                }
                SettingsRow("Import Settings", description: "Applies the settings in a file saved with Export.") {
                    Button("Import…") { importFile() }
                }
                SettingsRow("Reset All Settings") {
                    Button("Reset…") { confirmingReset = true }
                }
            }
        }
        .confirmationDialog("Reset all settings?", isPresented: $confirmingReset) {
            Button("Reset All", role: .destructive) {
                Prefs.areas.forEach(Prefs.reset)
                status = "Every setting is back to how Nook comes."
            }
        } message: {
            Text("Every page goes back to how Nook comes. The shelf's files and your timer stay.")
        }
    }

    private func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Nook Settings.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try SettingsFile.export().write(to: url, options: .atomic)
            status = "Saved to \(url.lastPathComponent)."
        } catch {
            status = "Couldn't save: \(error.localizedDescription)"
        }
    }

    private func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let count = try SettingsFile.apply(Data(contentsOf: url))
            status = count == 1 ? "1 setting applied." : "\(count) settings applied."
        } catch {
            status = "Couldn't read that file: it isn't a Nook settings file."
        }
    }
}

/// Settings as JSON: every key an area owns, with its current value. Importing only touches keys
/// Nook knows, with values of the type the key's default has.
enum SettingsFile {
    static func export() throws -> Data {
        var values: [String: Any] = [:]
        for area in Prefs.areas {
            for key in area.defaults.keys {
                if let value = UserDefaults.standard.object(forKey: key), JSONSerialization.isValidJSONObject([value]) {
                    values[key] = value
                }
            }
        }
        return try JSONSerialization.data(withJSONObject: ["nook": 1, "settings": values], options: [.prettyPrinted, .sortedKeys])
    }

    /// Returns how many settings were applied.
    static func apply(_ data: Data) throws -> Int {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let values = root["settings"] as? [String: Any]
        else { throw CocoaError(.fileReadCorruptFile) }
        var defaults: [String: Any] = [:]
        for area in Prefs.areas { defaults.merge(area.defaults) { first, _ in first } }
        var applied = 0
        for (key, value) in values {
            guard let fallback = defaults[key], sameKind(value, fallback) else { continue }
            UserDefaults.standard.set(value, forKey: key)
            applied += 1
        }
        return applied
    }

    /// JSON numbers come back as NSNumber, which covers Bool, Int and Double alike.
    private static func sameKind(_ value: Any, _ fallback: Any) -> Bool {
        switch fallback {
        case is String: value is String
        case is Bool, is Int, is Double: value is NSNumber
        default: false
        }
    }
}
