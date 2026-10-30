import AppKit
import Carbon.HIToolbox

/// Shortcuts that work from any app, through the system hotkey API: no Accessibility access, and the
/// key never reaches the app in front. One for the app's lifetime, which the event handler relies on.
final class HotKeys {
    static let shared = HotKeys()
    var onPress: ((ShortcutAction) -> Void)?

    private var registered: [EventHotKeyRef] = []
    private var actions: [UInt32: ShortcutAction] = [:]
    private var handler: EventHandlerRef?
    private var current: [ShortcutAction: Shortcut] = [:]

    /// Off while Settings records a shortcut, so pressing one Nook already has records it instead of
    /// running it.
    var isSuspended = false {
        didSet {
            guard isSuspended != oldValue else { return }
            current = [:]
            unregisterAll()
            update()
        }
    }

    private init() {}

    /// Registers what Settings has, when it changed since last time.
    func update() {
        guard !isSuspended else { return }
        var wanted: [ShortcutAction: Shortcut] = [:]
        // One saved before the rule tightened, or edited by hand, isn't registered either.
        for action in ShortcutAction.allCases {
            if let shortcut = Shortcut.saved(action), shortcut.isAllowed { wanted[action] = shortcut }
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
    /// A shortcut here works in every app and wins over their menus, so it needs Control, or Option
    /// with Command: a plain letter or an Option letter (é is Option-E) would stop that character typing
    /// anywhere, and Command with a key (Close, Settings, Quit) belongs to the app in front. Function
    /// keys can stand alone.
    var isAllowed: Bool {
        Self.functionKeys[UInt16(keyCode)] != nil
            || modifiers & UInt32(controlKey) != 0
            || (modifiers & UInt32(optionKey) != 0 && modifiers & UInt32(cmdKey) != 0)
    }

    /// The shortcut a key press makes, or nil for one it shouldn't take (see `isAllowed`).
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
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
        // The key itself, as printed on it: Shift's own character (@ for 2) would mislabel ⌃⇧2.
        let key = Self.functionKeys[event.keyCode] ?? Self.namedKeys[event.keyCode]
            ?? (event.characters(byApplyingModifiers: []) ?? event.charactersIgnoringModifiers)?.uppercased() ?? ""
        guard !key.isEmpty else { return nil }
        self.init(keyCode: UInt32(event.keyCode), modifiers: carbon, label: label + key)
        guard isAllowed else { return nil }
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
