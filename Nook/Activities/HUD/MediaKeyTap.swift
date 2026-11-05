import AppKit
import ApplicationServices

/// Intercepts only the volume, mute and brightness keys (system-defined aux-control events) so
/// Nook can draw its own HUD instead of the system one. All other input passes through untouched;
/// nothing is recorded. Needs Accessibility access.
final class MediaKeyTap {
    enum Key: Int {
        case volumeUp = 0
        case volumeDown = 1
        case brightnessUp = 2
        case brightnessDown = 3
        case mute = 7
    }

    /// Which keys to swallow; others are passed to the system.
    var handles: (Key) -> Bool = { _ in false }
    /// Called on key down (and auto-repeat) for a handled key. `fine` is Option-Shift.
    var onKey: ((Key, _ fine: Bool) -> Void)?
    /// Called after the tap was dropped because Accessibility access went away.
    var onRevoked: (() -> Void)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    /// Keys whose current press Nook took. A press goes wholly to Nook or wholly to macOS: if macOS
    /// sees a key go down and never come up, it treats the key as held and keeps repeating it.
    private var owned: Set<Key> = []

    var isRunning: Bool { tap != nil }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestTrust() {
        // The value of kAXTrustedCheckOptionPrompt; the imported global is not concurrency-safe.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    @discardableResult
    func start() -> Bool {
        if let tap {
            if CGEvent.tapIsEnabled(tap: tap) { return true }
            stop()
        }
        guard Self.isTrusted else { return false }
        let mask = CGEventMask(1 << 14) // NSEvent.EventType.systemDefined
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .defaultTap,
                                          eventsOfInterest: mask,
                                          callback: mediaKeyCallback,
                                          userInfo: refcon)
        else { return false }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        owned.removeAll()
    }

    fileprivate static func instance(at address: UInt) -> MediaKeyTap? {
        UnsafeRawPointer(bitPattern: address).map { Unmanaged<MediaKeyTap>.fromOpaque($0).takeUnretainedValue() }
    }

    /// macOS switched the tap off for a while. Keys went straight to macOS meanwhile, so a release
    /// that arrives now may belong to a press macOS saw go down.
    func tapWasDisabled() {
        owned.removeAll()
        // Re-enabling after Accessibility was revoked would fight the system; drop the tap instead.
        guard Self.isTrusted else {
            stop()
            onRevoked?()
            return
        }
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    /// Returns true when the event should be swallowed. A press is decided on its first down, and
    /// its repeats and release follow that decision whatever changed meanwhile (the screen
    /// unlocked, the island opened, a setting changed).
    func handle(_ event: MediaKeyEvent) -> Bool {
        guard let key = Key(rawValue: event.code) else { return false }
        if event.isDown, !event.isRepeat {
            // Option alone with these keys opens Sound or Displays settings; leave that to macOS.
            if !event.isOptionOnly, handles(key) { owned.insert(key) } else { owned.remove(key) }
        }
        guard owned.contains(key) else { return false }
        if event.isDown { onKey?(key, event.isFine) } else { owned.remove(key) }
        // Swallow both down and up so the system HUD never appears.
        return true
    }
}

/// The parts of an aux-control key event Nook needs, decoded on the tap thread.
nonisolated struct MediaKeyEvent: Sendable {
    let code: Int
    let isDown: Bool
    /// A down sent while the key is held, after the first.
    let isRepeat: Bool
    let isFine: Bool
    let isOptionOnly: Bool

    init?(_ event: CGEvent) {
        guard let nsEvent = NSEvent(cgEvent: event),
              nsEvent.type == .systemDefined,
              nsEvent.subtype.rawValue == 8 // NX_SUBTYPE_AUX_CONTROL_BUTTONS
        else { return nil }
        // data1 is key << 16 | state << 8 | repeat.
        let data = nsEvent.data1
        code = (data & 0xFFFF_0000) >> 16
        isDown = (data & 0xFF00) >> 8 == 0xA // 0xA down, 0xB up
        isRepeat = data & 0xFF != 0
        let flags = nsEvent.modifierFlags
        isFine = flags.contains(.option) && flags.contains(.shift)
        isOptionOnly = flags.contains(.option) && !flags.contains(.shift)
    }
}

nonisolated private func mediaKeyCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let address = UInt(bitPattern: refcon)
    // The tap's run loop source is on the main run loop, so this runs on the main thread.
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        MainActor.assumeIsolated { MediaKeyTap.instance(at: address)?.tapWasDisabled() }
        return Unmanaged.passUnretained(event)
    }
    guard let parsed = MediaKeyEvent(event) else { return Unmanaged.passUnretained(event) }
    let swallow = MainActor.assumeIsolated {
        MediaKeyTap.instance(at: address)?.handle(parsed) ?? false
    }
    return swallow ? nil : Unmanaged.passUnretained(event)
}
