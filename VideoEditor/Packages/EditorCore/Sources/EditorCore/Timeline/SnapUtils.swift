import Foundation

/// Pure snap point calculations — no side effects.
public struct SnapUtils: Sendable {

    /// Find the nearest snap point within threshold. Returns nil if no snap found.
    public static func snap(
        time: TimeInterval,
        to snapPoints: [TimeInterval],
        threshold: TimeInterval
    ) -> TimeInterval? {
        var nearest: TimeInterval?
        var nearestDist = Double.infinity

        for point in snapPoints {
            let dist = abs(time - point)
            if dist < threshold && dist < nearestDist {
                nearest = point
                nearestDist = dist
            }
        }
        return nearest
    }

    /// Collect snap points from a timeline: clip edges, playhead, markers.
    public static func snapPoints(
        from timeline: Timeline,
        playhead: TimeInterval,
        excludeClipIDs: Set<UUID> = []
    ) -> [TimeInterval] {
        var points: [TimeInterval] = [0, playhead]

        for track in timeline.tracks {
            for clip in track.clips where !excludeClipIDs.contains(clip.id) {
                points.append(clip.timelineRange.start)
                points.append(clip.timelineRange.end)
            }
        }

        for marker in timeline.markers {
            points.append(marker.time)
        }

        return Array(Set(points)).sorted()
    }
}
