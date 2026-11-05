import AppKit
import SwiftUI

/// A conversion running or just finished: a place on the shelf while it's made and, if it takes a
/// while, a ring beside the notch.
struct ConvertJob: Identifiable, Equatable {
    enum State: Equatable { case running, done, failed(String) }

    let id = UUID()
    let sources: [URL]
    let target: ConvertTarget
    var progress: Double = 0
    var state: State = .running

    /// What the result will be called, for its place on the shelf.
    var name: String {
        let base = ConvertOutput.baseName(sources[0])
        if target == .onePDF, sources.count > 1 { return "\(base) and \(sources.count - 1) more.pdf" }
        return "\(base).\(target.fileExtension)"
    }
}

/// How the shelf's Convert place stands, which also decides how wide the shelf is.
enum ShelfConvert: Equatable {
    case hidden
    /// Beside AirDrop while files are dragged.
    case offered
    /// Sprung open: the row shows this many format places.
    case open(places: Int)
}

/// Converting from the shelf: Convert beside AirDrop while files are dragged, springing open into the
/// formats they can become, and the conversions it starts.
@Observable
final class ConvertModel {
    /// The files Convert opened for, and what they can become; while set, the shelf's row shows formats.
    private(set) var sources: [URL] = []
    private(set) var targets: [ConvertTarget] = []
    /// Which group of four the row shows.
    private(set) var page = 0
    /// The drag under way carries files (not only text or a link), so Convert can take it.
    var dragCarriesFiles = false
    private(set) var jobs: [ConvertJob] = []
    /// The conversion beside the notch while the island is closed: one that's taken a moment.
    private(set) var activity: ConvertJob?

    /// Results to keep on the shelf.
    @ObservationIgnored var onMade: (([URL]) -> Void)?
    /// What the shelf shows changed (its width follows), or the activity beside the notch did.
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private var activityTask: Task<Void, Never>?

    static let perPage = 4

    var isOpen: Bool { !sources.isEmpty }
    var shownTargets: [ConvertTarget] { Array(targets.dropFirst(page * Self.perPage).prefix(Self.perPage)) }
    var hasMore: Bool { targets.count > Self.perPage }
    var isLastPage: Bool { (page + 1) * Self.perPage >= targets.count }

    func shelfState(dragging: Bool) -> ShelfConvert {
        if isOpen { return .open(places: shownTargets.count + (hasMore ? 1 : 0)) }
        return dragging && dragCarriesFiles && Prefs.bool(Prefs.convert) ? .offered : .hidden
    }

    /// Opened by letting go on Convert, so the drag has ended and a click picks the format; otherwise
    /// the drag ending without a drop puts the shelf back.
    private(set) var awaitingClick = false

    /// The row turns into what these files can become. False when there's nothing to offer.
    @discardableResult
    func open(with urls: [URL], awaitingClick: Bool = false) -> Bool {
        let kind = urls.first.flatMap(ConvertSource.of)
        let list = ConvertCatalog.targets(for: urls, withPack: false, lastUsed: kind.flatMap(Prefs.convertLastUsed))
        guard !list.isEmpty else { return false }
        withAnimation(Motion.reshape) {
            sources = urls
            targets = list
            page = 0
        }
        self.awaitingClick = awaitingClick
        onChange?()
        return true
    }

    /// A drag ended: unless it was let go on Convert, the shelf comes back.
    func dragEnded() {
        if isOpen, !awaitingClick { close() }
    }

    /// The next four formats; after the last, back to the first.
    func nextPage() {
        withAnimation(Motion.reshape) { page = isLastPage ? 0 : page + 1 }
        onChange?()
    }

    func close() {
        guard isOpen else { return }
        withAnimation(Motion.reshape) {
            sources = []
            targets = []
            page = 0
        }
        awaitingClick = false
        onChange?()
    }

