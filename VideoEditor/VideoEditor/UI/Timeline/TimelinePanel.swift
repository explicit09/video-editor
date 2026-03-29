import Foundation
import SwiftUI
import AppKit
import EditorCore

struct TimelinePanel: View {
    let tool: EditorTool
    @Environment(AppState.self) private var appState
    @State private var thumbnails: [UUID: CGImage] = [:]
    @State private var trackHeights: [UUID: Double] = [:]
    @State private var collapsedTrackIDs: Set<UUID> = []
    @State private var pinchBaseZoom: Double?
    @State private var dragReorderTrackID: UUID?
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
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .frame(width: totalWidth, height: geo.size.height)
                            .onTapGesture {
                                viewState.clearSelection()
                            }

                        VStack(spacing: 0) {
                            TimelineRuler(viewState: viewState, totalWidth: totalWidth)
                                .frame(height: 28)
                                .padding(.leading, 182) // Align with clip area (after track label)

                            if timeline.tracks.isEmpty {
                                emptyTimeline(width: totalWidth, height: geo.size.height - 30)
                            } else {
                                trackStack(timeline: timeline, viewState: viewState, width: totalWidth)
                            }
                        }
                        .frame(width: totalWidth)

                        MarkersOverlay(markers: timeline.markers, viewState: viewState)
                            .frame(width: totalWidth, height: geo.size.height)
                            .padding(.leading, 182)

