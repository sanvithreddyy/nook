import Foundation
import IOBluetooth

/// Reports Bluetooth devices as they connect, once each, with the battery level when macOS publishes
/// one. AirPods report theirs a moment after connecting, so the report waits for it (up to 3 s), the way
/// Apple's own connection view arrives with the level already in its ring.
final class BluetoothMonitor: NSObject {
    nonisolated struct Device: Sendable {
        let name: String
        let symbol: String
        let address: String
    }

    var onConnect: ((Device, _ battery: Int?) -> Void)?
    /// When a device last connected, reported or not: sound moving to it is part of connecting.
    private(set) var lastConnection: Date?

    private var connectNotification: IOBluetoothUserNotification?
    private var startedAt = Date()
    /// Names reported in the last few seconds: AirPods connect over more than one link.
    private var recent: [String: Date] = [:]

    func start() {
        startedAt = Date()
        connectNotification = IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(deviceConnected(_:device:)))
    }

    func stop() {
        connectNotification?.unregister()
        connectNotification = nil
    }

    /// IOBluetooth calls this on its own queue; read the device there, then hop to main.
    @objc nonisolated private func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        let name = device.name ?? ""
        let info = Device(name: name, symbol: Self.symbol(for: device), address: device.addressString ?? "")
        Task { @MainActor [weak self] in self?.connected(info) }
    }

    private func connected(_ info: Device) {
        // Registration replays devices that were already connected; only announce new connections.
        guard Date().timeIntervalSince(startedAt) > 3 else { return }
        lastConnection = .now
        // A link without a name is a second link of something already connecting (AirPods open one
        // before their name arrives); it has nothing to show.
        guard !info.name.isEmpty else { return }
        if let at = recent[info.name], Date.now.timeIntervalSince(at) < 10 { return }
        recent = recent.filter { Date.now.timeIntervalSince($0.value) < 10 }
        recent[info.name] = .now
        Task { [weak self] in
            var listing: Listing?
            if !info.address.isEmpty {
                for delay in [0.3, 0.6, 0.9, 1.2] {
                    try? await Task.sleep(for: .seconds(delay))
                    listing = await Self.listing(address: info.address)
                    if listing?.level != nil { break }
                }
            }
            // macOS knows the exact model by now: the symbol Apple draws for it.
            let symbol = HeadphoneSymbol.symbol(productID: listing?.productID, name: info.name) ?? info.symbol
            self?.onConnect?(Device(name: info.name, symbol: symbol, address: info.address), listing?.level)
        }
    }

    nonisolated struct Listing: Sendable {
        var level: Int?
        var productID: Int?
    }

    /// What system_profiler, the public place AirPods' levels appear, lists for one device.
    nonisolated private static func listing(address: String) async -> Listing? {
        await Task.detached(priority: .utility) { () -> Listing? in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            process.arguments = ["SPBluetoothDataType", "-json"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return parseListing(data, address: address)
        }.value
    }

    nonisolated static func parseListing(_ data: Data, address: String) -> Listing? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sections = root["SPBluetoothDataType"] as? [[String: Any]]
        else { return nil }
        let wanted = address.lowercased().replacingOccurrences(of: "-", with: ":")
        for section in sections {
            for list in (section["device_connected"] as? [[String: Any]]) ?? [] {
                for (_, value) in list {
                    guard let props = value as? [String: Any],
                          (props["device_address"] as? String)?.lowercased().replacingOccurrences(of: "-", with: ":") == wanted
                    else { continue }
                    // AirPods report left/right/case; headphones and keyboards report one level.
                    let keys = ["device_batteryLevelMain", "device_batteryLevelLeft", "device_batteryLevelRight"]
                    let levels = keys.compactMap { (props[$0] as? String).flatMap { Int($0.replacingOccurrences(of: "%", with: "")) } }
                    let productID = (props["device_productID"] as? String).flatMap { Int($0.replacingOccurrences(of: "0x", with: ""), radix: 16) }
                    return Listing(level: levels.min(), productID: productID)
                }
            }
        }
        return nil
    }

    nonisolated private static func symbol(for device: IOBluetoothDevice) -> String {
        let name = device.name ?? ""
        if name.lowercased().contains("airpods") || name.lowercased().contains("beats"),
           let symbol = HeadphoneSymbol.symbol(productID: nil, name: name) {
            return symbol
        }
        // Major class 0x04 audio/video, 0x05 peripheral.
        switch device.deviceClassMajor {
        case 0x04: return "headphones"
        case 0x05:
            let minor = device.deviceClassMinor
            if minor & 0x10 != 0 { return "keyboard" }
            if minor & 0x20 != 0 { return "computermouse" }
            return "keyboard"
        case 0x02: return "iphone"
        default: return "dot.radiowaves.left.and.right"
        }
    }
}
