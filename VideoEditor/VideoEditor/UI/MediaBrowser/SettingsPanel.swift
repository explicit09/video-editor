import SwiftUI

struct SettingsPanel: View {
    @Environment(AppState.self) private var appState
    @State private var exportFolder: URL? = ExportFolderManager.defaultFolder
    @State private var mediaFolders: [URL] = ExportFolderManager.mediaFolders
    @State private var storageInfo = StorageInfo()

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: CinematicSpacing.lg) {
                    exportSection
                    mediaSourcesSection
                    storageSection
                }
                .padding(CinematicSpacing.md)
            }
        }
        .background(CinematicTheme.surfaceContainerLow)
        .onAppear { refreshStorage() }
    }

    // MARK: - Header

    private var header: some View {
        UtilityPanelHeader(
            eyebrow: "PREFERENCES",
            title: "Settings",
            subtitle: "Export, media sources, and storage"
        )
    }

    // MARK: - Export Section

    private var exportSection: some View {
        settingsSection(title: "Export Folder", icon: "square.and.arrow.up") {
            VStack(alignment: .leading, spacing: CinematicSpacing.xs) {
                HStack(spacing: 8) {
                    Image(systemName: "folder")
                        .font(.system(size: 12))
                        .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.5))
                    Text(exportFolder?.path ?? "Not set -- using system tmp")
                        .font(.cinLabelRegular)
                        .foregroundStyle(
                            exportFolder != nil
                                ? CinematicTheme.onSurface
                                : CinematicTheme.onSurfaceVariant.opacity(0.5)
                        )
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                }
                .padding(CinematicSpacing.xs)
                .background(CinematicTheme.surfaceContainerLowest)
                .clipShape(RoundedRectangle(cornerRadius: CinematicRadius.sm))

                HStack(spacing: 8) {
                    CinematicToolbarButton(icon: "folder.badge.plus", label: "Set Export Folder", isActive: true) {
                        if let url = ExportFolderManager.pickDefaultFolder() {
                            exportFolder = url
                        }
                    }
                    if exportFolder != nil {
                        CinematicToolbarButton(icon: "xmark", label: "Clear", isDestructive: true) {
                            ExportFolderManager.clearDefaultFolder()
                            exportFolder = nil
                        }
                    }
                }
            }
        }
    }

    // MARK: - Media Sources Section

    private var mediaSourcesSection: some View {
        settingsSection(title: "Media Sources", icon: "film.stack") {
            VStack(alignment: .leading, spacing: CinematicSpacing.xs) {
                Text("Files imported from these folders are referenced in-place, saving disk space.")
                    .font(.cinLabelRegular)
                    .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.6))

                if mediaFolders.isEmpty {
                    HStack {
                        Spacer()
                        Text("No media folders added")
                            .font(.cinBody)
                            .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.4))
                        Spacer()
                    }
                    .padding(.vertical, CinematicSpacing.md)
                } else {
                    ForEach(mediaFolders, id: \.absoluteString) { folder in
                        mediaFolderRow(folder)
                    }
                }

                CinematicToolbarButton(icon: "plus", label: "Add Media Folder", isActive: true) {
                    if ExportFolderManager.addMediaFolder() != nil {
                        mediaFolders = ExportFolderManager.mediaFolders
                    }
                }
            }
        }
    }

    private func mediaFolderRow(_ folder: URL) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "folder.fill")
                .font(.system(size: 11))
                .foregroundStyle(CinematicTheme.tertiary.opacity(0.7))

            Text(folder.lastPathComponent)
                .font(.cinTitleSmall)
                .foregroundStyle(CinematicTheme.onSurface)
                .lineLimit(1)

            Text(folder.deletingLastPathComponent().path)
                .font(.cinLabelRegular)
                .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.4))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Button {
                removeMediaFolder(folder)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.4))
            }
            .buttonStyle(.plain)
            .help("Remove folder")
        }
        .padding(CinematicSpacing.xs)
        .background(CinematicTheme.surfaceContainerLowest)
        .clipShape(RoundedRectangle(cornerRadius: CinematicRadius.sm))
    }

    // MARK: - Storage Section

    private var storageSection: some View {
        settingsSection(title: "Storage", icon: "internaldrive") {
            VStack(alignment: .leading, spacing: CinematicSpacing.xs) {
                storageRow(label: "Project Media", size: storageInfo.mediaSize)
                storageRow(label: "Proxy Renders", size: storageInfo.proxySize)
                storageRow(label: "Temp Exports", size: storageInfo.tmpSize)

                HStack(spacing: 8) {
                    CinematicToolbarButton(icon: "trash", label: "Clean Proxies") {
                        cleanDirectory(appState.projectBundleURL.appendingPathComponent("Proxies"))
                        refreshStorage()
                    }
                    CinematicToolbarButton(icon: "trash", label: "Clean Temp Exports") {
                        cleanDirectory(FileManager.default.temporaryDirectory)
                        refreshStorage()
                    }
                }
            }
        }
    }

    private func storageRow(label: String, size: Int64) -> some View {
        HStack {
            Text(label)
                .font(.cinBody)
                .foregroundStyle(CinematicTheme.onSurface)
            Spacer()
            Text(formattedSize(size))
                .font(.cinLabel)
                .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.6))
        }
        .padding(.vertical, 2)
    }

    // MARK: - Section Container

    private func settingsSection<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: CinematicSpacing.sm) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CinematicTheme.primary)
                Text(title.uppercased())
                    .font(.cinLabel)
                    .tracking(1.2)
                    .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.72))
            }

            content()
        }
        .padding(CinematicSpacing.md)
        .background(
            LinearGradient(
                colors: [CinematicTheme.surfaceContainerLowest, CinematicTheme.surfaceContainerHigh.opacity(0.76)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: CinematicRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: CinematicRadius.lg)
                .strokeBorder(CinematicTheme.outlineVariant.opacity(0.14), lineWidth: 1)
        )
    }

    // MARK: - Helpers

    private func removeMediaFolder(_ folder: URL) {
        ExportFolderManager.removeMediaFolderBookmark(url: folder)
        mediaFolders = ExportFolderManager.mediaFolders
    }

    private func refreshStorage() {
        let fm = FileManager.default
        let bundleURL = appState.projectBundleURL
        storageInfo.mediaSize = directorySize(bundleURL.appendingPathComponent("Media"), fm: fm)
        storageInfo.proxySize = directorySize(bundleURL.appendingPathComponent("Proxies"), fm: fm)
        storageInfo.tmpSize = directorySize(fm.temporaryDirectory, fm: fm)
    }

    private func directorySize(_ url: URL, fm: FileManager) -> Int64 {
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    private func cleanDirectory(_ url: URL) {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) else { return }
        for item in contents {
            try? fm.removeItem(at: item)
        }
    }

    private func formattedSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

private struct StorageInfo {
    var mediaSize: Int64 = 0
    var proxySize: Int64 = 0
    var tmpSize: Int64 = 0
}
