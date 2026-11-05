import AppKit
import Testing

/// The volume and brightness keys as macOS sends them. Each press goes wholly to Nook or wholly to
/// macOS: when macOS saw a key go down and never come up, it treated the key as held and kept its
/// brightness banner on screen, repeating, until the next press of that key.
@MainActor
struct MediaKeyTapTests {
    /// A key event built from the same bytes macOS sends: key << 16 | state << 8 | repeat.
    private func event(_ key: MediaKeyTap.Key, down: Bool, repeat isRepeat: Bool = false, option: Bool = false, shift: Bool = false) -> MediaKeyEvent {
        var flags: NSEvent.ModifierFlags = []
        if option { flags.insert(.option) }
        if shift { flags.insert(.shift) }
        let data1 = key.rawValue << 16 | (down ? 0xA : 0xB) << 8 | (isRepeat ? 1 : 0)
        let ns = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags, timestamp: 0,
                                    windowNumber: 0, context: nil, subtype: 8, data1: data1, data2: -1)!
        return MediaKeyEvent(ns.cgEvent!)!
    }

    /// What macOS is left holding: keys it saw go down and not yet come up.
    private struct System {
        var held: Set<Int> = []
        mutating func receive(_ event: MediaKeyEvent) {
            if !event.isDown { held.remove(event.code) } else if !event.isRepeat { held.insert(event.code) }
        }
    }

    /// The tap, with whether Nook wants a key switchable mid-press, and every event routed to Nook
    /// or macOS as the real callback does.
    private final class Rig {
        let tap = MediaKeyTap()
        var system = System()
        var wants = true
        var acted = 0
        /// False while macOS has the tap switched off: events skip it.
        var tapOn = true

        init() {
            tap.handles = { [unowned self] _ in wants }
            tap.onKey = { [unowned self] _, _ in acted += 1 }
        }

        /// Returns true when Nook swallowed the event.
        @discardableResult
        func send(_ event: MediaKeyEvent) -> Bool {
            if tapOn, tap.handle(event) { return true }
            system.receive(event)
            return false
        }
    }

    @Test func decodesTheBytesMacOSSends() {
        let down = event(.brightnessUp, down: true)
        #expect(down.code == 2 && down.isDown && !down.isRepeat && !down.isFine && !down.isOptionOnly)
        let held = event(.volumeDown, down: true, repeat: true)
        #expect(held.code == 1 && held.isDown && held.isRepeat)
        let up = event(.mute, down: false)
        #expect(up.code == 7 && !up.isDown && !up.isRepeat)
        #expect(event(.volumeUp, down: true, option: true, shift: true).isFine)
        #expect(event(.volumeUp, down: true, option: true).isOptionOnly)
    }

    @Test func nookTakesAWholePress() {
        let rig = Rig()
        #expect(rig.send(event(.brightnessUp, down: true)))
        #expect(rig.send(event(.brightnessUp, down: true, repeat: true)))
        #expect(rig.send(event(.brightnessUp, down: false)))
        #expect(rig.acted == 2)
        #expect(rig.system.held.isEmpty)
    }

    @Test func aKeyNookDoesntWantGoesToMacOS() {
        let rig = Rig()
        rig.wants = false
        #expect(!rig.send(event(.volumeUp, down: true)))
        #expect(!rig.send(event(.volumeUp, down: true, repeat: true)))
        #expect(!rig.send(event(.volumeUp, down: false)))
        #expect(rig.acted == 0)
        #expect(rig.system.held.isEmpty)
    }

    /// Nov 5, 07:23:17: brightness up went down on the lock screen (Nook leaves keys to macOS there),
    /// the screen unlocked 15 ms later, and Nook swallowed the release.
    @Test func theScreenUnlockingMidPressLeavesThePressToMacOS() {
        let rig = Rig()
        rig.wants = false
        rig.send(event(.brightnessUp, down: true))
        rig.wants = true
        #expect(!rig.send(event(.brightnessUp, down: true, repeat: true)))
        #expect(!rig.send(event(.brightnessUp, down: false)))
        #expect(rig.acted == 0)
        #expect(rig.system.held.isEmpty)
        // The next press is Nook's again.
        #expect(rig.send(event(.brightnessUp, down: true)))
        #expect(rig.send(event(.brightnessUp, down: false)))
    }

    @Test func aPressNookTookStaysNooksWhenItStopsWantingTheKey() {
        let rig = Rig()
        rig.send(event(.volumeDown, down: true))
        rig.wants = false
        #expect(rig.send(event(.volumeDown, down: true, repeat: true)))
        #expect(rig.send(event(.volumeDown, down: false)))
        #expect(rig.acted == 2)
        #expect(rig.system.held.isEmpty)
    }

    /// Option alone opens Sound or Displays settings, so that press is macOS's, even if Option
    /// comes up before the key does; and a press Nook took stays Nook's if Option goes down.
    @Test func optionDecidesOnlyAtTheFirstDown() {
        let rig = Rig()
        #expect(!rig.send(event(.brightnessDown, down: true, option: true)))
        #expect(!rig.send(event(.brightnessDown, down: false)))
        #expect(rig.send(event(.brightnessDown, down: true)))
        #expect(rig.send(event(.brightnessDown, down: false, option: true)))
        #expect(rig.system.held.isEmpty)
    }

    /// While macOS has the tap switched off, keys go straight to it, so the release that arrives
    /// once the tap is back on may be for a press macOS saw go down.
    @Test func aPressMacOSGotWhileTheTapWasOffStaysWithMacOS() {
        let rig = Rig()
        rig.send(event(.brightnessUp, down: true))
        rig.tapOn = false
        rig.send(event(.brightnessUp, down: false))
        rig.send(event(.brightnessUp, down: true))
        rig.tap.tapWasDisabled()
        rig.tapOn = true
        #expect(!rig.send(event(.brightnessUp, down: true, repeat: true)))
        #expect(!rig.send(event(.brightnessUp, down: false)))
        #expect(rig.system.held.isEmpty)
    }

    @Test func aPressMacOSGotWhileTheTapWasStoppedStaysWithMacOS() {
        let rig = Rig()
        rig.send(event(.volumeUp, down: true))
        rig.tap.stop()
        rig.tapOn = false
        rig.send(event(.volumeUp, down: false))
        rig.send(event(.volumeUp, down: true))
        rig.tapOn = true
        #expect(!rig.send(event(.volumeUp, down: false)))
        #expect(rig.system.held.isEmpty)
    }

    @Test func otherKeysPassThrough() {
        let rig = Rig()
        let play = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                      context: nil, subtype: 8, data1: 16 << 16 | 0xA << 8, data2: -1)!
        #expect(!rig.send(MediaKeyEvent(play.cgEvent!)!))
        #expect(rig.acted == 0)
    }

    /// Every way the answer can change between a key going down and coming up: whether Nook wants
    /// the key (screen lock, open island, full screen, a setting, the display), Option, and the tap
    /// being switched off or stopped. macOS is never left holding a key, and Nook acts only on
    /// presses it took.
    @Test(arguments: [false, true], [false, true])
    func macOSIsNeverLeftHoldingAKey(wantsAtDown: Bool, wantsAtUp: Bool) {
        enum Gap: CaseIterable { case none, tapDisabled, tapStopped }
        for key in [MediaKeyTap.Key.volumeUp, .volumeDown, .mute, .brightnessUp, .brightnessDown] {
            for optionAtDown in [false, true] {
                for optionAtUp in [false, true] {
                    for gap in Gap.allCases {
                        let rig = Rig()
                        rig.wants = wantsAtDown
                        let took = rig.send(event(key, down: true, option: optionAtDown))
                        #expect(took == (wantsAtDown && !optionAtDown))
                        rig.wants = wantsAtUp
                        rig.send(event(key, down: true, repeat: true, option: optionAtUp))
                        switch gap {
                        case .none: break
                        case .tapDisabled: rig.tap.tapWasDisabled()
                        case .tapStopped: rig.tap.stop()
                        }
                        rig.send(event(key, down: false, option: optionAtUp))
                        #expect(rig.system.held.isEmpty, "\(key) \(wantsAtDown) \(wantsAtUp) \(optionAtDown) \(optionAtUp) \(gap)")
                        #expect(rig.acted == (took ? 2 : 0))
                    }
                }
            }
        }
    }
}
