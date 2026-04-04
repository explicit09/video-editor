import Foundation

public struct TimelineTrackLayoutEntry: Sendable, Equatable {
    public let id: UUID
    public let type: TrackType
    public let isLocked: Bool
    public let height: Double

    public init(id: UUID, type: TrackType, isLocked: Bool, height: Double) {
        self.id = id
        self.type = type
        self.isLocked = isLocked
        self.height = height
    }
}

public struct TimelineSelectionSnapshot: Sendable, Equatable {
    public var selectedClipIDs: Set<UUID>
    public var selectedTrackID: UUID?
    public var lastSelectedClipID: UUID?

    public init(
        selectedClipIDs: Set<UUID>,
        selectedTrackID: UUID?,
        lastSelectedClipID: UUID?
    ) {
        self.selectedClipIDs = selectedClipIDs
        self.selectedTrackID = selectedTrackID
        self.lastSelectedClipID = lastSelectedClipID
    }
}

public struct ClipTrimProposal: Sendable, Equatable {
    public let sourceRange: TimeRange
    public let timelineRange: TimeRange

    public init(sourceRange: TimeRange, timelineRange: TimeRange) {
        self.sourceRange = sourceRange
        self.timelineRange = timelineRange
    }
}

public enum TimelineSelectionNormalizer {
    public static func normalize(
        selection: TimelineSelectionSnapshot,
        in timeline: Timeline
    ) -> TimelineSelectionSnapshot {
        let validTrackIDs = Set(timeline.tracks.map(\.id))
        var clipToTrack: [UUID: UUID] = [:]
        for track in timeline.tracks {
            for clip in track.clips {
                clipToTrack[clip.id] = track.id
            }
        }

        let validClipIDs = Set(selection.selectedClipIDs.filter { clipToTrack[$0] != nil })
        let normalizedTrackID: UUID?
        let normalizedLastSelected: UUID?

        if validClipIDs.isEmpty {
            normalizedTrackID = selection.selectedTrackID.flatMap { validTrackIDs.contains($0) ? $0 : nil }
            normalizedLastSelected = nil
        } else {
            let selectedTrackIDs = Set(validClipIDs.compactMap { clipToTrack[$0] })
            if selectedTrackIDs.count == 1 {
                normalizedTrackID = selectedTrackIDs.first
            } else if let selectedTrackID = selection.selectedTrackID, selectedTrackIDs.contains(selectedTrackID) {
                normalizedTrackID = selectedTrackID
            } else {
                normalizedTrackID = nil
            }

            if let anchor = selection.lastSelectedClipID, validClipIDs.contains(anchor) {
                normalizedLastSelected = anchor
            } else {
                normalizedLastSelected = validClipIDs.sorted { $0.uuidString < $1.uuidString }.first
            }
        }

        return TimelineSelectionSnapshot(
            selectedClipIDs: validClipIDs,
            selectedTrackID: normalizedTrackID,
            lastSelectedClipID: normalizedLastSelected
        )
    }
}

public enum TimelineDropResolver {
    public static func targetTrackID(
        currentIndex: Int,
        verticalOffset: Double,
        movingTrackType: TrackType,
        tracks: [TimelineTrackLayoutEntry],
        clipGap: Double
    ) -> UUID {
        guard tracks.indices.contains(currentIndex) else { return UUID() }
        let fallback = tracks[currentIndex]
        let fallbackTrackID = (fallback.type == movingTrackType && !fallback.isLocked) ? fallback.id : nil
        let baseCenter = trackCenterY(at: currentIndex, in: tracks, clipGap: clipGap)
        let proposedCenter = baseCenter + verticalOffset

        var cursor: Double = 0
        for track in tracks {
            let upperBound = cursor + track.height
            if proposedCenter <= upperBound {
                if track.type == movingTrackType, !track.isLocked {
                    return track.id
                }
                if let fallbackTrackID {
                    return fallbackTrackID
                }
            }
            cursor = upperBound + clipGap
        }

        if let sameTypeUnlocked = tracks.last(where: { $0.type == movingTrackType && !$0.isLocked }) {
            return sameTypeUnlocked.id
        }

        return fallback.id
    }

    private static func trackCenterY(
        at index: Int,
        in tracks: [TimelineTrackLayoutEntry],
        clipGap: Double
    ) -> Double {
        var cursor: Double = 0
        for priorIndex in tracks.indices {
            let height = tracks[priorIndex].height
            if priorIndex == index {
                return cursor + (height / 2)
            }
            cursor += height + clipGap
        }
        return cursor
    }
}

public enum ClipTrimResolver {
    public static func proposal(
        for clip: Clip,
        proposedSourceRange: TimeRange,
        in trackClips: [Clip],
        minDuration: TimeInterval = 0.1
    ) -> ClipTrimProposal {
        let priorClipEnd = trackClips
            .filter { $0.id != clip.id && $0.timelineRange.end <= clip.timelineRange.start }
            .map(\.timelineRange.end)
            .max() ?? 0

        let headDelta = proposedSourceRange.start - clip.sourceRange.start
        let proposedTimelineStart = clip.timelineRange.start + headDelta
        let newTimelineStart = max(proposedTimelineStart, priorClipEnd)

        let effectiveHeadDelta = newTimelineStart - clip.timelineRange.start
        let adjustedSourceStart = max(0, clip.sourceRange.start + effectiveHeadDelta)
        let adjustedSourceEnd = max(proposedSourceRange.end, adjustedSourceStart + minDuration)
        var adjustedSourceRange = TimeRange(start: adjustedSourceStart, end: adjustedSourceEnd)
        var newTimelineDuration = max(adjustedSourceRange.duration, minDuration)

        if let nextClip = trackClips
            .filter({ $0.id != clip.id })
            .sorted(by: { $0.timelineRange.start < $1.timelineRange.start })
            .first(where: { $0.timelineRange.start >= clip.timelineRange.end }) {
            let maxDuration = max(nextClip.timelineRange.start - newTimelineStart, minDuration)
            if newTimelineDuration > maxDuration {
                newTimelineDuration = maxDuration
                adjustedSourceRange = TimeRange(start: adjustedSourceRange.start, duration: maxDuration)
            }
        }

        return ClipTrimProposal(
            sourceRange: adjustedSourceRange,
            timelineRange: TimeRange(start: newTimelineStart, duration: newTimelineDuration)
        )
    }

    public static func linkedSiblingSourceRange(
        primaryOriginalSourceRange: TimeRange,
        primaryProposedSourceRange: TimeRange,
        siblingSourceRange: TimeRange,
        minDuration: TimeInterval = 0.1
    ) -> TimeRange {
        let headDelta = primaryProposedSourceRange.start - primaryOriginalSourceRange.start
        let tailDelta = primaryProposedSourceRange.end - primaryOriginalSourceRange.end
        let newStart = max(0, siblingSourceRange.start + headDelta)
        let newEnd = max(newStart + minDuration, siblingSourceRange.end + tailDelta)
        return TimeRange(start: newStart, end: newEnd)
    }
}
