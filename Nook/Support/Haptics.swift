import AppKit

enum Haptics {
    static func tap() {
        guard Prefs.bool(Prefs.enableHaptics) else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
}
