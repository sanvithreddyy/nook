import Testing

/// Shortcuts are stored as "keyCode,modifiers,label"; the label can hold a comma of its own.
struct ShortcutTests {
    @Test func storedShortcutReadsBack() {
        let shortcut = Shortcut(keyCode: 45, modifiers: 6144, label: "⌃⌥N")
        #expect(Shortcut(stored: shortcut.stored) == shortcut)
    }

    @Test func commaKeyKeepsItsLabel() {
        let shortcut = Shortcut(keyCode: 43, modifiers: 256, label: "⌘,")
        #expect(Shortcut(stored: shortcut.stored)?.label == "⌘,")
    }

    @Test func emptyOrBrokenIsNone() {
        #expect(Shortcut(stored: "") == nil)
        #expect(Shortcut(stored: "x,1,A") == nil)
    }
}