                        PlayheadView(viewState: viewState) {
                            appState.seekFromPlayhead()
                        }
                        .padding(.leading, 182)
                        .frame(width: totalWidth, height: geo.size.height)
                    }
                }
                .onAppear { viewState.visibleWidth = geo.size.width }
                .onChange(of: geo.size.width) { _, new in viewState.visibleWidth = new }
                .gesture(
                    MagnifyGesture()
                        .onChanged { value in
                            if pinchBaseZoom == nil {
                                pinchBaseZoom = viewState.zoom
                            }
                            viewState.setZoom((pinchBaseZoom ?? viewState.zoom) * value.magnification)
                        }
                        .onEnded { _ in
                            pinchBaseZoom = nil
                        }
                )
            }
        }
        .background(CinematicTheme.surfaceContainer)
        .task(id: mediaLoadKey) {
            await loadVisibleMedia()
        }
        .onChange(of: appState.timeline.tracks.map(\.id)) { _, trackIDs in
            let pruned = TimelineTrackDisplayStatePruner.prune(
                TimelineTrackDisplayState(trackHeights: trackHeights, collapsedTrackIDs: collapsedTrackIDs),
                validTrackIDs: Set(trackIDs)
            )
            trackHeights = pruned.trackHeights
            collapsedTrackIDs = pruned.collapsedTrackIDs
        }
        .focusable()
        .onKeyPress(.space) {
            guard EditorShortcutGuard.shouldHandleGlobalShortcut(isTextInputFocused: textInputIsFocused) else {
                return .ignored
            }
            appState.playbackEngine.togglePlayPause()
            return .handled
        }
        .onKeyPress(.delete) {
            guard EditorShortcutGuard.shouldHandleGlobalShortcut(isTextInputFocused: textInputIsFocused) else {
                return .ignored
            }
            deleteSelectedClips()
            return .handled
        }
        .onKeyPress(KeyEquivalent("\u{7F}")) {
            guard EditorShortcutGuard.shouldHandleGlobalShortcut(isTextInputFocused: textInputIsFocused) else {
                return .ignored
            }
            guard !appState.timelineViewState.selectedClipIDs.isEmpty else { return .ignored }
            deleteSelectedClips()
            return .handled
        }
    }

    private var textInputIsFocused: Bool {
        NSApp.keyWindow?.firstResponder is NSTextView
    }

    private func loadVisibleMedia() async {
        for track in appState.timeline.tracks {
            for clip in track.clips {
                let assetID = clip.assetID
                guard let asset = appState.assets.first(where: { $0.id == assetID }) else { continue }

                // Load thumbnail
                if thumbnails[assetID] == nil {
                    let thumb = await appState.media.thumbnail(for: assetID)
                    if let thumb { thumbnails[assetID] = thumb }
                }
                await appState.media.refreshWaveformState(for: asset.id)
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
        let selectedRange = selectedTimelineRange(in: timeline)

        return HStack(spacing: CinematicSpacing.sm) {
            Menu {
                Button("Video Track") { appState.addTrack(of: .video, positionedAfter: viewState.selectedTrackID) }
                Button("Audio Track") { appState.addTrack(of: .audio, positionedAfter: viewState.selectedTrackID) }
                Button("Text Track") { appState.addTrack(of: .text, positionedAfter: viewState.selectedTrackID) }
                Button("Effect Track") { appState.addTrack(of: .effect, positionedAfter: viewState.selectedTrackID) }
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
                    icon: "scope",
                    tone: viewState.snapEnabled ? CinematicTheme.primary : CinematicTheme.onSurfaceVariant
                )
            }
            .buttonStyle(.plain)

            Button {
                viewState.linkedSelectionEnabled.toggle()
            } label: {
                CinematicStatusPill(
                    text: viewState.linkedSelectionEnabled ? "LINKED ON" : "LINKED OFF",
                    icon: "link",
                    tone: viewState.linkedSelectionEnabled ? CinematicTheme.success : CinematicTheme.onSurfaceVariant
                )
            }
            .buttonStyle(.plain)

            CinematicStatusPill(
                text: "\(timeline.tracks.count) lanes",
                icon: "square.stack.3d.down.right",
                tone: CinematicTheme.aqua
            )

            CinematicStatusPill(
                text: zoomLabel(for: viewState.zoom),
                icon: "timeline.selection",
                tone: CinematicTheme.tertiary
            )

            Menu {
                Button("Zoom In") { viewState.zoomIn() }
                Button("Zoom Out") { viewState.zoomOut() }
                Divider()
                Button("Full Extent") { viewState.zoomToFit(duration: timeline.duration) }
                    .disabled(timeline.duration == 0)
                Button("Detail Zoom") { viewState.zoomToDetail() }
                if let selectedRange {
                    Button("Fit Selection") { viewState.zoomToRange(selectedRange) }
                }
                Divider()
                ForEach(TimelineViewState.zoomPresets, id: \.self) { preset in
                    Button(zoomLabel(for: preset)) { viewState.setZoom(preset) }
                }
            } label: {
                HStack(spacing: 6) {
                    CinematicToolbarButton(icon: "minus", action: { viewState.zoomOut() })
                    CinematicToolbarButton(icon: "arrow.left.and.right", action: { viewState.zoomToFit(duration: timeline.duration) })
                        .disabled(timeline.duration == 0)
                    CinematicToolbarButton(icon: "plus", action: { viewState.zoomIn() })
                }
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
                    tool: tool,
                    playheadTime: viewState.playheadPosition,
                    trackHeight: trackHeight(for: track.id),
                    viewState: viewState,
                    selectedClipIDs: viewState.selectedClipIDs,
                    isSelectedTrack: viewState.selectedTrackID == track.id,
                    totalWidth: width,
                    thumbnails: thumbnails,
                    waveformStates: appState.media.waveformStates,
                    snapTime: { proposedTime, excludedClipIDs in
                        snappedTime(for: proposedTime, excluding: excludedClipIDs)
                    },
                    onTrackTap: { viewState.selectTrack(track.id) },
                    onRenameTrack: { newName in
                        appState.updateTrack(id: track.id) { $0.name = newName }
                    },
                    onToggleMute: {
                        try? appState.perform(.muteTrack(trackID: track.id, muted: !track.isMuted))
                    },
                    onToggleLock: {
                        try? appState.perform(.lockTrack(trackID: track.id, locked: !track.isLocked))
                    },
                    onAddLane: {
                        appState.addTrack(of: track.type, positionedAfter: track.id)
                    },
                    onCycleHeight: {
                        cycleTrackHeight(for: track.id)
                    },
                    onRemoveTrack: track.clips.isEmpty ? {
                        try? appState.perform(.removeTrack(trackID: track.id))
                    } : nil,
                    onClipTap: { clipID, extend in
                        appState.toggleClipSelection(clipID, extend: extend)
                    },
                    onClipDrag: { clipID, newStart, verticalOffset in
                        let targetTrackID = targetTrackID(
                            from: index,
                            verticalOffset: verticalOffset,
                            trackType: track.type,
                            in: timeline
                        )
                        let excludedClipIDs = viewState.selectedClipIDs.contains(clipID)
                            ? viewState.selectedClipIDs
                            : [clipID]
                        let snappedStart = snappedTime(
                            for: newStart,
                            excluding: excludedClipIDs
                        )
                        appState.moveSelection(primaryClipID: clipID, newStart: snappedStart, targetTrackID: targetTrackID)
                    },
                    onAssetDrop: { assetID, dropTime in
                        guard let asset = appState.assets.first(where: { $0.id == assetID }) else { return }
                        // Validate track type compatibility
                        let isCompatible: Bool
                        switch (asset.type, track.type) {
                        case (.video, .video), (.video, .effect), (.audio, .audio):
                            isCompatible = true
                        default:
                            isCompatible = false
                        }
                        guard isCompatible else { return }
                        Task { @MainActor in
                            await appState.addAssetToTimeline(
                                asset,
                                preferredTrackID: track.id,
                                startTime: snappedTime(for: dropTime)
                            )
                        }
                    },
                    onClipTrim: { clipID, newSourceStart, newSourceEnd in
                        try? appState.perform(.trimClip(clipID: clipID, newSourceRange: TimeRange(start: newSourceStart, end: newSourceEnd)))
                    },
                    onClipSplit: { clipID, at in
                        try? appState.perform(.splitClip(clipID: clipID, at: at))
                    },
                    onClipDelete: { clipID in
                        try? appState.perform(.deleteClips(clipIDs: [clipID]))
                    },
                    onClipDuplicate: { clipID in
                        try? appState.perform(.duplicateClip(clipID: clipID))
                    },
                    onClipLink: { clipID in
                        let selected = Array(viewState.selectedClipIDs)
                        let toLink = selected.isEmpty ? [clipID] : selected
                        guard toLink.count >= 2 else { return }
                        try? appState.perform(.linkClips(clipIDs: toLink, linkGroupID: UUID()))
                    },
                    onClipUnlink: { clipID in
                        // Unlink this clip and all siblings
                        if let clip = appState.timeline.tracks.flatMap(\.clips).first(where: { $0.id == clipID }),
                           let group = clip.linkGroupID {
                            let siblings = appState.timeline.tracks.flatMap(\.clips).filter { $0.linkGroupID == group }.map(\.id)
                            try? appState.perform(.linkClips(clipIDs: siblings, linkGroupID: nil))
                        }
                    },
                    isCollapsed: collapsedTrackIDs.contains(track.id),
                    onToggleCollapse: {
                        if collapsedTrackIDs.contains(track.id) {
                            collapsedTrackIDs.remove(track.id)
                        } else {
                            collapsedTrackIDs.insert(track.id)
                        }
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
        let layout = timeline.tracks.map { track in
            TimelineTrackLayoutEntry(
                id: track.id,
                type: track.type,
                isLocked: track.isLocked,
                height: trackHeight(for: track.id)
            )
        }
        return TimelineDropResolver.targetTrackID(
            currentIndex: currentIndex,
            verticalOffset: verticalOffset,
            movingTrackType: trackType,
            tracks: layout,
            clipGap: CinematicSpacing.clipGap
        )
    }

    private func trackHeight(for trackID: UUID) -> Double {
        if collapsedTrackIDs.contains(trackID) { return 28 }
        return trackHeights[trackID] ?? defaultTrackHeight
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

    private func selectedTimelineRange(in timeline: Timeline) -> TimeRange? {
        let selectedClips = timeline.tracks
            .flatMap(\.clips)
            .filter { appState.timelineViewState.selectedClipIDs.contains($0.id) }

        guard let start = selectedClips.map(\.timelineRange.start).min(),
              let end = selectedClips.map(\.timelineRange.end).max(),
              end > start else {
            return nil
        }

        return TimeRange(start: start, end: end)
    }

    private func zoomLabel(for zoom: Double) -> String {
        if zoom < 10 {
            return String(format: "%.1f px/s", zoom)
        }
        return "\(Int(zoom.rounded())) px/s"
    }

    private func snappedTime(for proposedTime: TimeInterval, excluding clipIDs: Set<UUID> = []) -> TimeInterval {
        let clampedTime = max(0, proposedTime)
        let viewState = appState.timelineViewState
        guard viewState.snapEnabled else { return clampedTime }

        let snapThreshold = viewState.snapThresholdPixels / max(viewState.zoom, 0.001)
        let points = SnapUtils.snapPoints(
            from: appState.timeline,
            playhead: viewState.playheadPosition,
            excludeClipIDs: clipIDs
        )
        return SnapUtils.snap(time: clampedTime, to: points, threshold: snapThreshold) ?? clampedTime
    }
}
