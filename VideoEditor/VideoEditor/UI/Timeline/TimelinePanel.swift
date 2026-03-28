import SwiftUI
import EditorCore

struct TimelinePanel: View {
    @Environment(AppState.self) private var appState
    @State private var thumbnails: [UUID: CGImage] = [:]
    @State private var waveforms: [UUID: [Float]] = [:]

    var body: some View {
        let viewState = appState.timelineViewState
        let timeline = appState.timeline

        VStack(spacing: 0) {
            timelineToolbar(viewState: viewState, timeline: timeline)
            GeometryReader { geo in
                let totalWidth = max(viewState.durationToWidth(timeline.duration + 10), geo.size.width)

                ScrollView([.horizontal], showsIndicators: true) {
                    ZStack(alignment: .topLeading) {
                        VStack(spacing: 0) {
                            TimelineRuler(viewState: viewState, totalWidth: totalWidth)
                                .frame(height: 28)

                            if timeline.tracks.isEmpty {
                                emptyTimeline(width: totalWidth, height: geo.size.height - 30)
                            } else {
                                trackStack(timeline: timeline, viewState: viewState, width: totalWidth)
                            }
                        }
                        .frame(width: totalWidth)

                        MarkersOverlay(markers: timeline.markers, viewState: viewState)
                            .frame(width: totalWidth, height: geo.size.height)

                        PlayheadView(viewState: viewState) {
                            appState.seekFromPlayhead()
                        }
                        .frame(width: totalWidth, height: geo.size.height)
                    }
                }
                .onAppear { viewState.visibleWidth = geo.size.width }
                .onChange(of: geo.size.width) { _, new in viewState.visibleWidth = new }
                .gesture(
                    MagnifyGesture()
                        .onChanged { value in
                            let newZoom = viewState.zoom * value.magnification
                            viewState.zoom = min(max(newZoom, TimelineViewState.zoomRange.lowerBound), TimelineViewState.zoomRange.upperBound)
                        }
                )
            }
        }
        .background(CinematicTheme.surfaceContainer)
        .task(id: appState.timeline.tracks.flatMap(\.clips).map(\.id)) {
            await loadWaveformsForAllClips()
        }
        .focusable()
        .onKeyPress(.space) {
            appState.playbackEngine.togglePlayPause()
            return .handled
        }
        .onKeyPress(.delete) {
            deleteSelectedClips()
            return .handled
        }
        .onKeyPress(KeyEquivalent("\u{7F}")) {
            guard !appState.timelineViewState.selectedClipIDs.isEmpty else { return .ignored }
            deleteSelectedClips()
            return .handled
        }
    }

    private func loadWaveformsForAllClips() async {
        for track in appState.timeline.tracks {
            for clip in track.clips {
                let assetID = clip.assetID
                // Skip if already loaded
                guard waveforms[assetID] == nil else { continue }
                guard let asset = appState.assets.first(where: { $0.id == assetID }) else { continue }

                // Load thumbnail
                if thumbnails[assetID] == nil {
                    let thumb = await appState.media.thumbnail(for: assetID)
                    if let thumb { thumbnails[assetID] = thumb }
                }

                // Load waveform — from analysis or extract
                if let profile = asset.analysis?.loudnessProfile, !profile.isEmpty {
                    waveforms[assetID] = profile
                } else {
                    let extractor = WaveformExtractor()
                    if let profile = await extractor.extract(from: asset.sourceURL) {
                        waveforms[assetID] = profile
                    }
                }
            }
        }
    }

    private func deleteSelectedClips() {
        let selected = Array(appState.timelineViewState.selectedClipIDs)
        guard !selected.isEmpty else { return }
        try? appState.perform(.deleteClips(clipIDs: selected))
        appState.timelineViewState.clearSelection()
    }

    // MARK: - Toolbar

