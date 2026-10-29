import AppKit
import SwiftUI

/// Persistent content shown beside the notch.
enum LiveActivity: Equatable {
    case nowPlaying
    case locked
    case unlocked
    case calendar(id: String)
    case timer

    /// Activities with the same identity morph in place (padlock closing → opening) instead of transitioning.
    var identity: String {
        switch self {
        case .nowPlaying: "nowPlaying"
        case .locked, .unlocked: "lock"
        case .calendar(let id): "calendar-\(id)"
        case .timer: "timer"
        }
    }

    /// The card the island opens to for this activity.
    var card: IslandCard? {
        switch self {
        case .nowPlaying: .nowPlaying
        case .calendar(let id): .meeting(id: id)
        case .timer: .timer
        case .locked, .unlocked: nil
        }
    }
}

/// Transient content that replaces the live activity for a few seconds.
enum NotchNotification: Equatable {
    /// `output`: the headphones' symbol when sound goes to AirPods or other Bluetooth headphones.
    case volume(level: Float, muted: Bool, output: String?)
    case brightness(level: Float)
    case charging(level: Int)
    case onBattery(level: Int)
    case lowBattery(level: Int)
    case lowPowerMode(on: Bool)
    case device(name: String, symbol: String, battery: Int?)
    /// Sound moved to these headphones (AirPods' automatic switching, or picked in Control Center).
    case audioSwitched(symbol: String)

    /// Notifications of the same kind update in place instead of transitioning.
    var kind: String {
        switch self {
        case .volume: "volume"
        case .brightness: "brightness"
        case .charging, .onBattery, .lowBattery: "battery"
        case .lowPowerMode: "lowPower"
        case .device(let name, _, _): "device-\(name)"
        case .audioSwitched: "audioSwitched"
        }
    }

    var isHUD: Bool {
        switch self {
        case .volume, .brightness: true
        default: false
        }
    }

    /// Volume and brightness show their level on a ledge under the notch.
    var hudLevel: (value: Float, muted: Bool)? {
        switch self {
        case .volume(let level, let muted, _): (level, muted)
        case .brightness(let level): (level, false)
        default: nil
        }
    }

