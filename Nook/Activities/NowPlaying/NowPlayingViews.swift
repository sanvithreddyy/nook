import SwiftUI

// MARK: Live activity sides

struct NowPlayingArtworkThumb: View {
    @Environment(NowPlayingModel.self) private var nowPlaying
    @Environment(NotchModel.self) private var model
    @AppStorage(Prefs.artworkFlip) private var flip = true

    var body: some View {
        let side = model.notch.size.height - 10
        // A ZStack, so the old and new covers overlap while they change.
        ZStack {
            ArtworkImage(image: nowPlaying.artwork, cornerRadius: 6)
                .id(nowPlaying.artworkToken)
                .transition(.artworkChange(flip: flip))
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
    @AppStorage(Prefs.musicLeftButton) private var leftButton = MusicButton.favorite
    @AppStorage(Prefs.musicRightButton) private var rightButton = MusicButton.output
    @AppStorage(Prefs.artworkFlip) private var flip = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 14 * k) {
                ZStack {
                    ArtworkImage(image: nowPlaying.artwork, cornerRadius: 12 * k)
                        .id(nowPlaying.artworkToken)
                        .transition(.artworkChange(flip: flip))
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
                SideButton(kind: leftButton)
                    .frame(width: 34 * k)
                Spacer(minLength: 0)
                ControlButton(symbol: "backward.fill", size: 20 * k, label: "Previous") { nowPlaying.previous() }
                Spacer(minLength: 0)
                ControlButton(symbol: nowPlaying.isPlaying ? "pause.fill" : "play.fill", size: 27 * k,
                              label: nowPlaying.isPlaying ? "Pause" : "Play", bounces: false) { nowPlaying.togglePlayPause() }
                Spacer(minLength: 0)
                ControlButton(symbol: "forward.fill", size: 20 * k, label: "Next") { nowPlaying.next() }
                Spacer(minLength: 0)
                SideButton(kind: rightButton)
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
            SettingsMenuItem(pane: .nowPlaying)
        }
    }
}

/// Elapsed time, the bar, time remaining, on one line. A thick bar, as Apple's music card has it;
/// it thickens further under the pointer and while dragged.
struct Scrubber: View {
    @Environment(NowPlayingModel.self) private var nowPlaying
    @Environment(\.homeScale) private var k
    @Environment(\.displayScale) private var displayScale
    @AppStorage(Prefs.musicShowsTotal) private var showsTotal = false
    @State private var dragElapsed: Double?
    @State private var hovering = false
    /// Steps while playing, so the time and bar move on.
    @State private var tick = 0
    @State private var steps = ScrubberSteps()

