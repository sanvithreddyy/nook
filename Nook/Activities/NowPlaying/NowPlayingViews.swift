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

/// Apple's expanded music view on the notch: artwork in the wing beside the notch, title and artist just
/// under the notch line with the waveform, the scrubber with both times, then three large controls.
/// Shuffle and repeat are in the right-click menu.
struct MusicCard: View {
    @Environment(NowPlayingModel.self) private var nowPlaying
    @Environment(NotchModel.self) private var model
    @AppStorage(Prefs.tintWaveform) private var tintWaveform = true

    private static let artwork: CGFloat = 56
    /// Title and artist together, bottom-aligned with the artwork.
    private static let textBlock: CGFloat = 34

    var body: some View {
        // The text block ends level with the artwork and starts just under the notch,
        // so the artwork's top follows the notch's height.
        let top = max(12, model.notch.size.height + Card.titleGap + Self.textBlock - Self.artwork)
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 12) {
                ZStack {
                    ArtworkImage(image: nowPlaying.artwork, cornerRadius: 12)
                        .id(nowPlaying.artworkToken)
                        .transition(.artworkSwap)
                }
                .sharedElement("artwork")
                .frame(width: Self.artwork, height: Self.artwork)
                .animation(Motion.ease(.easeOut(duration: 0.25)), value: nowPlaying.artworkToken)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 10) {
                        MarqueeText(id: nowPlaying.trackID + "t") {
                            Text(nowPlaying.title)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        Waveform(isPlaying: nowPlaying.isPlaying, tint: tintWaveform ? nowPlaying.tint : .white)
                    }
                    Text(nowPlaying.artist)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
                .padding(.bottom, 1)
            }
            .padding(.top, top)
            Scrubber()
                .padding(.top, 12)
            HStack(spacing: 30) {
                ControlButton(symbol: "backward.fill", size: 20, label: "Previous") { nowPlaying.previous() }
                ControlButton(symbol: nowPlaying.isPlaying ? "pause.fill" : "play.fill", size: 27,
                              label: nowPlaying.isPlaying ? "Pause" : "Play", bounces: false) { nowPlaying.togglePlayPause() }
                ControlButton(symbol: "forward.fill", size: 20, label: "Next") { nowPlaying.next() }
            }
            .padding(.top, 6)
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

/// Elapsed time, the bar, time remaining, on one line. The bar thickens under the pointer and while dragged.
struct Scrubber: View {
    @Environment(NowPlayingModel.self) private var nowPlaying
    @State private var dragElapsed: Double?
    @State private var hovering = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 10, paused: !nowPlaying.isPlaying || dragElapsed != nil)) { context in
            let duration = nowPlaying.duration
            let elapsed = dragElapsed ?? nowPlaying.elapsed(at: context.date)
            let fraction = duration > 0 ? min(max(elapsed / duration, 0), 1) : 0
            let active = hovering || dragElapsed != nil
            HStack(spacing: 10) {
                Text(Self.format(elapsed))
                    .frame(minWidth: 28, alignment: .leading)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.18))
                        Capsule().fill(.white.opacity(active ? 1 : 0.72))
                            .frame(width: max(geo.size.width * fraction, active ? 7 : 4))
                    }
                    .frame(height: active ? 7 : 4)
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
                .frame(height: 14)
                .animation(Motion.ease(.spring(duration: 0.25, bounce: 0)), value: active)
                .onHover { hovering = $0 }
                .accessibilityElement()
                .accessibilityLabel("Playback position")
                .accessibilityValue("\(Self.format(elapsed)) of \(Self.format(duration))")
                Text("−" + Self.format(max(duration - elapsed, 0)))
                    .frame(minWidth: 34, alignment: .trailing)
            }
            .font(.system(size: 11, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.5))
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
