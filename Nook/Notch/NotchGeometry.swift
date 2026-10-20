import AppKit

/// The hardware notch of a screen, or a simulated one of the same proportions.
struct NotchMetrics: Equatable {
    var size: CGSize
    var isHardware: Bool

    /// Square slot on each side of the notch for live-activity content.
    var slot: CGFloat { size.height + 10 }

    static let simulated = NotchMetrics(size: CGSize(width: 185, height: 32), isHardware: false)
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    var isBuiltIn: Bool {
        guard let displayID else { return false }
        return CGDisplayIsBuiltin(displayID) != 0
    }

    var notchMetrics: NotchMetrics {
        guard safeAreaInsets.top > 0,
              let left = auxiliaryTopLeftArea,
              let right = auxiliaryTopRightArea
        else {
            // Match the menu bar height so the simulated notch sits flush with it.
            let barHeight = frame.maxY - visibleFrame.maxY
            var metrics = NotchMetrics.simulated
            if barHeight > 20 { metrics.size.height = barHeight }
            return metrics
        }
        let width = frame.width - left.width - right.width
        return NotchMetrics(size: CGSize(width: width, height: safeAreaInsets.top), isHardware: true)
    }

    static func target(for choice: DisplayChoice) -> NSScreen? {
        switch choice {
        case .builtIn:
            screens.first(where: \.isBuiltIn) ?? main
        case .main:
            screens.first ?? main
        }
    }
}
