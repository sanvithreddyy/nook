import AppKit

/// The SF Symbol for a pair of headphones: by Apple product ID where CoreAudio reports one (so
/// renamed AirPods still get the right picture), then by name. Symbols newer than this macOS fall
/// back to the nearest one that exists.
nonisolated enum HeadphoneSymbol {
    /// Apple Bluetooth product IDs, from the model UID CoreAudio reports ("2024 4c").
    private static let byProduct: [Int: [String]] = [
        0x2002: ["airpods"], 0x200F: ["airpods"],
        0x2013: ["airpods.gen3", "airpods"],
        0x2019: ["airpods.gen4", "airpods.gen3", "airpods"], 0x201B: ["airpods.gen4", "airpods.gen3", "airpods"],
        // Pro and Pro 2 share a shape, which macOS draws as gen1 since Pro 3 took "airpods.pro".
        0x200E: ["airpods.pro.gen1", "airpods.pro"], 0x2014: ["airpods.pro.gen1", "airpods.pro"], 0x2024: ["airpods.pro.gen1", "airpods.pro"],
        0x2027: ["airpods.pro.gen3", "airpods.pro"],
        0x200A: ["airpods.max"], 0x201F: ["airpods.max"],
    ]

    /// Nil for Bluetooth outputs that aren't recognisably headphones (speakers, car stereos), which
    /// keep the speaker.
    static func symbol(productID: Int?, name: String) -> String? {
        if let productID, let candidates = byProduct[productID] { return firstAvailable(candidates) }
        let name = name.lowercased()
        if name.contains("airpods max") { return "airpods.max" }
        if name.contains("airpods pro") { return "airpods.pro" }
        if name.contains("airpods") { return "airpods" }
        if name.contains("beats") { return "beats.headphones" }
        if name.contains("headphone") || name.contains("buds") { return "headphones" }
        return nil
    }

    /// A pair's single buds and its case, as the Batteries widget draws them; the pair itself for buds
    /// without a glyph of their own.
    static func parts(of pair: String) -> (left: String, right: String, case: String) {
        let names: [String] = switch pair {
        case "airpods": ["airpod.left", "airpod.right", "airpods.chargingcase.wireless.fill"]
        case "airpods.gen3": ["airpod.gen3.left", "airpod.gen3.right", "airpods.gen3.chargingcase.wireless.fill"]
        default: [pair + ".left", pair + ".right", pair + ".chargingcase.wireless.fill"]
        }
        return (available(names[0]) ?? pair, available(names[1]) ?? pair,
                available(names[2]) ?? "airpods.chargingcase.wireless.fill")
    }

    /// "2024 4c" → 0x2024.
    static func productID(modelUID: String?) -> Int? {
        guard let first = modelUID?.split(separator: " ").first else { return nil }
        return Int(first, radix: 16)
    }

    private static func firstAvailable(_ names: [String]) -> String {
        names.lazy.compactMap(available).first ?? "headphones"
    }

    private static func available(_ name: String) -> String? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil ? name : nil
    }
}
