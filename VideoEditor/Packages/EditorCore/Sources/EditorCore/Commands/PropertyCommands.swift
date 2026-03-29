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

/// Change a clip's normalized crop rect.
public struct SetClipCropCommand: Command {
    public let name = "Set Clip Crop"
    public let clipID: UUID
    public let newCropRect: CropRect
    public var affectedClipIDs: [UUID] { [clipID] }
    private var previousCropRect: CropRect?

    public init(clipID: UUID, cropRect: CropRect) {
        self.clipID = clipID
        self.newCropRect = cropRect.clamped
    }

    public mutating func execute(context: EditingContext) throws {
        try modifyClip(id: clipID, context: context) { clip in
            previousCropRect = clip.cropRect
            clip.cropRect = newCropRect
        }
    }

    public func undo(context: EditingContext) throws {
        guard let previousCropRect else { return }
        try modifyClip(id: clipID, context: context) { $0.cropRect = previousCropRect }
    }
}

/// Set track audio effect chain (EQ, compression, noise gate).
public struct SetTrackAudioEffectsCommand: Command {
    public let name = "Set Track Audio Effects"
    public let trackID: UUID
    public let newEffectChain: AudioEffectChain?
    public var affectedTrackIDs: [UUID] { [trackID] }
    private var previousEffectChain: AudioEffectChain?

    public init(trackID: UUID, effectChain: AudioEffectChain?) {
        self.trackID = trackID
        self.newEffectChain = effectChain
    }

    public mutating func execute(context: EditingContext) throws {
        try modifyTrack(id: trackID, context: context) { track in
            previousEffectChain = track.audioEffectChain
            track.audioEffectChain = newEffectChain
        }
    }

    public func undo(context: EditingContext) throws {
        try modifyTrack(id: trackID, context: context) { $0.audioEffectChain = previousEffectChain }
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
        let adjustedStart = collisionAdjustedStart(
            proposedStart: original.timelineRange.end,
            duration: original.timelineRange.duration,
            in: context.timelineState.timeline.tracks[location.trackIndex].clips
        )

        let duplicate = Clip(
            id: id,
            assetID: original.assetID,
            timelineRange: TimeRange(start: adjustedStart, duration: original.timelineRange.duration),
            sourceRange: original.sourceRange,
            transform: original.transform,
            cropRect: original.cropRect,
            opacity: original.opacity,
            volume: original.volume,
            effects: original.effects,
            keyframes: original.keyframes,
            metadata: ClipMetadata(label: (original.metadata.label ?? "Clip") + " (copy)"),
            speed: original.speed,
            transitionIn: original.transitionIn,
            linkGroupID: original.linkGroupID,
            blendMode: original.blendMode
        )
        let insertionIndex = MoveClipCommand.insertionIndex(
            for: duplicate,
            in: context.timelineState.timeline.tracks[location.trackIndex].clips
        )
        context.timelineState.timeline.tracks[location.trackIndex].clips.insert(duplicate, at: insertionIndex)
    }

    public func undo(context: EditingContext) throws {
        guard let newClipID else { return }
        for trackIndex in context.timelineState.timeline.tracks.indices {
            context.timelineState.timeline.tracks[trackIndex].clips.removeAll { $0.id == newClipID }
        }
    }
}

/// Add or update an effect on a clip.
public struct SetClipEffectCommand: Command {
    public let name = "Set Effect"
    public let clipID: UUID
    public let effect: EffectInstance
    public var affectedClipIDs: [UUID] { [clipID] }
    private var previousEffects: [EffectInstance]?

    public init(clipID: UUID, effect: EffectInstance) {
        self.clipID = clipID
        self.effect = effect
    }

    public mutating func execute(context: EditingContext) throws {
        let location = try editableClipLocation(for: clipID, context: context)
        let clip = context.timelineState.timeline.tracks[location.trackIndex].clips[location.clipIndex]
        previousEffects = clip.effects

        var effects = clip.effects
        if let idx = effects.firstIndex(where: { $0.type == effect.type }) {
            effects[idx] = effect
        } else {
            effects.append(effect)
        }
        context.timelineState.timeline.tracks[location.trackIndex].clips[location.clipIndex].effects = effects
    }

    public func undo(context: EditingContext) throws {
        guard let prev = previousEffects else { return }
        for trackIndex in context.timelineState.timeline.tracks.indices {
            if let clipIndex = context.timelineState.timeline.tracks[trackIndex].clips.firstIndex(where: { $0.id == clipID }) {
                context.timelineState.timeline.tracks[trackIndex].clips[clipIndex].effects = prev
                return
            }
        }
    }
}

/// Set clip playback speed.
public struct SetClipSpeedCommand: Command {
    public let name = "Set Clip Speed"
    public let clipID: UUID
    public let newSpeed: Double
    public var affectedClipIDs: [UUID] { [clipID] }
    private var previousSpeed: Double?
    private var previousTimelineRange: TimeRange?

    public init(clipID: UUID, speed: Double) {
        self.clipID = clipID
        self.newSpeed = max(speed, 0.1)
    }

    public mutating func execute(context: EditingContext) throws {
        let location = try editableClipLocation(for: clipID, context: context)
        let clip = context.timelineState.timeline.tracks[location.trackIndex].clips[location.clipIndex]
        previousSpeed = clip.speed
        previousTimelineRange = clip.timelineRange

        // Changing speed changes the effective duration on the timeline
        let newDuration = clip.sourceRange.duration / newSpeed
        context.timelineState.timeline.tracks[location.trackIndex].clips[location.clipIndex].speed = newSpeed
        context.timelineState.timeline.tracks[location.trackIndex].clips[location.clipIndex].timelineRange = TimeRange(
            start: clip.timelineRange.start,
            duration: newDuration
        )
    }

