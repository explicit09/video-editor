import Foundation

// MARK: - EditorIntent

/// Shared vocabulary for all editor operations.
/// Humans, AI, keyboard shortcuts, and macros all speak this language.
public enum EditorIntent: Sendable {
    case addTrack(track: Track)
    case removeTrack(trackID: UUID)
    case insertClip(clip: Clip, trackID: UUID)
    case deleteClips(clipIDs: [UUID])
    case moveClip(clipID: UUID, newStart: TimeInterval, trackID: UUID)
    case trimClip(clipID: UUID, newSourceRange: TimeRange)
    case splitClip(clipID: UUID, at: TimeInterval)
    case setMarker(at: TimeInterval, label: String)
    case deleteMarker(markerID: UUID)
}

// MARK: - IntentResolver

/// Resolves EditorIntents into executable Commands.
/// Every intent case is handled — no fallthrough, no stubs.
public struct IntentResolver: Sendable {

    public init() {}

    @MainActor
    public func resolve(_ intent: EditorIntent) throws -> any Command {
        switch intent {
        case .addTrack(let track):
            return AddTrackCommand(track: track)
        case .removeTrack(let trackID):
            return RemoveTrackCommand(trackID: trackID)
        case .insertClip(let clip, let trackID):
            return InsertClipCommand(clip: clip, trackID: trackID)
        case .deleteClips(let clipIDs):
            return DeleteClipsCommand(clipIDs: clipIDs)
        case .moveClip(let clipID, let newStart, let trackID):
            return MoveClipCommand(clipID: clipID, newStart: newStart, targetTrackID: trackID)
        case .trimClip(let clipID, let newSourceRange):
            return TrimClipCommand(clipID: clipID, newSourceRange: newSourceRange)
        case .splitClip(let clipID, let at):
            return SplitClipCommand(clipID: clipID, at: at)
        case .setMarker(let at, let label):
            return SetMarkerCommand(at: at, label: label)
        case .deleteMarker(let markerID):
            return DeleteMarkerCommand(markerID: markerID)
        }
    }
}

// MARK: - DeleteMarkerCommand

public struct DeleteMarkerCommand: Command {
    public let name = "Delete Marker"
    public let markerID: UUID
    private var removedMarker: Marker?

    public init(markerID: UUID) {
        self.markerID = markerID
    }

    public mutating func execute(context: EditingContext) throws {
        removedMarker = context.timelineState.timeline.markers.first { $0.id == markerID }
        context.timelineState.timeline.markers.removeAll { $0.id == markerID }
    }

    public func undo(context: EditingContext) throws {
        guard let marker = removedMarker else { return }
        context.timelineState.timeline.markers.append(marker)
        context.timelineState.timeline.markers.sort { $0.time < $1.time }
    }
}
