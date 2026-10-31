import AppKit
import IOKit

/// The trackpad's own actuator, through MultitouchSupport. It's a private framework, used here because
/// it's the only way to make a tap land harder than macOS's public haptic patterns allow. It's loaded
/// when first needed; if it's missing or refuses, `tap` returns false and Haptics plays a public pattern.
enum TrackpadActuator {
    private typealias Create = @convention(c) (UInt64) -> Unmanaged<CFTypeRef>?
    private typealias Open = @convention(c) (CFTypeRef) -> Int32
    private typealias Actuate = @convention(c) (CFTypeRef, Int32, UInt32, Float, Float) -> Int32

    private struct Functions {
        let create: Create
        let open: Open
        let actuate: Actuate
    }

    private static let functions: Functions? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW),
              let create = dlsym(handle, "MTActuatorCreateFromDeviceID"),
              let open = dlsym(handle, "MTActuatorOpen"),
              let actuate = dlsym(handle, "MTActuatorActuate")
        else { return nil }
        return Functions(create: unsafeBitCast(create, to: Create.self),
                         open: unsafeBitCast(open, to: Open.self),
                         actuate: unsafeBitCast(actuate, to: Actuate.self))
    }()

    /// Every trackpad that can tap back (the built-in one, a Magic Trackpad), opened once.
    private static var actuators: [CFTypeRef] = []

    /// Taps every trackpad with one of its actuations: 3 is Nook's Medium, 4 its Strong (picked by feel).
    /// Opens them again once if none took it, after sleep or with a trackpad plugged in since.
    static func tap(_ actuation: Int32) -> Bool {
        guard let functions else { return false }
        for attempt in 0..<2 {
            if actuators.isEmpty || attempt > 0 { actuators = openAll(functions) }
            // Every one, not just the first that takes it: the finger may be on either.
            let taken = actuators.map { functions.actuate($0, actuation, 0, 0, 0) == 0 }
            if taken.contains(true) { return true }
        }
        return false
    }

    private static func openAll(_ functions: Functions) -> [CFTypeRef] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleMultitouchDevice"), &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var opened: [CFTypeRef] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            func property(_ key: String) -> Any? {
                IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
            }
            guard (property("ActuationSupported") as? Bool) == true,
                  let id = (property("Multitouch ID") as? NSNumber)?.uint64Value,
                  let actuator = functions.create(id)?.takeRetainedValue(),
                  functions.open(actuator) == 0
            else { continue }
            opened.append(actuator)
        }
        return opened
    }
}
