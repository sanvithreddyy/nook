import SwiftUI

/// The open island, one page at a time: home pages of modules side by side, or a card that stands
/// on its own (a meeting, a timer, the shelf). Takes the page from the island rather than reading the
/// model, so it always redraws with the island (see TopRow).
struct ExpandedView: View {
    @Environment(CalendarModel.self) private var calendar
    @Environment(DeviceBatteries.self) private var batteries
    @Environment(ShortcutsModel.self) private var shortcuts
    @Environment(WeatherModel.self) private var weather
    @Environment(RemindersModel.self) private var reminders
    @Environment(NotchModel.self) private var model
    let card: IslandCard
    let direction: PageDirection
    /// The other pages, built once the island has opened and kept while it's open, so a swipe only moves
    /// pages that are already there: building one as the fingers start, or again as it lands, cost the
    /// main thread 17-48 ms each time, a visible catch. A turn by the dots builds them afresh, so the
    /// pages arrive and leave as `cardTurn`.
    @State private var kept: Set<PageKey> = []

    var body: some View {
        // Mid-swipe the page rides on the fingers with the next one beside it, a page's width away and
        // coming up from a little faded as it arrives; let go, it settles. Drawn each frame meanwhile.
        TimelineView(.animation(paused: model.pageSettle == nil && !model.isDraggingPage)) { context in
            let drag = model.pageSettle?.offset(at: context.date) ?? model.pageDrag
            let width = model.layout(for: .expanded).size.width
            let travelled = width > 0 ? min(abs(drag) / width, 1) : 0
            let neighbor = drag != 0 ? model.neighbor(forDrag: drag) : nil
            let turn = model.pageTurns
            ZStack(alignment: .top) {
                ForEach(model.cards.map { PageKey(card: $0, turn: turn) }.filter { $0.card == card || $0.card == neighbor || kept.contains($0) }, id: \.self) { key in
                    page(key.card)
                        // Set as a page lands, while nothing moves: it reaches every view on the page.
                        .environment(\.isPageShowing, key.card == card)
                        .modifier(key.card == card ? PageSlot.current(drag: drag, travelled: travelled)
                            : key.card == neighbor ? .arriving(at: drag + (drag < 0 ? width : -width), travelled: travelled)
                            : .waiting)
                        .transition(.cardTurn(direction))
                }
                // One place on every page, so they hold still as the pages turn under them.
                PageDots(drag: drag)
                    .padding(.horizontal, NotchModel.cardEar + HomeMetrics.inset * model.home.scale)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Built while nothing moves: after the island has opened, and after a page turns, comes or goes;
        // not under a swipe or a drag (the scrubber).
        .task(id: PageKeep(cards: model.cards, turn: model.pageTurns)) {
            try? await Task.sleep(for: .seconds(0.9))
            let turn = model.pageTurns
            if kept.contains(where: { $0.turn != turn }) { kept = kept.filter { $0.turn == turn } }
            for page in model.cards.map({ PageKey(card: $0, turn: turn) }) where !kept.contains(page) {
                while !Task.isCancelled, model.pageDrag != 0 || model.pageSettle != nil || NSEvent.pressedMouseButtons != 0 {
                    try? await Task.sleep(for: .milliseconds(100))
                }
                guard !Task.isCancelled else { return }
                kept.insert(page)
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
        // Right-click anywhere on the card, not only on what's drawn.
        .contentShape(Rectangle())
        .contextMenu {
            TimerMenu()
            Divider()
            if !card.modules.isEmpty {
                Button("Edit Home…") {
                    SettingsWindowController.shared.show(pane: .home)
                    IslandPreview.shared.isOn = true
                }
            }
            AppMenuItems(pane: card.settingsPane)
        }
        .onAppear {
            // Calendar access granted in System Settings shows up the next time the island opens,
            // whichever card it opens on, and Reminders access too; device batteries, shortcuts and a
            // stale forecast are read fresh each time it opens.
            calendar.recheckAuthorization()
            reminders.recheckAuthorization()
            batteries.refresh()
            shortcuts.refresh()
            weather.refresh()
        }
    }

    /// A page, inside the island's ears and its own inset from the edge.
    private func page(_ card: IslandCard) -> some View {
        Group {
            switch card {
            case .home(let modules): HomePage(modules: modules)
            case .meeting(let id): MeetingCard(eventID: id)
            case .timer: TimerCard()
            case .shelf: ShelfPage()
            }
        }
        .padding(.horizontal, NotchModel.cardEar + inset(card))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// Home pages and the shelf keep 20 pt from the edge; the meeting and timer cards keep 16.
    private func inset(_ card: IslandCard) -> CGFloat {
        switch card {
        case .home: HomeMetrics.inset * model.home.scale
        case .shelf: ShelfMetrics.inset
        case .meeting, .timer: Card.inset
        }
    }
}

/// A page as built for one turn of the island's pages.
private struct PageKey: Hashable {
    let card: IslandCard
    let turn: Int
}

/// What the kept pages are built for; when it changes, they're built again.
private struct PageKeep: Equatable {
    let cards: [IslandCard]
    let turn: Int
}

/// Where a page is drawn: the one showing, riding on the fingers mid-swipe; the one a swipe brings in
/// beside it; or one kept out of sight. One chain of modifiers for all three, so a page keeps its views as
/// it moves between them.
private enum PageSlot: ViewModifier {
    case current(drag: CGFloat, travelled: CGFloat)
    case arriving(at: CGFloat, travelled: CGFloat)
    case waiting

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .opacity(opacity)
            .allowsHitTesting(isCurrent)
            .accessibilityHidden(!isCurrent)
    }

    private var isCurrent: Bool {
        if case .current = self { true } else { false }
    }

    private var offset: CGFloat {
        switch self {
        case .current(let drag, _): drag
        case .arriving(let x, _): x
        case .waiting: 0
        }
    }

    private var opacity: Double {
        switch self {
        case .current(_, let travelled): 1 - 0.4 * travelled
        case .arriving(_, let travelled): 0.6 + 0.4 * travelled
        case .waiting: 0
        }
    }
}

/// Spacing shared by the meeting and timer cards.
enum Card {
    static let inset: CGFloat = 16
    /// Space between the notch line and the title under it.
    static let titleGap: CGFloat = 4
}

/// One dot per card in the wing right of the notch, when there's more than one card.
/// Swiping sideways does the same; the dots show there's somewhere to go.
private struct PageDots: View {
    @Environment(NotchModel.self) private var model
    /// Where a swipe has the page.
    var drag: CGFloat = 0

    var body: some View {
        if model.cards.count > 1 {
            // Past halfway through a swipe, the dot moves to the page arriving.
            let width = model.layout(for: .expanded).size.width
            let current = abs(drag) > width / 2 ? model.neighbor(forDrag: drag) ?? model.card : model.card
            HStack(spacing: 0) {
                ForEach(model.cards, id: \.self) { card in
                    Button { model.show(card) } label: {
                        Circle()
                            .fill(.white.opacity(card == current ? 0.9 : 0.28))
                            .frame(width: 5, height: 5)
                            .frame(width: 13, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(card.name)
                    .accessibilityAddTraits(card == model.card ? .isSelected : [])
                }
            }
            .padding(.trailing, -4)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .frame(height: model.notch.size.height)
            .animation(.easeOut(duration: 0.2), value: model.card)
        }
    }
}

/// Opens Settings on the page for what was right-clicked.
/// The end of every right-click menu on the island: Settings… for the page clicked, then Quit Nook,
/// which is the way out when the menu bar icon is hidden.
struct AppMenuItems: View {
    var pane: SettingsPane?

    var body: some View {
        Button("Settings…") { SettingsWindowController.shared.show(pane: pane) }
        Divider()
        Button("Quit Nook") { NSApp.terminate(nil) }
    }
}

extension IslandCard {
    var settingsPane: SettingsPane {
        switch self {
        case .home: .home
        case .meeting: .calendar
        case .timer: .timer
        case .shelf: .shelf
        }
    }
}

extension NotchModel {
    /// The settings page for what the closed island shows.
    var settingsPane: SettingsPane {
        if let notification {
            switch notification {
            case .volume, .brightness: return .huds
            case .charging, .onBattery, .lowBattery, .lowPowerMode: return .battery
            case .device, .audioSwitched: return .connectivity
            }
        }
        switch liveActivity {
        case .nowPlaying: return .nowPlaying
        case .locked, .unlocked: return .lock
        case .calendar: return .calendar
        case .timer: return .timer
        case .converting: return .converter
        case nil: return .general
        }
    }
}

extension IslandCard {
    var name: String {
        switch self {
        case .home(let modules): modules.map(\.title).formatted(.list(type: .and))
        case .meeting: "Meeting"
        case .timer: "Timer"
        case .shelf: "Shelf"
        }
    }
}

/// Full-width capsule button for a card's actions, coloured as the AirDrop request's Decline and Accept:
/// grey with white type, and the accent at 42% with light blue type (measured from Apple's image).
struct CardButton: View {
    enum Style { case primary, secondary }

    let title: String
    var style: Style = .secondary
    let action: () -> Void

    init(_ title: String, style: Style = .secondary, action: @escaping () -> Void) {
        self.title = title
        self.style = style
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13.5, weight: .semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
        }
        .buttonStyle(CardButtonStyle(style: style))
    }
}

struct CardButtonStyle: ButtonStyle {
    let style: CardButton.Style
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(style == .primary ? Color(red: 0.36, green: 0.78, blue: 1) : .white)
            .background(Capsule().fill(fill(pressed: configuration.isPressed)))
            .contentShape(Capsule())
            .animation(ButtonFeedback.press, value: configuration.isPressed)
            .animation(ButtonFeedback.hover(hovering), value: hovering)
            .onHover { hovering = $0 }
    }

    private func fill(pressed: Bool) -> Color {
        switch style {
        case .primary: Color(nsColor: .systemBlue).opacity(pressed ? 0.34 : (hovering ? 0.5 : 0.42))
        case .secondary: .white.opacity(pressed ? 0.3 : (hovering ? 0.42 : 0.37))
        }
    }
}
