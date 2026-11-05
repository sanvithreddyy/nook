import SwiftUI

struct ConverterPane: View {
    @AppStorage(Prefs.convert) private var enabled = true
    @AppStorage(Prefs.convertToDownloads) private var toDownloads = false
    @AppStorage(Prefs.convertKeepOriginal) private var keepOriginal = true
    @AppStorage(Prefs.convertPhotoQuality) private var photoQuality = "high"
    @AppStorage(Prefs.convertAudioKbps) private var audioKbps = 256
    private let pack = FormatPack.shared

    var body: some View {
        SettingsPage(title: "Converter", area: Prefs.convertArea, preview: "Opens the shelf on the notch while you change things here.") {
            SettingsSection(footer: "Files are converted on this Mac. Nothing is uploaded.") {
                SettingsToggle("Convert on the shelf",
                               description: "While you drag files, Convert shows beside AirDrop. Rest them on it to pick a format. Files already on the shelf have Convert To in their menu.",
                               isOn: $enabled)
                SettingsRow("Save converted files") {
                    Picker("Save converted files", selection: $toDownloads) {
                        Text("Next to the original").tag(false)
                        Text("In Downloads").tag(true)
                    }
                    .menuStyle()
                }
                SettingsToggle("Keep the original", description: keepOriginal ? nil : "The original goes to the Trash once it's converted.",
                               isOn: $keepOriginal)
            }
            SettingsSection("Quality") {
                SettingsRow("Photos", description: "JPEG, HEIC and AVIF.") {
                    Picker("Photos", selection: $photoQuality) {
                        Text("High").tag("high")
                        Text("Balanced").tag("balanced")
                        Text("Smaller files").tag("smaller")
                    }
                    .menuStyle()
                }
                SettingsRow("Audio", description: "AAC in M4A files.") {
                    Picker("Audio", selection: $audioKbps) {
                        ForEach([128, 192, 256, 320], id: \.self) { Text("\($0) kbps").tag($0) }
                    }
                    .menuStyle()
                }
            }
            SettingsSection(footer: "Adds MP3, WebP, WebM, MKV and Opus, and converting WebM, MKV and Ogg files, with open-source encoders (FFmpeg, LAME, libwebp, libvpx and Opus). Kept in Application Support/Nook.") {
                SettingsRow("More Formats", description: packStatus) {
                    switch pack.state {
                    case .installed:
                        Button("Remove") { pack.remove() }
                    case .downloading(let share):
                        ProgressView(value: share).frame(width: 120)
                    case .notInstalled, .failed:
                        Button(FormatPack.size > 0 ? "Download (\(ByteCountFormatter.string(fromByteCount: FormatPack.size, countStyle: .file)))" : "Download") {
                            Task { await pack.install() }
                        }
                    }
                }
            }
        }
    }

    private var packStatus: String? {
        switch pack.state {
        case .installed: "Installed."
        case .downloading: "Downloading…"
        case .failed(let reason): reason
        case .notInstalled: nil
        }
    }
}
