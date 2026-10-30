import Foundation
import Testing

/// Search finds a page by any of its row labels, so every label in Settings/Panes must be listed in
/// its page's keywords. Reads the page sources, so a new row without a keyword fails here.
struct SettingsSearchTests {
    @Test func everyRowLabelIsSearchable() throws {
        let panes = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Nook/Settings/Panes")
        let files = try FileManager.default.contentsOfDirectory(at: panes, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        #expect(!files.isEmpty)
        let pattern = try Regex(#"(SettingsToggle|SettingsRow)\("([^"]+)""#)
        let keywords = Set(SettingsPane.allCases.flatMap { $0.keywords + [$0.title] })
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            for match in source.matches(of: pattern) {
                let label = String(match.output[2].substring ?? "")
                #expect(keywords.contains(label), "\"\(label)\" in \(file.lastPathComponent) isn't in SettingsPane.keywords")
            }
        }
    }

    @Test func searchMatchesLabelsAndTitles() {
        #expect(SettingsPane.home.match("week starts") == "Week starts on")
        #expect(SettingsPane.calendar.match("calendar") == "Calendar")
        #expect(SettingsPane.timer.match("zzz") == nil)
    }
}

/// Export and import round-trip, and import ignores keys and types Nook doesn't know.
struct SettingsFileTests {
    @Test func importSkipsUnknownKeysAndWrongTypes() throws {
        let json = #"{"nook":1,"settings":{"notARealSetting":true,"homeColumns":"three"}}"#
        #expect(try SettingsFile.apply(Data(json.utf8)) == 0)
    }

    @Test func notASettingsFileThrows() {
        #expect(throws: (any Error).self) { try SettingsFile.apply(Data("[1,2]".utf8)) }
    }
}