    private func timelineToolbar(viewState: TimelineViewState, timeline: Timeline) -> some View {
        HStack(spacing: 12) {
            // Add Track
            Button(action: {
                let count = timeline.tracks.count
                let track = Track(name: "Video \(count + 1)", type: .video)
                try? appState.perform(.addTrack(track: track))
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                    Text("Add Track")
                        .font(.cinLabel)
                }
                .foregroundStyle(CinematicTheme.onSurfaceVariant)
            }
            .buttonStyle(.plain)

            Spacer()

            // Undo/Redo
            HStack(spacing: 8) {
                Button(action: { try? appState.undo() }) {
                    Image(systemName: "arrow.uturn.backward")
                        .foregroundStyle(appState.commandHistory.canUndo ? CinematicTheme.onSurface : CinematicTheme.onSurfaceVariant.opacity(0.3))
                }
                .buttonStyle(.plain)
                .disabled(!appState.commandHistory.canUndo)

                Button(action: { try? appState.redo() }) {
                    Image(systemName: "arrow.uturn.forward")
                        .foregroundStyle(appState.commandHistory.canRedo ? CinematicTheme.onSurface : CinematicTheme.onSurfaceVariant.opacity(0.3))
                }
                .buttonStyle(.plain)
                .disabled(!appState.commandHistory.canRedo)
            }

            Spacer()

            // Magnet/snap toggle
            HStack(spacing: 4) {
                Image(systemName: "magnet")
                    .font(.system(size: 11))
                Text("MAGNET: ON")
                    .font(.cinLabel)
                    .tracking(0.5)
            }
            .foregroundStyle(CinematicTheme.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(CinematicTheme.primaryContainer.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: CinematicRadius.md))

            Spacer()

            // AI Sync indicator
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10))
                Text("AI SYNC ACTIVE")
                    .font(.cinLabel)
                    .tracking(0.5)
            }
            .foregroundStyle(CinematicTheme.primary.opacity(0.6))

            Spacer()

            // Zoom controls
            HStack(spacing: 8) {
                Button(action: { viewState.zoomOut() }) {
                    Image(systemName: "minus")
                        .font(.system(size: 10))
                        .foregroundStyle(CinematicTheme.onSurfaceVariant)
                }
                .buttonStyle(.plain)

                Button(action: { viewState.zoomToFit(duration: timeline.duration) }) {
                    Image(systemName: "arrow.left.and.right")
                        .font(.system(size: 10))
                        .foregroundStyle(CinematicTheme.onSurfaceVariant)
                }
                .buttonStyle(.plain)
                .disabled(timeline.duration == 0)

                Text("\(Int(viewState.zoom))px/s")
                    .font(.cinLabelRegular)
                    .monospacedDigit()
                    .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.5))
                    .frame(width: 50)

                Button(action: { viewState.zoomIn() }) {
                    Image(systemName: "plus")
                        .font(.system(size: 10))
                        .foregroundStyle(CinematicTheme.onSurfaceVariant)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(CinematicTheme.surfaceContainerHigh)
    }

    // MARK: - Empty State

    private func emptyTimeline(width: Double, height: Double) -> some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "film.stack")
                .font(.system(size: 28))
                .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.3))
            Text("Add a track to begin editing")
                .font(.cinBody)
                .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.5))
            Spacer()
        }
        .frame(width: width, height: height)
    }

    // MARK: - Track Stack

    private func trackStack(timeline: Timeline, viewState: TimelineViewState, width: Double) -> some View {
        VStack(spacing: CinematicSpacing.clipGap) {
            ForEach(timeline.tracks) { track in
                TimelineTrackView(
                    track: track,
                    viewState: viewState,
                    selectedClipIDs: viewState.selectedClipIDs,
                    isSelectedTrack: viewState.selectedTrackID == track.id,
                    totalWidth: width,
                    thumbnails: thumbnails,
                    waveforms: waveforms,
                    onTrackTap: { viewState.selectedTrackID = track.id },
                    onClipTap: { clipID, extend in
                        viewState.selectedTrackID = track.id
                        viewState.toggleSelection(clipID, extend: extend)
                    },
                    onClipDrag: { clipID, newStart in
                        try? appState.perform(.moveClip(clipID: clipID, newStart: newStart, trackID: track.id))
                    },
                    onClipTrim: { clipID, newSourceStart, newSourceEnd in
                        try? appState.perform(.trimClip(clipID: clipID, newSourceRange: TimeRange(start: newSourceStart, end: newSourceEnd)))
                    }
                )
            }
            Spacer()
        }
    }
}
