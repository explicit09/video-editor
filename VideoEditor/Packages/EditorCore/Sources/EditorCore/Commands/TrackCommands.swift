import Foundation

// MARK: - AddTrackCommand

public struct AddTrackCommand: Command {
    public let name = "Add Track"
    public let track: Track
    public var affectedTrackIDs: [UUID] { [track.id] }
    public var metadata: [String: String] { ["trackType": track.type.rawValue, "trackName": track.name] }

    public init(track: Track) {
        self.track = track
    }

    public mutating func execute(context: EditingContext) throws {
        context.timelineState.timeline.tracks.append(track)
    }

    public func undo(context: EditingContext) throws {
        context.timelineState.timeline.tracks.removeAll { $0.id == track.id }
    }
}

// MARK: - RemoveTrackCommand

public struct RemoveTrackCommand: Command {
    public let name = "Remove Track"
    public let trackID: UUID
    public var affectedTrackIDs: [UUID] { [trackID] }
    private var removedTrack: Track?
    private var removedIndex: Int?

    public init(trackID: UUID) {
        self.trackID = trackID
    }

    public mutating func execute(context: EditingContext) throws {
        guard let index = context.timelineState.timeline.tracks.firstIndex(where: { $0.id == trackID }) else {
            throw CommandError.trackNotFound(trackID)
        }
        removedTrack = context.timelineState.timeline.tracks[index]
        removedIndex = index
        context.timelineState.timeline.tracks.remove(at: index)
    }

    public func undo(context: EditingContext) throws {
        guard let track = removedTrack, let index = removedIndex else { return }
        let insertAt = min(index, context.timelineState.timeline.tracks.count)
        context.timelineState.timeline.tracks.insert(track, at: insertAt)
    }
}
