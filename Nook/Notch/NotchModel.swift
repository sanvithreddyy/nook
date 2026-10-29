import SwiftUI

/// Persistent content shown beside the notch.
enum LiveActivity: Equatable {
    case nowPlaying
    case locked
    case unlocked
    case calendar(id: String)

    /// Activities with the same identity morph in place (padlock closing → opening) instead of transitioning.
    var identity: String {
        switch self {
        case .nowPlaying: "nowPlaying"
        case .locked, .unlocked: "lock"
        case .calendar(let id): "calendar-\(id)"
        }
    }
}

/// Transient content that replaces the live activity for a few seconds.
enum NotchNotification: Equatable {
    case volume(level: Float, muted: Bool)
    case brightness(level: Float)
    case charging(level: Int)
    case onBattery(level: Int)
    case lowBattery(level: Int)
    case lowPowerMode(on: Bool)
    case device(name: String, symbol: String, battery: Int?)

    /// Notifications of the same kind update in place instead of transitioning.
    var kind: String {
        switch self {
        case .volume: "volume"
        case .brightness: "brightness"
        case .charging, .onBattery, .lowBattery: "battery"
        case .lowPowerMode: "lowPower"
        case .device(let name, _, _): "device-\(name)"
        }
    }

    var isHUD: Bool {
        switch self {
        case .volume, .brightness: true
        default: false
        }
    }
}

/// A taller view that drops below the live activity: the current track, an event.
enum QuickPeek: Equatable {
    case track
    case event(id: String)
}

enum Presentation: Equatable {
    case idle
    case activity(LiveActivity)
    case peek(QuickPeek, LiveActivity?)
    case notification(NotchNotification)
    case expanded
}

/// What the open island shows: one card at a time, like the Dynamic Island's expanded views.
enum IslandCard: Hashable {
    case nowPlaying
    /// An event about to start or under way, with Join and Dismiss.
    case meeting(id: String)
    /// The next event and the month after it, or the calendar access prompt.
    case upNext
    /// Files kept for later and AirDrop.
    case shelf

    /// The cards the island can open to, most relevant first, so hovering opens what the closed island
    /// shows. `music`: a track is loaded, playing or paused; `musicIsLive`: the closed island shows it.
    /// An imminent meeting stands in for Up next, which would only repeat it, and opens first unless
    /// music is what the closed island shows. The shelf is always last: empty, it's a drop target.
    static func available(music: Bool, musicIsLive: Bool, meeting: String?, agenda: Bool, shelf: Bool) -> [IslandCard] {
        var cards: [IslandCard] = []
        if music { cards.append(.nowPlaying) }
        if let meeting {
            cards.insert(.meeting(id: meeting), at: music && musicIsLive ? cards.count : 0)
        } else if agenda {
            cards.append(.upNext)
        }
        if shelf { cards.append(.shelf) }
        return cards
    }
}

struct IslandLayout: Equatable {
    var size: CGSize
    var topRadius: CGFloat
    var bottomRadius: CGFloat
}

@Observable
final class NotchModel {
    var notch: NotchMetrics = .simulated

    private(set) var liveActivity: LiveActivity?
    private(set) var notification: NotchNotification?
    private(set) var peek: QuickPeek?
    private(set) var isExpanded = false
    /// The card the open island shows.
    private(set) var card: IslandCard = .shelf
    /// Cards the island can open to, most relevant first. Set by the coordinator.
    private(set) var cards: [IslandCard] = []

    var isHovering = false
    var isPressed = false
    /// Up next has no events to show yet, only the calendar access prompt (a shorter card).
    var calendarNeedsAccess = false
    /// The shelf holds files (a taller card with the files row).
    var shelfHasFiles = false
    /// A file drag from another app is under way, so the shelf shows its drop targets.
    private(set) var isDraggingFile = false
    /// A second activity while music plays: a meeting about to start, shown as its own drop beside
    /// the island, like the Dynamic Island's detached minimal view.
    private(set) var companion: LiveActivity?
    /// Hidden while a fullscreen app owns the notch screen.
    var isSuppressed = false

    /// Bumped when an expanded island should re-run its content entrance.
    private(set) var expandToken = 0

    @ObservationIgnored private var notificationTask: Task<Void, Never>?
    @ObservationIgnored private var peekTask: Task<Void, Never>?

    var presentation: Presentation {
        if isExpanded { return .expanded }
        if let notification { return .notification(notification) }
        if let peek { return .peek(peek, liveActivity) }
        if let liveActivity { return .activity(liveActivity) }
        return .idle
    }

    // MARK: Layout

    var layout: IslandLayout { layout(for: presentation) }

    func layout(for presentation: Presentation) -> IslandLayout {
        let n = notch.size
        let slot = notch.slot
        switch presentation {
        case .idle:
            return IslandLayout(size: n, topRadius: 6, bottomRadius: notch.isHardware ? 10 : 9)
        case .activity(let activity):
            // Glyphs sit snug against the notch; a countdown needs a little more room than a glyph.
            let side: CGFloat = if case .calendar = activity { slot + 18 } else { slot }
            return IslandLayout(size: CGSize(width: n.width + side * 2, height: n.height), topRadius: 6, bottomRadius: 11)
        case .peek:
            return IslandLayout(size: CGSize(width: max(n.width + slot * 2, 300), height: n.height + 36), topRadius: 8, bottomRadius: 20)
        case .notification(let note):
            let side: CGFloat
            switch note {
            case .volume, .brightness: side = slot + 52
            case .device: side = slot + 84
            default: side = slot + 64
            }
            return IslandLayout(size: CGSize(width: n.width + side * 2, height: n.height), topRadius: 6, bottomRadius: 11)
        case .expanded:
            // Every card is as wide as the next, so switching cards only changes the height.
            // The ears are outside the card's body, which is `cardWidth` wide.
            return IslandLayout(size: CGSize(width: Self.cardWidth + Self.cardEar * 2, height: n.height + cardBody),
                                topRadius: Self.cardEar, bottomRadius: 30)
        }
    }

