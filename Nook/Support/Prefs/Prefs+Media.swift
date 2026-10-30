import Foundation

extension Prefs {
    static let nowPlaying = "nowPlaying"
    static let peekOnTrackChange = "peekOnTrackChange"
    static let peekOnHover = "peekOnHover"
    static let showWaveform = "showWaveform"
    static let tintWaveform = "tintWaveform"
    static let artworkFlip = "artworkFlip"

    static var mediaArea: PrefsArea {
        PrefsArea(id: "media", defaults: [
            nowPlaying: true,
            peekOnTrackChange: true,
            peekOnHover: true,
            showWaveform: true,
            tintWaveform: true,
            artworkFlip: true,
        ])
    }
}
