import SwiftUI

struct ExpandedView: View {
    @Environment(NotchModel.self) private var model

    var body: some View {
        ZStack {
            switch model.tab {
            case .home:
                HomeView().transition(.tabSwitch)
            case .shelf:
                ShelfView().transition(.tabSwitch)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 6)
        .padding(.bottom, 18)
    }
}

/// The player with what's next beside it; the next event alone when nothing plays; one line when neither has anything.
private struct HomeView: View {
    @Environment(NotchModel.self) private var model
    @Environment(CalendarModel.self) private var calendar

    var body: some View {
        if model.hasPlayer {
            HStack(alignment: .top, spacing: 40) {
                ExpandedPlayer()
                    .frame(width: model.showsAgenda ? 300 : nil)
                    .frame(maxWidth: model.showsAgenda ? nil : .infinity, alignment: .leading)
                if model.showsAgenda {
                    AgendaColumn()
                }
            }
        } else if model.showsAgenda {
            AgendaSpread()
        } else {
            Text(calendar.isEnabled && calendar.isAuthorized ? "Nothing playing · No events this week" : "Nothing playing")
                .font(.system(size: 12.5))
                .foregroundStyle(.white.opacity(0.45))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

// MARK: Header beside the notch

/// Tab switcher shown left of the notch while expanded.
struct ExpandedTabs: View {
    @Environment(NotchModel.self) private var model
    @Environment(ShelfModel.self) private var shelf

    var body: some View {
        HStack(spacing: 4) {
            TabButton(symbol: "house.fill", tab: .home)
            TabButton(symbol: "tray.fill", tab: .shelf, count: shelf.items.count)
        }
        // The first glyph lines up with the content below; its hit area reaches left of it.
        .padding(.leading, -8)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Same inset as the content below, so the capsule lines up with the artwork and tiles.
        .padding(.leading, 22)
    }
}

private struct TabButton: View {
    @Environment(NotchModel.self) private var model
    let symbol: String
    let tab: ExpandedTab
    var count = 0

    var body: some View {
        let selected = model.tab == tab
        Button { model.select(tab) } label: {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                }
            }
            .foregroundStyle(.white.opacity(selected ? 1 : 0.4))
            .padding(.horizontal, 8)
            .frame(height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: selected)
    }
}

/// Actions shown right of the notch while expanded.
struct ExpandedActions: View {
    @Environment(NotchModel.self) private var model
    @Environment(ShelfModel.self) private var shelf

    var body: some View {
        HStack(spacing: 10) {
            if model.tab == .shelf, !shelf.isEmpty {
                Button { withAnimation(Motion.peekOut) { shelf.clear() } } label: {
                    Text("Clear")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
            Button { SettingsWindowController.shared.show() } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(width: 24, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.trailing, 16)
        .animation(.easeOut(duration: 0.15), value: model.tab)
    }
}

private extension AnyTransition {
    static var tabSwitch: AnyTransition {
        .modifier(
            active: IslandContentModifier(opacity: 0, blur: 6, scaleX: 0.98, scaleY: 0.98, anchor: .top),
            identity: IslandContentModifier(opacity: 1, blur: 0, scaleX: 1, scaleY: 1, anchor: .top)
        )
    }
}
