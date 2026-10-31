import Testing

/// A change from one kind of closed content to another shrinks the band before growing into the new
/// one. The pointer is tested against what the band is growing into, so a hover isn't dropped.
@MainActor
struct HandOffTests {
    private let volume = NotchNotification.volume(level: 0.5, muted: false, output: nil)
    private let charging = NotchNotification.charging(level: 80)

    @Test func aNoticeOverMusicHandsOverAndKeepsWhereItsGoing() {
        let model = NotchModel()
        model.setLiveActivity(.nowPlaying)
        model.post(charging)
        // While the band shrinks it draws the bare notch, but it's already headed for the notice.
        #expect(model.isHandingOff == true)
        #expect(model.presentation == .idle)
        #expect(model.settledPresentation == .notification(charging))
    }

    /// A key's answer can't wait: volume goes straight from the music to its level, and straight back.
    @Test func volumeOverMusicGoesStraightIn() {
        let model = NotchModel()
        model.setLiveActivity(.nowPlaying)
        model.post(volume)
        #expect(model.isHandingOff == false)
        #expect(model.presentation == .notification(volume))
        model.dismissNotification()
        #expect(model.isHandingOff == false)
        #expect(model.presentation == .activity(.nowPlaying))
    }

    @Test func fromNothingTheBandJustGrows() {
        let model = NotchModel()
        model.post(volume)
        #expect(model.isHandingOff == false)
        #expect(model.presentation == .notification(volume))
    }

    @Test func openingEndsAHandOver() {
        let model = NotchModel()
        model.setCards([.shelf])
        model.setLiveActivity(.nowPlaying)
        model.post(volume)
        model.expand()
        #expect(model.isHandingOff == false)
        #expect(model.presentation == .expanded)
    }
}
