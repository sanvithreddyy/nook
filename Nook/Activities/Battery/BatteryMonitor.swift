import Foundation
import IOKit.ps

/// Internal battery state from IOKit power-source notifications.
final class BatteryMonitor {
    struct Reading: Equatable {
        var level: Int
        var onAC: Bool
        var isCharging: Bool
    }

    private(set) var reading: Reading?
    private(set) var isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

    var onPowerSourceChange: ((Reading) -> Void)?
    /// Every reading, and Low Power Mode, for the Batteries module.
    var onReadingChange: ((Reading?, Bool) -> Void)?
    var onLowBattery: ((Reading) -> Void)?
    var onLowPowerModeChange: ((Bool) -> Void)?

    private var source: CFRunLoopSource?
    private var powerStateObserver: NSObjectProtocol?
    private var warnedLow = false

    func start() {
        reading = Self.read()
        onReadingChange?(reading, isLowPowerMode)
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource(powerSourceCallback, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            self.source = source
        }
        powerStateObserver = NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.lowPowerModeChanged() }
        }
    }

    fileprivate func powerSourcesChanged() {
        guard let new = Self.read() else { return }
        let old = reading
        reading = new
        if new != old { onReadingChange?(new, isLowPowerMode) }
        guard let old else { return }
        if new.onAC != old.onAC {
            onPowerSourceChange?(new)
        }
        let threshold = Prefs.int(Prefs.lowBatteryThreshold)
        if !new.onAC, new.level <= threshold, !warnedLow {
            warnedLow = true
            onLowBattery?(new)
        } else if new.onAC || new.level > threshold {
            warnedLow = false
        }
    }

    private func lowPowerModeChanged() {
        let on = ProcessInfo.processInfo.isLowPowerModeEnabled
        guard on != isLowPowerMode else { return }
        isLowPowerMode = on
        onLowPowerModeChange?(on)
        onReadingChange?(reading, on)
    }

    private static func read() -> Reading? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }
        for source in list {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
            else { continue }
            let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = description[kIOPSMaxCapacityKey] as? Int ?? 100
            let state = description[kIOPSPowerSourceStateKey] as? String
            let charging = description[kIOPSIsChargingKey] as? Bool ?? false
            let level = max > 0 ? Int((Double(current) / Double(max) * 100).rounded()) : current
            return Reading(level: level, onAC: state == kIOPSACPowerValue, isCharging: charging)
        }
        return nil
    }
}

nonisolated private func powerSourceCallback(context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    let address = UInt(bitPattern: context)
    // Delivered on the main run loop, where the source was added.
    MainActor.assumeIsolated {
        guard let pointer = UnsafeRawPointer(bitPattern: address) else { return }
        Unmanaged<BatteryMonitor>.fromOpaque(pointer).takeUnretainedValue().powerSourcesChanged()
    }
}
