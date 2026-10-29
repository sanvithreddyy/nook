import SwiftUI

/// The second thing going on, in its own drop right of the island, like the Dynamic Island's
/// detached minimal view: a timer's draining ring, or the minutes until a meeting.
/// Pointing at it or clicking it opens its card.
struct CompanionDrop: View {
    @Environment(NotchModel.self) private var model
    let activity: LiveActivity

    var body: some View {
        let size = model.companionSize
        let shape = NotchShape(topRadius: NotchModel.companionEar, bottomRadius: size.height / 2)
        Group {
            switch activity {
            case .calendar(let id): MeetingDropContent(eventID: id)
            case .timer: TimerDropContent()
            case .nowPlaying, .locked, .unlocked: EmptyView()
            }
        }
        .frame(width: size.width, height: size.height)
        .contentShape(shape)
        .onTapGesture { if let card = activity.card { model.expand(card: card) } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// Minutes until the meeting, where there's room for three characters: "5m", "Now".
private struct MeetingDropContent: View {
    @Environment(CalendarModel.self) private var calendar
    let eventID: String

    var body: some View {
        TimelineView(.everyMinute) { context in
            let text = calendar.event(id: eventID).map { EventTiming.minimal($0, now: context.date) } ?? ""
            Text(text)
                .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
                .contentTransition(.numericText(countsDown: true))
                .animation(Motion.level, value: text)
        }
        .accessibilityLabel(calendar.event(id: eventID)?.title ?? "Meeting")
    }
}

// MARK: Liquid split

/// The drop pulls out of the island's round end like liquid: a neck of black stretches between them
/// and snaps, and it flows back the same way when it goes. `progress` runs 0 (inside the island's
/// end) to 1 (settled beside it). The neck is a metaball curve between the two round ends, drawn as
/// a shape so its edges stay crisp.
struct LiquidSplit: ViewModifier, Animatable {
    var progress: CGFloat
    let size: CGSize

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    #if DEBUG
    /// `-debug-liquid` draws the island and the drop in grey, to see their motion against a black menu bar.
    static let fill: Color = CommandLine.arguments.contains("-debug-liquid") ? .gray : .black
    #else
    static let fill = Color.black
    #endif

    func body(content: Content) -> some View {
        let geometry = SplitGeometry(progress: progress, size: size, gap: NotchModel.companionGap,
                                     islandEar: 6, ear: NotchModel.companionEar)
        content
            .opacity(Double(min(max((progress - 0.55) / 0.45, 0), 1)))
            .offset(x: geometry.dropCenter - geometry.restingCenter)
            // These follow `progress` frame by frame; animating them again on top makes them lag.
            .transaction { $0.animation = nil }
            .background(alignment: .topLeading) {
                LiquidShape(geometry: geometry)
                    .fill(Self.fill)
                    .frame(width: size.width, height: size.height)
            }
    }
}

extension AnyTransition {
    /// The drop splitting off the island's right end, and merging back.
    static func liquidSplit(size: CGSize) -> AnyTransition {
        .modifier(active: LiquidSplit(progress: 0, size: size), identity: LiquidSplit(progress: 1, size: size))
            .animation(Motion.ease(.spring(duration: 0.62, bounce: 0.22)))
    }
}

/// Where things are, in the drop's own frame (its ears included, left edge at 0).
nonisolated struct SplitGeometry {
    let radius: CGFloat
    let ear: CGFloat
    /// Centre of the island's round end: its body ends the gap plus the island's ear left of the drop.
    let islandCenter: CGFloat
    let restingCenter: CGFloat
    let dropCenter: CGFloat

    init(progress: CGFloat, size: CGSize, gap: CGFloat, islandEar: CGFloat, ear: CGFloat) {
        radius = size.height / 2
        self.ear = ear
        islandCenter = -gap - islandEar - radius
        restingCenter = size.width / 2
        dropCenter = islandCenter + (restingCenter - islandCenter) * progress
    }
}

nonisolated private struct LiquidShape: Shape {
    let geometry: SplitGeometry

    func path(in rect: CGRect) -> Path {
        let r = geometry.radius
        let ear = geometry.ear
        var path = NotchShape(topRadius: ear, bottomRadius: r)
            .path(in: CGRect(x: geometry.dropCenter - r - ear, y: 0, width: r * 2 + ear * 2, height: rect.height))
        if let neck = Self.neck(from: CGPoint(x: geometry.islandCenter, y: r), CGPoint(x: geometry.dropCenter, y: r), radius: r) {
            path.addPath(neck)
        }
        return path
    }

    /// The bridge between two equal round ends (after Hiroyuki Sato's metaball curves): tangent points
    /// spread as they near each other, and the neck pinches off a little past touching.
    static func neck(from c1: CGPoint, _ c2: CGPoint, radius r: CGFloat) -> Path? {
        let d = hypot(c2.x - c1.x, c2.y - c1.y)
        let reach = r * 2 + 6
        guard d > 0.5, d < reach else { return nil }
        let v: CGFloat = 0.55, handle: CGFloat = 2.4
        let overlap = d < r * 2 ? acos(d / (2 * r)) : 0
        let heading = atan2(c2.y - c1.y, c2.x - c1.x)
        let spread = CGFloat.pi / 2
        let a1 = heading + overlap + (spread - overlap) * v
        let b1 = heading - overlap - (spread - overlap) * v
        let a2 = heading + .pi - overlap - (.pi - overlap - spread) * v
        let b2 = heading - .pi + overlap + (.pi - overlap - spread) * v
        func on(_ c: CGPoint, _ angle: CGFloat) -> CGPoint { CGPoint(x: c.x + r * cos(angle), y: c.y + r * sin(angle)) }
        let p1a = on(c1, a1), p1b = on(c1, b1), p2a = on(c2, a2), p2b = on(c2, b2)
        var length = min(v * handle, hypot(p1a.x - p2a.x, p1a.y - p2a.y) / (r * 2))
        length *= min(1, d * 2 / (r * 2))
        let h = r * length
        func toward(_ p: CGPoint, _ angle: CGFloat) -> CGPoint { CGPoint(x: p.x + h * cos(angle), y: p.y + h * sin(angle)) }
        var neck = Path()
        neck.move(to: p1a)
        neck.addCurve(to: p2a, control1: toward(p1a, a1 - .pi / 2), control2: toward(p2a, a2 + .pi / 2))
        neck.addLine(to: p2b)
        neck.addCurve(to: p1b, control1: toward(p2b, b2 - .pi / 2), control2: toward(p1b, b1 + .pi / 2))
        neck.closeSubpath()
        return neck
    }
}

