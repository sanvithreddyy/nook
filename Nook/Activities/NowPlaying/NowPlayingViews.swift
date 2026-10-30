import SwiftUI

// MARK: Live activity sides

struct NowPlayingArtworkThumb: View {
    @Environment(NowPlayingModel.self) private var nowPlaying
    @Environment(NotchModel.self) private var model

    var body: some View {
        let side = model.notch.size.height - 10
        // A ZStack, so the old and new covers overlap while they cross-fade.
        ZStack {
            ArtworkImage(image: nowPlaying.artwork, cornerRadius: 6)
                .id(nowPlaying.artworkToken)
                .transition(.artworkSwap)
        }
        .sharedElement("artwork")
        .frame(width: side, height: side)
        .animation(Motion.ease(.easeOut(duration: 0.25)), value: nowPlaying.artworkToken)
    }
}

struct NowPlayingWaveformSlot: View {
    @Environment(NowPlayingModel.self) private var nowPlaying
    @Environment(NotchModel.self) private var model
    @AppStorage(Prefs.showWaveform) private var showWaveform = true
    @AppStorage(Prefs.tintWaveform) private var tintWaveform = true
    @AppStorage(Prefs.expandOnHover) private var expandOnHover = true
    @State private var pointing = false

    /// The waveform turns into play/pause under the pointer, unless hovering opens the island anyway,
    /// where the glyph would show for an instant and vanish.
    private var hovering: Bool { pointing && !expandOnHover }

