import SwiftUI
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
        HStack {
            Text("PROJECT BIN")
                .font(.cinLabel)
                .tracking(1.5)
                .foregroundStyle(CinematicTheme.onSurface)
            Spacer()
            Button(action: { isImporting = true }) {
                Image(systemName: "plus")
                    .foregroundStyle(CinematicTheme.onSurfaceVariant)
            }
            .buttonStyle(.plain)
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: Self.allowedTypes,
                allowsMultipleSelection: true
            ) { result in
                Task { await handleImport(result) }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "film")
                .font(.system(size: 32))
                .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.4))
            Text("Import media to get started")
                .font(.cinBody)
                .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.6))
            Button(action: { isImporting = true }) {
                Text("Import Media")
                    .font(.cinTitleSmall)
                    .foregroundStyle(CinematicTheme.onPrimaryContainer)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(CinematicTheme.primaryContainer)
                    .clipShape(RoundedRectangle(cornerRadius: CinematicRadius.md))
            }
            .buttonStyle(.plain)
            if let error = importError {
                Text(error)
                    .font(.cinLabelRegular)
                    .foregroundStyle(CinematicTheme.error)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Asset List (vertical clips with thumbnails)

    private var assetList: some View {
        ScrollView {
            VStack(spacing: 8) {
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
            .padding(12)
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
        appState.addAssetToTimeline(asset)
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
            // Thumbnail
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
            .frame(width: 80, height: 50)
            .clipShape(RoundedRectangle(cornerRadius: CinematicRadius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: CinematicRadius.lg)
                    .strokeBorder(CinematicTheme.outlineVariant.opacity(0.1), lineWidth: 1)
            )

            // Info
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
        }
        .padding(6)
        .background(CinematicTheme.surfaceContainerLowest)
        .clipShape(RoundedRectangle(cornerRadius: CinematicRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: CinematicRadius.lg)
                .strokeBorder(CinematicTheme.outlineVariant.opacity(0.1), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onAddToTimeline?() }
        .onTapGesture(count: 1) { }
        .help("Double-click to add to timeline")
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
        let mins = Int(asset.duration) / 60
        let secs = Int(asset.duration) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
