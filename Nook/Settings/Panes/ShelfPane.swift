import SwiftUI

struct ShelfPane: View {
    @AppStorage(Prefs.shelf) private var enabled = true

    var body: some View {
        SettingsPage(title: "Shelf") {
            SettingsSection {
                SettingsToggle("Open the shelf when a file is dragged to the notch",
                               description: "Files stay where they are; the shelf keeps a reference. Dropped text, links and images are saved in Application Support/Nook/Shelf until you remove them.",
                               isOn: $enabled)
            }
        }
    }
}
