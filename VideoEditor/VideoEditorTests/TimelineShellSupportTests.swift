import Foundation
import Testing
@testable import VideoEditor

@Suite("Timeline Shell Support Tests")
struct TimelineShellSupportTests {

    @Test("Shell metrics reserve compact header and ruler space")
    func shellMetricsReserveCompactHeaderAndRulerSpace() {
        let metrics = TimelineShellMetrics()

        #expect(metrics.compactHeaderHeight == 50)
        #expect(metrics.rulerHeight == 28)
        #expect(metrics.reservedTopInset == 78)
    }

    @Test("Selection visibility requests horizontal reveal when clip is offscreen")
    func selectionVisibilityRequestsHorizontalRevealWhenClipIsOffscreen() {
        let viewport = TimelineViewport(
            visibleFrame: TimelineVisibleFrame(originX: 100, width: 200)
        )
        let clipFrame = TimelineVisibleFrame(originX: 320, width: 60)

        let request = TimelineScrollTargetResolver.selectionVisibilityRequest(
            for: clipFrame,
            in: viewport
        )

        #expect(request == TimelineScrollRequest(horizontalOffset: 80))
    }

    @Test("Auto-follow keeps playhead visible only when enabled")
    func autoFollowKeepsPlayheadVisibleOnlyWhenEnabled() {
        let viewport = TimelineViewport(
            visibleFrame: TimelineVisibleFrame(originX: 100, width: 200)
        )

        #expect(
            TimelineScrollTargetResolver.playheadVisibilityRequest(
                playheadX: 340,
                in: viewport,
                autoFollowEnabled: false
            ) == nil
        )

        #expect(
            TimelineScrollTargetResolver.playheadVisibilityRequest(
                playheadX: 340,
                in: viewport,
                autoFollowEnabled: true
            ) == TimelineScrollRequest(horizontalOffset: 40)
        )
    }
}
