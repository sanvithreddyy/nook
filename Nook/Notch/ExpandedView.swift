import SwiftUI

/// The open island: one card at a time, as Apple's expanded views are. Each card lays out across
/// the whole island, using the wings beside the notch the way Apple's use the space beside the camera.
/// Takes the card from the island rather than reading the model, so it always redraws with the
/// island (see TopRow).
struct ExpandedView: View {
    @Environment(CalendarModel.self) private var calendar
    let card: IslandCard
    let showsDropTargets: Bool

    var body: some View {
        ZStack(alignment: .top) {
            Group {
                switch card {
                case .nowPlaying: MusicCard()
                case .meeting(let id): MeetingCard(eventID: id)
                case .upNext: UpNextCard()
                case .shelf: ShelfCard(showsDropTargets: showsDropTargets)
                }
            }
            .id(card)
            .transition(.blurReplace)
            PageDots()
        }
        // The body starts inside the ears; content keeps 16 pt from its edge.
        .padding(.horizontal, NotchModel.cardEar + Card.inset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Right-click anywhere on the card, not only on what's drawn.
        .contentShape(Rectangle())
        .contextMenu { SettingsMenuItem() }
        // Calendar access granted in System Settings shows up the next time the island opens,
        // whichever card it opens on.
        .onAppear { calendar.recheckAuthorization() }
    }
}

/// Spacing shared by every card.
enum Card {
    static let inset: CGFloat = 16
    /// Space between the notch line and the title under it.
    static let titleGap: CGFloat = 4
}

/// One dot per card in the wing right of the notch, when there's more than one card.
/// Swiping sideways does the same; the dots show there's somewhere to go.
private struct PageDots: View {
    @Environment(NotchModel.self) private var model

    var body: some View {
        if model.cards.count > 1 {
            HStack(spacing: 0) {
                ForEach(model.cards, id: \.self) { card in
                    Button { model.show(card) } label: {
                        Circle()
                            .fill(.white.opacity(card == model.card ? 0.9 : 0.28))
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

struct SettingsMenuItem: View {
    var body: some View {
        Button("Settings…") { SettingsWindowController.shared.show() }
    }
}

extension IslandCard {
    var name: String {
        switch self {
        case .nowPlaying: "Now Playing"
        case .meeting: "Meeting"
        case .upNext: "Up Next"
        case .shelf: "Shelf"
        }
    }
}

/// Full-width capsule button for a card's actions, like the AirDrop request's Decline and Accept.
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

private struct CardButtonStyle: ButtonStyle {
    let style: CardButton.Style
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(style == .primary ? .black : .white)
            .background(Capsule().fill(fill(pressed: configuration.isPressed)))
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Motion.press, value: configuration.isPressed)
            .animation(.easeOut(duration: 0.15), value: hovering)
            .onHover { hovering = $0 }
    }

    private func fill(pressed: Bool) -> Color {
        switch style {
        case .primary: .white.opacity(pressed ? 0.8 : (hovering ? 0.9 : 1))
        case .secondary: .white.opacity(pressed ? 0.26 : (hovering ? 0.21 : 0.16))
        }
    }
}
