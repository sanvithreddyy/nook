import SwiftUI

/// The newer version, Update Now, and what changed, as System Settings shows a macOS update.
struct UpdatePane: View {
    private let updates = Updates.shared

    var body: some View {
        SettingsPage(title: SettingsPane.update.title) {
            if let release = updates.release {
                SettingsSection {
                    HStack(spacing: 12) {
                        Image(nsImage: NSApp.applicationIconImage)
                            .resizable()
                            .frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Nook \(release.version)").font(.headline)
                            Text(status(of: release))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Spacer(minLength: 12)
                        action
                            .frame(minWidth: 120, alignment: .trailing)
                    }
                    .padding(.vertical, 12)
                    if !release.notes.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(release.notes, id: \.self) { note in
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text("•").foregroundStyle(.secondary)
                                    Text(note).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12)
                    }
                }
            }
        }
    }

    @ViewBuilder private var action: some View {
        switch updates.phase {
        case .ready:
            Button("Update Now") { updates.install() }
                .buttonStyle(.borderedProminent)
        case .downloading(let received, let total):
            ProgressView(value: Double(received), total: Double(max(total, received, 1)))
                .frame(width: 120)
        case .installing:
            ProgressView()
                .progressViewStyle(.linear)
                .frame(width: 120)
        case .failed:
            Button("Try Again") { updates.install() }
        }
    }

    private func status(of release: Updates.Release) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        // "0 KB", not "Zero KB", as the download starts.
        formatter.allowsNonnumericFormatting = false
        let size = { (bytes: Int64) in formatter.string(fromByteCount: bytes) }
        return switch updates.phase {
        case .ready: size(release.size)
        case .downloading(let received, let total): "Downloading… \(size(received)) of \(size(max(total, received)))"
        case .installing: "Installing… Nook will reopen."
        case .failed: "The update didn't finish."
        }
    }
}

/// At the top of the sidebar while there's a newer version, as System Settings shows a macOS update.
struct UpdateSidebarRow: View {
    var body: some View {
        HStack(spacing: 8) {
            Text("Update Available")
            Spacer(minLength: 4)
            Text("1")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .frame(minWidth: 18, minHeight: 18)
                .background(.red, in: .circle)
        }
    }
}
