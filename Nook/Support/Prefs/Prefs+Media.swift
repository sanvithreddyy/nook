import Foundation

/// Apps that have played something, and the ones the island leaves out.
enum MediaSources {
    static var seen: [String] { list(Prefs.mediaSeenApps) }
    static var ignored: Set<String> { Set(list(Prefs.mediaIgnoredApps)) }

    /// Keeps the twelve most recent.
    static func remember(_ app: String) {
        let apps = seen
        guard !apps.contains(app) else { return }
        UserDefaults.standard.set((apps + [app]).suffix(12).joined(separator: ","), forKey: Prefs.mediaSeenApps)
    }

    static func setIgnored(_ app: String, _ ignore: Bool) {
        var apps = ignored
        if ignore { apps.insert(app) } else { apps.remove(app) }
        UserDefaults.standard.set(apps.sorted().joined(separator: ","), forKey: Prefs.mediaIgnoredApps)
    }

    private static func list(_ key: String) -> [String] {
        Prefs.string(key).split(separator: ",").map(String.init)
    }
}

extension Prefs {
    static let nowPlaying = "nowPlaying"
    static let peekOnTrackChange = "peekOnTrackChange"
    static let peekOnHover = "peekOnHover"
    static let showWaveform = "showWaveform"
    static let tintWaveform = "tintWaveform"
    static let artworkFlip = "artworkFlip"
    /// Seconds a paused player stays on the island; -1 keeps it until the player lets go of the track.
    static let pausedLinger = "pausedLinger"
    /// Seconds the title shows under the island when the track changes.
    static let peekDuration = "peekDuration"
    /// The player leaves the island while its own app is in front.
    static let hideWhenPlayerFront = "hideWhenPlayerFront"
    /// Apps the island leaves out, comma separated bundle identifiers.
    static let mediaIgnoredApps = "mediaIgnoredApps"
    /// Apps that have played something, for Settings to list. Not a setting, so Reset keeps it.
    static let mediaSeenApps = "mediaSeenApps"

    static var mediaArea: PrefsArea {
        PrefsArea(id: "media", defaults: [
            nowPlaying: true,
            peekOnTrackChange: true,
            peekOnHover: true,
            showWaveform: true,
            tintWaveform: true,
            artworkFlip: true,
            pausedLinger: 5,
            peekDuration: 3.0,
            hideWhenPlayerFront: false,
            mediaIgnoredApps: "",
        ])
    }
}
