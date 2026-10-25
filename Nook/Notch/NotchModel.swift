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

/// The two pages of the expanded island, switched from the strip beside the notch.
enum ExpandedTab: String {
    case home   // now playing + calendar
    case shelf  // files kept for later, AirDrop
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
    private(set) var tab: ExpandedTab = .home

    var isHovering = false
    var isPressed = false
    /// Calendar is on and has something to show on Home: events still to come, or the access prompt.
    var showsAgenda = false
    /// False when nothing is playing, so the expanded island stays short instead of showing an empty panel.
    var hasPlayer = true
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
        case .activity:
            return IslandLayout(size: CGSize(width: n.width + slot * 2, height: n.height), topRadius: 6, bottomRadius: 11)
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
            // One width for every tab, so the tab buttons never fall outside the island when switching.
            // The height follows what Home shows, so there is never an empty panel.
            let body: CGFloat = switch tab {
            case .shelf: Self.expandedBodyHeight
            case .home where hasPlayer: 146
            case .home where showsAgenda: 128
            case .home: 40
            }
            return IslandLayout(size: CGSize(width: max(n.width + 300, Self.expandedWidth), height: n.height + body),
                                topRadius: 12, bottomRadius: body < 60 ? 22 : 32)
        }
    }

    static let expandedWidth: CGFloat = 660
    /// The tallest page (the shelf); the panel is sized for it.
    static let expandedBodyHeight: CGFloat = 160

    /// The biggest island the panel must hold, with room for its shadow.
    var maximumSize: CGSize {
        CGSize(width: max(notch.size.width + 300, Self.expandedWidth) + 80, height: notch.size.height + Self.expandedBodyHeight + 40)
    }

    // MARK: Live activity

    func setLiveActivity(_ activity: LiveActivity?) {
        guard activity != liveActivity else { return }
        let animation = activity == nil ? Motion.activityOut : Motion.activityIn
        withAnimation(animation) { liveActivity = activity }
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

    /// Opens the island, optionally on a given tab (a file drag opens the shelf).
    func expand(tab target: ExpandedTab? = nil) {
        guard !isExpanded else {
            if let target { select(target) }
            return
        }
        peekTask?.cancel()
        expandToken &+= 1
        withAnimation(Motion.expand) {
            if let target { tab = target }
            isExpanded = true
            peek = nil
        }
        Haptics.tap()
    }

    func select(_ target: ExpandedTab) {
        guard target != tab else { return }
        withAnimation(Motion.expand) { tab = target }
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
