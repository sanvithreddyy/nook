import SwiftUI

struct NotchRootView: View {
    @Environment(NotchModel.self) private var model

    var body: some View {
        IslandView()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .opacity(model.isSuppressed ? 0 : 1)
            .animation(.easeOut(duration: 0.2), value: model.isSuppressed)
            .preferredColorScheme(.dark)
    }
}

private struct IslandView: View {
    @Environment(NotchModel.self) private var model
    @Environment(ShelfModel.self) private var shelf
    @AppStorage(Prefs.peekOnHover) private var peekOnHover = true
    @AppStorage(Prefs.expandOnHover) private var expandOnHover = true

    var body: some View {
        let layout = model.layout
        let shape = NotchShape(topRadius: layout.topRadius, bottomRadius: layout.bottomRadius)

        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                TopRow(layout: layout, notch: model.notch.size, activity: model.liveActivity,
                       notification: model.notification, isExpanded: model.isExpanded)
                if let peek = model.peek, !model.isExpanded {
                    PeekRow(peek: peek)
                        .transition(.islandBody)
                }
                if !model.isExpanded, let note = model.notification, let level = note.hudLevel {
                    HUDLedge(level: level.value, muted: level.muted, bump: model.hudBump, bumpUp: model.hudBumpUp)
                        .padding(.horizontal, layout.topRadius + 12)
                        .padding(.top, 5)
                        .transition(.islandBody)
                }
            }
            // An open card spans the whole island, the strip beside the notch included,
            // the way Apple's expanded views use the space beside the camera.
            if model.isExpanded {
                ExpandedView(card: model.card, showsDropTargets: model.isDraggingFile || !model.shelfHasFiles)
                    .id(model.expandToken)
                    .transition(.islandBody)
            }
        }
        .frame(width: layout.size.width, height: layout.size.height, alignment: .top)
        .background(shape.fill(LiquidSplit.fill))
        .clipShape(shape)
        .background(alignment: .top) { Shadow(shape: shape, visible: model.presentation != .idle) }
        .scaleEffect(scale, anchor: .top)
        .contentShape(shape)
        .onTapGesture { if !model.isExpanded { model.expand() } }
        // Right-click the closed island too; the open card has its own menu.
        .contextMenu {
            TimerMenu()
            Divider()
            SettingsMenuItem()
        }
        // The whole island takes drops for the shelf (the AirDrop tile inside takes its own),
        // so letting go right at the notch works too.
        .onDrop(of: shelfDropTypes, isTargeted: shelfTargeted) { providers in
            guard Prefs.bool(Prefs.shelf) else { return false }
            shelf.add(providers)
            model.setDraggingFile(false)
            model.expand(card: .shelf)
            return true
        }
        .simultaneousGesture(pressGesture)
        // After the island's own gestures, so a click on the drop opens it, not the island. Placed by
        // layout (a spacer the island's width) rather than an offset: the liquid split transition wraps
        // the drop, and its liquid has to share the drop's frame.
        .overlay(alignment: .topLeading) {
            HStack(alignment: .top, spacing: 0) {
                Color.clear.frame(width: layout.size.width + NotchModel.companionGap, height: 1)
                if model.showsCompanion, let companion = model.companion {
                    CompanionDrop(activity: companion)
                        .transition(.liquidSplit(size: model.companionSize))
                }
            }
        }
        // One side can hold more than the other; the notch stays covered either way.
        .offset(x: layout.shift)
    }

    private var shelfTargeted: Binding<Bool> {
        Binding(get: { shelf.isTargeted }, set: { shelf.isTargeted = $0 })
    }

    private var scale: CGFloat {
        guard !model.isExpanded else { return 1 }
        var scale: CGFloat = 1
        // A hover that is about to open the island or the track peek grows into it instead of bumping first.
        let hoverOpens = expandOnHover || (peekOnHover && model.liveActivity == .nowPlaying && model.notification == nil)
        if model.isHovering, model.peek == nil, !hoverOpens { scale *= 1.045 }
        if model.isPressed { scale *= 0.96 }
        return scale
    }

    private var pressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in if !model.isExpanded { model.setPressed(true) } }
            .onEnded { _ in model.setPressed(false) }
    }
}

/// Soft shadow under an open island so it lifts off bright wallpapers.
private struct Shadow: View {
    let shape: NotchShape
    let visible: Bool

    var body: some View {
        shape
            .fill(.black)
            .shadow(color: .black.opacity(visible ? 0.35 : 0), radius: 14, y: 4)
            .animation(.easeOut(duration: 0.25), value: visible)
    }
}

// MARK: Top row

/// The strip beside the hardware notch: live activity or notification content in two side slots.
/// Takes what it shows from the island rather than reading the model itself, so it redraws
/// whenever the island does (it once kept showing a track after a meeting took over).
private struct TopRow: View {
    let layout: IslandLayout
    let notch: CGSize
    let activity: LiveActivity?
    let notification: NotchNotification?
    let isExpanded: Bool

    var body: some View {
        let half = max(0, (layout.size.width - notch.width) / 2)
        HStack(spacing: 0) {
            ZStack { content(.leading) }
                .frame(width: max(0, half - layout.shift), height: notch.height)
            Spacer(minLength: 0)
            ZStack { content(.trailing) }
                .frame(width: max(0, half + layout.shift), height: notch.height)
        }
        .frame(height: notch.height)
    }

    // The open card owns the strip beside the notch, so nothing shows here while it's open;
    // a notification that arrives meanwhile shows if it's still current when the card closes.
    @ViewBuilder private func content(_ edge: HorizontalEdge) -> some View {
        if isExpanded {
            EmptyView()
        } else if let notification {
            NotificationSide(note: notification, edge: edge)
                .id("n-\(notification.kind)")
                .transition(.islandSide(edge))
        } else if let activity {
            ActivitySide(activity: activity, edge: edge)
                .id("a-\(activity.identity)")
                .transition(.islandSide(edge))
        }
    }
}

private struct ActivitySide: View {
    let activity: LiveActivity
    let edge: HorizontalEdge

    var body: some View {
        switch activity {
        case .nowPlaying:
            if edge == .leading { NowPlayingArtworkThumb() } else { NowPlayingWaveformSlot() }
        case .locked, .unlocked:
            if edge == .leading { LockGlyph(unlocked: activity == .unlocked) }
        case .calendar(let id):
            CalendarActivitySide(eventID: id, edge: edge)
        case .timer:
            TimerActivitySide(edge: edge)
        }
    }
}

// MARK: Peek

private struct PeekRow: View {
    let peek: QuickPeek

    var body: some View {
        Group {
            switch peek {
            case .track: TrackPeek()
            case .event(let id): EventPeek(eventID: id)
            }
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 4)
    }
}