    /// The files under the drag right now. Read only once the drag rests on Convert, which is the
    /// person asking for them to be converted; the drag watcher otherwise reads only the type list.
    static func draggedFiles() -> [URL] {
        let urls = NSPasteboard(name: .drag).readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        return urls ?? []
    }

    // MARK: Converting

    func convert(_ urls: [URL], to target: ConvertTarget) {
        guard !urls.isEmpty else { return }
        if let kind = ConvertSource.of(urls[0]) { Prefs.setConvertLastUsed(target, for: kind) }
        let job = ConvertJob(sources: urls, target: target)
        withAnimation(Motion.peekIn) { jobs.append(job) }
        onChange?()
        let id = job.id
        let options = ConvertOptions(photoQuality: Self.photoQuality, audioBitRate: max(64, Prefs.int(Prefs.convertAudioKbps)) * 1000,
                                     toDownloads: Prefs.bool(Prefs.convertToDownloads))
        let keepOriginal = Prefs.bool(Prefs.convertKeepOriginal)
        showActivitySoon(for: id)
        Task {
            do {
                let made = try await ConvertEngine.run(urls, to: target, options: options) { [weak self] share in
                    Task { @MainActor in self?.update(id, progress: share) }
                }
                finish(id, made: made, removing: keepOriginal ? [] : urls)
            } catch {
                fail(id, error.localizedDescription)
            }
        }
    }

    private static var photoQuality: Double {
        switch Prefs.string(Prefs.convertPhotoQuality) {
        case "balanced": 0.75
        case "smaller": 0.55
        default: 0.9
        }
    }

    private func update(_ id: UUID, progress: Double) {
        guard let index = jobs.firstIndex(where: { $0.id == id }), jobs[index].state == .running,
              progress - jobs[index].progress >= 0.01 || progress >= 1 else { return }
        jobs[index].progress = progress
        if activity?.id == id { activity?.progress = progress }
    }

    private func finish(_ id: UUID, made: [URL], removing originals: [URL]) {
        withAnimation(Motion.peekOut) { jobs.removeAll { $0.id == id } }
        onMade?(made)
        // Only once there's something to show for it does the original go, and to the Trash.
        for url in originals where !made.contains(url) { try? FileManager.default.trashItem(at: url, resultingItemURL: nil) }
        settleActivity(id, as: .done)
        onChange?()
    }

    private func fail(_ id: UUID, _ reason: String) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].state = .failed(reason)
        settleActivity(id, as: .failed(reason))
        // The place stays a few seconds to say so, then goes.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            withAnimation(Motion.peekOut) { self?.jobs.removeAll { $0.id == id } }
            self?.onChange?()
        }
    }

    func dismiss(_ job: ConvertJob) {
        guard job.state != .running else { return }
        withAnimation(Motion.peekOut) { jobs.removeAll { $0.id == job.id } }
        onChange?()
    }

    /// A conversion that's done within a moment never shows beside the notch; a longer one does, with
    /// its ring, then a check (or a warning) for a moment before the island goes back to what it showed.
    private func showActivitySoon(for id: UUID) {
        activityTask?.cancel()
        activityTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled, let self, let job = jobs.first(where: { $0.id == id }), job.state == .running else { return }
            activity = job
            onChange?()
        }
    }

    private func settleActivity(_ id: UUID, as state: ConvertJob.State) {
        guard activity?.id == id else {
            activityTask?.cancel()
            return
        }
        activity?.state = state
        activity?.progress = 1
        activityTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled, let self, activity?.id == id else { return }
            activity = nil
            onChange?()
        }
    }

    #if DEBUG
    /// For stills: the row open on these files, or a conversion part-way through.
    func debugOpen(_ urls: [URL]) { open(with: urls) }

    func debugJob(_ urls: [URL], to target: ConvertTarget, progress: Double, beside notch: Bool) {
        var job = ConvertJob(sources: urls, target: target)
        job.progress = progress
        jobs.append(job)
        if notch { activity = job }
        onChange?()
    }
    #endif
}
