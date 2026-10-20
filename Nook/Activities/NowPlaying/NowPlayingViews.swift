import SwiftUI

// MARK: Live activity sides

struct NowPlayingArtworkThumb: View {
    @Environment(NowPlayingModel.self) private var nowPlaying
    @Environment(NotchModel.self) private var model

    var body: some View {
        let side = model.notch.size.height - 10
        ArtworkImage(image: nowPlaying.artwork, cornerRadius: 6)
            .frame(width: side, height: side)
            .id(nowPlaying.trackID)
            .transition(.artworkFlip)
            .animation(Motion.peekIn, value: nowPlaying.trackID)
    }
}

struct NowPlayingWaveformSlot: View {
    @Environment(NowPlayingModel.self) private var nowPlaying
    @Environment(NotchModel.self) private var model
    @AppStorage(Prefs.showWaveform) private var showWaveform = true
    @AppStorage(Prefs.tintWaveform) private var tintWaveform = true
    @State private var hovering = false

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
        .onHover { inside in withAnimation(.easeOut(duration: 0.18)) { hovering = inside } }
        // A fast exit can skip the slot's own exit event once the panel stops taking the mouse.
        .onChange(of: model.isHovering) { _, island in if !island { hovering = false } }
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

struct ExpandedPlayer: View {
    @Environment(NowPlayingModel.self) private var nowPlaying
    @AppStorage(Prefs.tintWaveform) private var tintWaveform = true

    var body: some View {
        if nowPlaying.hasTrack {
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 12) {
                    ArtworkImage(image: nowPlaying.artwork, cornerRadius: 11)
                        .frame(width: 54, height: 54)
                        .overlay(alignment: .bottomTrailing) { AppBadge() }
                        .id(nowPlaying.trackID)
                        .transition(.artworkFlip)
                    VStack(alignment: .leading, spacing: 2) {
                        MarqueeText(id: nowPlaying.trackID + "t") {
                            Text(nowPlaying.title)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        Text(nowPlaying.artist)
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                    }
                    Waveform(isPlaying: nowPlaying.isPlaying, tint: tintWaveform ? nowPlaying.tint : .white)
                        .frame(width: 22)
                }
                Scrubber()
                    .padding(.top, 14)
                PlaybackControls()
                    .padding(.top, 2)
            }
            .animation(Motion.peekIn, value: nowPlaying.trackID)
        } else {
            Text("Nothing playing")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.45))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct AppBadge: View {
    @Environment(NowPlayingModel.self) private var nowPlaying

    var body: some View {
        if let icon = nowPlaying.appIcon {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 20, height: 20)
                .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                .offset(x: 5, y: 5)
        }
    }
}

struct Scrubber: View {
    @Environment(NowPlayingModel.self) private var nowPlaying
    @State private var dragElapsed: Double?
    @State private var hovering = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 10, paused: !nowPlaying.isPlaying || dragElapsed != nil)) { context in
            let duration = nowPlaying.duration
            let elapsed = dragElapsed ?? nowPlaying.elapsed(at: context.date)
            let fraction = duration > 0 ? min(max(elapsed / duration, 0), 1) : 0
            VStack(spacing: 4) {
                GeometryReader { geo in
                    let thick = hovering || dragElapsed != nil
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.16))
                        Capsule().fill(.white).frame(width: max(geo.size.width * fraction, thick ? 6 : 4))
                    }
                    .frame(height: thick ? 7 : 4)
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
                .frame(height: 10)
                .animation(Motion.ease(.spring(duration: 0.25, bounce: 0)), value: hovering || dragElapsed != nil)
                .onHover { hovering = $0 }

                HStack {
                    Text(Self.format(elapsed))
                    Spacer()
                    Text("-" + Self.format(max(duration - elapsed, 0)))
                }
                .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.45))
            }
        }
    }

    static func format(_ seconds: Double) -> String {
        let total = Int(seconds.rounded(.down))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

private struct PlaybackControls: View {
    @Environment(NowPlayingModel.self) private var nowPlaying

    var body: some View {
        HStack(spacing: 0) {
            ControlButton(symbol: "shuffle", size: 13, active: nowPlaying.isShuffled) { nowPlaying.toggleShuffle() }
            Spacer(minLength: 0)
            ControlButton(symbol: "backward.fill", size: 17) { nowPlaying.previous() }
            Spacer(minLength: 0)
            ControlButton(symbol: nowPlaying.isPlaying ? "pause.fill" : "play.fill", size: 24) { nowPlaying.togglePlayPause() }
            Spacer(minLength: 0)
            ControlButton(symbol: "forward.fill", size: 17) { nowPlaying.next() }
            Spacer(minLength: 0)
            ControlButton(symbol: nowPlaying.repeatMode == 2 ? "repeat.1" : "repeat", size: 13, active: nowPlaying.repeatMode != 1) { nowPlaying.cycleRepeat() }
        }
        .frame(height: 30)
    }
}

struct ControlButton: View {
    let symbol: String
    var size: CGFloat = 16
    var active = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(.white.opacity(active ? 1 : 0.4))
                .frame(width: size + 20, height: 30)
        }
        .buttonStyle(IslandButtonStyle())
    }
}

/// Press shrinks with a spring; hover shows a faint round backing.
struct IslandButtonStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Circle().fill(.white.opacity(hovering ? 0.1 : 0)).padding(-2))
            .scaleEffect(configuration.isPressed ? 0.84 : 1)
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

private struct FlipModifier: ViewModifier {
    var angle: Double
    var opacity: Double
    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
            .opacity(opacity)
    }
}

extension AnyTransition {
    /// New artwork turns in like a card; the old one turns away.
    static var artworkFlip: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: FlipModifier(angle: -90, opacity: 0), identity: FlipModifier(angle: 0, opacity: 1))
                .animation(.spring(duration: 0.4, bounce: 0.15).delay(0.12)),
            removal: .modifier(active: FlipModifier(angle: 90, opacity: 0), identity: FlipModifier(angle: 0, opacity: 1))
                .animation(.easeIn(duration: 0.14))
        )
    }
}
