import AppKit
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

/// Convert, beside AirDrop while files are dragged. A drag that rests on it opens it, the way a Finder
/// folder springs open: the shelf's row becomes the formats the files can become. Let go on it before it
/// opens and it opens anyway, for a click on a format.
struct ConvertPlace: View {
    @Environment(ConvertModel.self) private var convert
    @Environment(NotchModel.self) private var model
    @State private var targeted = false
    @State private var cannot = false
    @State private var spring: Task<Void, Never>?

    var body: some View {
        let lit = targeted && !cannot
        ShelfPlace(name: cannot ? "Can't Convert" : "Convert", nameOpacity: cannot ? 0.5 : 0.92, highlight: lit ? 0.1 : 0, ring: lit) {
            Circle()
                .fill(Color(white: convert.isOpen ? 0.3 : 0.22))
                .overlay(
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.white.opacity(cannot ? 0.35 : 0.95))
                )
                .frame(width: 56, height: 56)
        }
        .scaleEffect(lit ? 1.03 : 1)
        .animation(Motion.press, value: lit)
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            model.setDraggingFile(false)
            Task {
                let urls = await providers.fileURLs()
                if convert.isOpen { return }
                if convert.open(with: urls, awaitingClick: true) { Haptics.tap() } else { cannot = true }
            }
            return true
        }
        .onChange(of: targeted) { _, now in
            spring?.cancel()
            guard now, !convert.isOpen, !cannot else { return }
            spring = Task {
                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled else { return }
                if convert.open(with: ConvertModel.draggedFiles()) { Haptics.tap() } else { cannot = true }
            }
        }
        .onChange(of: model.isDraggingFile) { _, dragging in if dragging { cannot = false } }
        .help("Rest a file here to convert it")
        .accessibilityLabel("Convert")
    }
}

/// The formats the files can become, four at a time, growing out of Convert toward the left.
struct ConvertFormatsRow: View {
    @Environment(ConvertModel.self) private var convert

    var body: some View {
        // The row and More keep their identity as the page turns; only the formats change. Rebuilding
        // the place a drag rests on (More, as it turns the page) left drops on the next page unanswered.
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(convert.shownTargets.enumerated()), id: \.element) { index, target in
                FormatPlace(target: target)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.5, anchor: .trailing).combined(with: .opacity)
                            .animation(Motion.reshape?.delay(Double(convert.shownTargets.count - index) * 0.03)),
                        removal: .opacity.animation(Motion.ease(.easeOut(duration: 0.1)))))
            }
            if convert.hasMore { MoreFormatsPlace() }
        }
    }
}

/// One format: the system's own icon for that kind of document, as Finder draws it.
private struct FormatPlace: View {
    @Environment(ConvertModel.self) private var convert
    @Environment(NotchModel.self) private var model
    let target: ConvertTarget
    @State private var targeted = false
    @State private var hovering = false

    var body: some View {
        let download = convert.downloads(target, for: convert.sources)
        ShelfPlace(name: target.name, highlight: targeted ? 0.1 : hovering ? 0.08 : 0, ring: targeted) {
            Image(nsImage: NSWorkspace.shared.icon(for: target.iconType))
                .resizable()
                .aspectRatio(contentMode: .fit)
                // From More Formats, which downloads the first time it's picked.
                .overlay(alignment: .bottomTrailing) {
                    if download {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 17))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color(white: 0.3))
                            .background(Circle().fill(.black).padding(-1.5))
                            .offset(x: 2, y: 2)
                    }
                }
        }
        .scaleEffect(targeted ? 1.03 : 1)
        .animation(Motion.press, value: targeted)
        .onHover { inside in withAnimation(.easeOut(duration: 0.15)) { hovering = inside } }
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            model.setDraggingFile(false)
            let opened = convert.sources
            Task {
                let dropped = await providers.fileURLs()
                choose(dropped.isEmpty ? opened : dropped)
            }
            return true
        }
        .onTapGesture { choose(convert.sources) }
        .help(download ? "Convert to \(target.name) (downloads More Formats first)" : "Convert to \(target.name)")
        .accessibilityAddTraits(.isButton)
    }

    private func choose(_ urls: [URL]) {
        convert.convert(urls, to: target)
        convert.close()
    }
}

/// The next four formats; on the last four, back to the first. A drag resting on it turns the page.
private struct MoreFormatsPlace: View {
    @Environment(ConvertModel.self) private var convert
    @State private var targeted = false
    @State private var hovering = false
    @State private var spring: Task<Void, Never>?

