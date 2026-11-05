import Foundation

extension Prefs {
    /// Convert shows beside AirDrop on the shelf while a file is dragged.
    static let convert = "convert"
    /// Converted files go to Downloads rather than next to the original.
    static let convertToDownloads = "convertToDownloads"
    /// The original stays where it is; off, it goes to the Trash once converted.
    static let convertKeepOriginal = "convertKeepOriginal"
    /// JPEG, HEIC and AVIF quality: "high", "balanced" or "smaller".
    static let convertPhotoQuality = "convertPhotoQuality"
    /// AAC bit rate in kbps.
    static let convertAudioKbps = "convertAudioKbps"

    static var convertArea: PrefsArea {
        PrefsArea(id: "convert", defaults: [
            convert: true,
            convertToDownloads: false,
            convertKeepOriginal: true,
            convertPhotoQuality: "high",
            convertAudioKbps: 256,
        ])
    }

    /// The last format used for a kind of file, so it comes first next time. Not a setting, so it isn't
    /// in the area that Settings resets and exports.
    static func convertLastUsed(_ source: ConvertSource) -> ConvertTarget? {
        UserDefaults.standard.string(forKey: "convertLast.\(source.rawValue)").flatMap(ConvertTarget.init)
    }

    static func setConvertLastUsed(_ target: ConvertTarget, for source: ConvertSource) {
        UserDefaults.standard.set(target.rawValue, forKey: "convertLast.\(source.rawValue)")
    }
}
