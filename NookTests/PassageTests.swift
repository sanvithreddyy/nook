import Testing

/// While a full-screen video starts or ends, the music beside the notch rides into it and back out
/// rather than fading where it sits. Opening the island takes over: the artwork moves to the card.
@MainActor
struct PassageTests {
    @Test func theMusicGoesThroughTheNotchUntilItHasSettled() async throws {
        let model = NotchModel()
        model.setLiveActivity(.nowPlaying)
        model.passThroughNotch()
        model.setLiveActivity(nil)
        #expect(model.passage.throughNotch)
        try await Task.sleep(for: .seconds(1.4))
        #expect(!model.passage.throughNotch)
    }

    @Test func openingTakesOver() {
        let model = NotchModel()
        model.setCards([.home([.music])])
        model.setLiveActivity(.nowPlaying)
        model.passThroughNotch()
        model.expand()
        #expect(model.isExpanded)
        #expect(!model.passage.throughNotch)
    }

    @Test func anOpenIslandDoesntPassThrough() {
        let model = NotchModel()
        model.setCards([.home([.music])])
        model.setLiveActivity(.nowPlaying)
        model.expand()
        #expect(model.isExpanded)
        model.passThroughNotch()
        #expect(!model.passage.throughNotch)
    }
}
