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
