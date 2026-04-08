import Foundation

// MARK: - Audio Effect Commands

/// Apply or update a noise gate on a clip's audio effect chain.
public struct ApplyGateCommand: Command {
    public let name = "Apply Gate"
    public let clipID: UUID
    public let config: GateConfig
    public var affectedClipIDs: [UUID] { [clipID] }
    private var previousGate: GateConfig?
    private var hadChain: Bool = false

    public init(clipID: UUID, config: GateConfig) {
        self.clipID = clipID
        self.config = config
    }

    public mutating func execute(context: EditingContext) throws {
        let location = try editableClipLocation(for: clipID, context: context)
        var clip = context.timelineState.timeline.tracks[location.trackIndex].clips[location.clipIndex]
        hadChain = clip.audioEffects != nil
        previousGate = clip.audioEffects?.gate
        if clip.audioEffects == nil { clip.audioEffects = AudioEffectChain() }
        clip.audioEffects?.gate = config
        context.timelineState.timeline.tracks[location.trackIndex].clips[location.clipIndex] = clip
    }

    public func undo(context: EditingContext) throws {
        let location = try editableClipLocation(for: clipID, context: context)
        if hadChain {
            context.timelineState.timeline.tracks[location.trackIndex].clips[location.clipIndex].audioEffects?.gate = previousGate
        } else {
            context.timelineState.timeline.tracks[location.trackIndex].clips[location.clipIndex].audioEffects = nil
        }
    }
}

/// Apply or update a compressor on a clip's audio effect chain.
public struct ApplyCompressorCommand: Command {
    public let name = "Apply Compressor"
    public let clipID: UUID
    public let config: CompressorConfig
    public var affectedClipIDs: [UUID] { [clipID] }
    private var previousCompressor: CompressorConfig?
    private var hadChain: Bool = false

    public init(clipID: UUID, config: CompressorConfig) {
        self.clipID = clipID
        self.config = config
    }

    public mutating func execute(context: EditingContext) throws {
        let location = try editableClipLocation(for: clipID, context: context)
        var clip = context.timelineState.timeline.tracks[location.trackIndex].clips[location.clipIndex]
        hadChain = clip.audioEffects != nil
        previousCompressor = clip.audioEffects?.compressor
        if clip.audioEffects == nil { clip.audioEffects = AudioEffectChain() }
        clip.audioEffects?.compressor = config
        context.timelineState.timeline.tracks[location.trackIndex].clips[location.clipIndex] = clip
    }

    public func undo(context: EditingContext) throws {
        let location = try editableClipLocation(for: clipID, context: context)
        if hadChain {
            context.timelineState.timeline.tracks[location.trackIndex].clips[location.clipIndex].audioEffects?.compressor = previousCompressor
        } else {
            context.timelineState.timeline.tracks[location.trackIndex].clips[location.clipIndex].audioEffects = nil
        }
    }
}

/// Apply or update a de-esser on a clip's audio effect chain.
public struct ApplyDeEsserCommand: Command {
    public let name = "Apply De-Esser"
    public let clipID: UUID
    public let config: DeEsserConfig
    public var affectedClipIDs: [UUID] { [clipID] }
    private var previousDeEsser: DeEsserConfig?
    private var hadChain: Bool = false

    public init(clipID: UUID, config: DeEsserConfig) {
        self.clipID = clipID
        self.config = config
    }

    public mutating func execute(context: EditingContext) throws {
        let location = try editableClipLocation(for: clipID, context: context)
        var clip = context.timelineState.timeline.tracks[location.trackIndex].clips[location.clipIndex]
        hadChain = clip.audioEffects != nil
        previousDeEsser = clip.audioEffects?.deEsser
        if clip.audioEffects == nil { clip.audioEffects = AudioEffectChain() }
        clip.audioEffects?.deEsser = config
        context.timelineState.timeline.tracks[location.trackIndex].clips[location.clipIndex] = clip
    }

    public func undo(context: EditingContext) throws {
        let location = try editableClipLocation(for: clipID, context: context)
        if hadChain {
            context.timelineState.timeline.tracks[location.trackIndex].clips[location.clipIndex].audioEffects?.deEsser = previousDeEsser
        } else {
            context.timelineState.timeline.tracks[location.trackIndex].clips[location.clipIndex].audioEffects = nil
        }
    }
}

