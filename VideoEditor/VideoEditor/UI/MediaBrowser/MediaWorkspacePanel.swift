import SwiftUI
import EditorCore
import UniformTypeIdentifiers

/// Media workspace — Stitch Screen 7: Smart Bins + grid + inspector.
/// Shown when "Media" workspace is selected in the side nav.
struct MediaWorkspacePanel: View {
    @Environment(AppState.self) private var appState
    @State private var searchQuery = ""
    @State private var selectedAssetID: UUID?
    @State private var sortOrder: SortOrder = .dateAdded
    @State private var isImporting = false
    @State private var thumbnails: [UUID: CGImage] = [:]

    enum SortOrder: String, CaseIterable {
        case dateAdded = "Date Added"
        case name = "Name"
        case duration = "Duration"
    }

    var body: some View {
        HStack(spacing: 0) {
            // Smart Bins sidebar
            smartBins
                .frame(width: 180)

            // Media grid
            mediaGrid

            // Inspector (when asset selected)
            if let assetID = selectedAssetID,
               let asset = appState.assets.first(where: { $0.id == assetID }) {
                assetInspector(asset)
                    .frame(width: 240)
            }
        }
        .background(CinematicTheme.surface)
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.movie, .video, .quickTimeMovie, .mpeg4Movie, .audio, .mp3, .wav, .image, .png, .jpeg],
            allowsMultipleSelection: true
        ) { result in
            Task { await handleImport(result) }
        }
    }

    // MARK: - Smart Bins

    private var smartBins: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("SMART BINS")
                    .font(.cinLabel)
                    .tracking(1.5)
                    .foregroundStyle(CinematicTheme.onSurface)
                Spacer()
                Button(action: {}) {
                    Image(systemName: "plus")
                        .font(.system(size: 11))
                        .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            VStack(spacing: 2) {
                smartBinRow(icon: "film", label: "All Clips", count: appState.assets.filter { $0.type == .video }.count)
                smartBinRow(icon: "waveform", label: "Audio", count: appState.assets.filter { $0.type == .audio }.count)
                smartBinRow(icon: "photo", label: "Images", count: appState.assets.filter { $0.type == .image }.count)
                smartBinRow(icon: "text.alignleft", label: "Transcribed", count: appState.assets.filter { $0.analysis?.transcript != nil }.count)
            }
            .padding(.horizontal, 8)

            Spacer()

            // Import button
            Button(action: { isImporting = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14))
                    Text("Import Media")
                        .font(.cinTitleSmall)
                }
                .foregroundStyle(CinematicTheme.onPrimaryContainer)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(CinematicTheme.primaryContainer)
                .clipShape(RoundedRectangle(cornerRadius: CinematicRadius.md))
            }
            .buttonStyle(.plain)
            .padding(12)
        }
        .background(CinematicTheme.surfaceContainerLow)
    }

    private func smartBinRow(icon: String, label: String, count: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(CinematicTheme.primary.opacity(0.7))
                .frame(width: 20)
            Text(label)
                .font(.cinBody)
                .foregroundStyle(CinematicTheme.onSurface)
            Spacer()
            Text("\(count)")
                .font(.cinLabelRegular)
                .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.4))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(CinematicTheme.surfaceContainerHighest)
                .clipShape(RoundedRectangle(cornerRadius: CinematicRadius.sm))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .clipShape(RoundedRectangle(cornerRadius: CinematicRadius.md))
    }

    // MARK: - Media Grid

    private var mediaGrid: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 12) {
                // Sort
                Menu {
                    ForEach(SortOrder.allCases, id: \.self) { order in
                        Button(order.rawValue) { sortOrder = order }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("Sort by: \(sortOrder.rawValue)")
                            .font(.cinLabelRegular)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8))
                    }
                    .foregroundStyle(CinematicTheme.onSurfaceVariant)
                }

                Spacer()

                // Search
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.5))
                    TextField("Search clips...", text: $searchQuery)
                        .textFieldStyle(.plain)
                        .font(.cinBody)
                        .foregroundStyle(CinematicTheme.onSurface)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(CinematicTheme.surfaceContainerLowest)
                .clipShape(RoundedRectangle(cornerRadius: CinematicRadius.md))
                .frame(width: 180)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(CinematicTheme.surfaceContainer)

            // Grid
            if filteredAssets.isEmpty {
                emptyGrid
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                        ForEach(filteredAssets) { asset in
                            mediaCard(asset)
                        }
                    }
                    .padding(16)
                }
            }
        }
    }

    private var emptyGrid: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 36))
                .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.3))
            Text("Drag and drop media files here")
                .font(.cinBody)
                .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.6))
            Text("ProRes, H.264, H.265, and RAW supported up to 8K")
                .font(.cinLabelRegular)
                .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.3))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func mediaCard(_ asset: MediaAsset) -> some View {
        let isSelected = selectedAssetID == asset.id
        return VStack(alignment: .leading, spacing: 0) {
            // Thumbnail
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let cgImage = thumbnails[asset.id] {
                        Image(decorative: cgImage, scale: 1.0)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Rectangle()
                            .fill(CinematicTheme.surfaceContainerLowest)
                            .overlay {
                                Image(systemName: asset.type == .video ? "film" : asset.type == .audio ? "waveform" : "photo")
                                    .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.3))
                            }
                    }
                }
                .frame(height: 100)
                .clipped()

                // Duration badge
                if asset.duration > 0 {
                    Text(formatDuration(asset.duration))
                        .font(.cinLabel)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: CinematicRadius.sm))
                        .padding(6)
                }
            }

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(asset.name)
                    .font(.cinLabelRegular)
                    .foregroundStyle(CinematicTheme.onSurface)
                    .lineLimit(1)
                if let codec = asset.codec {
                    Text(codec)
                        .font(.cinLabelRegular)
                        .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.4))
                }
            }
            .padding(8)
        }
        .background(CinematicTheme.surfaceContainerHigh)
        .clipShape(RoundedRectangle(cornerRadius: CinematicRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: CinematicRadius.lg)
                .strokeBorder(isSelected ? CinematicTheme.primary : CinematicTheme.outlineVariant.opacity(0.1), lineWidth: isSelected ? 1.5 : 0.5)
        )
        .onTapGesture { selectedAssetID = asset.id }
        .onTapGesture(count: 2) { addToTimeline(asset) }
        .task {
            if thumbnails[asset.id] == nil {
                let thumb = await appState.media.thumbnail(for: asset.id)
                if let thumb { thumbnails[asset.id] = thumb }
            }
        }
    }

    // MARK: - Asset Inspector

    private func assetInspector(_ asset: MediaAsset) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("INSPECTOR")
                    .font(.cinLabel)
                    .tracking(1.5)
                    .foregroundStyle(CinematicTheme.onSurface)
                Spacer()
                Button(action: { selectedAssetID = nil }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10))
                        .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            // Preview thumbnail
            if let cgImage = thumbnails[asset.id] {
                Image(decorative: cgImage, scale: 1.0)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 140)
                    .clipShape(RoundedRectangle(cornerRadius: CinematicRadius.lg))
                    .padding(.horizontal, 12)
            }

            Spacer().frame(height: 16)

            // Metadata
            VStack(alignment: .leading, spacing: 12) {
                metadataRow("FILENAME", asset.name)
                if let w = asset.width, let h = asset.height {
                    metadataRow("RESOLUTION", "\(w) × \(h)")
                }
                if let codec = asset.codec {
                    metadataRow("CODEC", codec)
                }
                if asset.duration > 0 {
                    metadataRow("DURATION", formatDuration(asset.duration))
                }
                if asset.fileSize > 0 {
                    metadataRow("SIZE", formatFileSize(asset.fileSize))
                }

                // AI tags
                if asset.analysis?.transcript != nil {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("AI TAGS")
                            .font(.cinLabel)
                            .tracking(1)
                            .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.5))
                        HStack(spacing: 4) {
                            aiTag("TRANSCRIBED")
                            if asset.analysis?.silenceRanges != nil {
                                aiTag("ANALYZED")
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 12)

            Spacer()
        }
        .background(CinematicTheme.surfaceContainerLow)
    }

    private func metadataRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.cinLabel)
                .tracking(1)
                .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.5))
            Text(value)
                .font(.cinBody)
                .foregroundStyle(CinematicTheme.onSurface)
        }
    }

    private func aiTag(_ label: String) -> some View {
        Text(label)
            .font(.cinLabel)
            .tracking(0.5)
            .foregroundStyle(CinematicTheme.primary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(CinematicTheme.primaryContainer.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: CinematicRadius.sm))
    }

    // MARK: - Helpers

    private var filteredAssets: [MediaAsset] {
        var assets = appState.assets
        if !searchQuery.isEmpty {
            assets = assets.filter { $0.name.localizedCaseInsensitiveContains(searchQuery) }
        }
        switch sortOrder {
        case .dateAdded: break // already in import order
        case .name: assets.sort { $0.name < $1.name }
        case .duration: assets.sort { $0.duration > $1.duration }
        }
        return assets
    }

    private func addToTimeline(_ asset: MediaAsset) {
        let trackType: TrackType = asset.type == .audio ? .audio : .video
        var trackID: UUID
        if let existing = appState.timeline.tracks.last(where: { $0.type == trackType }) {
            trackID = existing.id
        } else {
            let track = Track(name: trackType.rawValue.capitalized, type: trackType)
            trackID = track.id
            try? appState.perform(.addTrack(track: track))
        }
        let trackEnd = appState.timeline.tracks.first(where: { $0.id == trackID })?.clips.map(\.timelineRange.end).max() ?? 0
        let clip = Clip(
            assetID: asset.id,
            timelineRange: TimeRange(start: trackEnd, duration: max(asset.duration, 1)),
            sourceRange: TimeRange(start: 0, duration: max(asset.duration, 1)),
            metadata: ClipMetadata(label: asset.name)
        )
        try? appState.perform(.insertClip(clip: clip, trackID: trackID))
    }

    private func handleImport(_ result: Result<[URL], Error>) async {
        switch result {
        case .success(let urls):
            for url in urls {
                guard url.startAccessingSecurityScopedResource() else { continue }
                defer { url.stopAccessingSecurityScopedResource() }
                _ = try? await appState.importMedia(from: url)
            }
        case .failure: break
        }
    }

    private func formatDuration(_ time: TimeInterval) -> String {
        let mins = Int(time) / 60
        let secs = Int(time) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func formatFileSize(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        let mb = Double(bytes) / 1_048_576
        return String(format: "%.0f MB", mb)
    }
}
