import Foundation

struct TimelineShellMetrics: Sendable, Equatable {
    let compactHeaderHeight: Double
    let rulerHeight: Double

    var reservedTopInset: Double {
        compactHeaderHeight + rulerHeight
    }

    init(compactHeaderHeight: Double = 50, rulerHeight: Double = 28) {
        self.compactHeaderHeight = compactHeaderHeight
        self.rulerHeight = rulerHeight
    }
}

struct TimelineVisibleFrame: Sendable, Equatable {
    var originX: Double
    var width: Double

    var endX: Double {
        originX + width
    }

    func contains(_ x: Double) -> Bool {
        x >= originX && x <= endX
    }

    func contains(_ frame: TimelineVisibleFrame) -> Bool {
        frame.originX >= originX && frame.endX <= endX
    }
}

struct TimelineViewport: Sendable, Equatable {
    var visibleFrame: TimelineVisibleFrame
    var shellMetrics: TimelineShellMetrics

    var contentTopInset: Double {
        shellMetrics.reservedTopInset
    }

    init(
        visibleFrame: TimelineVisibleFrame,
        shellMetrics: TimelineShellMetrics = TimelineShellMetrics()
    ) {
        self.visibleFrame = visibleFrame
        self.shellMetrics = shellMetrics
    }
}

struct TimelineScrollRequest: Sendable, Equatable {
    let horizontalOffset: Double
}

enum TimelineScrollTargetResolver {
    static func selectionVisibilityRequest(
        for clipFrame: TimelineVisibleFrame,
        in viewport: TimelineViewport
    ) -> TimelineScrollRequest? {
        scrollRequest(for: clipFrame, in: viewport.visibleFrame)
    }

    static func playheadVisibilityRequest(
        playheadX: Double,
        in viewport: TimelineViewport,
        autoFollowEnabled: Bool
    ) -> TimelineScrollRequest? {
        guard autoFollowEnabled else { return nil }
        return scrollRequest(
            for: TimelineVisibleFrame(originX: playheadX, width: 0),
            in: viewport.visibleFrame
        )
    }

    private static func scrollRequest(
        for targetFrame: TimelineVisibleFrame,
        in visibleFrame: TimelineVisibleFrame
    ) -> TimelineScrollRequest? {
        guard visibleFrame.width > 0 else { return nil }

        if targetFrame.originX < visibleFrame.originX {
            return TimelineScrollRequest(horizontalOffset: targetFrame.originX - visibleFrame.originX)
        }

        if targetFrame.endX > visibleFrame.endX {
            return TimelineScrollRequest(horizontalOffset: targetFrame.endX - visibleFrame.endX)
        }

        return nil
    }
}
