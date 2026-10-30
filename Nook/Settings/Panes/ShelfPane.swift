import SwiftUI

struct ShelfPane: View {
    @AppStorage(Prefs.shelf) private var enabled = true
    @AppStorage(Prefs.shelfCatchWide) private var catchWide = false
    @AppStorage(Prefs.shelfDropMissing) private var dropMissing = false

    var body: some View {
        SettingsPage(title: "Shelf", area: Prefs.shelfArea, preview: "Opens the shelf on the notch while you change things here.") {
            SettingsSection {
                SettingsToggle("Open the shelf when a file is dragged to the notch",
                               description: "Files stay where they are; the shelf keeps a reference. Dropped text, links and images are saved in Application Support/Nook/Shelf until you remove them.",
                               isOn: $enabled)
                Group {
                    SettingsRow("Catch area", description: catchWide ? "A drag anywhere along the top of the screen near the notch opens it, and a little below." : "Only a drag right at the notch opens it, so drags to tab bars below don't.") {
                        Picker("Catch area", selection: $catchWide) {
                            Text("Tight").tag(false)
                            Text("Wide").tag(true)
                        }
                        .segmentedStyle()
                    }
                    SettingsToggle("Remove files that are gone", description: "Files that were deleted, or are on a disk that isn't connected, leave the shelf when it opens.",
                                   isOn: $dropMissing)
                }
                .disabled(!enabled)
            }
        }
    }
}