    /// Height of the open card below the notch line.
    private var cardBody: CGFloat {
        switch card {
        case .nowPlaying: 124
        case .meeting: 104
        case .upNext: calendarNeedsAccess ? 88 : 164
        case .shelf: shelfHasFiles && !isDraggingFile ? 112 : 96
        }
    }

    /// Width of an open card's body: the notch plus a wing either side wide enough for artwork.
    static let cardWidth: CGFloat = 360
    static let cardEar: CGFloat = 12
    /// The tallest card body (Up next); the panel is sized for it.
    static let tallestCardBody: CGFloat = 164

    /// The biggest island the panel must hold, with room for its shadow and the meeting drop beside it.
    var maximumSize: CGSize {
        let widest = max(Self.cardWidth + Self.cardEar * 2, notch.size.width + (notch.slot + 84) * 2)
        return CGSize(width: widest + 120, height: notch.size.height + Self.tallestCardBody + 40)
    }

    // MARK: Live activity

    func setLiveActivity(_ activity: LiveActivity?) {
        guard activity != liveActivity else { return }
        let animation = activity == nil ? Motion.activityOut : Motion.activityIn
        withAnimation(animation) { liveActivity = activity }
    }

    func setCompanion(_ activity: LiveActivity?) {
        guard activity != companion else { return }
        withAnimation(activity == nil ? Motion.activityOut : Motion.activityIn) { companion = activity }
    }

    /// The drop shows only beside the closed island playing music, never under a notification or an open card.
    var showsCompanion: Bool { companion != nil && presentation == .activity(.nowPlaying) }

    /// Space between the island's ear and the drop's, at the top edge.
    static let companionGap: CGFloat = 4
    static let companionEar: CGFloat = 4

    /// The drop's frame, ears included: as wide as the notch is tall, so its bottom is round.
    var companionSize: CGSize {
        CGSize(width: notch.size.height + Self.companionEar * 2, height: notch.size.height)
    }

    // MARK: Notifications

    /// Notifications also show while expanded, in the strip beside the notch.
    func post(_ note: NotchNotification, for duration: Duration = .seconds(2.2)) {
        let sameKind = notification?.kind == note.kind
        withAnimation(sameKind ? Motion.level : Motion.notificationIn) { notification = note }
        notificationTask?.cancel()
        notificationTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.dismissNotification()
        }
    }

    func dismissNotification() {
        notificationTask?.cancel()
        guard notification != nil else { return }
        withAnimation(Motion.notificationOut) { notification = nil }
    }

    // MARK: Quick peek

    func showPeek(_ peek: QuickPeek, for duration: Duration? = .seconds(3.2)) {
        guard !isExpanded else { return }
        peekTask?.cancel()
        if self.peek != peek {
            withAnimation(Motion.peekIn) { self.peek = peek }
        }
        guard let duration else { return }
        peekTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled, let self, !self.isHovering else { return }
            self.hidePeek()
        }
    }

    func hidePeek() {
        peekTask?.cancel()
        guard peek != nil else { return }
        withAnimation(Motion.peekOut) { peek = nil }
    }

    // MARK: Expand

    /// Opens the island on the most relevant card, or on a given one (a file drag opens the shelf).
    func expand(card target: IslandCard? = nil) {
        guard let next = target ?? cards.first else { return }
        guard !isExpanded else {
            show(next)
            return
        }
        peekTask?.cancel()
        expandToken &+= 1
        withAnimation(Motion.expand) {
            card = next
            isExpanded = true
            peek = nil
        }
        Haptics.tap()
    }

    func show(_ target: IslandCard) {
        guard target != card else { return }
        withAnimation(Motion.expand) { card = target }
    }

    /// A sideways swipe or a page dot: the next or previous card, stopping at either end.
    func page(_ step: Int) {
        guard isExpanded, let index = cards.firstIndex(of: card), cards.indices.contains(index + step) else { return }
        show(cards[index + step])
        Haptics.tap()
    }

    func setDraggingFile(_ dragging: Bool) {
        guard dragging != isDraggingFile else { return }
        withAnimation(isExpanded ? Motion.expand : nil) { isDraggingFile = dragging }
    }

    /// Keeps an open island on a card that still exists: a track ending moves it to the next one.
    func setCards(_ available: [IslandCard]) {
        guard available != cards else { return }
        withAnimation(isExpanded ? Motion.expand : nil) {
            cards = available
            guard isExpanded, !available.contains(card) else { return }
            if let first = available.first { card = first } else { isExpanded = false }
        }
    }

    func collapse() {
        guard isExpanded else { return }
        withAnimation(Motion.collapse) { isExpanded = false }
    }

    // MARK: Pointer

    func setHovering(_ hovering: Bool) {
        guard hovering != isHovering else { return }
        withAnimation(hovering ? Motion.hoverIn : Motion.hoverOut) { isHovering = hovering }
    }

    func setPressed(_ pressed: Bool) {
        guard pressed != isPressed else { return }
        withAnimation(Motion.press) { isPressed = pressed }
    }
}
