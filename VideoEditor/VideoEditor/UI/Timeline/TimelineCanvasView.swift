import SwiftUI
import AppKit
import EditorCore

struct TimelineCanvasView: View {
    @Environment(AppState.self) private var appState

    let tool: EditorTool
    let timeline: Timeline
    let viewState: TimelineViewState
    let layoutState: TrackLayoutState
    let thumbnails: [UUID: CGImage]
    let waveformStates: [UUID: WaveformLoadState]
    let coordinator: TimelineScrollCoordinator
    let rowSpacing: Double

    @State private var scrollRequestToken = UUID()
    @State private var pendingScrollTarget: TimelineScrollTarget?

    var body: some View {
        GeometryReader { geo in
            let contentWidth = max(viewState.durationToWidth(timeline.duration + 10), geo.size.width)
            let contentHeight = max(layoutState.totalContentHeight(for: timeline.tracks, rowSpacing: rowSpacing), geo.size.height)

            ScrollViewReader { proxy in
                ScrollView([.horizontal, .vertical], showsIndicators: true) {
                    ZStack(alignment: .topLeading) {
                        timelineBackdrop(width: contentWidth, height: contentHeight)

                        if timeline.tracks.isEmpty {
                            emptyTimeline(width: contentWidth, height: contentHeight)
                        } else {
                            ForEach(Array(timeline.tracks.enumerated()), id: \.element.id) { index, track in
                                timelineRow(
                                    track: track,
                                    trackIndex: index,
                                    contentWidth: contentWidth
                                )
                                .offset(y: layoutState.yOffset(for: index, in: timeline.tracks, rowSpacing: rowSpacing))
                            }
                        }

                        MarkersOverlay(markers: timeline.markers, viewState: viewState)
                            .frame(width: contentWidth, height: contentHeight, alignment: .topLeading)

                        if let pendingScrollTarget {
                            Color.clear
                                .frame(width: 1, height: 1)
                                .position(
                                    x: pendingScrollTarget.horizontalOffset,
                                    y: pendingScrollTarget.verticalOffset
                                )
                                .id(Self.scrollTargetMarkerID)
                        }
                    }
                    .frame(width: contentWidth, height: contentHeight, alignment: .topLeading)
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: TimelineScrollOffsetPreferenceKey.self,
                                value: CGPoint(
                                    x: -proxy.frame(in: .named(Self.scrollSpaceName)).minX,
                                    y: -proxy.frame(in: .named(Self.scrollSpaceName)).minY
                                )
                            )
                        }
                    )
                }
                .coordinateSpace(name: Self.scrollSpaceName)
                .onPreferenceChange(TimelineScrollOffsetPreferenceKey.self) { offset in
                    coordinator.update(horizontal: offset.x, vertical: offset.y)
                }
                .onChange(of: coordinator.pendingRequest) { _, _ in
                    guard let request = coordinator.takePendingRequest() else { return }
                    pendingScrollTarget = TimelineScrollTargetResolver.resolveScrollTarget(
                        for: request,
                        horizontalOffset: coordinator.horizontalOffset,
                        verticalOffset: coordinator.verticalOffset
                    )
                    scrollRequestToken = UUID()
                }
                .task(id: scrollRequestToken) {
                    guard pendingScrollTarget != nil else { return }
                    proxy.scrollTo(Self.scrollTargetMarkerID, anchor: .topLeading)
                }
                .background(CinematicTheme.surfaceContainer)
                .overlay(alignment: .topLeading) {
                    Rectangle()
                        .fill(CinematicTheme.outlineVariant.opacity(0.18))
                        .frame(height: 1)
                }
                .clipShape(Rectangle())
            }
        }
    }

    private func timelineRow(
        track: Track,
        trackIndex: Int,
        contentWidth: Double
    ) -> some View {
        TimelineTrackView(
            track: track,
            tool: tool,
            playheadTime: viewState.playheadPosition,
            trackHeight: layoutState.height(for: track),
            viewState: viewState,
            selectedClipIDs: viewState.selectedClipIDs,
            isSelectedTrack: viewState.selectedTrackID == track.id,
            totalWidth: contentWidth,
            thumbnails: thumbnails,
            waveformStates: waveformStates,
            snapTime: snapTime,
            onTrackTap: { appState.timelineViewState.selectTrack(track.id) },
            onRenameTrack: { _ in },
            onToggleMute: { },
            onToggleLock: { },
            onAddLane: { },
            onCycleHeight: { },
            onRemoveTrack: nil,
            onClipTap: { clipID, extend in appState.toggleClipSelection(clipID, extend: extend) },
            onClipDrag: { clipID, newStart, verticalOffset in
                handleClipDrag(
                    clipID: clipID,
                    newStart: newStart,
                    verticalOffset: verticalOffset,
                    sourceTrackIndex: trackIndex
                )
            },
            onAssetDrop: { assetID, startTime in
                handleAssetDrop(assetID: assetID, startTime: startTime, trackID: track.id)
            },
            onClipTrim: { clipID, newSourceStart, newSourceEnd in
                try? appState.perform(
                    .trimClip(
                        clipID: clipID,
                        newSourceRange: TimeRange(start: newSourceStart, end: newSourceEnd)
                    )
                )
            },
            onClipRippleTrim: { clipID, edge, delta in
                try? appState.perform(.rippleTrim(clipID: clipID, edge: edge, delta: delta))
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
                linkClips(for: clipID)
            },
            onClipUnlink: { clipID in
                unlinkClips(for: clipID)
            },
            isCollapsed: false,
            onToggleCollapse: nil
        )
        .frame(width: contentWidth, height: layoutState.height(for: track), alignment: .leading)
        .clipped()
    }

    private func timelineBackdrop(width: Double, height: Double) -> some View {
        Rectangle()
            .fill(CinematicTheme.surfaceContainer)
            .frame(width: width, height: height)
            .overlay(alignment: .topLeading) {
                Path { path in
                    var y = 8.0
                    for track in timeline.tracks {
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: width, y: y))
                        y += layoutState.height(for: track) + rowSpacing
                    }
                }
                .stroke(CinematicTheme.outlineVariant.opacity(0.14), lineWidth: 0.6)
            }
    }

    private func emptyTimeline(width: Double, height: Double) -> some View {
        VStack(spacing: 10) {
            Spacer()

            Image(systemName: "film.stack")
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.28))

            Text("Add a track to begin editing")
                .font(.cinBody)
                .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.5))

            Spacer()
        }
        .frame(width: width, height: height)
    }

    private func handleClipDrag(
        clipID: UUID,
        newStart: TimeInterval,
        verticalOffset: Double,
        sourceTrackIndex: Int
    ) {
        guard timeline.tracks.indices.contains(sourceTrackIndex) else { return }
        let snappedStart = snappedTime(for: newStart, excluding: [clipID])
        let targetTrackID = TimelineDropResolver.targetTrackID(
            currentIndex: sourceTrackIndex,
            verticalOffset: verticalOffset,
            movingTrackType: timeline.tracks[sourceTrackIndex].type,
            tracks: layoutState.timelineEntries(for: timeline.tracks),
            clipGap: rowSpacing
        )
        appState.moveSelection(primaryClipID: clipID, newStart: snappedStart, targetTrackID: targetTrackID)
    }

    private func handleAssetDrop(assetID: UUID, startTime: TimeInterval, trackID: UUID) {
        guard let asset = appState.assets.first(where: { $0.id == assetID }) else { return }
        let snappedStart = snappedTime(for: startTime, excluding: [])

        Task { @MainActor in
            await appState.addAssetToTimeline(
                asset,
                preferredTrackID: trackID,
                startTime: snappedStart
            )
        }
    }

    private func linkClips(for clipID: UUID) {
        let clipIDs = selectionIDs(for: clipID)
        let linkGroupID = UUID()
        try? appState.perform(.linkClips(clipIDs: clipIDs, linkGroupID: linkGroupID))
    }

    private func unlinkClips(for clipID: UUID) {
        let clipIDs = selectionIDs(for: clipID)
        try? appState.perform(.linkClips(clipIDs: clipIDs, linkGroupID: nil))
    }

    private func selectionIDs(for clipID: UUID) -> [UUID] {
        let selected = appState.timelineViewState.selectedClipIDs
        if selected.contains(clipID), !selected.isEmpty {
            return Array(selected)
        }
        return [clipID]
    }

    private func snapTime(_ proposedTime: TimeInterval, _ clipIDs: Set<UUID>) -> TimeInterval {
        snappedTime(for: proposedTime, excluding: clipIDs)
    }

    private func snappedTime(for proposedTime: TimeInterval, excluding clipIDs: Set<UUID>) -> TimeInterval {
        TimelineSnapResolver.snappedTime(
            for: proposedTime,
            excluding: clipIDs,
            in: timeline,
            playhead: viewState.playheadPosition,
            snapEnabled: viewState.snapEnabled,
            snapThresholdPixels: viewState.snapThresholdPixels,
            zoom: viewState.zoom
        )
    }

    private static let scrollSpaceName = "TimelineCanvasScrollSpace"
    private static let scrollTargetMarkerID = "TimelineCanvasScrollTarget"
}

private struct TimelineScrollOffsetPreferenceKey: PreferenceKey {
    static let defaultValue: CGPoint = .zero

    static func reduce(value: inout CGPoint, nextValue: () -> CGPoint) {
        value = nextValue()
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
