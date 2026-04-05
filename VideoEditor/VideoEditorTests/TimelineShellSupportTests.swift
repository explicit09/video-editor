import Foundation
import Testing
@testable import VideoEditor

@Suite("Timeline Shell Support Tests")
struct TimelineShellSupportTests {

    @Test("workspace shell sizes the composed top section within the available height budget")
    func workspaceShellSectionSizingContract() {
        let containerHeight = 680.0
        let layout = EditorWorkspaceShellLayout.make(
            containerWidth: 1360,
            containerHeight: containerHeight,
            leftRailVisible: true,
            rightRailVisible: true
        )

        let verticalSectionsHeight =
            layout.topSectionMinHeight +
            layout.timelineSectionMinHeight +
            Double(CinematicSpacing.md)

        #expect(layout.topSectionMinHeight > EditorWorkspaceShellLayout.topSectionChromeHeight)
        #expect(layout.previewContentMinHeight >= 220)
        #expect(layout.timelineSectionMinHeight >= 240)
        #expect(verticalSectionsHeight <= containerHeight)
    }

    @Test("workspace shell posture responds to container width")
    func workspaceShellWidthResponsivePosture() {
        let narrowLayout = EditorWorkspaceShellLayout.make(
            containerWidth: 1280,
            containerHeight: 980,
            leftRailVisible: true,
            rightRailVisible: true
        )
        let wideLayout = EditorWorkspaceShellLayout.make(
            containerWidth: 1880,
            containerHeight: 980,
            leftRailVisible: true,
            rightRailVisible: true
        )

        #expect(narrowLayout.centerColumnMaxWidth == nil)
        #expect(wideLayout.centerColumnMaxWidth != nil)
        #expect(narrowLayout.leftRailWidth < wideLayout.leftRailWidth)
        #expect(narrowLayout.rightRailWidth < wideLayout.rightRailWidth)
        #expect(wideLayout.rightRailWidth > wideLayout.leftRailWidth)
    }

    @Test("workspace shell preserves a readable program monitor on large editing windows")
    func workspaceShellPreservesReadableProgramMonitor() {
        let layout = EditorWorkspaceShellLayout.make(
            containerWidth: 1880,
            containerHeight: 980,
            leftRailVisible: true,
            rightRailVisible: true
        )

        #expect(layout.previewContentMinHeight >= 340)
        #expect(layout.timelineSectionMinHeight >= 380)
    }

    @Test("workspace shell gives landscape monitor content enough height in constrained windows")
    func workspaceShellAvoidsTinyLandscapeMonitorInConstrainedWindows() {
        let layout = EditorWorkspaceShellLayout.make(
            containerWidth: 980,
            containerHeight: 720,
            leftRailVisible: true,
            rightRailVisible: true,
            previewAspectRatio: 16.0 / 9.0
        )

        #expect(layout.previewContentMinHeight >= 240)
        #expect(layout.timelineSectionMinHeight >= 240)
        #expect(layout.previewContentMinHeight >= (layout.centerColumnWidth / (16.0 / 9.0)) * 0.88)
    }

    @Test("workspace shell gives portrait monitor content more vertical room")
    func workspaceShellAllocatesMoreHeightForPortraitMonitorContent() {
        let landscapeLayout = EditorWorkspaceShellLayout.make(
            containerWidth: 1880,
            containerHeight: 980,
            leftRailVisible: true,
            rightRailVisible: true,
            previewAspectRatio: 16.0 / 9.0
        )
        let portraitLayout = EditorWorkspaceShellLayout.make(
            containerWidth: 1880,
            containerHeight: 980,
            leftRailVisible: true,
            rightRailVisible: true,
            previewAspectRatio: 9.0 / 16.0
        )

        #expect(portraitLayout.previewContentMinHeight > landscapeLayout.previewContentMinHeight)
        #expect(portraitLayout.previewContentMinHeight >= 280)
    }

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
