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

/// Large artwork, title, three buttons and the scrubber. Shuffle and repeat are in the right-click menu.
struct ExpandedPlayer: View {
    @Environment(NowPlayingModel.self) private var nowPlaying
    @AppStorage(Prefs.tintWaveform) private var tintWaveform = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                ArtworkImage(image: nowPlaying.artwork, cornerRadius: 16)
                    .frame(width: 88, height: 88)
                    .shadow(color: .black.opacity(0.45), radius: 12, y: 8)
                    .id(nowPlaying.trackID)
                    .transition(.artworkFlip)
                VStack(alignment: .leading, spacing: 2) {
                    MarqueeText(id: nowPlaying.trackID + "t") {
                        Text(nowPlaying.title)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    Text(nowPlaying.artist)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        ControlButton(symbol: "backward.fill", size: 17) { nowPlaying.previous() }
                        ControlButton(symbol: nowPlaying.isPlaying ? "pause.fill" : "play.fill", size: 24) { nowPlaying.togglePlayPause() }
                        ControlButton(symbol: "forward.fill", size: 17) { nowPlaying.next() }
                        Spacer(minLength: 0)
                        Waveform(isPlaying: nowPlaying.isPlaying, tint: tintWaveform ? nowPlaying.tint : .white)
                            .frame(width: 22)
                    }
                    // The buttons' hit areas reach past their glyphs; line the first glyph up with the text.
                    .padding(.leading, -10)
                    .padding(.top, 8)
                }
            }
            Scrubber()
        }
        .animation(Motion.peekIn, value: nowPlaying.trackID)
        .contextMenu {
            Toggle("Shuffle", isOn: Binding(get: { nowPlaying.isShuffled }, set: { _ in nowPlaying.toggleShuffle() }))
            Picker("Repeat", selection: Binding(get: { nowPlaying.repeatMode }, set: { nowPlaying.setRepeat($0) })) {
                Text("Off").tag(1)
                Text("All").tag(3)
                Text("One").tag(2)
            }
        }
    }
}

/// A blurred copy of the artwork that lights the left of the expanded island and fades out before
/// the calendar. Kept clear of the top strip, where the hardware notch would show as a black block.
struct CoverBackdrop: View {
    @Environment(NowPlayingModel.self) private var nowPlaying
    let notchHeight: CGFloat

    var body: some View {
        if let image = nowPlaying.backdrop {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 420, height: 280)
                .clipped()
                .mask(LinearGradient(stops: [.init(color: .black, location: 0.35), .init(color: .clear, location: 0.9)],
                                     startPoint: .leading, endPoint: .trailing))
                .mask(alignment: .top) {
                    VStack(spacing: 0) {
                        Color.clear.frame(height: notchHeight - 6)
                        LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: 48)
                        Color.black
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .id(nowPlaying.trackID)
                .transition(.opacity.animation(.easeInOut(duration: 0.4)))
                .allowsHitTesting(false)
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
            VStack(spacing: 3) {
                GeometryReader { geo in
                    let thick = hovering || dragElapsed != nil
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.22))
                        Capsule().fill(.white).frame(width: max(geo.size.width * fraction, thick ? 6 : 3))
                    }
                    .frame(height: thick ? 6 : 3)
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
                .foregroundStyle(.white.opacity(0.55))
            }
        }
    }

    static func format(_ seconds: Double) -> String {
        let total = Int(seconds.rounded(.down))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
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
