import SwiftUI
import EditorCore

struct TimelinePanel: View {
    @Environment(AppState.self) private var appState
    @State private var thumbnails: [UUID: CGImage] = [:]
    @State private var waveforms: [UUID: [Float]] = [:]
    @State private var trackHeights: [UUID: Double] = [:]
    private let defaultTrackHeight: Double = 76
    private let expandedTrackHeight: Double = 104

    /// Re-run media loading when the timeline changes, when assets become available,
    /// or when background analysis writes a waveform profile onto an existing asset.
    private var mediaLoadKey: [String] {
        let assetsByID = Dictionary(uniqueKeysWithValues: appState.assets.map { ($0.id, $0) })

        return appState.timeline.tracks
            .flatMap(\.clips)
            .map { clip in
                guard let asset = assetsByID[clip.assetID] else {
                    return "\(clip.assetID.uuidString):missing"
                }

                let waveformCount = asset.analysis?.loudnessProfile?.count ?? 0
                return "\(clip.assetID.uuidString):present:\(waveformCount)"
            }
    }

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
        .task(id: mediaLoadKey) {
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
        HStack(spacing: CinematicSpacing.sm) {
            Menu {
                Button("Video Track") { appState.addTrack(of: .video) }
                Button("Audio Track") { appState.addTrack(of: .audio) }
                Button("Text Track") { appState.addTrack(of: .text) }
                Button("Effect Track") { appState.addTrack(of: .effect) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text("Add Track")
                        .font(.cinLabel)
                }
                .foregroundStyle(CinematicTheme.onSurface)
                .padding(.horizontal, 12)
                .frame(height: CinematicMetrics.controlHeight)
                .background(CinematicTheme.surfaceContainerHighest)
                .clipShape(Capsule())
            }
            .menuStyle(.button)

            HStack(spacing: 6) {
                CinematicToolbarButton(icon: "arrow.uturn.backward", action: { try? appState.undo() })
                    .disabled(!appState.commandHistory.canUndo)
                CinematicToolbarButton(icon: "arrow.uturn.forward", action: { try? appState.redo() })
                    .disabled(!appState.commandHistory.canRedo)
            }

            Spacer(minLength: 12)

            Button {
                viewState.snapEnabled.toggle()
            } label: {
                CinematicStatusPill(
                    text: viewState.snapEnabled ? "SNAP ON" : "SNAP OFF",
                    icon: "magnet",
                    tone: viewState.snapEnabled ? CinematicTheme.primary : CinematicTheme.onSurfaceVariant
                )
            }
            .buttonStyle(.plain)

            CinematicStatusPill(
                text: "\(timeline.tracks.count) lanes",
                icon: "square.stack.3d.down.right",
                tone: CinematicTheme.aqua
            )

            CinematicStatusPill(
                text: "\(Int(viewState.zoom)) px/s",
                icon: "timeline.selection",
                tone: CinematicTheme.tertiary
            )

            HStack(spacing: 6) {
                CinematicToolbarButton(icon: "minus", action: { viewState.zoomOut() })
                CinematicToolbarButton(icon: "arrow.left.and.right", action: { viewState.zoomToFit(duration: timeline.duration) })
                    .disabled(timeline.duration == 0)
                CinematicToolbarButton(icon: "plus", action: { viewState.zoomIn() })
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            LinearGradient(
                colors: [CinematicTheme.surfaceContainerHigh, CinematicTheme.surfaceContainerHighest.opacity(0.84)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
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
            ForEach(Array(timeline.tracks.enumerated()), id: \.element.id) { index, track in
                TimelineTrackView(
                    track: track,
                    trackHeight: trackHeight(for: track.id),
                    viewState: viewState,
                    selectedClipIDs: viewState.selectedClipIDs,
                    isSelectedTrack: viewState.selectedTrackID == track.id,
                    totalWidth: width,
                    thumbnails: thumbnails,
                    waveforms: waveforms,
                    onTrackTap: { viewState.selectedTrackID = track.id },
                    onRenameTrack: { newName in
                        appState.updateTrack(id: track.id) { $0.name = newName }
                    },
                    onToggleMute: {
                        appState.updateTrack(id: track.id) { $0.isMuted.toggle() }
                    },
                    onToggleLock: {
                        appState.updateTrack(id: track.id) { $0.isLocked.toggle() }
                    },
                    onAddLane: {
                        appState.addTrack(of: track.type)
                    },
                    onCycleHeight: {
                        cycleTrackHeight(for: track.id)
                    },
                    onRemoveTrack: track.clips.isEmpty ? {
                        try? appState.perform(.removeTrack(trackID: track.id))
                    } : nil,
                    onClipTap: { clipID, extend in
                        viewState.selectedTrackID = track.id
                        viewState.toggleSelection(clipID, extend: extend)
                    },
                    onClipDrag: { clipID, newStart, verticalOffset in
                        let targetTrackID = targetTrackID(
                            from: index,
                            verticalOffset: verticalOffset,
                            trackType: track.type,
                            in: timeline
                        )
                        try? appState.perform(.moveClip(clipID: clipID, newStart: newStart, trackID: targetTrackID))
                    },
                    onAssetDrop: { assetID, dropTime in
                        guard let asset = appState.assets.first(where: { $0.id == assetID }) else { return }
                        Task { @MainActor in
                            await appState.addAssetToTimeline(
                                asset,
                                preferredTrackID: track.id,
                                startTime: dropTime
                            )
                        }
                    },
                    onClipTrim: { clipID, newSourceStart, newSourceEnd in
                        try? appState.perform(.trimClip(clipID: clipID, newSourceRange: TimeRange(start: newSourceStart, end: newSourceEnd)))
                    }
                )
            }
            Spacer()
        }
    }

    private func targetTrackID(
        from currentIndex: Int,
        verticalOffset: Double,
        trackType: TrackType,
        in timeline: Timeline
    ) -> UUID {
        guard !timeline.tracks.isEmpty else { return UUID() }
        let baseCenter = trackCenterY(at: currentIndex, in: timeline)
        let proposedCenter = baseCenter + verticalOffset

        var cursor: Double = 0
        let fallback = timeline.tracks[currentIndex]

        for track in timeline.tracks {
            let height = trackHeight(for: track.id)
            let upperBound = cursor + height
            if proposedCenter <= upperBound {
                return track.type == trackType ? track.id : fallback.id
            }
            cursor = upperBound + CinematicSpacing.clipGap
        }

        let lastTrack = timeline.tracks.last ?? fallback
        return lastTrack.type == trackType ? lastTrack.id : fallback.id
    }

    private func trackHeight(for trackID: UUID) -> Double {
        trackHeights[trackID] ?? defaultTrackHeight
    }

    private func cycleTrackHeight(for trackID: UUID) {
        let current = trackHeights[trackID] ?? defaultTrackHeight
        let next: Double
        switch current {
        case ..<75:
            next = expandedTrackHeight
        case ..<100:
            next = 60
        default:
            next = defaultTrackHeight
        }
        trackHeights[trackID] = next
    }

    private func trackCenterY(at index: Int, in timeline: Timeline) -> Double {
        var cursor: Double = 0
        for priorIndex in timeline.tracks.indices {
            let height = trackHeight(for: timeline.tracks[priorIndex].id)
            if priorIndex == index {
                return cursor + (height / 2)
            }
            cursor += height + CinematicSpacing.clipGap
        }
        return cursor
    }
}
