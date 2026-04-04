import Foundation

@MainActor
func trackIndex(for trackID: UUID, context: EditingContext) throws -> Int {
    guard let index = context.timelineState.timeline.tracks.firstIndex(where: { $0.id == trackID }) else {
        throw CommandError.trackNotFound(trackID)
    }
    return index
}

@MainActor
func editableTrackIndex(for trackID: UUID, context: EditingContext) throws -> Int {
    let index = try trackIndex(for: trackID, context: context)
    guard !context.timelineState.timeline.tracks[index].isLocked else {
        throw CommandError.trackLocked(trackID)
    }
    return index
}

@MainActor
func clipLocation(for clipID: UUID, context: EditingContext) throws -> (trackIndex: Int, clipIndex: Int) {
    for trackIndex in context.timelineState.timeline.tracks.indices {
        if let clipIndex = context.timelineState.timeline.tracks[trackIndex].clips.firstIndex(where: { $0.id == clipID }) {
            return (trackIndex, clipIndex)
        }
    }
    throw CommandError.clipNotFound(clipID)
}

@MainActor
func editableClipLocation(for clipID: UUID, context: EditingContext) throws -> (trackIndex: Int, clipIndex: Int) {
    let location = try clipLocation(for: clipID, context: context)
    let track = context.timelineState.timeline.tracks[location.trackIndex]
    guard !track.isLocked else {
        throw CommandError.trackLocked(track.id)
    }
    return location
}

@MainActor
func collisionAdjustedStart(
    proposedStart: TimeInterval,
    duration: TimeInterval,
    in clips: [Clip],
    excluding excludedClipID: UUID? = nil
) -> TimeInterval {
    let sortedClips = clips
        .filter { $0.id != excludedClipID }
        .sorted { lhs, rhs in
            if lhs.timelineRange.start != rhs.timelineRange.start {
                return lhs.timelineRange.start < rhs.timelineRange.start
            }
            return lhs.timelineRange.end < rhs.timelineRange.end
        }

    var adjustedStart = max(0, proposedStart)
    for other in sortedClips {
        let adjustedEnd = adjustedStart + duration
        if adjustedEnd <= other.timelineRange.start {
            break
        }
        if adjustedStart >= other.timelineRange.end {
            continue
        }
        adjustedStart = other.timelineRange.end
    }
    return adjustedStart
}
