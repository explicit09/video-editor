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
