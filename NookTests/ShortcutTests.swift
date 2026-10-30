import AppKit
import Testing

/// Shortcuts are stored as "keyCode,modifiers,label"; the label can hold a comma of its own.
struct ShortcutTests {
    @Test func storedShortcutReadsBack() {
        let shortcut = Shortcut(keyCode: 45, modifiers: 6144, label: "⌃⌥N")
        #expect(Shortcut(stored: shortcut.stored) == shortcut)
    }

    @Test func commaKeyKeepsItsLabel() {
        let shortcut = Shortcut(keyCode: 43, modifiers: 6144, label: "⌃⌥,")
        #expect(Shortcut(stored: shortcut.stored)?.label == "⌃⌥,")
    }

    @Test func emptyOrBrokenIsNone() {
        #expect(Shortcut(stored: "") == nil)
        #expect(Shortcut(stored: "x,1,A") == nil)
    }
}

/// A shortcut works in every app and wins over its menus, so it needs Control or Option.
@MainActor
struct ShortcutRuleTests {
    private func press(_ key: String, code: UInt16, _ flags: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
                         context: nil, characters: key, charactersIgnoringModifiers: key, isARepeat: false, keyCode: code)!
    }

    @Test func commandShortcutsStayWithTheApp() {
        #expect(Shortcut(event: press("w", code: 13, [.command])) == nil)
        #expect(Shortcut(event: press(",", code: 43, [.command])) == nil)
        #expect(Shortcut(event: press("q", code: 12, [.command, .shift])) == nil)
    }

    @Test func plainLettersStayTyping() {
        #expect(Shortcut(event: press("n", code: 45, [])) == nil)
    }

    @Test func controlOrOptionMakesAShortcut() {
        #expect(Shortcut(event: press("n", code: 45, [.control, .option]))?.label == "⌃⌥N")
        #expect(Shortcut(event: press("n", code: 45, [.command, .option]))?.label == "⌥⌘N")
    }

    @Test func functionKeysStandAlone() {
        #expect(Shortcut(event: press("", code: 113, []))?.label == "F15")
    }
}
