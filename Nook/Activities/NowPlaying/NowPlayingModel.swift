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
        didSet { if bundleIdentifier != oldValue { appIcon = Self.icon(for: bundleIdentifier) } }
    }
    /// Icon of the app that is playing, resolved once per app change.
    private(set) var appIcon: NSImage?
    private(set) var artwork: NSImage?
    /// Average artwork color, lifted so it reads on black.
    private(set) var tint: Color = .white
    private(set) var isShuffled = false
    private(set) var repeatMode = 1
    /// Changes whenever the track changes; drives the artwork flip and the quick peek.
    private(set) var trackID = ""

    /// Elapsed time at `elapsedTimestamp`; extrapolate with `elapsed(at:)`.
    private var elapsedAtTimestamp: Double = 0
    private var elapsedTimestamp = Date()

    @ObservationIgnored var onTrackChange: (() -> Void)?
    @ObservationIgnored var onPlaybackChange: (() -> Void)?
    @ObservationIgnored private let client = MediaRemoteClient()
    @ObservationIgnored private var state: [String: NowPlayingUpdate.Value] = [:]
    @ObservationIgnored private var artworkGeneration = 0

    var hasTrack: Bool { !title.isEmpty }

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
        let rate = isPlaying ? max(playbackRate, 1) : 0
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

    func seek(to seconds: Double) {
        elapsedAtTimestamp = seconds
        elapsedTimestamp = Date()
        client.seek(to: seconds)
    }

    func toggleShuffle() {
        isShuffled.toggle()
        client.setShuffle(isShuffled)
    }

    func cycleRepeat() {
        repeatMode = repeatMode == 1 ? 3 : (repeatMode == 3 ? 2 : 1)
        client.setRepeat(repeatMode)
    }

    #if DEBUG
    /// Shows the current (or a sample) track as playing without sending anything to the player.
    func previewPlaying() {
        client.onUpdate = nil
        if title.isEmpty {
            title = "Emagination (B-Side)"
            artist = "Miami Horror"
            duration = 241
            trackID = "preview"
        }
        elapsedAtTimestamp = duration * 0.3
        elapsedTimestamp = Date()
        isPlaying = true
    }

    func previewPaused() {
        setPlaying(false)
    }

    func debugClear() {
        client.onUpdate = nil
        title = ""
        artist = ""
        artwork = nil
        isPlaying = false
    }
    #endif

    // MARK: Stream

    private func apply(_ update: NowPlayingUpdate) {
        if !update.isDiff { state.removeAll() }
        for (key, value) in update.values {
            if case .null = value { state.removeValue(forKey: key) } else { state[key] = value }
        }

        let newTitle = string("title")
        let newArtist = string("artist")
        let newAlbum = string("album")
        let newID = [newTitle, newArtist, newAlbum].joined(separator: "\u{1F}")
        let trackChanged = newID != trackID

        title = newTitle
        artist = newArtist
        album = newAlbum
        duration = number("duration") ?? 0
        playbackRate = number("playbackRate") ?? 0
        bundleIdentifier = string("parentApplicationBundleIdentifier").nilIfEmpty ?? string("bundleIdentifier").nilIfEmpty
        if let shuffle = number("shuffleMode") { isShuffled = shuffle != 1 }
        if let mode = number("repeatMode") { repeatMode = Int(mode) }

        if let elapsed = number("elapsedTime") {
            elapsedAtTimestamp = elapsed
            elapsedTimestamp = date("timestamp") ?? Date()
        }

        if let data = update.artwork {
            loadArtwork(data)
        } else if state["artworkData"] == nil, artwork != nil {
            artworkGeneration += 1
            artwork = nil
            tint = .white
        }

        let playing = bool("playing") ?? (playbackRate > 0)
        if trackChanged {
            trackID = newID
            onTrackChange?()
        }
        setPlaying(playing)
    }

    private func setPlaying(_ playing: Bool) {
        guard playing != isPlaying else { return }
        // Freeze the clock at the moment playback stops so the scrubber doesn't jump.
        let now = Date()
        elapsedAtTimestamp = elapsed(at: now)
        elapsedTimestamp = now
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

    private func bool(_ key: String) -> Bool? {
        if case .bool(let b) = state[key] { return b }
        return nil
    }

    private func date(_ key: String) -> Date? {
        guard case .string(let s) = state[key] else { return nil }
        return try? Date(s, strategy: .iso8601)
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
