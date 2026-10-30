import AppKit

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
            DeviceBattery(id: "mac", name: Self.macName, symbol: Self.macSymbol, level: $0.level,
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
    /// A Mac and AirPods Pro listed as macOS lists them, twice; `-preview-batteries-full` adds a low
    /// mouse for a full row.
    func debugPreview() {
        mac = DeviceBattery(id: "mac", name: "Mac", symbol: Self.macSymbol, level: 80, isCharging: true)
        bluetooth = Self.parse(Data(Self.sampleListing.utf8))
        if CommandLine.arguments.contains("-preview-batteries-full") {
            bluetooth.append(DeviceBattery(id: "mouse", name: "Mouse", symbol: "magicmouse.fill", level: 18))
        }
        lastRead = .distantFuture
        publish()
    }

    /// system_profiler's listing of one pair of AirPods Pro, the short second listing included.
    static let sampleListing = """
        {"SPBluetoothDataType": [{"device_connected": [
          {"AirPods Pro": {"device_address": "00:00:00:00:00:01", "device_batteryLevelCase": "51%",
                           "device_batteryLevelLeft": "100%"}},
          {"AirPods Pro": {"device_address": "00:00:00:00:00:02", "device_batteryLevelCase": "51%",
                           "device_batteryLevelLeft": "100%", "device_batteryLevelRight": "76%",
                           "device_minorType": "Headphones", "device_productID": "0x2024"}}
        ]}]}
        """
    #endif

    // MARK: Reading

    /// "…'s MacBook Pro" → "MacBook Pro": the owner's name doesn't fit under a ring.
    nonisolated static func shortName(_ name: String) -> String {
        guard let range = name.range(of: #"^.+?['’]s\s+"#, options: .regularExpression) else { return name }
        let rest = String(name[range.upperBound...])
        return rest.isEmpty ? name : rest
    }

    private static let macName = shortName(Host.current().localizedName ?? "Mac")

    /// The laptop with a notch, as the widget draws a MacBook that has one.
    private static var macSymbol: String {
        NSScreen.screens.contains { $0.safeAreaInsets.top > 0 } ? "macbook" : "laptopcomputer"
    }

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

    /// Connected devices with a level. AirPods report each bud and the case. As the Batteries widget
    /// does, buds at the same level share one ring and buds that differ get one each, left then right;
    /// the case gets its own.
    nonisolated static func parse(_ data: Data) -> [DeviceBattery] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sections = root["SPBluetoothDataType"] as? [[String: Any]]
        else { return [] }
        // macOS can list one pair of AirPods twice, the second time with only some of its levels:
        // one device per name, the fuller listing winning where the two disagree.
        var listed: [(name: String, props: [String: Any])] = []
        for section in sections {
            for list in (section["device_connected"] as? [[String: Any]]) ?? [] {
                for (fullName, value) in list {
                    guard let props = value as? [String: Any] else { continue }
                    if let i = listed.firstIndex(where: { $0.name == fullName }) {
                        let fuller = props.count > listed[i].props.count
                        listed[i].props.merge(props) { old, new in fuller ? new : old }
                    } else {
                        listed.append((fullName, props))
                    }
                }
            }
        }
        var found: [(rank: Int, battery: DeviceBattery)] = []
        for (fullName, props) in listed {
            func level(_ key: String) -> Int? {
                (props[key] as? String).flatMap { Int($0.replacingOccurrences(of: "%", with: "")) }
            }
            let name = shortName(fullName)
            let address = props["device_address"] as? String ?? fullName
            let minor = (props["device_minorType"] as? String ?? "").lowercased()
            let left = level("device_batteryLevelLeft"), right = level("device_batteryLevelRight")
            let productID = (props["device_productID"] as? String).flatMap { Int($0.replacingOccurrences(of: "0x", with: ""), radix: 16) }
            let pair = HeadphoneSymbol.symbol(productID: productID, name: fullName)
            // Connected AirPods can come without a type; their buds' levels give them away.
            let isHeadphones = minor == "headphones" || minor == "headset" || left != nil || right != nil || pair != nil
            if isHeadphones {
                let pair = pair ?? "headphones"
                let parts = HeadphoneSymbol.parts(of: pair)
                if let main = level("device_batteryLevelMain") ?? (left == right ? left : nil) {
                    found.append((0, DeviceBattery(id: address, name: name, symbol: pair, level: main)))
                } else {
                    if let left {
                        found.append((0, DeviceBattery(id: address + "-left", name: name + " Left", symbol: parts.left, level: left)))
                    }
                    if let right {
                        found.append((0, DeviceBattery(id: address + "-right", name: name + " Right", symbol: parts.right, level: right)))
                    }
                }
                if let level = level("device_batteryLevelCase") {
                    found.append((1, DeviceBattery(id: address + "-case", name: name + " Case", symbol: parts.case, level: level)))
                }
            } else if let main = level("device_batteryLevelMain") {
                let (rank, symbol): (Int, String) = switch minor {
                case "keyboard": (2, "keyboard.fill")
                case "mouse": (3, "magicmouse.fill")
                case "trackpad": (4, "hand.point.up.left")
                default: (5, "dot.radiowaves.left.and.right")
                }
                found.append((rank, DeviceBattery(id: address, name: name, symbol: symbol, level: main)))
            }
        }
        return found.sorted { $0.rank < $1.rank }.map(\.battery)
    }
}
