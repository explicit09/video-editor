import SwiftUI
import CoreTransferable
import EditorCore
import UniformTypeIdentifiers

/// Media workspace — Stitch Screen 7: Smart Bins + grid + inspector.
/// Shown when "Media" workspace is selected in the side nav.
struct MediaWorkspacePanel: View {
    @Environment(AppState.self) private var appState
    @State private var searchQuery = ""
    @State private var selectedAssetID: UUID?
    @State private var selectedBinID: String?
    @State private var sortOrder: SortOrder = .dateAdded
    @State private var isImporting = false
    @State private var importError: String?
    @State private var thumbnails: [UUID: CGImage] = [:]

    enum SortOrder: String, CaseIterable {
        case dateAdded = "Date Added"
        case name = "Name"
        case duration = "Duration"
    }

    var body: some View {
        VStack(spacing: 0) {
            CinematicPanelHeader(
                eyebrow: "MEDIA WORKSPACE",
                title: "Library Browser",
                subtitle: "Organize sources, review metadata, and send assets to the timeline",
                trailingAccessory: {
                    HStack(spacing: 8) {
                        CinematicStatusPill(
                            text: "\(filteredAssets.count) visible",
                            icon: "rectangle.grid.2x2",
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

            HStack(spacing: 0) {
                smartBins
                    .frame(width: 220)

                mediaGrid

                if let assetID = selectedAssetID,
                   let asset = appState.assets.first(where: { $0.id == assetID }) {
                    assetInspector(asset)
                        .frame(width: 280)
                }
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
        .onDrop(of: [.movie, .video, .audio, .fileURL], isTargeted: nil) { providers in
            Task { await handleDrop(providers) }
            return true
        }
    }

    // MARK: - Smart Bins

    private var smartBins: some View {
        let bins = SmartBinClassifier.classify(appState.assets)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("SMART BINS")
                    .font(.cinLabel)
                    .tracking(1.5)
                    .foregroundStyle(CinematicTheme.onSurface)
                Spacer()
                Button(action: { selectedBinID = nil }) {
                    CinematicStatusPill(
                        text: "All",
                        icon: "line.3.horizontal.decrease.circle",
                        tone: selectedBinID == nil ? CinematicTheme.primary : CinematicTheme.onSurfaceVariant
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(bins) { bin in
                        smartBinRow(bin: bin, isSelected: selectedBinID == bin.id)
                    }
                }
                .padding(.horizontal, 8)
            }

            Spacer()

            HStack {
                CinematicToolbarButton(icon: "plus.circle.fill", label: "Import Media", isActive: true) {
                    isImporting = true
                }
                Spacer()
            }
            .padding(CinematicSpacing.md)
        }
        .background(CinematicTheme.surfaceContainerLow)
    }

    private func smartBinRow(bin: SmartBinClassifier.SmartBin, isSelected: Bool) -> some View {
        Button(action: { selectedBinID = isSelected ? nil : bin.id }) {
            HStack(spacing: 8) {
                Image(systemName: bin.icon)
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? CinematicTheme.primary : CinematicTheme.primary.opacity(0.5))
                    .frame(width: 20)
                Text(bin.label)
                    .font(.cinBody)
                    .foregroundStyle(isSelected ? CinematicTheme.onSurface : CinematicTheme.onSurfaceVariant)
                Spacer()
                Text("\(bin.count)")
                    .font(.cinLabelRegular)
                    .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.4))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(CinematicTheme.surfaceContainerHighest)
                    .clipShape(RoundedRectangle(cornerRadius: CinematicRadius.sm))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(isSelected ? CinematicTheme.primaryContainer.opacity(0.14) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: CinematicRadius.md))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Media Grid

    private var mediaGrid: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Menu {
                    ForEach(SortOrder.allCases, id: \.self) { order in
                        Button(order.rawValue) { sortOrder = order }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("Sort: \(sortOrder.rawValue)")
                            .font(.cinLabelRegular)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8))
                    }
                    .foregroundStyle(CinematicTheme.onSurface)
                    .padding(.horizontal, 10)
                    .frame(height: CinematicMetrics.controlHeight)
                    .background(CinematicTheme.surfaceContainerHighest)
                    .clipShape(Capsule())
                }

                Spacer()

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
                .padding(.vertical, 6)
                .background(CinematicTheme.surfaceContainerLowest)
                .clipShape(RoundedRectangle(cornerRadius: CinematicRadius.md))
                .frame(width: 220)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(CinematicTheme.surfaceContainer)

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
            CinematicEmptyStateBlock(
                icon: "rectangle.stack.badge.plus",
                title: "No assets match this view",
                detail: "Adjust the smart bin or search query, or import more media into the project."
            )
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
                    Text(TimeFormatter.duration(asset.duration))
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
        .background(
            LinearGradient(
                colors: [CinematicTheme.surfaceContainerHigh, CinematicTheme.surfaceContainerLowest],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: CinematicRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: CinematicRadius.lg)
                .strokeBorder(isSelected ? CinematicTheme.primary : CinematicTheme.outlineVariant.opacity(0.1), lineWidth: isSelected ? 1.5 : 0.5)
        )
        .onTapGesture(count: 2) { addToTimeline(asset) }
        .onTapGesture(count: 1) { selectedAssetID = asset.id }
        .draggable(TimelineAssetDragPayload(assetID: asset.id))
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
            CinematicPanelHeader(
                eyebrow: "INSPECTOR",
                title: asset.name,
                subtitle: "Source metadata and AI analysis",
                trailingAccessory: {
                    CinematicToolbarButton(icon: "xmark", action: { selectedAssetID = nil })
                }
            )
            .background(CinematicTheme.surfaceContainerHighest.opacity(0.72))

            if let cgImage = thumbnails[asset.id] {
                Image(decorative: cgImage, scale: 1.0)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 140)
                    .clipShape(RoundedRectangle(cornerRadius: CinematicRadius.lg))
                    .padding(.horizontal, 12)
            }

            Spacer().frame(height: 16)

            VStack(alignment: .leading, spacing: 12) {
                metadataRow("FILENAME", asset.name)
                if let w = asset.width, let h = asset.height {
                    metadataRow("RESOLUTION", "\(w) × \(h)")
                }
                if let codec = asset.codec {
                    metadataRow("CODEC", codec)
                }
                if asset.duration > 0 {
                    metadataRow("DURATION", TimeFormatter.duration(asset.duration))
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
        CinematicInspectorFieldRow(label: label) {
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

        // Filter by selected bin
        if let binID = selectedBinID {
            let bins = SmartBinClassifier.classify(appState.assets)
            if let bin = bins.first(where: { $0.id == binID }) {
                let binIDs = Set(bin.assetIDs)
                assets = assets.filter { binIDs.contains($0.id) }
            }
        }

        // Filter by search
        if !searchQuery.isEmpty {
            assets = assets.filter { $0.name.localizedCaseInsensitiveContains(searchQuery) }
        }

        // Sort
        switch sortOrder {
        case .dateAdded: break
        case .name: assets.sort { $0.name < $1.name }
        case .duration: assets.sort { $0.duration > $1.duration }
        }
        return assets
    }

    private func addToTimeline(_ asset: MediaAsset) {
        Task { @MainActor in
            await appState.addAssetToTimeline(asset)
        }
    }

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


    private func formatFileSize(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        let mb = Double(bytes) / 1_048_576
        return String(format: "%.0f MB", mb)
    }
}