/// Apply or update an EQ on a clip's audio effect chain.
public struct ApplyEQCommand: Command {
    public let name = "Apply EQ"
    public let clipID: UUID
    public let config: EQConfig
    public var affectedClipIDs: [UUID] { [clipID] }
    private var previousEQ: EQConfig?
    private var hadChain: Bool = false

    public init(clipID: UUID, config: EQConfig) {
        self.clipID = clipID
        self.config = config
    }

    public mutating func execute(context: EditingContext) throws {
        let location = try editableClipLocation(for: clipID, context: context)
        var clip = context.timelineState.timeline.tracks[location.trackIndex].clips[location.clipIndex]
        hadChain = clip.audioEffects != nil
        previousEQ = clip.audioEffects?.eq
        if clip.audioEffects == nil { clip.audioEffects = AudioEffectChain() }
        clip.audioEffects?.eq = config
        context.timelineState.timeline.tracks[location.trackIndex].clips[location.clipIndex] = clip
    }

    public func undo(context: EditingContext) throws {
        let location = try editableClipLocation(for: clipID, context: context)
        if hadChain {
            context.timelineState.timeline.tracks[location.trackIndex].clips[location.clipIndex].audioEffects?.eq = previousEQ
        } else {
            context.timelineState.timeline.tracks[location.trackIndex].clips[location.clipIndex].audioEffects = nil
        }
    }
}

/// Apply or update a limiter on a clip's audio effect chain.
public struct ApplyLimiterCommand: Command {
    public let name = "Apply Limiter"
    public let clipID: UUID
    public let config: LimiterConfig
    public var affectedClipIDs: [UUID] { [clipID] }
    private var previousLimiter: LimiterConfig?
    private var hadChain: Bool = false

    public init(clipID: UUID, config: LimiterConfig) {
        self.clipID = clipID
        self.config = config
    }

    public mutating func execute(context: EditingContext) throws {
        let location = try editableClipLocation(for: clipID, context: context)
        var clip = context.timelineState.timeline.tracks[location.trackIndex].clips[location.clipIndex]
        hadChain = clip.audioEffects != nil
        previousLimiter = clip.audioEffects?.limiter
        if clip.audioEffects == nil { clip.audioEffects = AudioEffectChain() }
        clip.audioEffects?.limiter = config
        context.timelineState.timeline.tracks[location.trackIndex].clips[location.clipIndex] = clip
    }

    public func undo(context: EditingContext) throws {
        let location = try editableClipLocation(for: clipID, context: context)
        if hadChain {
            context.timelineState.timeline.tracks[location.trackIndex].clips[location.clipIndex].audioEffects?.limiter = previousLimiter
        } else {
            context.timelineState.timeline.tracks[location.trackIndex].clips[location.clipIndex].audioEffects = nil
        }
    }
}

/// Set a target LUFS normalization target on a clip's audio effect chain.
public struct NormalizeLUFSCommand: Command {
    public let name = "Normalize Audio to LUFS"
    public let clipID: UUID
    public let targetLUFS: Double
    public var affectedClipIDs: [UUID] { [clipID] }
    private var previousLUFS: Double?
    private var hadChain: Bool = false

    public init(clipID: UUID, targetLUFS: Double) {
        self.clipID = clipID
        self.targetLUFS = targetLUFS
    }

    public mutating func execute(context: EditingContext) throws {
        let location = try editableClipLocation(for: clipID, context: context)
        var clip = context.timelineState.timeline.tracks[location.trackIndex].clips[location.clipIndex]
        hadChain = clip.audioEffects != nil
        previousLUFS = clip.audioEffects?.normalizeLUFS
        if clip.audioEffects == nil { clip.audioEffects = AudioEffectChain() }
        clip.audioEffects?.normalizeLUFS = targetLUFS
        context.timelineState.timeline.tracks[location.trackIndex].clips[location.clipIndex] = clip
    }

    public func undo(context: EditingContext) throws {
        let location = try editableClipLocation(for: clipID, context: context)
        if hadChain {
            context.timelineState.timeline.tracks[location.trackIndex].clips[location.clipIndex].audioEffects?.normalizeLUFS = previousLUFS
        } else {
            context.timelineState.timeline.tracks[location.trackIndex].clips[location.clipIndex].audioEffects = nil
        }
    }
}
