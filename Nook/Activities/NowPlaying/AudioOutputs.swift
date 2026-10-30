import AppKit
import CoreAudio
import SwiftUI

/// The Mac's sound outputs, for the Music module's output button: which one plays now, and a menu
/// to move the sound to another, as Control Center's Sound menu does.
@Observable
final class AudioOutputs {
    struct Output: Equatable {
        let id: AudioObjectID
        let name: String
        /// The headphones' own glyph (AirPods, Beats…), or nil for speakers and displays.
        let headphones: String?
    }

    private(set) var current: Output?

    /// The headphones' glyph when they're the output; otherwise AirPlay's, which Apple's music card uses.
    var symbol: String { current?.headphones ?? "airplayaudio" }
    var currentName: String { current?.name ?? "Output" }

    init() {
        current = Self.output(Self.defaultOutput())
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.current = Self.output(Self.defaultOutput()) }
        }
    }

    /// Every device that plays sound, in the system's order.
    func all() -> [Output] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.filter(Self.playsSound).compactMap(Self.output)
    }

    func select(_ output: Output) {
        var id = output.id
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, UInt32(MemoryLayout<AudioObjectID>.size), &id)
    }

    /// Pops the outputs up under the pointer. The menu runs its own loop, so the island is held open
    /// until it closes, even if the pointer leaves the island to reach an item.
    func showMenu(holding model: NotchModel) {
        let menu = NSMenu()
        let outputs = all()
        for output in outputs {
            let item = MenuAction.item(output.name) { [weak self] in self?.select(output) }
            item.state = output.id == current?.id ? .on : .off
            let symbol = output.headphones ?? (Self.isBuiltIn(output.id) ? "laptopcomputer" : "speaker.wave.2")
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            menu.addItem(item)
        }
        if outputs.isEmpty { menu.addItem(withTitle: "No outputs", action: nil, keyEquivalent: "") }
        menu.addItem(.separator())
        menu.addItem(MenuAction.item("Sound Settings…") {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")!)
        })
        model.holdsOpen = true
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        model.holdsOpen = false
    }

    // MARK: CoreAudio

    private static func defaultOutput() -> AudioObjectID {
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
        return id
    }

    private static func output(_ id: AudioObjectID) -> Output? {
        guard id != kAudioObjectUnknown, let name = string(id, kAudioObjectPropertyName) else { return nil }
        let transport = uint32(id, kAudioDevicePropertyTransportType)
        let bluetooth = transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
        let headphones = bluetooth
            ? HeadphoneSymbol.symbol(productID: HeadphoneSymbol.productID(modelUID: string(id, kAudioDevicePropertyModelUID)), name: name)
            : nil
        return Output(id: id, name: name, headphones: headphones)
    }

    private static func isBuiltIn(_ id: AudioObjectID) -> Bool {
        uint32(id, kAudioDevicePropertyTransportType) == kAudioDeviceTransportTypeBuiltIn
    }

    /// Has output streams, and isn't a hidden aggregate some apps create for themselves.
    private static func playsSound(_ id: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                                 mScope: kAudioDevicePropertyScopeOutput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return false }
        return uint32(id, kAudioDevicePropertyIsHidden) == 0
    }

    private static func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    private static func uint32(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32 {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value)
        return value
    }
}

/// A menu item that runs a closure, for menus built in code.
final class MenuAction: NSObject {
    private let run: () -> Void

    private init(_ run: @escaping () -> Void) {
        self.run = run
    }

    @objc private func fire() { run() }

    static func item(_ title: String, _ run: @escaping () -> Void) -> NSMenuItem {
        let action = MenuAction(run)
        let item = NSMenuItem(title: title, action: #selector(fire), keyEquivalent: "")
        item.target = action
        // The item holds its target weakly; keep the action alive with it.
        item.representedObject = action
        return item
    }
}
