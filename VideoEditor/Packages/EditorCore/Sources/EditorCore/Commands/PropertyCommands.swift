import Foundation

// MARK: - Clip Property Commands

/// Change a clip's audio volume.
public struct SetClipVolumeCommand: Command {
    public let name = "Set Clip Volume"
    public let clipID: UUID
    public let newVolume: Double
    public var affectedClipIDs: [UUID] { [clipID] }
    private var previousVolume: Double?

    public init(clipID: UUID, volume: Double) {
        self.clipID = clipID
        self.newVolume = max(volume, 0)
    }

    public mutating func execute(context: EditingContext) throws {
        try modifyClip(id: clipID, context: context) { clip in
            previousVolume = clip.volume
            clip.volume = newVolume
        }
    }

    public func undo(context: EditingContext) throws {
        guard let prev = previousVolume else { return }
        try modifyClip(id: clipID, context: context) { $0.volume = prev }
    }
}

/// Change a clip's visual opacity.
public struct SetClipOpacityCommand: Command {
    public let name = "Set Clip Opacity"
    public let clipID: UUID
    public let newOpacity: Double
    public var affectedClipIDs: [UUID] { [clipID] }
    private var previousOpacity: Double?

    public init(clipID: UUID, opacity: Double) {
        self.clipID = clipID
        self.newOpacity = min(max(opacity, 0), 1)
    }

    public mutating func execute(context: EditingContext) throws {
        try modifyClip(id: clipID, context: context) { clip in
            previousOpacity = clip.opacity
            clip.opacity = newOpacity
        }
    }

    public func undo(context: EditingContext) throws {
        guard let prev = previousOpacity else { return }
        try modifyClip(id: clipID, context: context) { $0.opacity = prev }
    }
}

/// Change a clip's 2D transform (position, scale, rotation).
public struct SetClipTransformCommand: Command {
    public let name = "Set Clip Transform"
    public let clipID: UUID
    public let newTransform: Transform2D
    public var affectedClipIDs: [UUID] { [clipID] }
    private var previousTransform: Transform2D?

    public init(clipID: UUID, transform: Transform2D) {
        self.clipID = clipID
        self.newTransform = transform
    }

    public mutating func execute(context: EditingContext) throws {
        try modifyClip(id: clipID, context: context) { clip in
            previousTransform = clip.transform
            clip.transform = newTransform
        }
    }

    public func undo(context: EditingContext) throws {
        guard let prev = previousTransform else { return }
        try modifyClip(id: clipID, context: context) { $0.transform = prev }
    }
}

// MARK: - Track Property Commands

/// Toggle track mute state.
public struct MuteTrackCommand: Command {
    public let name = "Toggle Mute Track"
    public let trackID: UUID
    public let muted: Bool
    public var affectedTrackIDs: [UUID] { [trackID] }
    private var previousMuted: Bool?

    public init(trackID: UUID, muted: Bool) {
        self.trackID = trackID
        self.muted = muted
    }

    public mutating func execute(context: EditingContext) throws {
        try modifyTrack(id: trackID, context: context) { track in
            previousMuted = track.isMuted
            track.isMuted = muted
        }
    }

    public func undo(context: EditingContext) throws {
        guard let prev = previousMuted else { return }
        try modifyTrack(id: trackID, context: context) { $0.isMuted = prev }
    }
}

/// Toggle track lock state.
public struct LockTrackCommand: Command {
    public let name = "Toggle Lock Track"
    public let trackID: UUID
    public let locked: Bool
    public var affectedTrackIDs: [UUID] { [trackID] }
    private var previousLocked: Bool?

    public init(trackID: UUID, locked: Bool) {
        self.trackID = trackID
        self.locked = locked
    }

    public mutating func execute(context: EditingContext) throws {
        try modifyTrack(id: trackID, context: context) { track in
            previousLocked = track.isLocked
            track.isLocked = locked
        }
    }