    var body: some View {
        ZStack {
            if showWaveform {
                Waveform(isPlaying: nowPlaying.isPlaying, tint: tintWaveform ? nowPlaying.tint : .white)
                    .scaleEffect(hovering ? 1.2 : 1)
                    .opacity(hovering ? 0.25 : 1)
            }
            Image(systemName: nowPlaying.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .opacity(hovering || !showWaveform ? 1 : 0)
                .scaleEffect(hovering || !showWaveform ? 1 : 0.6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onHover { inside in withAnimation(.easeOut(duration: 0.18)) { pointing = inside } }
        // A fast exit can skip the slot's own exit event once the panel stops taking the mouse.
        .onChange(of: model.isHovering) { _, island in if !island { pointing = false } }
        .onTapGesture { nowPlaying.togglePlayPause() }
    }
}

// MARK: Peek

struct TrackPeek: View {
    @Environment(NowPlayingModel.self) private var nowPlaying

    var body: some View {
        MarqueeText(id: nowPlaying.trackID) {
            Text("\(Text(nowPlaying.title).foregroundStyle(.white))\(Text(nowPlaying.artist.isEmpty ? "" : "  ·  \(nowPlaying.artist)").foregroundStyle(.white.opacity(0.55)))")
                .font(.system(size: 13, weight: .medium))
        }
    }
}

// MARK: Expanded

/// Apple's music card on the notch: the artwork with the title and artist beside
/// it at one size, the waveform at the end of that line, a thick scrubber with both times, then the
/// favourite star, the transport and the output. Shuffle and repeat are in the right-click menu.
struct MusicModule: View {
    @Environment(NowPlayingModel.self) private var nowPlaying
    @Environment(\.homeScale) private var k
    @AppStorage(Prefs.tintWaveform) private var tintWaveform = true
    @AppStorage(Prefs.musicFavorite) private var showFavorite = true
    @AppStorage(Prefs.musicOutput) private var showOutput = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 14 * k) {
                ZStack {
                    ArtworkImage(image: nowPlaying.artwork, cornerRadius: 12 * k)
                        .id(nowPlaying.artworkToken)
                        .transition(.artworkSwap)
                }
                .sharedElement("artwork")
                .frame(width: 64 * k, height: 64 * k)
                .animation(Motion.ease(.easeOut(duration: 0.25)), value: nowPlaying.artworkToken)
                VStack(alignment: .leading, spacing: 0) {
                    MarqueeText(id: nowPlaying.trackID + "t") {
                        Text(nowPlaying.title)
                            .font(.system(size: 15 * k, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    Text(nowPlaying.artist)
                        .font(.system(size: 15 * k))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
                .padding(.top, 12 * k)
                Waveform(isPlaying: nowPlaying.isPlaying, tint: tintWaveform ? nowPlaying.tint : .white)
                    .padding(.top, 15 * k)
            }
            Scrubber()
                .padding(.top, 16 * k)
            HStack(spacing: 0) {
                Group {
                    if showFavorite, nowPlaying.canFavorite { FavoriteButton() }
                }
                .frame(width: 34 * k)
                Spacer(minLength: 0)
                ControlButton(symbol: "backward.fill", size: 20 * k, label: "Previous") { nowPlaying.previous() }
                Spacer(minLength: 0)
                ControlButton(symbol: nowPlaying.isPlaying ? "pause.fill" : "play.fill", size: 27 * k,
                              label: nowPlaying.isPlaying ? "Pause" : "Play", bounces: false) { nowPlaying.togglePlayPause() }
                Spacer(minLength: 0)
                ControlButton(symbol: "forward.fill", size: 20 * k, label: "Next") { nowPlaying.next() }
                Spacer(minLength: 0)
                Group {
                    if showOutput { OutputButton() }
                }
                .frame(width: 34 * k)
            }
            .padding(.horizontal, -6 * k)
            .padding(.top, 10 * k)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contextMenu {
            Toggle("Shuffle", isOn: Binding(get: { nowPlaying.isShuffled }, set: { _ in nowPlaying.toggleShuffle() }))
            Picker("Repeat", selection: Binding(get: { nowPlaying.repeatMode }, set: { nowPlaying.setRepeat($0) })) {
                Text("Off").tag(1)
                Text("All").tag(3)
                Text("One").tag(2)
            }
            Divider()
            SettingsMenuItem()
        }
    }
}

/// Elapsed time, the bar, time remaining, on one line. A thick bar, as Apple's music card has it;
/// it thickens further under the pointer and while dragged.
struct Scrubber: View {
    @Environment(NowPlayingModel.self) private var nowPlaying
    @Environment(\.homeScale) private var k
    @State private var dragElapsed: Double?
    @State private var hovering = false
    /// Steps ten times a second while playing, so the time and bar move on.
    @State private var tick = 0

    var body: some View {
        let duration = nowPlaying.duration
        let _ = tick
        let elapsed = dragElapsed ?? nowPlaying.elapsed(at: .now)
        let fraction = duration > 0 ? min(max(elapsed / duration, 0), 1) : 0
        let active = hovering || dragElapsed != nil
        let thickness = (active ? 9 : 6) * k
        HStack(spacing: 10 * k) {
            Text(Self.format(elapsed))
                .frame(minWidth: 30 * k, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.18))
                    Capsule().fill(.white.opacity(active ? 0.95 : 0.55))
                        .frame(width: max(geo.size.width * fraction, thickness))
                }
                .frame(height: thickness)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard duration > 0 else { return }
                            dragElapsed = min(max(value.location.x / geo.size.width, 0), 1) * duration
                        }
                        .onEnded { _ in
                            if let dragElapsed { nowPlaying.seek(to: dragElapsed) }
                            dragElapsed = nil
                        }
                )
            }
            .frame(height: 14 * k)
            .animation(Motion.ease(.spring(duration: 0.25, bounce: 0)), value: active)
            .onHover { hovering = $0 }
            .accessibilityElement()
            .accessibilityLabel("Playback position")
            .accessibilityValue("\(Self.format(elapsed)) of \(Self.format(duration))")
            Text("−" + Self.format(max(duration - elapsed, 0)))
                .frame(minWidth: 36 * k, alignment: .trailing)
        }
        .font(.system(size: 12 * k, weight: .medium).monospacedDigit())
        .foregroundStyle(.white.opacity(0.6))
        // A TimelineView this frequent runs SwiftUI's update on every display frame, redrawing the
        // whole island at 120 Hz; a sleeping task wakes only for the ten steps.
        .task(id: nowPlaying.isPlaying && dragElapsed == nil) {
            guard nowPlaying.isPlaying, dragElapsed == nil else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                tick &+= 1
            }
        }
    }

    static func format(_ seconds: Double) -> String {
        let total = Int(seconds.rounded(.down))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

/// A transport control. The glyph swaps with the system's replace effect and bounces when clicked.
struct ControlButton: View {
    let symbol: String
    var size: CGFloat = 16
    let label: String
    var bounces = true
    let action: () -> Void
    @State private var clicks = 0

    var body: some View {
        Button {
            if bounces { clicks += 1 }
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce.down, options: .speed(1.4), value: clicks)
                .foregroundStyle(.white.opacity(0.95))
                .frame(width: size + 24, height: size + 14)
        }
        .buttonStyle(IslandButtonStyle())
        .accessibilityLabel(label)
    }
}

