import AppKit
import SwiftUI

/// Screen lock state from the distributed notifications loginwindow posts.
final class LockMonitor {
    enum State { case unlocked, locked, justUnlocked }

    private(set) var state: State = .unlocked
    var onChange: (() -> Void)?
    private var observers: [NSObjectProtocol] = []
    private var settleTask: Task<Void, Never>?

    func start() {
        let center = DistributedNotificationCenter.default()
        observers.append(center.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.set(.locked) }
        })
        observers.append(center.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.unlocked() }
        })
    }

    private func set(_ state: State) {
        settleTask?.cancel()
        self.state = state
        onChange?()
    }

    private func unlocked() {
        set(.justUnlocked)
        // Hold the open padlock long enough to read, then let other activities back in.
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900) + Motion.unlockHold)
            guard !Task.isCancelled else { return }
            self?.set(.unlocked)
        }
    }
}

struct LockGlyph: View {
    let unlocked: Bool

    var body: some View {
        Image(systemName: unlocked ? "lock.open.fill" : "lock.fill")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .contentTransition(.symbolEffect(.replace))
    }
}
