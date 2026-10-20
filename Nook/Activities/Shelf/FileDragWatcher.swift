import AppKit
import UniformTypeIdentifiers

/// Notices a file (or link, text, image) being dragged in another app and reports when the
/// pointer reaches the notch, so the island can open its shelf as a drop target.
/// Watches only the drag pasteboard's change count and type list, never its contents.
final class FileDragWatcher {
    var isInsideNotch: (CGPoint) -> Bool = { _ in false }
    var onEnterNotch: (() -> Void)?

    private let pasteboard = NSPasteboard(name: .drag)
    private var monitors: [Any] = []
    private var changeCountAtPress = 0
    private var pressed = false
    private var carryingContent = false
    private var entered = false

    func start() {
        guard monitors.isEmpty else { return }
        if let down = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] _ in
            self?.pressBegan()
        }) { monitors.append(down) }
        if let drag = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged, handler: { [weak self] _ in
            self?.dragged()
        }) { monitors.append(drag) }
        if let up = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp, handler: { [weak self] _ in
            self?.pressed = false
        }) { monitors.append(up) }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }

    private func pressBegan() {
        changeCountAtPress = pasteboard.changeCount
        pressed = true
        carryingContent = false
        entered = false
    }

    private func dragged() {
        guard pressed else { return }
        // A drag session writes to the drag pasteboard once it starts; plain mouse drags don't.
        if !carryingContent, pasteboard.changeCount != changeCountAtPress {
            let accepted: [NSPasteboard.PasteboardType] = [.fileURL, .URL, .string, .png, .tiff]
            carryingContent = pasteboard.types?.contains(where: accepted.contains) ?? false
        }
        guard carryingContent else { return }
        let inside = isInsideNotch(NSEvent.mouseLocation)
        if inside, !entered {
            entered = true
            onEnterNotch?()
        } else if !inside {
            entered = false
        }
    }
}
