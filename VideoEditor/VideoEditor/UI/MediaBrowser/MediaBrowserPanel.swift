import SwiftUI
import CoreTransferable
import EditorCore
import UniformTypeIdentifiers

struct MediaBrowserPanel: View {
    @Environment(AppState.self) private var appState
    @State private var thumbnails: [UUID: CGImage] = [:]
    @State private var isImporting = false
    @State private var importError: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            if appState.assets.isEmpty {
                emptyState
            } else {
                assetList
            }
        }
        .background(CinematicTheme.surfaceContainerLow)
        .onDrop(of: SupportedMediaTypes.dropTypes, isTargeted: nil) { providers in
            Task { await handleDrop(providers) }
            return true
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) async {
        importError = nil

        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            let url = await loadDroppedFileURL(from: provider)
            guard let url else { continue }
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let asset = try await appState.importMedia(from: url)
                let thumb = await appState.media.thumbnail(for: asset.id)
                if let thumb {
                    thumbnails[asset.id] = thumb
                }
            } catch {
                importError = error.localizedDescription
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 0) {
            UtilityPanelHeader(
                eyebrow: "LIBRARY",
                title: "Project Bin",
                subtitle: "Import media and drag it into exact timeline lanes",
                badgeCount: 1,
                showsPrimaryAction: true,
                trailingAccessory: { layout in
                    HStack(spacing: 8) {
                        if layout.showsSecondaryBadges {
                            UtilityHeaderBadge(
                                text: "\(appState.assets.count) assets",
                                systemImage: "shippingbox"
                            )
                        }

                        UtilityHeaderButton(
                            icon: "plus",
                            title: layout.showsSecondaryBadges ? "Import" : nil,
                            isProminent: true
                        ) {
                            isImporting = true
                        }
                    }
                }
            )

            if let importError {
                HStack {
                    UtilityStatusBadge(
                        text: importError,
                        icon: "exclamationmark.triangle.fill",
                        style: .danger
                    )
                    Spacer()
                }
                .padding(.horizontal, CinematicSpacing.md)
                .padding(.bottom, CinematicSpacing.sm)
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: Self.allowedTypes,
            allowsMultipleSelection: true
        ) { result in
            Task { await handleImport(result) }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            CinematicEmptyStateBlock(
                icon: "film.stack",
                title: "Import media to start building the edit",
                detail: "Double-click to append an asset or drag it onto a specific video or audio lane."
            ) {
                CinematicToolbarButton(icon: "plus", label: "Import Media", isActive: true) {
                    isImporting = true
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Asset List (vertical clips with thumbnails)

    private var assetList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(appState.assets) { asset in
                    let usedIDs = Set(appState.timeline.tracks.flatMap(\.clips).map(\.assetID))
                    AssetThumbnailView(
                        asset: asset,
                        thumbnail: thumbnails[asset.id],
                        onAddToTimeline: { addToTimeline(asset) },
                        onTranscribe: {
                            Task { await appState.media.transcribeAssets([asset.id]) }
                        },
                        onDelete: {
                            Task { @MainActor in
                                await appState.media.mediaManager.remove(id: asset.id)
                                await appState.media.refreshAssets()
                            }
                        },
                        hasTranscript: asset.analysis?.transcript != nil,
                        isInUse: usedIDs.contains(asset.id)
                    )
                    .task {
                        // Load thumbnail if not cached
                        if thumbnails[asset.id] == nil {
                            let thumb = await appState.media.thumbnail(for: asset.id)
                            if let thumb { thumbnails[asset.id] = thumb }
                        }
                    }
                }
            }
            .padding(CinematicSpacing.md)
        }
    }

    // MARK: - Import handling

    private func handleImport(_ result: Result<[URL], Error>) async {
        importError = nil
        switch result {
        case .success(let urls):
            for url in urls {
                let didAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if didAccess {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                do {
                    let asset = try await appState.importMedia(from: url)
                    let thumb = await appState.media.thumbnail(for: asset.id)
                    if let thumb { thumbnails[asset.id] = thumb }
                } catch {
                    importError = error.localizedDescription
                }
            }
        case .failure(let error):
            importError = error.localizedDescription
        }
    }

    private func loadDroppedFileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let data = item as? Data {
                    continuation.resume(returning: URL(dataRepresentation: data, relativeTo: nil))
                } else if let url = item as? URL {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    // MARK: - Add to timeline

    private func addToTimeline(_ asset: MediaAsset) {
        Task { @MainActor in
            await appState.addAssetToTimeline(asset)
        }
    }
    private static let allowedTypes: [UTType] = SupportedMediaTypes.fileImporterTypes
}

// MARK: - Thumbnail View

struct AssetThumbnailView: View {
    let asset: MediaAsset
    let thumbnail: CGImage?
    var onAddToTimeline: (() -> Void)?
    var onTranscribe: (() -> Void)?
    var onDelete: (() -> Void)?
    var hasTranscript: Bool = false
    var isInUse: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let cgImage = thumbnail {
                    Image(decorative: cgImage, scale: 1.0)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Rectangle()
                        .fill(CinematicTheme.surfaceContainerLowest)
                        .overlay {
                            Image(systemName: iconName)
                                .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.4))
                        }
                }
            }
            .frame(width: 88, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: CinematicRadius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: CinematicRadius.lg)
                    .strokeBorder(CinematicTheme.outlineVariant.opacity(0.1), lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(asset.name)
                    .font(.cinTitleSmall)
                    .foregroundStyle(CinematicTheme.onSurface)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 6) {
                    Text(formattedDuration)
                        .font(.cinLabelRegular)
                        .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.6))

                    if let codec = asset.codec {
                        Text(codec)
                            .font(.cinLabelRegular)
                            .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.4))
                    }
                }
            }

            Spacer()

            Image(systemName: "arrow.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.38))
        }
        .padding(8)
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
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onAddToTimeline?() }
        .onTapGesture(count: 1) { }
        .help("Double-click to add to timeline")
        .draggable(TimelineAssetDragPayload(assetID: asset.id))
        .contextMenu {
            Button("Add to Timeline") { onAddToTimeline?() }
            Divider()
            if hasTranscript {
                Label("Transcribed", systemImage: "checkmark.circle.fill")
            } else {
                Button("Transcribe") { onTranscribe?() }
            }
            Divider()
            Button("Delete Asset", role: .destructive) { onDelete?() }
                .disabled(isInUse)
        }
    }

    private var iconName: String {
        switch asset.type {
        case .video: "film"
        case .audio: "waveform"
        case .image: "photo"
        }
    }

    private var formattedDuration: String {
        guard asset.duration > 0 else { return "" }
        return TimeFormatter.duration(asset.duration)
    }
}