    public func undo(context: EditingContext) throws {
        guard let prev = previousLocked else { return }
        try modifyTrack(id: trackID, context: context) { $0.isLocked = prev }
    }
}

/// Change track volume.
public struct SetTrackVolumeCommand: Command {
    public let name = "Set Track Volume"
    public let trackID: UUID
    public let newVolume: Double
    public var affectedTrackIDs: [UUID] { [trackID] }
    private var previousVolume: Double?

    public init(trackID: UUID, volume: Double) {
        self.trackID = trackID
        self.newVolume = max(volume, 0)
    }

    public mutating func execute(context: EditingContext) throws {
        try modifyTrack(id: trackID, context: context) { track in
            previousVolume = track.volume
            track.volume = newVolume
        }
    }

    public func undo(context: EditingContext) throws {
        guard let prev = previousVolume else { return }
        try modifyTrack(id: trackID, context: context) { $0.volume = prev }
    }
}

/// Rename a clip's label.
public struct RenameClipCommand: Command {
    public let name = "Rename Clip"
    public let clipID: UUID
    public let newLabel: String
    public var affectedClipIDs: [UUID] { [clipID] }
    private var previousLabel: String?

    public init(clipID: UUID, label: String) {
        self.clipID = clipID
        self.newLabel = label
    }

    public mutating func execute(context: EditingContext) throws {
        try modifyClip(id: clipID, context: context) { clip in
            previousLabel = clip.metadata.label
            clip.metadata.label = newLabel
        }
    }

    public func undo(context: EditingContext) throws {
        try modifyClip(id: clipID, context: context) { $0.metadata.label = previousLabel }
    }
}

/// Duplicate a clip within the same track, placed immediately after the original.
public struct DuplicateClipCommand: Command {
    public let name = "Duplicate Clip"
    public let clipID: UUID
    public var affectedClipIDs: [UUID] { [clipID] + (newClipID.map { [$0] } ?? []) }
    private var newClipID: UUID?
    private var trackID: UUID?

    public init(clipID: UUID) {
        self.clipID = clipID
    }

    public mutating func execute(context: EditingContext) throws {
        let location = try editableClipLocation(for: clipID, context: context)
        let original = context.timelineState.timeline.tracks[location.trackIndex].clips[location.clipIndex]
        let id = UUID()
        newClipID = id
        trackID = context.timelineState.timeline.tracks[location.trackIndex].id

        let duplicate = Clip(
            id: id,
            assetID: original.assetID,
            timelineRange: TimeRange(start: original.timelineRange.end, duration: original.timelineRange.duration),
            sourceRange: original.sourceRange,
            transform: original.transform,
            opacity: original.opacity,
            volume: original.volume,
            effects: original.effects,
            keyframes: original.keyframes,
            metadata: ClipMetadata(label: (original.metadata.label ?? "Clip") + " (copy)")
        )
        context.timelineState.timeline.tracks[location.trackIndex].clips.insert(duplicate, at: location.clipIndex + 1)
    }

    public func undo(context: EditingContext) throws {
        guard let newClipID else { return }
        for trackIndex in context.timelineState.timeline.tracks.indices {
            context.timelineState.timeline.tracks[trackIndex].clips.removeAll { $0.id == newClipID }
        }
    }
}

// MARK: - Helpers

@MainActor
private func modifyClip(id: UUID, context: EditingContext, _ body: (inout Clip) -> Void) throws {
    let location = try editableClipLocation(for: id, context: context)
    body(&context.timelineState.timeline.tracks[location.trackIndex].clips[location.clipIndex])
}

@MainActor
private func modifyTrack(id: UUID, context: EditingContext, _ body: (inout Track) -> Void) throws {
    guard let index = context.timelineState.timeline.tracks.firstIndex(where: { $0.id == id }) else {
        throw CommandError.trackNotFound(id)
    }
    body(&context.timelineState.timeline.tracks[index])
}
