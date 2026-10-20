import CoreGraphics
import Foundation

/// Built-in display brightness. macOS has no public API for it, so this uses the
/// DisplayServices functions every brightness utility relies on, resolved at runtime.
final class BrightnessService {
    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private let getBrightness: GetFn?
    private let setBrightness: SetFn?

    init() {
        let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
        getBrightness = handle.flatMap { dlsym($0, "DisplayServicesGetBrightness") }.map { unsafeBitCast($0, to: GetFn.self) }
        setBrightness = handle.flatMap { dlsym($0, "DisplayServicesSetBrightness") }.map { unsafeBitCast($0, to: SetFn.self) }
    }

    var isAvailable: Bool { getBrightness != nil && setBrightness != nil && builtInDisplay != nil }

    private var builtInDisplay: CGDirectDisplayID? {
        var count: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &count)
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetOnlineDisplayList(count, &displays, &count)
        return displays.first { CGDisplayIsBuiltin($0) != 0 }
    }

    var level: Float {
        guard let getBrightness, let display = builtInDisplay else { return 0 }
        var value: Float = 0
        _ = getBrightness(display, &value)
        return value
    }

    /// Steps like the system: 1/16 per press, 1/64 with Option-Shift. Returns the new level.
    func step(up: Bool, fine: Bool) -> Float {
        guard let setBrightness, let display = builtInDisplay else { return level }
        let unit: Float = fine ? 1 / 64 : 1 / 16
        let snapped = (level / unit).rounded() * unit
        let next = min(max(snapped + (up ? unit : -unit), 0), 1)
        _ = setBrightness(display, next)
        return next
    }
}
