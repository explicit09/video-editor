import Foundation
import CoreGraphics
import EditorCore

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
        let headerWidth = TrackHeaderLayout.headerWidth
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

enum TrackHeaderControl: Sendable, Equatable {
    case arm
    case mute
    case solo
    case lock
    case addLane
    case cycleHeight
    case removeTrack
}

struct TrackHeaderLayout: Sendable, Equatable {
    static let headerWidth = 136.0
    static let textFieldHeight = 28.0
    static let controlSize = 18.0

    let inlineControls: [TrackHeaderControl]
    let overflowControls: [TrackHeaderControl]

    var showsOverflowMenu: Bool {
        !overflowControls.isEmpty
    }

    static func make(isCollapsed: Bool, canRemoveTrack: Bool) -> Self {
        let coreControls: [TrackHeaderControl] = [.arm, .mute, .solo, .lock]
        guard !isCollapsed else {
            return Self(
                inlineControls: coreControls,
                overflowControls: []
            )
        }

        var overflowControls: [TrackHeaderControl] = [.addLane, .cycleHeight]
        if canRemoveTrack {
            overflowControls.append(.removeTrack)
        }

        return Self(
            inlineControls: coreControls,
            overflowControls: overflowControls
        )
    }
}

struct TimelineScrollTarget: Sendable, Equatable {
    let horizontalOffset: Double
    let verticalOffset: Double
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
    static func resolveScrollTarget(
        for request: TimelineScrollRequest,
        horizontalOffset: Double,
        verticalOffset: Double
    ) -> TimelineScrollTarget {
        TimelineScrollTarget(
            horizontalOffset: request.anchorX ?? horizontalOffset,
            verticalOffset: request.anchorY ?? verticalOffset
        )
    }

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

enum TimelineSnapResolver {
    static func snappedTime(
        for proposedTime: TimeInterval,
        excluding clipIDs: Set<UUID> = [],
        in timeline: Timeline,
        playhead: TimeInterval,
        snapEnabled: Bool,
        snapThresholdPixels: Double,
        zoom: Double
    ) -> TimeInterval {
        let clampedTime = max(0, proposedTime)
        guard snapEnabled else { return clampedTime }

        let snapThreshold = snapThresholdPixels / max(zoom, 0.001)
        let points = SnapUtils.snapPoints(
            from: timeline,
            playhead: playhead,
            excludeClipIDs: clipIDs
        )
        return SnapUtils.snap(time: clampedTime, to: points, threshold: snapThreshold) ?? clampedTime
    }
}

struct TimelineTrackInteractionLayout: Sendable, Equatable {
    struct ClipFrame: Sendable, Equatable {
        let id: UUID
        let minX: Double
        let maxX: Double

        init(id: UUID, minX: Double, maxX: Double) {
            self.id = id
            self.minX = min(minX, maxX)
            self.maxX = max(minX, maxX)
        }
    }

    static func backgroundHitRects(
        totalWidth: Double,
        trackHeight: Double,
        clipFrames: [ClipFrame]
    ) -> [CGRect] {
        let clampedWidth = max(totalWidth, 0)
        let clampedHeight = max(trackHeight, 0)
        guard clampedWidth > 0, clampedHeight > 0 else { return [] }

        let sortedFrames = clipFrames
            .map { frame in
                ClipFrame(
                    id: frame.id,
                    minX: min(max(frame.minX, 0), clampedWidth),
                    maxX: min(max(frame.maxX, 0), clampedWidth)
                )
            }
            .filter { $0.maxX > $0.minX }
            .sorted { lhs, rhs in
                if lhs.minX == rhs.minX {
                    return lhs.maxX < rhs.maxX
                }
                return lhs.minX < rhs.minX
            }

        var gaps: [CGRect] = []
        var cursor = 0.0

        for frame in sortedFrames {
            if frame.minX > cursor {
                gaps.append(CGRect(x: cursor, y: 0, width: frame.minX - cursor, height: clampedHeight))
            }
            cursor = max(cursor, frame.maxX)
        }

        if cursor < clampedWidth {
            gaps.append(CGRect(x: cursor, y: 0, width: clampedWidth - cursor, height: clampedHeight))
        }

        return gaps.filter { $0.width > 0.5 && $0.height > 0.5 }
    }
}

enum PlayheadInteractionLayout {
    static func scrubRect(
        containerWidth: Double,
        containerHeight: Double,
        scrubHeight: Double
    ) -> CGRect {
        CGRect(
            x: 0,
            y: 0,
            width: max(containerWidth, 0),
            height: min(max(scrubHeight, 0), max(containerHeight, 0))
        )
    }
}
