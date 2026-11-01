import AppKit
import Sparkle

/// Newer versions of Nook. Sparkle finds them, downloads them, checks their signature and installs them;
/// Settings shows what it found and Update Now, through the driver below in place of Sparkle's windows.
@Observable
final class Updates {
    static let shared = Updates()

    struct Release: Equatable {
        var version: String
        var size: Int64
        var notes: [String]
    }

    enum Phase: Equatable {
        case ready
        case downloading(received: Int64, total: Int64)
        case installing
        case failed
    }

    /// The newer version, while there is one.
    private(set) var release: Release?
    private(set) var phase = Phase.ready

    @ObservationIgnored private var updater: SPUUpdater?
    @ObservationIgnored private let driver = UpdateDriver()
    @ObservationIgnored private let delegate = UpdaterDelegate()
    /// Sparkle's question, "install this one?", answered when Update Now is pressed.
    @ObservationIgnored private var answer: ((SPUUserUpdateChoice) -> Void)?
    /// Update Now after a failure checks again, and what that finds installs straight away.
    @ObservationIgnored private var installWhenFound = false

    private static let reopenKey = "openSettingsAfterUpdate"

    func start() {
        #if DEBUG
        // Test copies check only a feed they're given, never the real one.
        guard UpdateDebug.feed != nil || UpdateDebug.previewPhase != nil else { return }
        if let phase = UpdateDebug.previewPhase {
            release = UpdateDebug.sample
            self.phase = phase
            return
        }
        #endif
        let updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: driver, delegate: delegate)
        do {
            try updater.start()
        } catch {
            return
        }
        self.updater = updater
        #if DEBUG
        if CommandLine.arguments.contains("-update-check-now") { updater.checkForUpdatesInBackground() }
        #endif
    }

    func install() {
        if let answer {
            self.answer = nil
            phase = .downloading(received: 0, total: release?.size ?? 0)
            answer(.install)
        } else if phase == .failed, let updater, updater.canCheckForUpdates {
            installWhenFound = true
            phase = .downloading(received: 0, total: release?.size ?? 0)
            updater.checkForUpdates()
        }
    }

    /// Nook reopens after an update with Settings where Update Now was pressed, showing the new version.
    func takeReopenRequest() -> Bool {
        guard UserDefaults.standard.bool(forKey: Self.reopenKey) else { return false }
        UserDefaults.standard.removeObject(forKey: Self.reopenKey)
        return true
    }

    /// The release notes' bullet lines, without their markers.
    nonisolated static func notes(from description: String?) -> [String] {
        let lines = (description ?? "").split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let bullets = lines.compactMap { line -> String? in
            for marker in ["- ", "* ", "• "] where line.hasPrefix(marker) {
                return String(line.dropFirst(marker.count))
            }
            return nil
        }
        return bullets.isEmpty ? lines : bullets
    }

    // What Sparkle reports, through the driver and delegate.

    fileprivate func found(_ item: SUAppcastItem, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        guard !item.isInformationOnlyUpdate else {
            reply(.dismiss)
            return
        }
        release = Release(version: item.displayVersionString, size: Int64(item.contentLength),
                          notes: Self.notes(from: item.itemDescription))
        if installWhenFound {
            installWhenFound = false
            reply(.install)
            return
        }
        phase = .ready
        answer = reply
        #if DEBUG
        if let delay = UpdateDebug.showPageAfter {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(delay))
                SettingsNavigation.shared.pane = .update
            }
        }
        if let delay = UpdateDebug.pressAfter {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(delay))
                self.install()
            }
        }
        #endif
    }

    fileprivate func downloadStarted() {
        phase = .downloading(received: 0, total: release?.size ?? 0)
    }

    fileprivate func downloadExpects(_ total: UInt64) {
        if case .downloading(let received, _) = phase { phase = .downloading(received: received, total: Int64(total)) }
    }

    fileprivate func downloadReceived(_ length: UInt64) {
        if case .downloading(let received, let total) = phase {
            phase = .downloading(received: received + Int64(length), total: total)
        }
    }

    fileprivate func installing() {
        phase = .installing
    }

    /// A failed check in the background, with nothing found yet, isn't worth a word.
    fileprivate func failed() {
        installWhenFound = false
        if release != nil { phase = .failed }
    }

    fileprivate func notFound() {
        installWhenFound = false
        release = nil
        phase = .ready
    }

    fileprivate func ended() {
        answer = nil
        guard phase != .failed else { return }
        release = nil
        phase = .ready
    }

    fileprivate func willRelaunch() {
        UserDefaults.standard.set(true, forKey: Self.reopenKey)
    }
}

