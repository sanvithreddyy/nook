import Foundation

/// One ring in the Batteries module.
struct DeviceBattery: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let symbol: String
    let level: Int
    var isCharging = false
    var isLowPower = false
}

/// What the Batteries module shows: this Mac's battery, then Bluetooth devices that report a level
/// (AirPods and their case, Magic Keyboard, Mouse and Trackpad, other headphones). Bluetooth levels
/// come from system_profiler, which takes well under a second; they're read when the island opens and
/// when a device connects, not on a timer. iPhone and Apple Watch levels aren't available to apps.
@Observable
final class DeviceBatteries {
    private(set) var devices: [DeviceBattery] = []

    @ObservationIgnored private var mac: DeviceBattery?
    @ObservationIgnored private var bluetooth: [DeviceBattery] = []
    @ObservationIgnored private var lastRead: Date?
    @ObservationIgnored private var reading = false

    /// This Mac's battery changed (level, charger, Low Power Mode).
    func updateMac(_ reading: BatteryMonitor.Reading?, lowPower: Bool) {
        mac = reading.map {
            DeviceBattery(id: "mac", name: Self.macName, symbol: "laptopcomputer", level: $0.level,
                          isCharging: $0.isCharging || $0.onAC, isLowPower: lowPower)
        }
        publish()
    }

    /// Reads Bluetooth levels again, unless they were read a moment ago.
    func refresh(force: Bool = false) {
        guard !reading else { return }
        if !force, let lastRead, Date.now.timeIntervalSince(lastRead) < 10 { return }
        reading = true
        Task { [weak self] in
            let found = await Self.readBluetooth()
            guard let self else { return }
            self.reading = false
            self.lastRead = .now
            self.bluetooth = found
            self.publish()
        }
    }

    func publish() {
        var all: [DeviceBattery] = []
        if Prefs.bool(Prefs.batteriesIncludeMac), let mac { all.append(mac) }
        all += bluetooth
        let shown = Array(all.prefix(HomeMetrics.maxBatteries))
        if shown != devices { devices = shown }
    }

    #if DEBUG
    /// A Mac, charging AirPods and their case, as Apple's own widget shows them; `-preview-batteries-full`
    /// adds a low mouse for a full row.
    func debugPreview() {
        mac = DeviceBattery(id: "mac", name: "Mac", symbol: "laptopcomputer", level: 80)
        bluetooth = [
            DeviceBattery(id: "pods", name: "AirPods Pro", symbol: "airpods.pro", level: 100, isCharging: true),
            DeviceBattery(id: "case", name: "Case", symbol: "airpods.pro.chargingcase.wireless.fill", level: 51),
        ]
        if CommandLine.arguments.contains("-preview-batteries-full") {
            bluetooth.append(DeviceBattery(id: "mouse", name: "Mouse", symbol: "magicmouse.fill", level: 18))
        }
        lastRead = .distantFuture
        publish()
    }
    #endif

    // MARK: Reading

    /// "…'s MacBook Pro" → "MacBook Pro": the owner's name doesn't fit under a ring.
    nonisolated static func shortName(_ name: String) -> String {
        guard let range = name.range(of: #"^.+?['’]s\s+"#, options: .regularExpression) else { return name }
        let rest = String(name[range.upperBound...])
        return rest.isEmpty ? name : rest
    }

    private static let macName = shortName(Host.current().localizedName ?? "Mac")

    nonisolated private static func readBluetooth() async -> [DeviceBattery] {
        await Task.detached(priority: .utility) { () -> [DeviceBattery] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            process.arguments = ["SPBluetoothDataType", "-json"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return [] }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return parse(data)
        }.value
    }

    /// Connected devices with a level. AirPods report each bud and the case: the buds show as one
    /// ring at the lower bud's level, the case as its own, as the Batteries widget does.
    nonisolated static func parse(_ data: Data) -> [DeviceBattery] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sections = root["SPBluetoothDataType"] as? [[String: Any]]
        else { return [] }
        var found: [(rank: Int, battery: DeviceBattery)] = []
        for section in sections {
            for list in (section["device_connected"] as? [[String: Any]]) ?? [] {
                for (fullName, value) in list {
                    guard let props = value as? [String: Any] else { continue }
                    func level(_ key: String) -> Int? {
                        (props[key] as? String).flatMap { Int($0.replacingOccurrences(of: "%", with: "")) }
                    }
                    let name = shortName(fullName)
                    let address = props["device_address"] as? String ?? fullName
                    let minor = (props["device_minorType"] as? String ?? "").lowercased()
                    let buds = [level("device_batteryLevelLeft"), level("device_batteryLevelRight")].compactMap { $0 }
                    let productID = (props["device_productID"] as? String).flatMap { Int($0.replacingOccurrences(of: "0x", with: ""), radix: 16) }
                    if let main = level("device_batteryLevelMain") ?? buds.min() {
                        let symbol: String
                        let rank: Int
                        // Connected AirPods can come without a type; their buds' levels give them away.
                        let isHeadphones = minor == "headphones" || minor == "headset" || !buds.isEmpty
                            || HeadphoneSymbol.symbol(productID: productID, name: fullName) != nil
                        switch isHeadphones ? "headphones" : minor {
                        case "headphones":
                            symbol = HeadphoneSymbol.symbol(productID: productID, name: fullName) ?? "headphones"
                            rank = 0
                        case "keyboard":
                            symbol = "keyboard.fill"
                            rank = 2
                        case "mouse":
                            symbol = "magicmouse.fill"
                            rank = 3
                        case "trackpad":
                            symbol = "hand.point.up.left"
                            rank = 4
                        default:
                            symbol = "dot.radiowaves.left.and.right"
                            rank = 5
                        }
                        found.append((rank, DeviceBattery(id: address, name: name, symbol: symbol, level: main)))
                    }
                    if let level = level("device_batteryLevelCase") {
                        // Filled, as the Batteries widget draws the case.
                        let caseSymbol = name.lowercased().contains("pro") ? "airpods.pro.chargingcase.wireless.fill" : "airpods.chargingcase.wireless.fill"
                        found.append((1, DeviceBattery(id: address + "-case", name: "Case", symbol: caseSymbol, level: level)))
                    }
                }
            }
        }
        return found.sorted { $0.rank < $1.rank }.map(\.battery)
    }
}