    var body: some View {
        let back = convert.isLastPage
        ShelfPlace(name: back ? "Back" : "More", nameOpacity: 0.6, highlight: targeted ? 0.1 : hovering ? 0.08 : 0, ring: targeted) {
            RoundedRectangle(cornerRadius: ShelfMetrics.corner, style: .continuous)
                .fill(.white.opacity(targeted ? 0.14 : 0.1))
                .overlay(
                    Image(systemName: back ? "arrow.uturn.backward" : "ellipsis")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                )
        }
        .onHover { inside in withAnimation(.easeOut(duration: 0.15)) { hovering = inside } }
        .onTapGesture { convert.nextPage() }
        .onDrop(of: [.fileURL], isTargeted: $targeted) { _ in false }
        .onChange(of: targeted) { _, now in
            spring?.cancel()
            guard now else { return }
            spring = Task {
                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled else { return }
                convert.nextPage()
                Haptics.tap()
            }
        }
        .accessibilityLabel(back ? "First formats" : "More formats")
    }
}

/// In Clear All's place while the row shows formats: what's being converted.
struct ConvertTitle: View {
    @Environment(ConvertModel.self) private var convert

    var body: some View {
        let what = convert.sources.count == 1
            ? FileManager.default.displayName(atPath: convert.sources[0].path)
            : "\(convert.sources.count) files"
        (Text("Convert ").foregroundStyle(.white.opacity(0.6)) + Text(what).foregroundStyle(.white.opacity(0.92)) + Text(" to").foregroundStyle(.white.opacity(0.6)))
            .font(.system(size: 11.5, weight: .medium))
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: 360, alignment: .leading)
            .padding(.horizontal, 2)
            .frame(height: 21)
    }
}

/// A file being made: the original's picture under a ring, in the place the result will take. A failed
/// one shows a warning, says why on hover, and goes on a click or after a few seconds.
struct ConvertingPlace: View {
    @Environment(ConvertModel.self) private var convert
    let job: ConvertJob

    var body: some View {
        let failed: String? = if case .failed(let reason) = job.state { reason } else { nil }
        ShelfPlace(name: job.name, nameOpacity: 0.7) {
            Thumbnail(url: job.sources[0])
                .overlay {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.black.opacity(0.5))
                        if failed != nil {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(.orange)
                        } else {
                            ProgressRing(progress: job.progress, lineWidth: 3)
                                .frame(width: 28, height: 28)
                        }
                    }
                }
        }
        .onTapGesture { convert.dismiss(job) }
        .help(failed ?? "Converting to \(job.target.name)")
    }
}

/// A conversion's progress as a ring, white on a faint track.
struct ProgressRing: View {
    var progress: Double
    var lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.25), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.02, progress))
                .stroke(.white, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.2), value: progress)
        }
    }
}

/// Beside the notch while a conversion takes a while: the file on one side, its ring on the other, then
/// a check when it's done or a warning if it couldn't be.
struct ConvertActivitySide: View {
    @Environment(ConvertModel.self) private var convert
    let edge: HorizontalEdge
    let height: CGFloat

    var body: some View {
        if let job = convert.activity {
            Group {
                if edge == .leading {
                    // As big as the artwork the music shows there.
                    SmallThumbnail(url: job.sources[0])
                        .frame(width: height - 10, height: height - 10)
                } else {
                    Group {
                        switch job.state {
                        case .running:
                            ProgressRing(progress: job.progress, lineWidth: 2.5).padding(1.5)
                        case .done:
                            Image(systemName: "checkmark.circle.fill")
                                .resizable()
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .green)
                        case .failed:
                            Image(systemName: "exclamationmark.triangle.fill")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .foregroundStyle(.orange)
                        }
                    }
                    .frame(width: height - 14, height: height - 14)
                }
            }
            .concentric(edge, height: height)
        }
    }
}

/// A file's picture small enough for beside the notch.
private struct SmallThumbnail: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Image(nsImage: image ?? NSWorkspace.shared.icon(forFile: url.path))
            .resizable()
            .aspectRatio(contentMode: .fill)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .task(id: url) {
                let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 24, height: 24), scale: 2, representationTypes: .thumbnail)
                image = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage
            }
    }
}

extension Array where Element == NSItemProvider {
    /// The file URLs among dropped items.
    func fileURLs() async -> [URL] {
        var urls: [URL] = []
        for provider in self where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            let url: URL? = await withCheckedContinuation { continuation in
                _ = provider.loadObject(ofClass: URL.self) { url, _ in continuation.resume(returning: url) }
            }
            if let url, url.isFileURL { urls.append(url) }
        }
        return urls
    }
}
