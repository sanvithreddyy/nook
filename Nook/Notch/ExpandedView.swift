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

/// Player on the left, the week on the right.
private struct HomeView: View {
    @Environment(NotchModel.self) private var model

    var body: some View {
        HStack(spacing: 0) {
            ExpandedPlayer()
                .frame(width: model.showsCalendarColumn ? 256 : nil)
                .frame(maxWidth: model.showsCalendarColumn ? nil : .infinity)
            if model.showsCalendarColumn {
                Rectangle()
                    .fill(.white.opacity(0.08))
                    .frame(width: 1)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 2)
                CalendarColumn()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// MARK: Header beside the notch

/// Tab switcher shown left of the notch while expanded.
struct ExpandedTabs: View {
    @Environment(NotchModel.self) private var model
    @Environment(ShelfModel.self) private var shelf

    var body: some View {
        HStack(spacing: 2) {
            TabButton(symbol: "house.fill", tab: .home)
            TabButton(symbol: "tray.fill", tab: .shelf, count: shelf.items.count)
        }
        .padding(2)
        .background(Capsule().fill(.white.opacity(0.06)))
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
            .foregroundStyle(.white.opacity(selected ? 1 : 0.45))
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(Capsule().fill(.white.opacity(selected ? 0.14 : 0)))
            .contentShape(Capsule())
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
