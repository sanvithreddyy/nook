import AppKit
import Carbon.HIToolbox

/// Shortcuts that work from any app, through the system hotkey API: no Accessibility access, and the
/// key never reaches the app in front.
final class HotKeys {
    var onPress: ((ShortcutAction) -> Void)?

    private var registered: [EventHotKeyRef] = []
    private var actions: [UInt32: ShortcutAction] = [:]
    private var handler: EventHandlerRef?
    private var current: [ShortcutAction: Shortcut] = [:]

    /// Registers what Settings has, when it changed since last time.
    func update() {
        var wanted: [ShortcutAction: Shortcut] = [:]
        for action in ShortcutAction.allCases {
            if let shortcut = Shortcut.saved(action) { wanted[action] = shortcut }
        }
        guard wanted != current else { return }
        current = wanted
        unregisterAll()
        guard !wanted.isEmpty else { return }
        installHandler()
        for (index, action) in ShortcutAction.allCases.enumerated() {
            guard let shortcut = wanted[action] else { continue }
            let id = UInt32(index + 1)
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, EventHotKeyID(signature: Self.signature, id: id),
                                             GetApplicationEventTarget(), 0, &ref)
            // Taken by another app or the system: that shortcut just doesn't fire.
            guard status == noErr, let ref else { continue }
            registered.append(ref)
            actions[id] = action
        }
    }

    private func unregisterAll() {
        registered.forEach { UnregisterEventHotKey($0) }
        registered = []
        actions = [:]
    }

    private func installHandler() {
        guard handler == nil else { return }
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &id)
            let keys = Unmanaged<HotKeys>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated {
                if let action = keys.actions[id.id] { keys.onPress?(action) }
            }
            return noErr
        }, 1, &type, me, &handler)
    }

    /// "NOOK".
    private static let signature: OSType = 0x4E4F_4F4B
}

extension Shortcut {
    /// The shortcut a key press makes, or nil for keys that can't stand alone: a plain letter would
    /// stop that letter from typing anywhere, so a modifier is needed except for function keys.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let isFunctionKey = Self.functionKeys[event.keyCode] != nil
        guard isFunctionKey || !flags.intersection([.command, .option, .control]).isEmpty else { return nil }
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        var label = ""
        if flags.contains(.control) { label += "⌃" }
        if flags.contains(.option) { label += "⌥" }
        if flags.contains(.shift) { label += "⇧" }
        if flags.contains(.command) { label += "⌘" }
        let key = Self.functionKeys[event.keyCode] ?? Self.namedKeys[event.keyCode]
            ?? event.charactersIgnoringModifiers?.uppercased() ?? ""
        guard !key.isEmpty else { return nil }
        self.init(keyCode: UInt32(event.keyCode), modifiers: carbon, label: label + key)
    }

    private static let functionKeys: [UInt16: String] = [
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
    ]

    private static let namedKeys: [UInt16: String] = [
        49: "Space", 36: "↩", 48: "⇥", 51: "⌫", 117: "⌦", 123: "←", 124: "→", 125: "↓", 126: "↑",
        115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
    ]
}