    /// The words on the leading side, where there are any.
    var title: String {
        switch self {
        case .charging: "Charging"
        case .onBattery: "On Battery"
        case .lowBattery: "Low Battery"
        case .lowPowerMode: "Low Power"
        default: ""
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
    /// A running, paused or finished timer.
    case timer
    /// Files kept for later and AirDrop.
    case shelf

    /// The cards the island can open to, most relevant first, so hovering opens what the closed island
    /// shows. `live`: the cards for what the closed island shows, the island's own activity first, then
    /// the drop beside it. `music`: a track is loaded, playing or paused. A meeting about to start stands
    /// in for Up next, which would only repeat it. The shelf is always last: empty, it's a drop target.
    static func available(live: [IslandCard], music: Bool, agenda: Bool, shelf: Bool) -> [IslandCard] {
        var cards = live
        if music, !cards.contains(.nowPlaying) { cards.append(.nowPlaying) }
        let meeting = cards.contains { if case .meeting = $0 { true } else { false } }
        if agenda, !meeting { cards.append(.upNext) }
        if shelf { cards.append(.shelf) }
        return cards
    }
}

struct IslandLayout: Equatable {
    var size: CGSize
    var topRadius: CGFloat
    var bottomRadius: CGFloat
    /// How far the island's centre sits right of the notch's, when one side holds more than the
    /// other ("Low Battery" left, "20%" right). Apple keeps compact views as narrow as their content.
    var shift: CGFloat = 0
}

/// Measurements of the compact views beside the notch, from macOS 27's compact assets:
/// large semibold text, glyphs concentric with the island's round ends.
enum Compact {
    static let fontSize: CGFloat = 14
    /// The island's top ears sit inside its frame at both ends.
    static let ear: CGFloat = 6
    /// From the island's outer edge to text.
    static let outer: CGFloat = 13
    /// From content to the notch.
    static let inner: CGFloat = 10
    static let battery: CGFloat = 26 + 3.5
    static let bottomRadius: CGFloat = 15

    /// Numbers are drawn with tabular digits, so they're measured that way.
    static func textWidth(_ text: String, digits: Bool = false) -> CGFloat {
        let font = digits ? NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .semibold)
                          : NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        return ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    /// A side holding one line of text.
    static func textSide(_ text: String) -> CGFloat { outer + textWidth(text) + inner }
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
    /// Which way the last card turn went, for the card transition.
    let pageDirection = PageDirection()

    var isHovering = false
    var isPressed = false
    /// Up next has no events to show yet, only the calendar access prompt (a shorter card).
    var calendarNeedsAccess = false
    /// The shelf holds files (a taller card with the files row).
    var shelfHasFiles = false
    /// A file drag from another app is under way, so the shelf shows its drop targets.
    private(set) var isDraggingFile = false
    /// A second activity beside the island's own: a timer or a meeting about to start, shown as its own
    /// drop beside the island, like the Dynamic Island's detached minimal view.
    private(set) var companion: LiveActivity?
    /// A timer of an hour or more needs room for "1:00:00" beside the notch.
    var timerShowsHours = false
    /// How volume and brightness show; from Settings.
    var hudStyle: HUDStyle = .ledge
    /// Counts presses past either end of the volume or brightness range, to stretch the bar.
    private(set) var hudBump = 0
    private(set) var hudBumpUp = true
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
            // Glyphs sit snug against the notch; a countdown needs room for its longest text.
            switch activity {
            case .calendar: return compact(leading: slot, trailing: Compact.inner + Compact.textWidth("00 min", digits: true) + Compact.outer)
            case .timer: return compact(leading: slot, trailing: Compact.inner + Compact.textWidth(timerShowsHours ? "0:00:00" : "00:00", digits: true) + Compact.outer)
            default: return compact(leading: slot, trailing: slot)
            }
        case .peek:
            return IslandLayout(size: CGSize(width: max(n.width + slot * 2, 300), height: n.height + 36), topRadius: 8, bottomRadius: 20)
        case .notification(let note):
            switch note {
            case .volume, .brightness:
                // Glyph and value beside the notch, the level below it (the slider holds the glyph itself).
                let side = hudStyle == .slider ? slot + 13 : slot + 8
                return compact(leading: side, trailing: side, below: hudStyle.below)
            case .charging(let level), .onBattery(let level), .lowBattery(let level):
                return compact(leading: Compact.textSide(note.title),
                               trailing: Compact.inner + Compact.textWidth("\(level)%", digits: true) + 6 + Compact.battery + Compact.outer - 3)
            case .lowPowerMode(let on):
                return compact(leading: Compact.textSide(note.title), trailing: Compact.textSide(on ? "On" : "Off"))
            case .device, .audioSwitched:
                return compact(leading: slot, trailing: slot)
            }
        case .expanded:
            // Every card is as wide as the next, so switching cards only changes the height.
            // The ears are outside the card's body, which is `cardWidth` wide.
            return IslandLayout(size: CGSize(width: Self.cardWidth + Self.cardEar * 2, height: n.height + cardBody),
                                topRadius: Self.cardEar, bottomRadius: 30)
        }
    }

    /// Beside the notch: as narrow as the content on each side, round at the ends like a capsule.
    private func compact(leading: CGFloat, trailing: CGFloat, below: CGFloat = 0) -> IslandLayout {
        IslandLayout(size: CGSize(width: notch.size.width + leading + trailing, height: notch.size.height + below),
                     topRadius: 6, bottomRadius: Compact.bottomRadius, shift: (trailing - leading) / 2)
    }

    /// Height of the open card below the notch line.
    private var cardBody: CGFloat {
        switch card {
        case .nowPlaying: 124
        case .meeting: 104
        case .upNext: calendarNeedsAccess ? 88 : 164
        case .timer: 76
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

    /// The drop shows only beside the closed island's own activity, never under a notification,
    /// a peek or an open card.
    var showsCompanion: Bool {
        guard companion != nil, case .activity = presentation else { return false }
        return true
    }

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

    /// A volume or brightness key pressed with the level already at that end.
    func bumpHUD(up: Bool) {
        hudBumpUp = up
        hudBump &+= 1
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
        if let from = cards.firstIndex(of: card), let to = cards.firstIndex(of: target) {
            pageDirection.forward = to > from
        } else {
            pageDirection.forward = true
        }
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
            pageDirection.forward = true
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
