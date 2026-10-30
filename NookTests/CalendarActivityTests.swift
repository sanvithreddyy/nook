import Foundation
import SwiftUI
import Testing

/// Which meeting the closed island counts down to.
@MainActor
struct CalendarActivityTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func event(_ id: String, startsIn minutes: Double, lasts length: Double, declined: Bool = false) -> CalendarEvent {
        var event = CalendarEvent(id: id, title: id, start: now.addingTimeInterval(minutes * 60),
                                  end: now.addingTimeInterval((minutes + length) * 60), color: .blue, isAllDay: false, joinURL: nil)
        event.isDeclined = declined
        return event
    }

    @Test func theNextMeetingBeatsOneStillGoing() {
        let model = CalendarModel()
        // A workshop under way since an hour ago, staying until it ends, and a 1:1 in five minutes.
        model.debugSet([event("workshop", startsIn: -60, lasts: 240), event("one-on-one", startsIn: 5, lasts: 30)])
        #expect(model.eventForLiveActivity(now: now, leadMinutes: 10, stayMinutes: -1)?.id == "one-on-one")
    }

    @Test func aMeetingThatJustStartedBeatsTheNext() {
        let model = CalendarModel()
        // The 10:00 started a minute ago; the 10:10 is nine minutes out. The 10:00 is the one to join.
        model.debugSet([event("ten", startsIn: -1, lasts: 30), event("ten-ten", startsIn: 9, lasts: 30)])
        #expect(model.eventForLiveActivity(now: now, leadMinutes: 10, stayMinutes: 5)?.id == "ten")
        #expect(model.eventForLiveActivity(now: now, leadMinutes: 10, stayMinutes: -1)?.id == "ten")
    }

    @Test func aMeetingUnderWayShowsWhenNothingIsNext() {
        let model = CalendarModel()
        model.debugSet([event("workshop", startsIn: -60, lasts: 240)])
        #expect(model.eventForLiveActivity(now: now, leadMinutes: 10, stayMinutes: -1)?.id == "workshop")
        #expect(model.eventForLiveActivity(now: now, leadMinutes: 10, stayMinutes: 5) == nil)
    }

    @Test func leaveAtStartDropsItOnce() {
        let model = CalendarModel()
        model.debugSet([event("standup", startsIn: 0, lasts: 15)])
        #expect(model.eventForLiveActivity(now: now.addingTimeInterval(1), leadMinutes: 10, stayMinutes: 0) == nil)
    }

    @Test func declinedMeetingsDontCountDown() {
        let model = CalendarModel()
        model.debugSet([event("declined", startsIn: 5, lasts: 30, declined: true)])
        #expect(model.eventForLiveActivity(now: now, leadMinutes: 10, stayMinutes: 5) == nil)
    }
}
