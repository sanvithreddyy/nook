import AppKit
import SwiftUI

@Observable
final class NowPlayingModel {
    private(set) var title = ""
    private(set) var artist = ""
    private(set) var album = ""
    private(set) var duration: Double = 0
    private(set) var isPlaying = false
    private(set) var playbackRate: Double = 0
    private(set) var bundleIdentifier: String? {
        didSet {
            guard bundleIdentifier != oldValue else { return }
            appIcon = Self.icon(for: bundleIdentifier)
            if let bundleIdentifier { MediaSources.remember(bundleIdentifier) }
            onSourceChange?()
        }
    }
    /// Apps Settings leaves out; what they play counts as nothing playing. Set by the coordinator.
    var ignoredApps: Set<String> = []
    /// Icon of the app that is playing, resolved once per app change.
    private(set) var appIcon: NSImage?
    private(set) var artwork: NSImage?
    /// Changes when the artwork itself changes (it decodes a moment after the track does), so views
    /// cross-fade to the new cover rather than the old one.
    private(set) var artworkToken = 0
    /// Average artwork color, lifted so it reads on black.
    private(set) var tint: Color = .white
    private(set) var isShuffled = false
    private(set) var repeatMode = 1
    /// The player takes favourites (Apple Music does; browsers don't), and whether this track is one.
    private(set) var canFavorite = false
    private(set) var isFavorite = false
    /// Changes whenever the track changes; drives the artwork flip and the quick peek.
    private(set) var trackID = ""

    /// Elapsed time at `elapsedTimestamp`; extrapolate with `elapsed(at:)`.
    private var elapsedAtTimestamp: Double = 0
    private var elapsedTimestamp = Date()

    @ObservationIgnored var onTrackChange: (() -> Void)?
    @ObservationIgnored var onPlaybackChange: (() -> Void)?
    /// The app that's playing changed, which can come a moment after its track.
    @ObservationIgnored var onSourceChange: (() -> Void)?
    @ObservationIgnored private let client = MediaRemoteClient()
    @ObservationIgnored private var state: [String: NowPlayingUpdate.Value] = [:]
    @ObservationIgnored private var artworkGeneration = 0

    var hasTrack: Bool { !title.isEmpty && !(bundleIdentifier.map(ignoredApps.contains) ?? false) }

