import Testing

/// Where the island opens when nothing asks for a page: Settings' "Opens to".
@MainActor
struct OpenToTests {
    private let cards: [IslandCard] = [.timer, .home([.music, .calendar]), .home([.batteries]), .shelf]

    private func model(_ openTo: OpenTo) -> NotchModel {
        let model = NotchModel()
        model.setCards(cards)
        model.openTo = openTo
        return model
    }

    @Test func whatsHappeningOpensTheFirstPage() {
        let model = model(.whatsHappening)
        model.expand()
        #expect(model.card == .timer)
    }

    @Test func homeSkipsPagesThatAreNotHome() {
        let model = model(.home)
        model.expand()
        #expect(model.card == .home([.music, .calendar]))
    }

    @Test func lastPageReopensWhereItClosed() {
        let model = model(.lastPage)
        model.expand()
        model.show(.home([.batteries]))
        model.collapse()
        model.expand()
        #expect(model.card == .home([.batteries]))
    }

    @Test func lastPageThatIsGoneFallsBackToTheFirst() {
        let model = model(.lastPage)
        model.expand()
        model.show(.shelf)
        model.collapse()
        model.setCards([.home([.music, .calendar])])
        model.expand()
        #expect(model.card == .home([.music, .calendar]))
    }
}

/// Turning a page changes what's inside the open island, never its size.
@MainActor
struct OpenSizeTests {
    @Test func everyPageTakesTheLargestPagesSize() {
        let model = NotchModel()
        model.batteryCount = 2
        let cards: [IslandCard] = [.home([.music, .calendar]), .home([.batteries]), .shelf]
        model.setCards(cards)
        model.expand(card: cards[0])
        let first = model.layout.size
        for card in cards.dropFirst() {
            model.show(card)
            #expect(abs(model.layout.size.width - first.width) < 0.001 && abs(model.layout.size.height - first.height) < 0.001)
        }
        let widest = cards.map { model.cardSize($0).width }.max() ?? 0
        let expected = widest + NotchModel.cardEar * 2
        #expect(abs(first.width - expected) < 0.001)
    }
}
