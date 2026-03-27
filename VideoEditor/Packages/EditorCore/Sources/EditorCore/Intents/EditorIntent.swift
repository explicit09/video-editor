import Foundation

// MARK: - EditorIntent

/// Shared vocabulary for all editor operations.
/// Humans, AI, keyboard shortcuts, and macros all speak this language.
public enum EditorIntent: Sendable {
    case trimClip(clipID: UUID, newSourceRange: TimeRange)
    case splitClip(clipID: UUID, at: TimeInterval)
    case moveClip(clipID: UUID, to: TimeRange, trackID: UUID)
    case deleteClips(clipIDs: [UUID])
    case insertClip(assetID: UUID, at: TimeInterval, trackID: UUID)
    case removeSilence(clipID: UUID, ranges: [TimeRange])
    case createSelectsSequence(clipIDs: [UUID])
    case groupBySpeaker(clipIDs: [UUID])
    case insertTitleCard(text: String, at: TimeInterval)
    case setMarker(at: TimeInterval, label: String)
    case deleteMarker(markerID: UUID)
    case addTrack(type: TrackType, name: String)
    case removeTrack(trackID: UUID)
}

// MARK: - IntentResolver

/// Resolves EditorIntents into executable Commands.
public struct IntentResolver: Sendable {

    public init() {}

    public func resolve(_ intent: EditorIntent, context: EditingContext) throws -> any Command {
        switch intent {
        case .trimClip(let clipID, let newSourceRange):
            return TrimClipCommand(clipID: clipID, newSourceRange: newSourceRange)
        case .splitClip(let clipID, let at):
            return SplitClipCommand(clipID: clipID, at: at)
        case .deleteClips(let clipIDs):
            return DeleteClipsCommand(clipIDs: clipIDs)
        case .insertClip(let assetID, let at, let trackID):
            return InsertClipCommand(assetID: assetID, at: at, trackID: trackID)
        case .setMarker(let at, let label):
            return SetMarkerCommand(at: at, label: label)
        default:
            throw IntentError.notYetImplemented(intent)
        }
    }
}

// MARK: - IntentError

public enum IntentError: Error {
    case notYetImplemented(EditorIntent)
}

// MARK: - Command stubs (minimal implementations for Phase 1)

public struct TrimClipCommand: Command {
    public let name = "Trim Clip"
    public let clipID: UUID
    public let newSourceRange: TimeRange

    public mutating func execute(context: EditingContext) throws {}
    public func undo(context: EditingContext) throws {}
}

public struct SplitClipCommand: Command {
    public let name = "Split Clip"
    public let clipID: UUID
    public let at: TimeInterval

    public mutating func execute(context: EditingContext) throws {}
    public func undo(context: EditingContext) throws {}
}

public struct DeleteClipsCommand: Command {
    public let name = "Delete Clips"
    public let clipIDs: [UUID]

    public mutating func execute(context: EditingContext) throws {}
    public func undo(context: EditingContext) throws {}
}

public struct InsertClipCommand: Command {
    public let name = "Insert Clip"
    public let assetID: UUID
    public let at: TimeInterval
    public let trackID: UUID

    public mutating func execute(context: EditingContext) throws {}
    public func undo(context: EditingContext) throws {}
}

public struct SetMarkerCommand: Command {
    public let name = "Set Marker"
    public let at: TimeInterval
    public let label: String

    public mutating func execute(context: EditingContext) throws {}
    public func undo(context: EditingContext) throws {}
}