    private static func icon(for bundleIdentifier: String?) -> NSImage? {
        guard let bundleIdentifier,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    func start() {
        client.onUpdate = { [weak self] update in self?.apply(update) }
        client.start()
    }

    func stop() { client.stop() }

    func elapsed(at date: Date) -> Double {
        guard duration > 0 else { return 0 }
        let rate = isPlaying ? (playbackRate > 0 ? playbackRate : 1) : 0
        let value = elapsedAtTimestamp + date.timeIntervalSince(elapsedTimestamp) * rate
        return min(max(value, 0), duration)
    }

    // MARK: Commands

    func togglePlayPause() {
        // Flip immediately; the stream confirms a moment later.
        setPlaying(!isPlaying)
        client.send(.togglePlayPause)
    }

    func next() { client.send(.nextTrack) }
    func previous() { client.send(.previousTrack) }

    /// MediaRemote has a command to favourite but none to take a favourite back, so a favourite
    /// stays until it's removed in the player.
    func favorite() {
        guard canFavorite, !isFavorite else { return }
        isFavorite = true
        client.send(.likeTrack)
    }

    func seek(to seconds: Double) {
        elapsedAtTimestamp = seconds
        elapsedTimestamp = Date()
        client.seek(to: seconds)
    }

    /// Back or forward from where the track is, within it.
    func skip(by seconds: Double) {
        guard duration > 0 else { return }
        seek(to: min(max(elapsed(at: .now) + seconds, 0), duration))
    }

    /// Off, all, one, off, as the player's own repeat button goes.
    func cycleRepeat() {
        setRepeat(repeatMode == 1 ? 3 : repeatMode == 3 ? 2 : 1)
    }

    func toggleShuffle() {
        isShuffled.toggle()
        client.setShuffle(isShuffled)
    }

    /// 1 off, 2 one, 3 all.
    func setRepeat(_ mode: Int) {
        repeatMode = mode
        client.setRepeat(mode)
    }

    #if DEBUG
    /// Shows the current (or a sample) track as playing without sending anything to the player.
    func previewPlaying() {
        client.onUpdate = nil
        // -preview-sample: the sample track even when something is playing; its title is long enough to scroll.
        if title.isEmpty || CommandLine.arguments.contains("-preview-sample") {
            title = "Golden Hour (B-Side) [Extended Mix]"
            artist = "Night Swim"
            duration = 241
            trackID = "preview"
            // A system wallpaper stands in for cover art.
            let sample = "/System/Library/Desktop Pictures/.thumbnails/Big Sur Night Grasses.heic"
            if let data = FileManager.default.contents(atPath: sample) { loadArtwork(data) }
        }
        elapsedAtTimestamp = duration * 0.3
        elapsedTimestamp = Date()
        isPlaying = true
        // As Apple Music reports it, so captures show the star.
        canFavorite = true
    }

    /// The next sample track by the same artist, to watch a track change.
    func debugNextTrack() {
        title = "Sometimes (Original Mix)"
        trackID = "preview-2"
        let sample = "/System/Library/Desktop Pictures/.thumbnails/Big Sur Coastline.heic"
        if let data = FileManager.default.contents(atPath: sample) { loadArtwork(data) }
        elapsedAtTimestamp = 0
        elapsedTimestamp = Date()
        onTrackChange?()
    }

    func previewPaused() {
        setPlaying(false)
    }

    func debugClear() {
        client.onUpdate = nil
        title = ""
        artist = ""
        artwork = nil
        artworkToken &+= 1
        isPlaying = false
    }
    #endif

    // MARK: Stream

    /// Applies one stream line. A diff only changes the fields it carries, so local changes made
    /// a moment ago (seek, shuffle, play/pause) survive unrelated updates until the player confirms.
    private func apply(_ update: NowPlayingUpdate) {
        let full = !update.isDiff
        if full { state.removeAll() }
        for (key, value) in update.values {
            if case .null = value { state.removeValue(forKey: key) } else { state[key] = value }
        }
        func carries(_ keys: String...) -> Bool { full || keys.contains { update.values[$0] != nil } }

        var trackChanged = false
        if carries("title", "artist", "album") {
            title = string("title")
            artist = string("artist")
            album = string("album")
            let newID = [title, artist, album].joined(separator: "\u{1F}")
            trackChanged = newID != trackID
            if trackChanged { trackID = newID }
        }
        if carries("durationMicros") { duration = micros("durationMicros") ?? 0 }
        if carries("playbackRate") { playbackRate = number("playbackRate") ?? 0 }
        if carries("parentApplicationBundleIdentifier", "bundleIdentifier") {
            bundleIdentifier = string("parentApplicationBundleIdentifier").nilIfEmpty ?? string("bundleIdentifier").nilIfEmpty
        }
        if carries("shuffleMode"), let shuffle = number("shuffleMode") { isShuffled = shuffle != 1 }
        if carries("repeatMode"), let mode = number("repeatMode") { repeatMode = Int(mode) }
        if carries("supportsIsLiked") { canFavorite = bool("supportsIsLiked") ?? false }
        if carries("isLiked") { isFavorite = bool("isLiked") ?? false }

        // A restart (Previous, repeat-one) leaves elapsed at 0 → 0, so its diff carries only a new timestamp.
        let carriesElapsed = carries("elapsedTimeMicros", "timestampEpochMicros") && micros("elapsedTimeMicros") != nil
        if carriesElapsed, let elapsed = micros("elapsedTimeMicros") {
            elapsedAtTimestamp = elapsed
            elapsedTimestamp = micros("timestampEpochMicros").map { Date(timeIntervalSince1970: $0) } ?? Date()
        }

        if let data = update.artwork {
            loadArtwork(data)
        } else if carries("artworkData"), state["artworkData"] == nil, artwork != nil {
            artworkGeneration += 1
            artwork = nil
            artworkToken &+= 1
            tint = .white
        }

        if trackChanged { onTrackChange?() }
        if carries("playing", "playbackRate") {
            // The player's own elapsed time is exact; only extrapolate when the update lacks it.
            setPlaying(bool("playing") ?? (playbackRate > 0), freezeClock: !carriesElapsed)
        }
    }

    private func setPlaying(_ playing: Bool, freezeClock: Bool = true) {
        guard playing != isPlaying else { return }
        if freezeClock {
            // Freeze the clock at the moment playback stops so the scrubber doesn't jump.
            let now = Date()
            elapsedAtTimestamp = elapsed(at: now)
            elapsedTimestamp = now
        }
        isPlaying = playing
        onPlaybackChange?()
    }

    private func loadArtwork(_ data: Data) {
        artworkGeneration += 1
        let generation = artworkGeneration
        Task.detached(priority: .userInitiated) { [weak self] in
            let tint = ArtworkTint.average(of: data)
            await MainActor.run {
                guard let self, generation == self.artworkGeneration else { return }
                self.artwork = NSImage(data: data)
                self.artworkToken &+= 1
                self.tint = tint.map { Color(red: $0.r, green: $0.g, blue: $0.b) } ?? .white
            }
        }
    }

    private func string(_ key: String) -> String {
        if case .string(let s) = state[key] { return s }
        return ""
    }

    private func number(_ key: String) -> Double? {
        if case .number(let n) = state[key] { return n }
        return nil
    }

    /// The stream runs with --micros: times arrive as integer microseconds.
    private func micros(_ key: String) -> Double? {
        number(key).map { $0 / 1_000_000 }
    }

    private func bool(_ key: String) -> Bool? {
        if case .bool(let b) = state[key] { return b }
        return nil
    }

}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