/// Apple Music's star. Shown only for players that report favourites, so it never sits there dead.
private struct FavoriteButton: View {
    @Environment(NowPlayingModel.self) private var nowPlaying
    @Environment(\.homeScale) private var k
    @State private var clicks = 0

    var body: some View {
        Button {
            clicks += 1
            nowPlaying.favorite()
        } label: {
            Image(systemName: nowPlaying.isFavorite ? "star.fill" : "star")
                .font(.system(size: 17 * k, weight: .semibold))
                .foregroundStyle(.white.opacity(nowPlaying.isFavorite ? 0.95 : 0.55))
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, options: .speed(1.4), value: clicks)
                .frame(width: 34 * k, height: 34 * k)
        }
        .buttonStyle(PlatterButtonStyle())
        .accessibilityLabel(nowPlaying.isFavorite ? "Favorited" : "Favorite")
    }
}

/// Where the sound goes: the headphones' own glyph when they're the output, otherwise AirPlay's.
/// Click to pick another output from the menu.
private struct OutputButton: View {
    @Environment(AudioOutputs.self) private var outputs
    @Environment(NotchModel.self) private var model
    @Environment(\.homeScale) private var k

    var body: some View {
        Button { outputs.showMenu(holding: model) } label: {
            Image(systemName: outputs.symbol)
                .font(.system(size: 17 * k, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 34 * k, height: 34 * k)
        }
        .buttonStyle(PlatterButtonStyle())
        .accessibilityLabel("Output: \(outputs.currentName)")
        .help(outputs.currentName)
    }
}

/// A small square platter under the pointer, as the music card's side buttons have.
struct PlatterButtonStyle: ButtonStyle {
    @Environment(\.homeScale) private var k
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(RoundedRectangle(cornerRadius: 9 * k, style: .continuous).fill(.white.opacity(configuration.isPressed ? 0.18 : (hovering ? 0.12 : 0))))
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(Motion.press, value: configuration.isPressed)
            .animation(.easeOut(duration: 0.15), value: hovering)
            .onHover { hovering = $0 }
            .contentShape(Rectangle())
    }
}

/// Press shrinks with a spring; hover shows a faint round backing.
struct IslandButtonStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Circle().fill(.white.opacity(hovering ? 0.08 : 0)))
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(Motion.press, value: configuration.isPressed)
            .animation(.easeOut(duration: 0.15), value: hovering)
            .onHover { hovering = $0 }
            .contentShape(Rectangle())
    }
}

// MARK: Shared

struct ArtworkImage: View {
    let image: NSImage?
    let cornerRadius: CGFloat

    var body: some View {
        // Color.clear takes the proposed square; the image fills it and is clipped to it,
        // so wide video thumbnails crop instead of spilling out.
        Color.clear
            .overlay {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                } else {
                    Rectangle().fill(.white.opacity(0.08))
                    Image(systemName: "music.note")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

extension AnyTransition {
    /// A new cover cross-fades in from a soft blur; the old one fades out under it.
    static var artworkSwap: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: IslandContentModifier(opacity: 0, blur: 6, scaleX: 1, scaleY: 1, anchor: .center),
                                 identity: IslandContentModifier.shown(anchor: .center)),
            removal: .opacity
        )
    }
}
