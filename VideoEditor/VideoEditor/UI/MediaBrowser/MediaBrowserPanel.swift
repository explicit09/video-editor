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
            Divider()
            if appState.assets.isEmpty {
                emptyState
            } else {
                assetGrid
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Media")
                .font(.headline)
            Spacer()
            Button(action: { isImporting = true }) {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: Self.allowedTypes,
                allowsMultipleSelection: true
            ) { result in
                Task { await handleImport(result) }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "film")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("Import media to get started")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Import Files") { isImporting = true }
                .buttonStyle(.bordered)
            if let error = importError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Asset Grid

    private var assetGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                ForEach(appState.assets) { asset in
                    AssetThumbnailView(asset: asset, thumbnail: thumbnails[asset.id]) {
                        addToTimeline(asset)
                    }
                }
            }
            .padding(8)
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
                    let thumb = await appState.context.media.thumbnail(for: asset.id)
                    if let thumb { thumbnails[asset.id] = thumb }
                } catch {
                    importError = error.localizedDescription
                }
            }
        case .failure(let error):
            importError = error.localizedDescription
        }
    }

    // MARK: - Add to timeline (through Intent → Command pipeline)

    private func addToTimeline(_ asset: MediaAsset) {
        let timeline = appState.timeline
        let trackType: TrackType = asset.type == .audio ? .audio : .video
        let viewState = appState.timelineViewState

        // Prefer selected track if compatible, otherwise first matching, otherwise create new
        var trackID: UUID
        if let selectedID = viewState.selectedTrackID,
           let selected = timeline.tracks.first(where: { $0.id == selectedID && $0.type == trackType }) {
            trackID = selected.id
        } else if let existing = timeline.tracks.last(where: { $0.type == trackType }) {
            trackID = existing.id
        } else {
            let newTrack = Track(name: trackType.rawValue.capitalized, type: trackType)
            trackID = newTrack.id
            try? appState.perform(.addTrack(track: newTrack))
        }

        // Place clip at end of track
        let trackEnd = appState.timeline.tracks
            .first(where: { $0.id == trackID })?
            .clips.map(\.timelineRange.end).max() ?? 0

        let clip = Clip(
            assetID: asset.id,
            timelineRange: TimeRange(start: trackEnd, duration: max(asset.duration, 1)),
            sourceRange: TimeRange(start: 0, duration: max(asset.duration, 1)),
            metadata: ClipMetadata(label: asset.name)
        )
        try? appState.perform(.insertClip(clip: clip, trackID: trackID))
    }

    // MARK: - Allowed types

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
        VStack(spacing: 4) {
            if let cgImage = thumbnail {
                Image(decorative: cgImage, scale: 1.0)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 60)
                    .clipped()
                    .cornerRadius(4)
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(nsColor: .separatorColor))
                    .frame(height: 60)
                    .overlay {
                        Image(systemName: iconName)
                            .foregroundStyle(.secondary)
                    }
            }

            Text(asset.name)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.middle)

            Text(formattedDuration)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onAddToTimeline?() }
        .onTapGesture(count: 1) { /* prevents swallowing double-tap on macOS */ }
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
