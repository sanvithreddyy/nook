import Foundation

extension Prefs {
    static let nowPlaying = "nowPlaying"
    static let peekOnTrackChange = "peekOnTrackChange"
    static let peekOnHover = "peekOnHover"
    static let showWaveform = "showWaveform"
    static let tintWaveform = "tintWaveform"
    /// The Music module's favourite star (shown only for players that take favourites) and output button.
    static let musicFavorite = "musicFavorite"
    static let musicOutput = "musicOutput"

    static var mediaArea: PrefsArea {
        PrefsArea(id: "media", defaults: [
            nowPlaying: true,
            peekOnTrackChange: true,
            peekOnHover: true,
            showWaveform: true,
            tintWaveform: true,
            musicFavorite: true,
            musicOutput: true,
        ])
    }
}
