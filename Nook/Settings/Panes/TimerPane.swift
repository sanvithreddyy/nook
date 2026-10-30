import AppKit
import SwiftUI

struct TimerPane: View {
    @AppStorage(Prefs.timerSound) private var sound = "Glass"

    private static let sounds: [String] = {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: "/System/Library/Sounds")) ?? []
        return files.map { ($0 as NSString).deletingPathExtension }.sorted()
    }()

    var body: some View {
        SettingsPage(title: "Timer", area: Prefs.timerArea) {
            SettingsSection {
                SettingsRow("Sound when it ends",
                            description: "Start a timer from the island's right-click menu. On the open timer, scroll over the time to add or take off minutes.") {
                    Picker("Sound when it ends", selection: $sound) {
                        Text("None").tag("")
                        Divider()
                        ForEach(Self.sounds, id: \.self) { Text($0).tag($0) }
                    }
                    .menuStyle()
                    .onChange(of: sound) { _, new in
                        if !new.isEmpty { NSSound(named: new)?.play() }
                    }
                }
            }
        }
    }
}
