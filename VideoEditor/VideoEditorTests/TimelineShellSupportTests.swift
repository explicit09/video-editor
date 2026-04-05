import Foundation
import Testing
@testable import EditorCore
@testable import VideoEditor

@Suite("Timeline Shell Support Tests")
struct TimelineShellSupportTests {

    @Test("shell metrics reserve compact header and ruler space")
    func shellMetricsCompactChrome() {
        let metrics = TimelineShellMetrics.make(
            viewportWidth: 1280,
            viewportHeight: 720,
            trackCount: 3,
            expandedTrackHeight: 84,
            collapsedTrackHeight: 28
        )

        #expect(metrics.headerWidth == 152)
        #expect(metrics.rulerHeight == 32)
        #expect(metrics.scrollContentHeight > metrics.rulerHeight)
    }

    @Test("selection reveal returns vertical and horizontal anchors when needed")
    func selectionRevealBothAxes() {
        let viewport = TimelineViewport(
            visibleXRange: 0...900,
            visibleYRange: 0...200
        )
        let frame = TimelineVisibleFrame(
            minX: 980,
            maxX: 1180,
            minY: 320,
            maxY: 408
        )

        let request = TimelineScrollTargetResolver.requestToReveal(
            frame,
            in: viewport,
            padding: 40
        )

        #expect(request?.anchorX == 940)
        #expect(request?.anchorY == 280)
    }

    @Test("auto-follow keeps playhead visible only when enabled")
    func autoFollowPlayheadRequest() {
        let viewport = TimelineViewport(
            visibleXRange: 200...800,
            visibleYRange: 0...240
        )

        #expect(
            TimelineScrollTargetResolver.requestToKeepPlayheadVisible(
                playheadX: 340,
                in: viewport,
                autoFollow: false,
                padding: 72
            ) == nil
        )

        let request = TimelineScrollTargetResolver.requestToKeepPlayheadVisible(
            playheadX: 860,
            in: viewport,
            autoFollow: true,
            padding: 72
        )

        #expect(request?.anchorX == 788)
    }

    @Test("scroll request resolution preserves the current axis when needed")
    func scrollTargetResolutionPreservesUnspecifiedAxis() {
        let request = TimelineScrollRequest(anchorX: 940, anchorY: nil)

        let target = TimelineScrollTargetResolver.resolveScrollTarget(
            for: request,
            horizontalOffset: 200,
            verticalOffset: 75
        )

        #expect(target == TimelineScrollTarget(horizontalOffset: 940, verticalOffset: 75))
    }

    @Test("timeline snapping respects playhead and nearby clip edges")
    func timelineSnapResolverUsesExistingPoints() {
        let clip = Clip(
            assetID: UUID(),
            timelineRange: TimeRange(start: 5.1, end: 9.1),
            sourceRange: TimeRange(start: 0, end: 4)
        )
        let timeline = Timeline(
            tracks: [Track(name: "V1", type: .video, clips: [clip])],
            markers: [Marker(time: 12, label: "Cut")]
        )

        let snapped = TimelineSnapResolver.snappedTime(
            for: 5.08,
            excluding: [UUID()],
            in: timeline,
            playhead: 0,
            snapEnabled: true,
            snapThresholdPixels: 8,
            zoom: 100
        )

        #expect(snapped == 5.1)
    }

    @Test("timeline view state exposes explicit auto-follow state")
    @MainActor
    func timelineViewStateAutoFollowFlag() {
        let viewState = TimelineViewState()

        #expect(viewState.autoFollowPlayhead == false)

        viewState.autoFollowPlayhead = true

        #expect(viewState.autoFollowPlayhead == true)
    }

    @Test("selection zoom expands to the minimum duration around the selection")
    func selectionZoomExpandsAroundSelection() {
        let range = TimelineSelectionZoomResolver.zoomRange(
            selection: 32...38,
            fallbackPlayhead: 36,
            viewportWidth: 1280,
            minimumDuration: 8
        )

        #expect(range == 31...39)
    }

    @Test("selection zoom clamps to zero without treating viewport width as timeline duration")
    func selectionZoomClampsToZero() {
        let range = TimelineSelectionZoomResolver.zoomRange(
            selection: 1...3,
            fallbackPlayhead: 2,
            viewportWidth: 320,
            minimumDuration: 8
        )

        #expect(range == 0...8)
    }
}
