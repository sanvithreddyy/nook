import CoreGraphics
import Testing

/// Pages run left to right as arranged; the island opens on what the closed island shows.
struct IslandCardTests {
    private func pages(_ groups: [[HomeModule]], shelfAt: Int? = nil) -> [HomeArrangement.Page] {
        var pages = groups.map(HomeArrangement.Page.modules)
        pages.insert(.shelf, at: shelfAt ?? pages.count)
        return pages
    }

    @Test func musicOpensTheHomePageThatHoldsIt() {
        let result = IslandCard.available(live: [.nowPlaying], pages: pages([[.music, .calendar], [.batteries]]), shelf: true)
        #expect(result.cards == [.home([.music, .calendar]), .home([.batteries]), .shelf])
        #expect(result.opening == .home([.music, .calendar]))
    }

    @Test func musicOnALaterPageStillOpensItWithoutMovingIt() {
        let result = IslandCard.available(live: [.nowPlaying], pages: pages([[.calendar, .batteries], [.music]]), shelf: false)
        #expect(result.cards == [.home([.calendar, .batteries]), .home([.music])])
        #expect(result.opening == .home([.music]))
    }

    @Test func aTimerTheNotchShowsComesBeforeTheHomeAndOpens() {
        let result = IslandCard.available(live: [.timer, .nowPlaying], pages: pages([[.music, .calendar], [.batteries]]), shelf: true)
        #expect(result.cards == [.timer, .home([.music, .calendar]), .home([.batteries]), .shelf])
        #expect(result.opening == .timer)
    }

    @Test func theDropBesideTheIslandComesAfterTheHome() {
        let result = IslandCard.available(live: [.nowPlaying, .calendar(id: "m")], pages: pages([[.music, .calendar, .batteries]]), shelf: true)
        #expect(result.cards == [.home([.music, .calendar, .batteries]), .meeting(id: "m"), .shelf])
    }

    /// The shelf first, to swipe to it from the left, or between pages.
    @Test func theShelfGoesWhereItIsPlaced() {
        let first = IslandCard.available(live: [.timer, .nowPlaying], pages: pages([[.music, .calendar], [.batteries]], shelfAt: 0), shelf: true)
        #expect(first.cards == [.shelf, .timer, .home([.music, .calendar]), .home([.batteries])])
        #expect(first.opening == .timer)
        let between = IslandCard.available(live: [.nowPlaying], pages: pages([[.music, .calendar], [.batteries]], shelfAt: 1), shelf: true)
        #expect(between.cards == [.home([.music, .calendar]), .shelf, .home([.batteries])])
        #expect(between.opening == .home([.music, .calendar]))
    }

    @Test func nothingGoingOnOpensTheHome() {
        let some = IslandCard.available(live: [], pages: pages([[.calendar, .batteries]], shelfAt: 0), shelf: true)
        #expect(some.cards == [.shelf, .home([.calendar, .batteries])])
        #expect(some.opening == .home([.calendar, .batteries]))
        #expect(IslandCard.available(live: [], pages: [.shelf], shelf: true).cards == [.shelf])
        #expect(IslandCard.available(live: [], pages: [.shelf], shelf: false).cards.isEmpty)
    }
}

/// Settings' page arrangement: modules fill pages in order until arranged, a full page carries on in
/// the next, modules that are off take no room, and drags group, swap and move pages.
struct HomeArrangementTests {
    private typealias Page = HomeArrangement.Page

