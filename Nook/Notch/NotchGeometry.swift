import AppKit

/// The hardware notch of a screen, or a simulated one of the same proportions.
struct NotchMetrics: Equatable {
    var size: CGSize
    var isHardware: Bool
    /// Drawn as a pill floating a little below the top edge (screens without a notch).
    var isPill = false
    /// Not drawn while it has nothing to show (screens without a notch).
    var hidesWhenIdle = false

    /// How far below the top edge the island starts: a pill floats, a notch hangs from the edge.
    var topInset: CGFloat { isPill ? 4 : 0 }

    /// Slot on each side of the notch for live-activity content: the island's 6 pt ear, then a glyph
    /// or artwork centred on the round end (half the notch's height in), then a few points to the notch.
    var slot: CGFloat { size.height + 8 }

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

    /// The island Settings asks for on this screen: its closed height, and on a screen without a notch
    /// a drawn notch, a pill, or nothing until there's something to show.
    var islandMetrics: NotchMetrics {
        var metrics = notchMetrics
        let barHeight = frame.maxY - visibleFrame.maxY
        switch ClosedHeight.current {
        case .notch: break
        case .menuBar: if barHeight > 20 { metrics.size.height = barHeight }
        case .custom: metrics.size.height = CGFloat(Prefs.double(Prefs.closedHeightCustom))
        }
        // Never shorter than a real notch, which would show under it.
        if metrics.isHardware { metrics.size.height = max(metrics.size.height, safeAreaInsets.top) }
        if !metrics.isHardware {
            switch NotchlessStyle.current {
            case .notch: break
            case .pill: metrics.isPill = true
            case .hidden: metrics.hidesWhenIdle = true
            }
        }
        return metrics
    }

    static func target(for choice: DisplayChoice) -> NSScreen? {
        switch choice {
        case .builtIn, .all:
            screens.first(where: \.isBuiltIn) ?? main
        case .main:
            screens.first ?? main
        case .named(let name):
            screens.first { $0.localizedName == name } ?? target(for: .builtIn)
        }
    }
}

extension DisplayChoice {
    /// The fixed choices, every connected screen by name, and the chosen screen even while unplugged.
    static func choices(keeping chosen: String) -> [DisplayChoice] {
        var all: [DisplayChoice] = [.builtIn, .main, .all]
        for name in NSScreen.screens.map(\.localizedName) where !all.contains(.named(name)) {
            all.append(.named(name))
        }
        if let kept = DisplayChoice(rawValue: chosen), !all.contains(kept) { all.append(kept) }
        return all
    }
}
