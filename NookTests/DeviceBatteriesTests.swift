import Foundation
import Testing

/// Bluetooth levels as system_profiler lists them, turned into the widget's rings.
struct DeviceBatteriesTests {
    private func rings(_ devices: String) -> [String] {
        let json = #"{"SPBluetoothDataType": [{"device_connected": [\#(devices)]}]}"#
        return DeviceBatteries.parse(Data(json.utf8)).map { "\($0.symbol) \($0.level)" }
    }

    private let fullListing = #"""
        {"AirPods Pro": {"device_address": "00:00:00:00:00:02", "device_batteryLevelCase": "51%",
                         "device_batteryLevelLeft": "100%", "device_batteryLevelRight": "76%",
                         "device_minorType": "Headphones", "device_productID": "0x2024"}}
        """#

    /// macOS lists a pair a second time with only some levels: still one left, one right, one case.
    @Test func aPairListedTwiceIsOneDevice() {
        let short = #"{"AirPods Pro": {"device_address": "00:00:00:00:00:01", "device_batteryLevelCase": "51%", "device_batteryLevelLeft": "100%"}}"#
        let expected = ["airpods.pro.left 100", "airpods.pro.right 76", "airpods.pro.chargingcase.wireless.fill 51"]
        #expect(rings(short + "," + fullListing) == expected)
        #expect(rings(fullListing + "," + short) == expected)
    }

    @Test func budsAtTheSameLevelShareARing() {
        let same = #"{"AirPods Pro": {"device_address": "a", "device_batteryLevelLeft": "90%", "device_batteryLevelRight": "90%", "device_productID": "0x2024"}}"#
        #expect(rings(same) == ["airpods.pro 90"])
    }

    /// The other bud is in its case: only the one out shows.
    @Test func oneBudOutShowsAlone() {
        let one = #"{"AirPods": {"device_address": "a", "device_batteryLevelRight": "40%", "device_productID": "0x200F"}}"#
        #expect(rings(one) == ["airpod.right 40"])
    }

    @Test func otherDevicesFollowHeadphonesAndCases() {
        let keyboard = #"{"Magic Keyboard": {"device_address": "k", "device_batteryLevelMain": "64%", "device_minorType": "Keyboard"}}"#
        #expect(rings(keyboard + "," + fullListing).first == "airpods.pro.left 100")
        #expect(rings(keyboard + "," + fullListing).last == "keyboard.fill 64")
    }
}
