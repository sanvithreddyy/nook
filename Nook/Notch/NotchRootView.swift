import SwiftUI

struct NotchRootView: View {
    @Environment(NotchModel.self) private var model

    var body: some View {
        IslandView()
            .padding(.top, model.notch.topInset)
            .frame(width: model.panelSize.width, height: model.panelSize.height, alignment: .top)
            .opacity(model.isSuppressed || isHiddenIdle ? 0 : 1)
            .animation(.easeOut(duration: 0.2), value: model.isSuppressed)
            .preferredColorScheme(.dark)
            .animation(.easeOut(duration: 0.2), value: isHiddenIdle)
    }

    /// Hidden on a screen without a notch: nothing shows until there's something to, or the pointer is there.
    private var isHiddenIdle: Bool {
        model.notch.hidesWhenIdle && model.settledPresentation == .idle && !model.isHovering
    }
}

private struct IslandView: View {
    @Environment(NotchModel.self) private var model
    /// Shared elements (the artwork) move between the closed island and the open card.
    @Namespace private var shared
    @Environment(ShelfModel.self) private var shelf
    @AppStorage(Prefs.islandShadow) private var shadow = true
    @AppStorage(Prefs.islandOutline) private var outline = false

    var body: some View {
        let layout = model.layout
        let shape = NotchShape(topRadius: layout.topRadius, bottomRadius: layout.bottomRadius, pill: model.notch.isPill)
        // Between two kinds of closed content the band shows nothing while it rests at the notch.
        let closed = !model.isExpanded && !model.isHandingOff

        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                TopRow(layout: layout, notch: model.notch.size, activity: model.liveActivity,
                       notification: model.notification, isHidden: !closed)
                // A notice takes the band's place; the peek comes back under it once the notice goes.
                if let peek = model.peek, closed, model.notification == nil {
                    PeekRow(peek: peek)
                        .transition(.islandBody)
                }
                if closed, let note = model.notification, note.isHUD {
                    HUDBelow(note: note, style: model.hudStyle, bump: model.hudBump, bumpUp: model.hudBumpUp)
                        // The slider's band runs edge to edge, the island's own bottom rounding it.
                        .padding(.horizontal, layout.topRadius + (model.hudStyle == .slider ? 0 : 12))
                        .transition(.hudBelow(toNotch: model.liveActivity == nil))
                }
            }
            // Outline: the island's own edge fills with the level.
            if closed, model.hudStyle == .outline, let level = model.notification?.hudLevel {
                HUDOutline(level: level.value, muted: level.muted, layout: layout)
                    .frame(width: layout.size.width, height: layout.size.height)
                    .transition(.opacity)
            }
            // An open card spans the whole island, the strip beside the notch included,
            // the way Apple's expanded views use the space beside the camera.
            if model.isExpanded {
                ExpandedView(card: model.card, direction: model.pageDirection)
                    .id(model.expandToken)
                    .transition(.islandBody)
            }
        }
        .frame(width: layout.size.width, height: layout.size.height, alignment: .top)
        .environment(\.islandNamespace, shared)
        .background(shape.fill(LiquidSplit.fill))
        .clipShape(shape)
        .overlay { if outline { EdgeOutline(shape: shape, alongTop: model.notch.isPill) } }
        // Only what hangs below the menu bar casts a shadow; compact views sit in it.
        .background(alignment: .top) { Shadow(shape: shape, visible: shadow && (model.isExpanded || (closed && model.peek != nil && model.notification == nil))) }
        .contentShape(shape)
        .onTapGesture { if !model.isExpanded { model.expand() } }
        // Right-click the closed island too; the open card has its own menu.
        .contextMenu {
            TimerMenu()
            Divider()
            AppMenuItems(pane: model.settingsPane)
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
        // After the island's own gestures, so a click on the drop opens it, not the island. Placed by
        // layout (a spacer the island's width) rather than an offset: the liquid split transition wraps
        // the drop, and its liquid has to share the drop's frame.
        .overlay(alignment: .topLeading) {
            HStack(alignment: .top, spacing: 0) {
                Color.clear.frame(width: layout.size.width + NotchModel.companionGap, height: 1)
                if model.showsCompanion, let companion = model.companion {
                    CompanionDrop(activity: companion)
                        .transition(.liquidSplit(size: model.companionSize, pill: model.notch.isPill))
                }
            }
        }
        // One side can hold more than the other; the notch stays covered either way.
        .offset(x: layout.shift)
    }

    private var shelfTargeted: Binding<Bool> {
        Binding(get: { shelf.isTargeted }, set: { shelf.isTargeted = $0 })
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
    /// The open card owns the strip, or the band is handing over between two kinds of content.
    let isHidden: Bool

    var body: some View {
        let half = max(0, (layout.size.width - notch.width) / 2)
        // Each side holds to the island's outer edge: content wider than a narrowing slot runs on under
        // the notch, the way it leaves, rather than past the island's edge.
        HStack(spacing: 0) {
            ZStack(alignment: .leading) { content(.leading) }
                .frame(width: max(0, half - layout.shift), height: notch.height, alignment: .leading)
            Spacer(minLength: 0)
            ZStack(alignment: .trailing) { content(.trailing) }
                .frame(width: max(0, half + layout.shift), height: notch.height, alignment: .trailing)
        }
        .frame(height: notch.height)
    }

    private func slotWidth(_ edge: HorizontalEdge) -> CGFloat {
        let half = max(0, (layout.size.width - notch.width) / 2)
        return max(0, edge == .leading ? half - layout.shift : half + layout.shift)
    }

    // The open card owns the strip beside the notch, so nothing shows here while it's open;
    // a notification that arrives meanwhile shows if it's still current when the card closes.
    @ViewBuilder private func content(_ edge: HorizontalEdge) -> some View {
        if isHidden {
            EmptyView()
        } else if let notification {
            NotificationSide(note: notification, edge: edge)
                .id("n-\(notification.kind)")
                .transition(notification.isHUD ? .hudSide(edge, toNotch: activity == nil, travel: slotWidth(edge)) : .islandSide(edge))
        } else if let activity {
            ActivitySide(activity: activity, edge: edge)
                .id("a-\(activity.identity)")
                .transition(.islandSide(edge))
        }
    }
}

private struct ActivitySide: View {
    @Environment(NotchModel.self) private var model
    let activity: LiveActivity
    let edge: HorizontalEdge

    var body: some View {
        let height = model.notch.size.height
        switch activity {
        case .nowPlaying:
            Group {
                if edge == .leading { NowPlayingArtworkThumb() } else { NowPlayingWaveformSlot() }
            }
            .concentric(edge, height: height)
        case .locked, .unlocked:
            if edge == .leading { LockGlyph(unlocked: activity == .unlocked).concentric(.leading, height: height) }
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

/// The island's hairline edge, for the outline setting: not along the top, which is the screen's own
/// edge, unless it's a pill floating below it.
struct EdgeOutline: View {
    let shape: NotchShape
    var alongTop = false

    var body: some View {
        shape.stroke(.white.opacity(0.22), lineWidth: 1)
            .mask {
                VStack(spacing: 0) {
                    Color.clear.frame(height: alongTop ? 0 : 1)
                    Rectangle()
                }
            }
    }
}
