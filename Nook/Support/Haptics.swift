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

    static var current: HapticStrength { HapticStrength(rawValue: Prefs.string(Prefs.hapticStrength)) ?? .light }
}

/// macOS lets an app pick a pattern but not how hard it lands, so the strengths are built from the
/// patterns: Light is the alignment tick, Medium the level-change click a Force Click gives, Strong
/// that click twice in quick succession.
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
            performer.perform(.alignment, performanceTime: .now)
        case .medium:
            performer.perform(.levelChange, performanceTime: .now)
        case .strong:
            performer.perform(.levelChange, performanceTime: .now)
            Task {
                try? await Task.sleep(for: .milliseconds(30))
                performer.perform(.levelChange, performanceTime: .now)
            }
        }
    }
}
