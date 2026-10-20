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
    @AppStorage(Prefs.peekOnHover) private var peekOnHover = true

    var body: some View {
        let layout = model.layout
        let shape = NotchShape(topRadius: layout.topRadius, bottomRadius: layout.bottomRadius)

        VStack(spacing: 0) {
            TopRow()
            if model.peek != nil, !model.isExpanded {
                PeekRow()
                    .transition(.islandBody)
            }
            if model.isExpanded {
                ExpandedView()
                    .id(model.expandToken)
                    .transition(.islandBody)
            }
        }
        .frame(width: layout.size.width, height: layout.size.height, alignment: .top)
        .background(shape.fill(.black))
        .clipShape(shape)
        .background(alignment: .top) { Shadow(shape: shape, visible: model.presentation != .idle) }
        .scaleEffect(scale, anchor: .top)
        .contentShape(shape)
        .onTapGesture { if !model.isExpanded { model.expand() } }
        .simultaneousGesture(pressGesture)
    }

    private var scale: CGFloat {
        guard !model.isExpanded else { return 1 }
        var scale: CGFloat = 1
        // A hover that is about to open the track peek grows into it instead of bumping first.
        let hoverPeeks = peekOnHover && model.liveActivity == .nowPlaying && model.notification == nil
        if model.isHovering, model.peek == nil, !hoverPeeks { scale *= 1.045 }
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
private struct TopRow: View {
    @Environment(NotchModel.self) private var model

    var body: some View {
        let layout = model.layout
        let side = max(0, (layout.size.width - model.notch.size.width) / 2)
        HStack(spacing: 0) {
            ZStack { leading }
                .frame(width: side, height: model.notch.size.height)
            Spacer(minLength: 0)
            ZStack { trailing }
                .frame(width: side, height: model.notch.size.height)
        }
        .frame(height: model.notch.size.height)
    }

    @ViewBuilder private var leading: some View {
        if let note = model.notification {
            NotificationSide(note: note, edge: .leading)
                .id("n-\(note.kind)")
                .transition(.islandSide(.leading))
        } else if let activity = model.liveActivity, !model.isExpanded {
            ActivitySide(activity: activity, edge: .leading)
                .id("a-\(activity.identity)")
                .transition(.islandSide(.leading))
        }
    }

    @ViewBuilder private var trailing: some View {
        if let note = model.notification {
            NotificationSide(note: note, edge: .trailing)
                .id("n-\(note.kind)")
                .transition(.islandSide(.trailing))
        } else if let activity = model.liveActivity, !model.isExpanded {
            ActivitySide(activity: activity, edge: .trailing)
                .id("a-\(activity.identity)")
                .transition(.islandSide(.trailing))
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
        }
    }
}

// MARK: Peek

private struct PeekRow: View {
    @Environment(NotchModel.self) private var model

    var body: some View {
        Group {
            switch model.peek {
            case .track: TrackPeek()
            case .event(let id): EventPeek(eventID: id)
            case nil: EmptyView()
            }
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 4)
    }
}
