import Testing

/// Hovering opens the first card, so it has to be what the closed island is showing.
struct IslandCardTests {
    @Test func liveMusicOpensFirst() {
        let cards = IslandCard.available(music: true, musicIsLive: true, meeting: "m", agenda: true, shelf: true)
        #expect(cards == [.nowPlaying, .meeting(id: "m"), .shelf])
    }

    @Test func aMeetingTheNotchCountsDownToOpensBeforePausedMusic() {
        let cards = IslandCard.available(music: true, musicIsLive: false, meeting: "m", agenda: true, shelf: true)
        #expect(cards == [.meeting(id: "m"), .nowPlaying, .shelf])
    }

    @Test func pausedMusicStillComesBeforeTheCalendar() {
        let cards = IslandCard.available(music: true, musicIsLive: false, meeting: nil, agenda: true, shelf: true)
        #expect(cards == [.nowPlaying, .upNext, .shelf])
    }

    @Test func aMeetingReplacesUpNext() {
        let cards = IslandCard.available(music: false, musicIsLive: false, meeting: "m", agenda: true, shelf: false)
        #expect(cards == [.meeting(id: "m")])
    }

    @Test func nothingGoingOnOpensTheShelf() {
        #expect(IslandCard.available(music: false, musicIsLive: false, meeting: nil, agenda: false, shelf: true) == [.shelf])
        #expect(IslandCard.available(music: false, musicIsLive: false, meeting: nil, agenda: false, shelf: false).isEmpty)
    }
}

/// Swipes and page dots move between cards without running off either end,
/// and an open island never shows a card that has gone away.
@MainActor
struct CardPagingTests {
    @Test func pagingStopsAtTheEnds() {
        let model = NotchModel()
        model.setCards([.nowPlaying, .upNext, .shelf])
        model.expand()
        #expect(model.card == .nowPlaying)
        model.page(-1)
        #expect(model.card == .nowPlaying)
        model.page(1)
        model.page(1)
        model.page(1)
        #expect(model.card == .shelf)
    }

    @Test func aCardThatGoesAwayMovesTheIslandToTheNextOne() {
        let model = NotchModel()
        model.setCards([.nowPlaying, .shelf])
        model.expand()
        model.setCards([.shelf])
        #expect(model.card == .shelf)
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
