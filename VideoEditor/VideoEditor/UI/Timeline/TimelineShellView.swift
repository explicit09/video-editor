import SwiftUI
import EditorCore

struct TimelineShellView: View {
    @Environment(AppState.self) private var appState

    let tool: EditorTool
    let timeline: Timeline
    let viewState: TimelineViewState
    let thumbnails: [UUID: CGImage]
    let waveformStates: [UUID: WaveformLoadState]

    @State private var scrollCoordinator = TimelineScrollCoordinator()

    private let rowSpacing = Double(CinematicSpacing.clipGap)
    private let toolbarHeight = Double(CinematicMetrics.controlHeight) + 20

    var body: some View {
        GeometryReader { geo in
            let metrics = TimelineShellMetrics.make(
                viewportWidth: geo.size.width,
                viewportHeight: geo.size.height,
                trackCount: timeline.tracks.count,
                expandedTrackHeight: viewState.trackLayoutState.expandedTrackHeight,
                collapsedTrackHeight: viewState.trackLayoutState.collapsedTrackHeight
            )
            let rightColumnWidth = max(geo.size.width - metrics.headerWidth, 0)
            let rightColumnHeight = max(geo.size.height - toolbarHeight, 0)

            VStack(spacing: 0) {
                TimelineToolbarView(tool: tool, viewState: viewState, timeline: timeline)

                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        TimelineCornerView()
                            .frame(width: metrics.headerWidth, height: metrics.rulerHeight)

                        TrackHeaderColumnView(
                            tracks: timeline.tracks,
                            viewState: viewState,
                            layoutState: viewState.trackLayoutState,
                            coordinator: scrollCoordinator
                        )
                        .frame(width: metrics.headerWidth)
                    }

                    VStack(spacing: 0) {
                        TimelineRuler(
                            viewState: viewState,
                            totalWidth: viewState.durationToWidth(timeline.duration + 10),
                            horizontalOffset: scrollCoordinator.horizontalOffset
                        )
                        .frame(height: metrics.rulerHeight)

                        TimelineCanvasView(
                            tool: tool,
                            timeline: timeline,
                            viewState: viewState,
                            layoutState: viewState.trackLayoutState,
                            thumbnails: thumbnails,
                            waveformStates: waveformStates,
                            coordinator: scrollCoordinator,
                            rowSpacing: rowSpacing
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(width: rightColumnWidth, height: rightColumnHeight, alignment: .topLeading)
                    .overlay(alignment: .topLeading) {
                        PlayheadView(
                            viewState: viewState,
                            onSeek: { appState.seekFromPlayhead() },
                            horizontalOffset: scrollCoordinator.horizontalOffset,
                            scrubHeight: metrics.rulerHeight
                        )
                        .frame(width: rightColumnWidth, height: rightColumnHeight, alignment: .topLeading)
                        .allowsHitTesting(true)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(shellBackground)
            .onAppear {
                updateVisibleWidth(containerSize: geo.size, metrics: metrics)
                updateScrollRequest(containerSize: geo.size, metrics: metrics)
            }
            .onChange(of: geo.size.width) { _, _ in
                updateVisibleWidth(containerSize: geo.size, metrics: metrics)
            }
            .onChange(of: viewState.selectedClipIDs) { _, _ in
                updateScrollRequest(containerSize: geo.size, metrics: metrics)
            }
            .onChange(of: viewState.playheadPosition) { _, _ in
                updateScrollRequest(containerSize: geo.size, metrics: metrics)
            }
            .onChange(of: viewState.autoFollowPlayhead) { _, _ in
                updateScrollRequest(containerSize: geo.size, metrics: metrics)
            }
            .onChange(of: scrollCoordinator.horizontalOffset) { _, _ in
                updateScrollRequest(containerSize: geo.size, metrics: metrics)
            }
            .onChange(of: scrollCoordinator.verticalOffset) { _, _ in
                updateScrollRequest(containerSize: geo.size, metrics: metrics)
            }
        }
    }

    private func updateVisibleWidth(containerSize: CGSize, metrics: TimelineShellMetrics) {
        viewState.visibleWidth = max(containerSize.width - metrics.headerWidth, 0)
    }

    private var shellBackground: some View {
        LinearGradient(
            colors: [
                CinematicTheme.surface,
                CinematicTheme.surfaceDim,
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(CinematicTheme.primaryContainer.opacity(0.08))
                .frame(width: 260, height: 260)
                .blur(radius: 70)
                .offset(x: 90, y: -50)
        }
    }

    private func updateScrollRequest(containerSize: CGSize, metrics: TimelineShellMetrics) {
        let visibleWidth = max(containerSize.width - metrics.headerWidth, 0)
        let visibleHeight = max(containerSize.height - toolbarHeight - metrics.rulerHeight, 0)
        let viewport = TimelineViewport(
            visibleXRange: scrollCoordinator.horizontalOffset ... (scrollCoordinator.horizontalOffset + visibleWidth),
            visibleYRange: scrollCoordinator.verticalOffset ... (scrollCoordinator.verticalOffset + visibleHeight)
        )

        let selectionRequest = selectionRevealRequest(in: viewport)
        let playheadRequest = TimelineScrollTargetResolver.requestToKeepPlayheadVisible(
            playheadX: viewState.durationToWidth(viewState.playheadPosition),
            in: viewport,
            autoFollow: viewState.autoFollowPlayhead,
            padding: 72
        )

        scrollCoordinator.requestScroll(selectionRequest ?? playheadRequest)
    }

    private func selectionRevealRequest(in viewport: TimelineViewport) -> TimelineScrollRequest? {
        guard let frame = selectedClipFrame() else { return nil }

        return TimelineScrollTargetResolver.requestToReveal(
            frame,
            in: viewport,
            padding: 40
        )
    }

    private func selectedClipFrame() -> TimelineVisibleFrame? {
        var minX: Double?
        var maxX: Double?
        var minY: Double?
        var maxY: Double?

        for (index, track) in timeline.tracks.enumerated() {
            let rowY = viewState.trackLayoutState.yOffset(for: index, in: timeline.tracks, rowSpacing: rowSpacing)
            let rowHeight = viewState.trackLayoutState.height(for: track)

            for clip in track.clips where viewState.selectedClipIDs.contains(clip.id) {
                let clipMinX = viewState.durationToWidth(clip.timelineRange.start)
                let clipMaxX = viewState.durationToWidth(clip.timelineRange.end)

                minX = min(minX ?? clipMinX, clipMinX)
                maxX = max(maxX ?? clipMaxX, clipMaxX)
                minY = min(minY ?? rowY, rowY)
                maxY = max(maxY ?? (rowY + rowHeight), rowY + rowHeight)
            }
        }

        guard let minX, let maxX, let minY, let maxY else { return nil }
        return TimelineVisibleFrame(minX: minX, maxX: maxX, minY: minY, maxY: maxY)
    }
}
