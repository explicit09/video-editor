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
    // Property commands
    case setClipVolume(clipID: UUID, volume: Double)
    case setClipOpacity(clipID: UUID, opacity: Double)
    case setClipTransform(clipID: UUID, transform: Transform2D)
    case setClipCrop(clipID: UUID, cropRect: CropRect)
    case muteTrack(trackID: UUID, muted: Bool)
    case lockTrack(trackID: UUID, locked: Bool)
    case soloTrack(trackID: UUID, soloed: Bool)
    case setTrackVolume(trackID: UUID, volume: Double)
    case renameClip(clipID: UUID, label: String)
    case duplicateClip(clipID: UUID)
    case setClipTransition(clipID: UUID, transition: ClipTransition)
    case setClipSpeed(clipID: UUID, speed: Double)
    case setClipEffect(clipID: UUID, effect: EffectInstance)
    case replacePrimaryClipEffect(clipID: UUID, effect: EffectInstance)
    case rollTrim(leftClipID: UUID, rightClipID: UUID, newBoundary: TimeInterval)
    case reorderTrack(trackID: UUID, newIndex: Int)
    case linkClips(clipIDs: [UUID], linkGroupID: UUID?)
    case removeClipEffect(clipID: UUID, effectID: UUID)
    case setClipBlendMode(clipID: UUID, blendMode: BlendMode)
    case setTrackAudioEffects(trackID: UUID, effectChain: AudioEffectChain?)
    case setBroadcastOverlay(config: BroadcastOverlayConfig?)
    case setClipKeyframes(clipID: UUID, track: String, keyframes: [Keyframe])
    case slipClip(clipID: UUID, delta: TimeInterval)
    case rippleTrim(clipID: UUID, edge: TrimEdge, delta: TimeInterval)
    /// Multiple intents as a single undoable operation.
    case batch([EditorIntent])
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
        case .setClipVolume(let clipID, let volume):
            return SetClipVolumeCommand(clipID: clipID, volume: volume)
        case .setClipOpacity(let clipID, let opacity):
            return SetClipOpacityCommand(clipID: clipID, opacity: opacity)
        case .setClipTransform(let clipID, let transform):
            return SetClipTransformCommand(clipID: clipID, transform: transform)
        case .setClipCrop(let clipID, let cropRect):
            return SetClipCropCommand(clipID: clipID, cropRect: cropRect)
        case .muteTrack(let trackID, let muted):
            return MuteTrackCommand(trackID: trackID, muted: muted)
        case .lockTrack(let trackID, let locked):
            return LockTrackCommand(trackID: trackID, locked: locked)
        case .soloTrack(let trackID, let soloed):
            return SoloTrackCommand(trackID: trackID, soloed: soloed)
        case .setTrackVolume(let trackID, let volume):
            return SetTrackVolumeCommand(trackID: trackID, volume: volume)
        case .renameClip(let clipID, let label):
            return RenameClipCommand(clipID: clipID, label: label)
        case .duplicateClip(let clipID):
            return DuplicateClipCommand(clipID: clipID)
        case .setClipTransition(let clipID, let transition):
            return SetClipTransitionCommand(clipID: clipID, transition: transition)
        case .setClipSpeed(let clipID, let speed):
            return SetClipSpeedCommand(clipID: clipID, speed: speed)
        case .setClipEffect(let clipID, let effect):
            return SetClipEffectCommand(clipID: clipID, effect: effect)
        case .replacePrimaryClipEffect(let clipID, let effect):
            return ReplacePrimaryClipEffectCommand(clipID: clipID, effect: effect)
        case .rollTrim(let leftClipID, let rightClipID, let newBoundary):
            return RollTrimCommand(leftClipID: leftClipID, rightClipID: rightClipID, newBoundary: newBoundary)
        case .reorderTrack(let trackID, let newIndex):
            return ReorderTrackCommand(trackID: trackID, newIndex: newIndex)
        case .linkClips(let clipIDs, let linkGroupID):
            return LinkClipsCommand(clipIDs: clipIDs, linkGroupID: linkGroupID)
        case .removeClipEffect(let clipID, let effectID):
            return RemoveClipEffectCommand(clipID: clipID, effectID: effectID)
        case .setClipBlendMode(let clipID, let blendMode):
            return SetClipBlendModeCommand(clipID: clipID, blendMode: blendMode)
        case .setTrackAudioEffects(let trackID, let effectChain):
            return SetTrackAudioEffectsCommand(trackID: trackID, effectChain: effectChain)
        case .setBroadcastOverlay(let config):
            return SetBroadcastOverlayCommand(config: config)
        case .setClipKeyframes(let clipID, let track, let keyframes):
            return SetClipKeyframesCommand(clipID: clipID, track: track, keyframes: keyframes)
        case .slipClip(let clipID, let delta):
            return SlipClipCommand(clipID: clipID, delta: delta)
        case .rippleTrim(let clipID, let edge, let delta):
            return RippleTrimCommand(clipID: clipID, edge: edge, delta: delta)
        case .batch(let intents):
            let commands = try intents.map { try resolve($0) }
            return BatchCommand(name: "Batch", commands: commands)
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
        guard let marker = context.timelineState.timeline.markers.first(where: { $0.id == markerID }) else {
            throw CommandError.clipNotFound(markerID) // reuse existing error type
        }
        removedMarker = marker
        context.timelineState.timeline.markers.removeAll { $0.id == markerID }
    }

    public func undo(context: EditingContext) throws {
        guard let marker = removedMarker else { return }
        context.timelineState.timeline.markers.append(marker)
        context.timelineState.timeline.markers.sort { $0.time < $1.time }
    }
}
