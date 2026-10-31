import AppKit

/// How strongly the trackpad answers: the island opening, a swipe, a file landing on the shelf.
enum HapticStrength: String, CaseIterable, Identifiable {
    case light, medium, strong

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: "Light"
        case .medium: "Medium"
        case .strong: "Strong"
        }
    }

    static var current: HapticStrength { HapticStrength(rawValue: Prefs.string(Prefs.hapticStrength)) ?? .medium }
}

/// macOS's public haptics pick a pattern but not how hard it lands, and their firmest, the level-change
/// click, is Light. Medium and Strong come from the trackpad's own actuator, at the two strengths picked
/// by feel; without it they fall back to the public click (once, or twice for Strong).
enum Haptics {
    static func tap() {
        guard Prefs.bool(Prefs.enableHaptics) else { return }
        play(HapticStrength.current)
    }

    /// Each detent of a dial: one tick at any strength, since they come quickly.
    static func detent() {
        guard Prefs.bool(Prefs.enableHaptics) else { return }
        let performer = NSHapticFeedbackManager.defaultPerformer
        performer.perform(HapticStrength.current == .light ? .alignment : .levelChange, performanceTime: .now)
    }

    /// Plays one strength regardless of the switch, for Settings to let you feel it as you pick it.
    static func play(_ strength: HapticStrength) {
        let performer = NSHapticFeedbackManager.defaultPerformer
        switch strength {
        case .light:
            performer.perform(.levelChange, performanceTime: .now)
        case .medium:
            if !TrackpadActuator.tap(3) { performer.perform(.levelChange, performanceTime: .now) }
        case .strong:
            guard !TrackpadActuator.tap(4) else { return }
            performer.perform(.levelChange, performanceTime: .now)
            Task {
                try? await Task.sleep(for: .milliseconds(30))
                performer.perform(.levelChange, performanceTime: .now)
            }
        }
    }
}
