import AppKit
import Testing

/// Two fingers on the open island, as the trackpad sends them. A page springing back is never left
/// part-way when the fingers rest or go up and down, and a sideways swipe picks it up where it is.
@MainActor
struct PageTrackerTests {
    init() { Prefs.registerDefaults() }

    enum Touch: String, CaseIterable {
        /// Fingers come down and lift without moving.
        case rest
        /// A small move up or down, too short to open or close.
        case upDown
        /// Fingers rest a moment, then move up or down.
        case restThenUpDown
    }

    /// CGEvent's phases: began 1, changed 2, ended 4, cancelled 8, may begin 128.
    private func scroll(_ phase: Int64, dx: Int32 = 0, dy: Int32 = 0) -> NSEvent {
        let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0)!
        cg.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
        return NSEvent(cgEvent: cg)!
    }

    /// The island open on its only page, pulled sideways and let go, so the page springs back.
    private func springingBack() async throws -> (NotchModel, PageTracker) {
        let model = NotchModel()
        model.setCards([.home([.music])])
        model.expand()
        let pages = PageTracker()
        _ = pages.consume(scroll(1), model: model)
        for _ in 0..<20 {
            _ = pages.consume(scroll(2, dx: 8), model: model)
            try await Task.sleep(for: .milliseconds(8))
        }
        _ = pages.consume(scroll(4), model: model)
        #expect(model.pageSettle != nil, "the page should be springing back")
        return (model, pages)
    }

    @Test(arguments: Touch.allCases)
    func aTouchWhileThePageSpringsBackLetsItLand(_ touch: Touch) async throws {
        let (model, pages) = try await springingBack()
        try await Task.sleep(for: .milliseconds(80))
        let events: [NSEvent] = switch touch {
        case .rest: [scroll(128), scroll(8)]
        case .upDown: [scroll(1), scroll(2, dy: 4), scroll(2, dy: 4), scroll(2, dy: 4), scroll(4)]
        case .restThenUpDown: [scroll(128), scroll(1), scroll(2, dy: 4), scroll(2, dy: 4), scroll(2, dy: 4), scroll(4)]
        }
        for event in events { _ = pages.consume(event, model: model) }
        try await Task.sleep(for: .seconds(1))
        #expect(model.pageDrag == 0)
        #expect(model.pageSettle == nil)
    }

    @Test func aSidewaysSwipePicksTheSpringingPageUpWhereItIs() async throws {
        let (model, pages) = try await springingBack()
        try await Task.sleep(for: .milliseconds(80))
        let held = try #require(model.pageSettle).offset(at: .now)
        // Fingers rest first, as they usually do, then move the same way a little.
        _ = pages.consume(scroll(128), model: model)
        _ = pages.consume(scroll(1), model: model)
        _ = pages.consume(scroll(2, dx: 8), model: model)
        // Caught near where the spring had it, not back at the start.
        #expect(abs(model.pageDrag - held) < 30, "page at \(model.pageDrag), spring had it at \(held)")
        _ = pages.consume(scroll(4), model: model)
        try await Task.sleep(for: .seconds(1))
        #expect(model.pageDrag == 0)
        #expect(model.pageSettle == nil)
    }

    /// The open island keeps its pages built through a swipe and builds them afresh for a turn by the dots
    /// (`pageTurns`); it draws each frame from the fingers only while they have the page.
    @Test func aSwipeKeepsThePagesBuiltAndTheDotsTurnThem() async throws {
        let model = NotchModel()
        model.setCards([.home([.weather]), .home([.music]), .shelf])
        model.expand()
        let turns = model.pageTurns
        let pages = PageTracker()
        _ = pages.consume(scroll(1), model: model)
        for _ in 0..<20 {
            _ = pages.consume(scroll(2, dx: 12), model: model)
            try await Task.sleep(for: .milliseconds(8))
        }
        #expect(model.isDraggingPage)
        _ = pages.consume(scroll(4), model: model)
        #expect(!model.isDraggingPage)
        try await Task.sleep(for: .seconds(1))
        #expect(model.card == .home([.music]), "the swipe turned to the next page")
        #expect(model.pageTurns == turns, "a swipe landing keeps the pages it has")
        model.page(1)
        #expect(model.card == .shelf)
        #expect(model.pageTurns == turns + 1, "a turn by the dots builds them afresh")

        // A drag whose lift never arrives ends when the island closes, even with the fingers back where
        // they started.
        _ = pages.consume(scroll(1), model: model)
        for dx: Int32 in [-12, -12, -12, 12, 12, 12] { _ = pages.consume(scroll(2, dx: dx), model: model) }
        #expect(model.isDraggingPage)
        #expect(model.pageDrag == 0)
        model.collapse()
        #expect(!model.isDraggingPage)
        #expect(model.pageDrag == 0)
    }
}
