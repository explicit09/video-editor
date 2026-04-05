import Foundation

struct TimelineShellMetrics: Sendable, Equatable {
    let headerWidth: Double
    let rulerHeight: Double
    let scrollContentHeight: Double

    static func make(
        viewportWidth: Double,
        viewportHeight: Double,
        trackCount: Int,
        expandedTrackHeight: Double,
        collapsedTrackHeight: Double
    ) -> TimelineShellMetrics {
        let headerWidth = 152.0
        let rulerHeight = 32.0
        let trackCountValue = Double(max(trackCount, 1))
        let rowHeight = max(expandedTrackHeight, collapsedTrackHeight)
        let minimumTrackStackHeight = max(viewportHeight - rulerHeight, trackCountValue * rowHeight)

        return TimelineShellMetrics(
            headerWidth: headerWidth,
            rulerHeight: rulerHeight,
            scrollContentHeight: minimumTrackStackHeight + rulerHeight
        )
    }
}

struct TimelineViewport: Sendable, Equatable {
    let visibleXRange: ClosedRange<Double>
    let visibleYRange: ClosedRange<Double>
}

struct TimelineVisibleFrame: Sendable, Equatable {
    let minX: Double
    let maxX: Double
    let minY: Double
    let maxY: Double

    var width: Double {
        max(0, maxX - minX)
    }

    var height: Double {
        max(0, maxY - minY)
    }
}

struct TimelineScrollRequest: Sendable, Equatable {
    let anchorX: Double?
    let anchorY: Double?
}

enum TimelineScrollTargetResolver {
    static func requestToReveal(
        _ frame: TimelineVisibleFrame,
        in viewport: TimelineViewport,
        padding: Double
    ) -> TimelineScrollRequest? {
        let anchorX = revealAnchor(
            lowerBound: viewport.visibleXRange.lowerBound,
            upperBound: viewport.visibleXRange.upperBound,
            minValue: frame.minX,
            maxValue: frame.maxX,
            padding: padding
        )
        let anchorY = revealAnchor(
            lowerBound: viewport.visibleYRange.lowerBound,
            upperBound: viewport.visibleYRange.upperBound,
            minValue: frame.minY,
            maxValue: frame.maxY,
            padding: padding
        )

        if anchorX == nil && anchorY == nil {
            return nil
        }

        return TimelineScrollRequest(anchorX: anchorX, anchorY: anchorY)
    }

    static func requestToKeepPlayheadVisible(
        playheadX: Double,
        in viewport: TimelineViewport,
        autoFollow: Bool,
        padding: Double
    ) -> TimelineScrollRequest? {
        guard autoFollow else { return nil }

        let anchorX = revealAnchor(
            lowerBound: viewport.visibleXRange.lowerBound,
            upperBound: viewport.visibleXRange.upperBound,
            minValue: playheadX,
            maxValue: playheadX,
            padding: padding
        )

        return anchorX.map { TimelineScrollRequest(anchorX: $0, anchorY: nil) }
    }

    private static func revealAnchor(
        lowerBound: Double,
        upperBound: Double,
        minValue: Double,
        maxValue: Double,
        padding: Double
    ) -> Double? {
        if maxValue > upperBound - padding {
            return minValue - padding
        }

        if minValue < lowerBound + padding {
            return maxValue + padding - (upperBound - lowerBound)
        }

        return nil
    }
}
