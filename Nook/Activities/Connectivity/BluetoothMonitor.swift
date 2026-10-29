import Foundation
import IOBluetooth

/// Reports Bluetooth devices as they connect, with battery levels when macOS publishes them.
final class BluetoothMonitor: NSObject {
    nonisolated struct Device: Sendable {
        let name: String
        let symbol: String
        let address: String
    }

    var onConnect: ((Device) -> Void)?
    /// A battery level arrived for a device that connected a moment ago.
    var onBattery: ((Device, Int) -> Void)?

    private var connectNotification: IOBluetoothUserNotification?
    private var startedAt = Date()

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
        let info = Device(name: device.name ?? "Bluetooth device", symbol: Self.symbol(for: device), address: device.addressString ?? "")
        Task { @MainActor [weak self] in self?.connected(info) }
    }

    private func connected(_ info: Device) {
        // Registration replays devices that were already connected; only announce new connections.
        guard Date().timeIntervalSince(startedAt) > 3 else { return }
        onConnect?(info)
        fetchBattery(for: info)
    }

    /// AirPods report battery a beat after connecting; system_profiler is the public place it appears.
    private func fetchBattery(for device: Device) {
        guard !device.address.isEmpty else { return }
        Task { [weak self] in
            for delay in [1.5, 3.0] {
                try? await Task.sleep(for: .seconds(delay))
                if let level = await Self.batteryLevel(address: device.address) {
                    self?.onBattery?(device, level)
                    return
                }
            }
        }
    }

    nonisolated private static func batteryLevel(address: String) async -> Int? {
        await Task.detached(priority: .utility) { () -> Int? in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            process.arguments = ["SPBluetoothDataType", "-json"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return parseBattery(data, address: address)
        }.value
    }

    nonisolated private static func parseBattery(_ data: Data, address: String) -> Int? {
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
                    return levels.min()
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
