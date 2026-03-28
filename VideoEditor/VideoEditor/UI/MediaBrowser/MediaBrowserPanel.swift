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
        .onDrop(of: [.movie, .video, .audio, .fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
            return true
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { data, _ in
                guard let data = data as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                Task { @MainActor in
                    _ = try? await appState.importMedia(from: url)
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 0) {
            CinematicPanelHeader(
                eyebrow: "LIBRARY",
                title: "Project Bin",
                subtitle: "Import media and drag it into exact timeline lanes",
                trailingAccessory: {
                    HStack(spacing: 8) {
                        CinematicStatusPill(
                            text: "\(appState.assets.count) assets",
                            icon: "shippingbox",
                            tone: CinematicTheme.aqua
                        )
                        CinematicToolbarButton(icon: "plus", label: "Import", isActive: true) {
                            isImporting = true
                        }
                    }
                }
            )
            .background(CinematicTheme.surfaceContainerHighest.opacity(0.72))

            if let importError {
                HStack {
                    CinematicStatusPill(
                        text: importError,
                        icon: "exclamationmark.triangle.fill",
                        tone: CinematicTheme.error
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
                    AssetThumbnailView(asset: asset, thumbnail: thumbnails[asset.id]) {
                        addToTimeline(asset)
                    }
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
                guard url.startAccessingSecurityScopedResource() else { continue }
                defer { url.stopAccessingSecurityScopedResource() }
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

    // MARK: - Add to timeline

    private func addToTimeline(_ asset: MediaAsset) {
        Task { @MainActor in
            await appState.addAssetToTimeline(asset)
        }
    }

    private static let allowedTypes: [UTType] = [
        .movie, .video, .quickTimeMovie, .mpeg4Movie, .avi,
        .audio, .mp3, .wav, .aiff,
        .image, .png, .jpeg, .heic, .tiff,
    ]
}

// MARK: - Thumbnail View

struct AssetThumbnailView: View {
    let asset: MediaAsset
    let thumbnail: CGImage?
    var onAddToTimeline: (() -> Void)?

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