    @Test func untouchedPagesFollowTheOrder() {
        #expect(HomeConfig().arrangement.pages == [.modules([.music, .calendar]), .modules([.batteries, .weather]),
                                                  .modules([.reminders, .clock]), .modules([.shortcuts, .timer]), .shelf])
        #expect(HomeConfig(layout: .oneAtATime).arrangement.pages.prefix(2) == [.modules([.music]), .modules([.calendar])])
    }

    @Test func aFullPageCarriesOnAndOffModulesTakeNoRoom() {
        let three = HomeArrangement(pages: [.modules([.music, .calendar, .batteries])])
        #expect(three.normalized(hidden: [], perPage: 2).pages.prefix(2) == [.modules([.music, .calendar]), .modules([.batteries])])
        #expect(three.normalized(hidden: [.calendar], perPage: 2).pages.first == .modules([.music, .calendar, .batteries]))
    }

    @Test func savedPagesRoundTripAndPickUpNewModules() {
        let saved = HomeArrangement.parse("shelf|music,calendar|stocks")
        #expect(saved?.pages == [.shelf, .modules([.music, .calendar])])
        #expect(saved?.string == "shelf|music,calendar")
        let completed = saved?.normalized(hidden: [], perPage: 2).pages ?? []
        #expect(completed.first == .shelf)
        #expect(completed.count == 2 + HomeModule.allCases.count - 2)
        #expect(HomeArrangement.parse("") == nil)
    }

    @Test func droppingOnAFullPageSwapsAndOnARoomyOneJoins() {
        let start = HomeArrangement(pages: [.modules([.music, .calendar]), .modules([.batteries, .weather]), .shelf])
        var swapped = start
        swapped.move(.batteries, onto: .music, hidden: [], perPage: 2)
        #expect(swapped.pages == [.modules([.batteries, .calendar]), .modules([.music, .weather]), .shelf])
        var joined = start
        joined.move(.batteries, onto: .music, hidden: [], perPage: 3)
        #expect(joined.pages == [.modules([.batteries, .music, .calendar]), .modules([.weather]), .shelf])
        var reordered = start
        reordered.move(.music, onto: .calendar, hidden: [], perPage: 2)
        #expect(reordered.pages.first == .modules([.calendar, .music]))
    }

    @Test func pagesMoveAndModulesGetPagesOfTheirOwn() {
        var arrangement = HomeArrangement(pages: [.modules([.music, .calendar]), .modules([.batteries]), .shelf])
        arrangement.movePage(2, to: 0)
        #expect(arrangement.pages == [.shelf, .modules([.music, .calendar]), .modules([.batteries])])
        arrangement.moveToNewPage(.calendar)
        #expect(arrangement.pages == [.shelf, .modules([.music]), .modules([.batteries]), .modules([.calendar])])
        arrangement.move(.batteries, toPage: 1, hidden: [], perPage: 2)
        #expect(arrangement.pages == [.shelf, .modules([.music, .batteries]), .modules([.calendar])])
        arrangement.movePageToEnd(0)
        #expect(arrangement.pages.last == .shelf)
    }
}

/// The saved order survives modules it doesn't know yet, and the home's size follows its modules.
struct HomeConfigTests {
    @Test func unknownAndMissingModulesAreHandled() {
        #expect(HomeOrder.parse("batteries,stocks,music") == [.batteries, .music])
        #expect(HomeOrder.string([.calendar, .music]) == "calendar,music")
    }

    @Test func aPageIsAsWideAsItsModules() {
        let two = HomeMetrics.pageSize([.music, .calendar], batteries: 0, scale: 1)
        #expect(two.width == CGFloat(20 + 300 + 24 + 320 + 20))
        #expect(two.height == CGFloat(180))
        let large = HomeMetrics.pageSize([.music], batteries: 0, scale: 1.14)
        #expect(abs(large.width - 340 * 1.14) < 0.001)
    }

    /// Four places, as Apple's widget has, empty rings holding the ones not used; a fifth device adds one.
    @Test func batteriesKeepFourPlacesUpToFive() {
        #expect(HomeMetrics.width(.batteries, batteries: 1) == CGFloat(4 * 76))
        #expect(HomeMetrics.width(.batteries, batteries: 4) == CGFloat(4 * 76))
        #expect(HomeMetrics.width(.batteries, batteries: 9) == CGFloat(5 * 76))
    }

    @Test func ownersNamesComeOffDeviceNames() {
        #expect(DeviceBatteries.shortName("Owner’s AirPods Pro") == "AirPods Pro")
        #expect(DeviceBatteries.shortName("Magic Keyboard") == "Magic Keyboard")
    }
}

/// Swipes and page dots move between cards without running off either end,
/// and an open island never shows a card that has gone away.
@MainActor
struct CardPagingTests {
    @Test func pagingStopsAtTheEnds() {
        let model = NotchModel()
        model.setCards([.home([.music, .calendar]), .timer, .shelf])
        model.expand()
        #expect(model.card == .home([.music, .calendar]))
        model.page(-1)
        #expect(model.card == .home([.music, .calendar]))
        model.page(1)
        model.page(1)
        model.page(1)
        #expect(model.card == .shelf)
    }

    @Test func aCardThatGoesAwayMovesTheIslandToTheNextOne() {
        let model = NotchModel()
        model.setCards([.home([.music, .calendar]), .shelf])
        model.expand()
        model.setCards([.home([.calendar]), .shelf])
        #expect(model.card == .home([.calendar]))
        #expect(model.isExpanded)
        model.setCards([])
        #expect(!model.isExpanded)
    }

    @Test func nothingToShowStaysClosed() {
        let model = NotchModel()
        model.expand()
        #expect(!model.isExpanded)
    }
}