/// Sparkle's questions and progress, turned into Updates' state instead of Sparkle's own windows.
private final class UpdateDriver: NSObject, SPUUserDriver {
    private var updates: Updates { .shared }

    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {}

    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState,
                         reply: @escaping (SPUUserUpdateChoice) -> Void) {
        updates.found(appcastItem, reply: reply)
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {}

    func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        updates.notFound()
        acknowledgement()
    }

    func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        updates.failed()
        acknowledgement()
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        updates.downloadStarted()
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        updates.downloadExpects(expectedContentLength)
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        updates.downloadReceived(length)
    }

    func showDownloadDidStartExtractingUpdate() {
        updates.installing()
    }

    func showExtractionReceivedProgress(_ progress: Double) {}

    /// Update Now already said yes.
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        reply(.install)
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool,
                              retryTerminatingApplication: @escaping () -> Void) {
        updates.installing()
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        acknowledgement()
    }

    func showUpdateInFocus() {
        SettingsWindowController.shared.show(pane: .update)
    }

    func dismissUpdateInstallation() {
        updates.ended()
    }
}

private final class UpdaterDelegate: NSObject, SPUUpdaterDelegate {
    func feedURLString(for updater: SPUUpdater) -> String? {
        #if DEBUG
        return UpdateDebug.feed
        #else
        return nil
        #endif
    }

    /// The notes come inside the feed.
    func updater(_ updater: SPUUpdater, shouldDownloadReleaseNotesForUpdate updateItem: SUAppcastItem) -> Bool {
        false
    }

    func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        Updates.shared.willRelaunch()
    }

    #if DEBUG
    func updaterShouldRelaunchApplication(_ updater: SPUUpdater) -> Bool {
        !CommandLine.arguments.contains("-update-no-relaunch")
    }
    #endif
}

#if DEBUG
extension Updates {
    /// The sidebar row and page with a made-up update, for probes.
    func previewFound() {
        release = UpdateDebug.sample
    }
}

/// -update-feed <url>: check this feed (test copies check nothing otherwise); -update-check-now: at launch;
/// -update-show-page-after, -update-press-after <seconds>: go to the update's page and press Update Now that
/// long after an update is found, as a click would, for recordings;
/// -update-no-relaunch: leave the installed copy closed; -preview-update ready|downloading|installing|failed:
/// the page with a made-up update, nothing checked.
enum UpdateDebug {
    static var feed: String? { value(after: "-update-feed") }
    static var pressAfter: Double? { value(after: "-update-press-after").flatMap(Double.init) }
    static var showPageAfter: Double? { value(after: "-update-show-page-after").flatMap(Double.init) }

    static var previewPhase: Updates.Phase? {
        switch value(after: "-preview-update") {
        case "ready": .ready
        case "downloading": .downloading(received: 1_180_000, total: 2_830_000)
        case "installing": .installing
        case "failed": .failed
        default: nil
        }
    }

    static let sample = Updates.Release(version: "0.1.2", size: 2_830_000, notes: [
        "What's playing steps aside only while its player is full screen.",
        "Full-screen apps are recognised on Macs with a notch.",
        "Volume and brightness fold back into the notch when they hide.",
    ])

    private static func value(after flag: String) -> String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
}
#endif
