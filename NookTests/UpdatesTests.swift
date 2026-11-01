import Testing

/// The feed's notes become the update page's list: one line each, without the markers.
struct UpdatesTests {
    @Test func bulletsLoseTheirMarkers() {
        let notes = Updates.notes(from: "\n- First change.\n* Second change.\n• Third change.\n")
        #expect(notes == ["First change.", "Second change.", "Third change."])
    }

    @Test func linesWithoutBulletsStayAsTheyAre() {
        #expect(Updates.notes(from: "One change.\n\n  Another.  ") == ["One change.", "Another."])
    }

    @Test func noNotes() {
        #expect(Updates.notes(from: nil).isEmpty)
        #expect(Updates.notes(from: "  \n ").isEmpty)
    }
}