    public func undo(context: EditingContext) throws {
        guard let prev = previousSpeed, let prevRange = previousTimelineRange else { return }
        for trackIndex in context.timelineState.timeline.tracks.indices {
            if let clipIndex = context.timelineState.timeline.tracks[trackIndex].clips.firstIndex(where: { $0.id == clipID }) {
                context.timelineState.timeline.tracks[trackIndex].clips[clipIndex].speed = prev
                context.timelineState.timeline.tracks[trackIndex].clips[clipIndex].timelineRange = prevRange
                return
            }
        }
    }
}

/// Set clip transition.
public struct SetClipTransitionCommand: Command {
    public let name = "Set Transition"
    public let clipID: UUID
    public let newTransition: ClipTransition
    public var affectedClipIDs: [UUID] { [clipID] }
    private var previousTransition: ClipTransition?

    public init(clipID: UUID, transition: ClipTransition) {
        self.clipID = clipID
        self.newTransition = transition
    }

    public mutating func execute(context: EditingContext) throws {
        let location = try editableClipLocation(for: clipID, context: context)
        previousTransition = context.timelineState.timeline.tracks[location.trackIndex].clips[location.clipIndex].transitionIn
        context.timelineState.timeline.tracks[location.trackIndex].clips[location.clipIndex].transitionIn = newTransition
    }

    public func undo(context: EditingContext) throws {
        guard let prev = previousTransition else { return }
        for trackIndex in context.timelineState.timeline.tracks.indices {
            if let clipIndex = context.timelineState.timeline.tracks[trackIndex].clips.firstIndex(where: { $0.id == clipID }) {
                context.timelineState.timeline.tracks[trackIndex].clips[clipIndex].transitionIn = prev
                return
            }
        }
    }
}

/// Set clip blend mode.
public struct SetClipBlendModeCommand: Command {
    public let name = "Set Blend Mode"
    public let clipID: UUID
    public let newBlendMode: BlendMode
    public var affectedClipIDs: [UUID] { [clipID] }
    private var previousBlendMode: BlendMode?

    public init(clipID: UUID, blendMode: BlendMode) {
        self.clipID = clipID
        self.newBlendMode = blendMode
    }

    public mutating func execute(context: EditingContext) throws {
        try modifyClip(id: clipID, context: context) { clip in
            previousBlendMode = clip.blendMode
            clip.blendMode = newBlendMode
        }
    }

    public func undo(context: EditingContext) throws {
        guard let prev = previousBlendMode else { return }
        try modifyClip(id: clipID, context: context) { $0.blendMode = prev }
    }
}

/// Link or unlink a set of clips (shared linkGroupID).
public struct LinkClipsCommand: Command {
    public let name = "Link Clips"
    public let clipIDs: [UUID]
    public let newLinkGroupID: UUID?
    public var affectedClipIDs: [UUID] { clipIDs }
    private var previousLinkGroupIDs: [UUID: UUID?] = [:]

    public init(clipIDs: [UUID], linkGroupID: UUID?) {
        self.clipIDs = clipIDs
        self.newLinkGroupID = linkGroupID
    }

    public mutating func execute(context: EditingContext) throws {
        for clipID in clipIDs {
            for ti in context.timelineState.timeline.tracks.indices {
                if let ci = context.timelineState.timeline.tracks[ti].clips.firstIndex(where: { $0.id == clipID }) {
                    previousLinkGroupIDs[clipID] = context.timelineState.timeline.tracks[ti].clips[ci].linkGroupID
                    context.timelineState.timeline.tracks[ti].clips[ci].linkGroupID = newLinkGroupID
                }
            }
        }
    }

    public func undo(context: EditingContext) throws {
        for (clipID, prevGroup) in previousLinkGroupIDs {
            for ti in context.timelineState.timeline.tracks.indices {
                if let ci = context.timelineState.timeline.tracks[ti].clips.firstIndex(where: { $0.id == clipID }) {
                    context.timelineState.timeline.tracks[ti].clips[ci].linkGroupID = prevGroup
                }
            }
        }
    }
}

/// Remove an effect from a clip by effect ID.
public struct RemoveClipEffectCommand: Command {
    public let name = "Remove Effect"
    public let clipID: UUID
    public let effectID: UUID
    public var affectedClipIDs: [UUID] { [clipID] }
    private var removedEffect: EffectInstance?
    private var removedIndex: Int?

    public init(clipID: UUID, effectID: UUID) {
        self.clipID = clipID
        self.effectID = effectID
    }

    public mutating func execute(context: EditingContext) throws {
        let location = try editableClipLocation(for: clipID, context: context)
        let effects = context.timelineState.timeline.tracks[location.trackIndex].clips[location.clipIndex].effects
        if let idx = effects.firstIndex(where: { $0.id == effectID }) {
            removedEffect = effects[idx]
            removedIndex = idx
            context.timelineState.timeline.tracks[location.trackIndex].clips[location.clipIndex].effects.remove(at: idx)
        }
    }

    public func undo(context: EditingContext) throws {
        guard let effect = removedEffect, let idx = removedIndex else { return }
        for ti in context.timelineState.timeline.tracks.indices {
            if let ci = context.timelineState.timeline.tracks[ti].clips.firstIndex(where: { $0.id == clipID }) {
                let safeIdx = min(idx, context.timelineState.timeline.tracks[ti].clips[ci].effects.count)
                context.timelineState.timeline.tracks[ti].clips[ci].effects.insert(effect, at: safeIdx)
                return
            }
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