    var body: some View {
        let duration = nowPlaying.duration
        let _ = tick
        let elapsed = dragElapsed ?? nowPlaying.elapsed(at: .now)
        let fraction = duration > 0 ? min(max(elapsed / duration, 0), 1) : 0
        let _ = steps.drew(steps.step(elapsed: elapsed, duration: duration, scale: displayScale))
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
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { steps.bar = $0 }
            .animation(Motion.ease(.spring(duration: 0.25, bounce: 0)), value: active)
            .onHover { hovering = $0 }
            .accessibilityElement()
            .accessibilityLabel("Playback position")
            .accessibilityValue("\(Self.format(elapsed)) of \(Self.format(duration))")
            // Click to switch between what's left and the track's length, as Music's own player does.
            Text(showsTotal ? Self.format(duration) : "−" + Self.format(max(duration - elapsed, 0)))
                .frame(minWidth: 36 * k, alignment: .trailing)
                .contentShape(Rectangle())
                .onTapGesture { showsTotal.toggle() }
        }
        .font(.system(size: 12 * k, weight: .medium).monospacedDigit())
        .foregroundStyle(.white.opacity(0.6))
        // A TimelineView this frequent runs SwiftUI's update on every display frame, redrawing the
        // whole island at 120 Hz; a sleeping task wakes only for the ten steps. Most steps would draw
        // the same frame (the bar's end is rounded to whole pixels), so only those that change it redraw.
        .task(id: nowPlaying.isPlaying && dragElapsed == nil) {
            guard nowPlaying.isPlaying, dragElapsed == nil else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                let step = steps.step(elapsed: nowPlaying.elapsed(at: .now), duration: nowPlaying.duration, scale: displayScale)
                if step != steps.drawn { tick &+= 1 }
            }
        }
    }

    static func format(_ seconds: Double) -> String {
        let total = Int(seconds.rounded(.down))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

/// What the scrubber drew last and where its bar sits, for the ticking task to compare against.
/// A reference held in state, so recording them doesn't redraw.
private final class ScrubberSteps {
    var bar: CGRect = .zero
    private(set) var drawn: [Int] = []

    func drew(_ step: [Int]) { drawn = step }

    /// What changes in the drawing as a track plays: both clocks' whole seconds and the device pixel
    /// the bar ends on. SwiftUI rounds edges to pixels where they fall in the window.
    func step(elapsed: Double, duration: Double, scale: CGFloat) -> [Int] {
        let fraction = duration > 0 ? min(max(elapsed / duration, 0), 1) : 0
        let end = (bar.minX + bar.width * fraction) * scale
        return [Int(elapsed), Int(max(duration - elapsed, 0)), Int(end.rounded())]
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

/// One of the player's side buttons, as Settings has it. The star shows only for players that take
/// favourites, so it never sits there dead.
private struct SideButton: View {
    @Environment(NowPlayingModel.self) private var nowPlaying
    let kind: MusicButton

    var body: some View {
        switch kind {
        case .none:
            EmptyView()
        case .favorite:
            if nowPlaying.canFavorite { FavoriteButton() }
        case .output:
            OutputButton()
        case .shuffle:
            SideGlyph(symbol: "shuffle", lit: nowPlaying.isShuffled, label: "Shuffle") { nowPlaying.toggleShuffle() }
        case .repeatMode:
            SideGlyph(symbol: nowPlaying.repeatMode == 2 ? "repeat.1" : "repeat", lit: nowPlaying.repeatMode != 1,
                      label: "Repeat") { nowPlaying.cycleRepeat() }
        case .back15:
            SideGlyph(symbol: "gobackward.15", label: "Back 15 seconds") { nowPlaying.skip(by: -15) }
        case .forward15:
            SideGlyph(symbol: "goforward.15", label: "Forward 15 seconds") { nowPlaying.skip(by: 15) }
        }
    }
}

/// A side button's glyph on its platter. `lit`: a mode that's on shows bright, off shows dim;
/// a plain action sits between.
private struct SideGlyph: View {
    @Environment(\.homeScale) private var k
    let symbol: String
    var lit: Bool?
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17 * k, weight: .semibold))
                .foregroundStyle(.white.opacity(lit.map { $0 ? 0.95 : 0.45 } ?? 0.75))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 34 * k, height: 34 * k)
        }
        .buttonStyle(PlatterButtonStyle())
        .accessibilityLabel(label)
        .accessibilityValue(lit.map { $0 ? "On" : "Off" } ?? "")
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
            .opacity(configuration.isPressed ? ButtonFeedback.pressed : 1)
            .animation(ButtonFeedback.press, value: configuration.isPressed)
            .background(RoundedRectangle(cornerRadius: 9 * k, style: .continuous).fill(.white.opacity(hovering ? 0.12 : 0)))
            .animation(ButtonFeedback.hover(hovering), value: hovering)
            .onHover { hovering = $0 }
            .contentShape(Rectangle())
    }
}

/// Hover shows a faint round backing; a press dims the glyph.
struct IslandButtonStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? ButtonFeedback.pressed : 1)
            .animation(ButtonFeedback.press, value: configuration.isPressed)
            .background(Circle().fill(.white.opacity(hovering ? 0.08 : 0)))
            .animation(ButtonFeedback.hover(hovering), value: hovering)
            .onHover { hovering = $0 }
            .contentShape(Rectangle())
    }
}

/// Buttons in the island don't move under the pointer: the backing appears at once and fades over
/// a tenth of a second, and a press dims the glyph rather than shrinking it.
enum ButtonFeedback {
    static let pressed = 0.4
    static var press: Animation? { Motion.ease(.easeOut(duration: 0.08)) }
    static func hover(_ on: Bool) -> Animation? { Motion.ease(.easeOut(duration: on ? 0.03 : 0.1)) }
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
    /// A new cover turns in like a card: the old one turns to its edge about the vertical axis, then the
    /// new one turns out from the other side. Without the flip, or with Reduce Motion, they cross-fade.
    static func artworkChange(flip: Bool) -> AnyTransition {
        guard flip, !Motion.reduceMotion else { return artworkSwap }
        return .asymmetric(
            insertion: .modifier(active: ArtworkTurn(angle: -90), identity: ArtworkTurn(angle: 0))
                .animation(Motion.ease(.easeOut(duration: 0.12))?.delay(0.11)),
            removal: .modifier(active: ArtworkTurn(angle: 90), identity: ArtworkTurn(angle: 0))
                .animation(Motion.ease(.easeIn(duration: 0.11)))
        )
    }

    /// A new cover cross-fades in from a soft blur; the old one fades out under it.
    static var artworkSwap: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: IslandContentModifier(opacity: 0, blur: 6, scaleX: 1, scaleY: 1, anchor: .center),
                                 identity: IslandContentModifier.shown(anchor: .center)),
            removal: .opacity
        )
    }
}

/// Half of the artwork's turn: edge-on at 90°, softened a little as it passes the edge.
private struct ArtworkTurn: ViewModifier {
    let angle: Double

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
            .blur(radius: abs(angle) / 90 * 2)
            // Edge-on it's a sliver; hidden there so the outgoing cover never shows behind the new one.
            .opacity(abs(angle) < 90 ? 1 : 0)
    }
}
