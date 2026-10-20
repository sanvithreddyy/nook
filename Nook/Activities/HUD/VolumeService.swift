import CoreAudio
import AudioToolbox
import Foundation

/// Reads and sets the default output device's volume and mute through CoreAudio.
final class VolumeService {
    private var device: AudioObjectID = kAudioObjectUnknown

    init() {
        device = Self.defaultOutputDevice()
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.device = Self.defaultOutputDevice() }
        }
    }

    var volume: Float {
        get { read(kAudioHardwareServiceDeviceProperty_VirtualMainVolume) ?? 0 }
        set { write(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, min(max(newValue, 0), 1)) }
    }

    var isMuted: Bool {
        get { (readUInt32(kAudioDevicePropertyMute) ?? 0) != 0 }
        set { writeUInt32(kAudioDevicePropertyMute, newValue ? 1 : 0) }
    }

    /// Steps like the system: 1/16 per press, 1/64 with Option-Shift.
    func step(up: Bool, fine: Bool) -> (level: Float, muted: Bool) {
        let unit: Float = fine ? 1 / 64 : 1 / 16
        let current = volume
        let snapped = (current / unit).rounded() * unit
        let next = min(max(snapped + (up ? unit : -unit), 0), 1)
        volume = next
        if up, isMuted { isMuted = false }
        return (volume, isMuted)
    }

    func toggleMute() -> (level: Float, muted: Bool) {
        isMuted.toggle()
        return (volume, isMuted)
    }

    // MARK: CoreAudio

    private static func defaultOutputDevice() -> AudioObjectID {
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
        return id
    }

    private func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    }

    private func read(_ selector: AudioObjectPropertySelector) -> Float? {
        var address = address(selector)
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    private func write(_ selector: AudioObjectPropertySelector, _ value: Float) {
        var address = address(selector)
        guard AudioObjectHasProperty(device, &address) else { return }
        var value = Float32(value)
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
    }

    private func readUInt32(_ selector: AudioObjectPropertySelector) -> UInt32? {
        var address = address(selector)
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    private func writeUInt32(_ selector: AudioObjectPropertySelector, _ value: UInt32) {
        var address = address(selector)
        guard AudioObjectHasProperty(device, &address) else { return }
        var value = value
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }
}
