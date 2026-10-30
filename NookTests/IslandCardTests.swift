import CoreGraphics
import Testing

/// Hovering opens the first page, so it has to be what the closed island is showing.
struct IslandCardTests {
    private let all: [HomeModule] = [.music, .calendar, .batteries]

    @Test func musicOpensTheHomePageThatHoldsIt() {
        let cards = IslandCard.available(live: [.nowPlaying], modules: all, perPage: 2, shelf: true)
        #expect(cards == [.home([.music, .calendar]), .home([.batteries]), .shelf])
    }

    @Test func musicOrderedLastStillOpensFirst() {
        let cards = IslandCard.available(live: [.nowPlaying], modules: [.calendar, .batteries, .music], perPage: 2, shelf: false)
        #expect(cards == [.home([.music]), .home([.calendar, .batteries])])
    }

    @Test func aTimerTheNotchShowsOpensBeforeTheHome() {
        let cards = IslandCard.available(live: [.timer, .nowPlaying], modules: all, perPage: 2, shelf: true)
        #expect(cards == [.timer, .home([.music, .calendar]), .home([.batteries]), .shelf])
    }

    @Test func theDropBesideTheIslandComesAfterTheHome() {
        let cards = IslandCard.available(live: [.nowPlaying, .calendar(id: "m")], modules: all, perPage: 3, shelf: true)
        #expect(cards == [.home([.music, .calendar, .batteries]), .meeting(id: "m"), .shelf])
    }

    @Test func oneAtATimeGivesEachModuleItsOwnPage() {
        let cards = IslandCard.available(live: [], modules: all, perPage: 1, shelf: true)
        #expect(cards == [.home([.music]), .home([.calendar]), .home([.batteries]), .shelf])
    }

    @Test func nothingGoingOnOpensTheHomeThenTheShelf() {
        #expect(IslandCard.available(live: [], modules: [.calendar, .batteries], perPage: 2, shelf: true) == [.home([.calendar, .batteries]), .shelf])
        #expect(IslandCard.available(live: [], modules: [], perPage: 2, shelf: true) == [.shelf])
        #expect(IslandCard.available(live: [], modules: [], perPage: 2, shelf: false).isEmpty)
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
