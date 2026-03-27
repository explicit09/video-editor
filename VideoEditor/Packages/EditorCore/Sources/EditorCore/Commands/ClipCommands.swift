import Foundation

// MARK: - InsertClipCommand

public struct InsertClipCommand: Command {
    public let name = "Insert Clip"
    public let clip: Clip
    public let trackID: UUID

    public init(clip: Clip, trackID: UUID) {
        self.clip = clip
        self.trackID = trackID
    }

    public mutating func execute(context: EditingContext) throws {
        guard let trackIndex = context.timelineState.timeline.tracks.firstIndex(where: { $0.id == trackID }) else {
            throw CommandError.trackNotFound(trackID)
        }
        context.timelineState.timeline.tracks[trackIndex].clips.append(clip)
    }

    public func undo(context: EditingContext) throws {
        guard let trackIndex = context.timelineState.timeline.tracks.firstIndex(where: { $0.id == trackID }) else { return }
        context.timelineState.timeline.tracks[trackIndex].clips.removeAll { $0.id == clip.id }
    }
}

// MARK: - DeleteClipsCommand

public struct DeleteClipsCommand: Command {
    public let name = "Delete Clips"
    public let clipIDs: [UUID]
    private var removedClips: [(clip: Clip, trackID: UUID)] = []

    public init(clipIDs: [UUID]) {
        self.clipIDs = clipIDs
    }

    public mutating func execute(context: EditingContext) throws {
        removedClips = []
        for trackIndex in context.timelineState.timeline.tracks.indices {
            let trackID = context.timelineState.timeline.tracks[trackIndex].id
            let toRemove = context.timelineState.timeline.tracks[trackIndex].clips.filter { clipIDs.contains($0.id) }
            for clip in toRemove {
                removedClips.append((clip: clip, trackID: trackID))
            }
            context.timelineState.timeline.tracks[trackIndex].clips.removeAll { clipIDs.contains($0.id) }
        }
    }

    public func undo(context: EditingContext) throws {
        for entry in removedClips {
            guard let trackIndex = context.timelineState.timeline.tracks.firstIndex(where: { $0.id == entry.trackID }) else { continue }
            context.timelineState.timeline.tracks[trackIndex].clips.append(entry.clip)
        }
    }
}

// MARK: - MoveClipCommand

public struct MoveClipCommand: Command {
    public let name = "Move Clip"
    public let clipID: UUID
    public let newStart: TimeInterval
    public let targetTrackID: UUID
    private var previousRange: TimeRange?
    private var previousTrackID: UUID?

    public init(clipID: UUID, newStart: TimeInterval, targetTrackID: UUID) {
        self.clipID = clipID
        self.newStart = newStart
        self.targetTrackID = targetTrackID
    }

    public mutating func execute(context: EditingContext) throws {
        // Find the clip
        for trackIndex in context.timelineState.timeline.tracks.indices {
            if let clipIndex = context.timelineState.timeline.tracks[trackIndex].clips.firstIndex(where: { $0.id == clipID }) {
                let clip = context.timelineState.timeline.tracks[trackIndex].clips[clipIndex]
                previousRange = clip.timelineRange
                previousTrackID = context.timelineState.timeline.tracks[trackIndex].id

                let duration = clip.timelineRange.duration
                context.timelineState.timeline.tracks[trackIndex].clips[clipIndex].timelineRange = TimeRange(start: newStart, duration: duration)
                return
            }
        }
        throw CommandError.clipNotFound(clipID)
    }

    public func undo(context: EditingContext) throws {
        guard let previousRange else { return }
        for trackIndex in context.timelineState.timeline.tracks.indices {
            if let clipIndex = context.timelineState.timeline.tracks[trackIndex].clips.firstIndex(where: { $0.id == clipID }) {
                context.timelineState.timeline.tracks[trackIndex].clips[clipIndex].timelineRange = previousRange
                return
            }
        }
    }
}

// MARK: - TrimClipCommand

public struct TrimClipCommand: Command {
    public let name = "Trim Clip"
    public let clipID: UUID
    public let newSourceRange: TimeRange
    private var previousSourceRange: TimeRange?

    public init(clipID: UUID, newSourceRange: TimeRange) {
        self.clipID = clipID
        self.newSourceRange = newSourceRange
    }

    public mutating func execute(context: EditingContext) throws {
        for trackIndex in context.timelineState.timeline.tracks.indices {
            if let clipIndex = context.timelineState.timeline.tracks[trackIndex].clips.firstIndex(where: { $0.id == clipID }) {
                previousSourceRange = context.timelineState.timeline.tracks[trackIndex].clips[clipIndex].sourceRange
                context.timelineState.timeline.tracks[trackIndex].clips[clipIndex].sourceRange = newSourceRange
                return
            }
        }
        throw CommandError.clipNotFound(clipID)
    }

    public func undo(context: EditingContext) throws {
        guard let previousSourceRange else { return }
        for trackIndex in context.timelineState.timeline.tracks.indices {
            if let clipIndex = context.timelineState.timeline.tracks[trackIndex].clips.firstIndex(where: { $0.id == clipID }) {
                context.timelineState.timeline.tracks[trackIndex].clips[clipIndex].sourceRange = previousSourceRange
                return
            }
        }
    }
}

// MARK: - SplitClipCommand

public struct SplitClipCommand: Command {
    public let name = "Split Clip"
    public let clipID: UUID
    public let at: TimeInterval
    private var originalClip: Clip?
    private var secondClipID: UUID?
    private var trackID: UUID?

    public init(clipID: UUID, at: TimeInterval) {
        self.clipID = clipID
        self.at = at
    }

    public mutating func execute(context: EditingContext) throws {
        for trackIndex in context.timelineState.timeline.tracks.indices {
            if let clipIndex = context.timelineState.timeline.tracks[trackIndex].clips.firstIndex(where: { $0.id == clipID }) {
                let clip = context.timelineState.timeline.tracks[trackIndex].clips[clipIndex]
                originalClip = clip
                trackID = context.timelineState.timeline.tracks[trackIndex].id

                guard clip.timelineRange.contains(at) else {
                    throw CommandError.splitPointOutOfRange
                }

                let splitOffset = at - clip.timelineRange.start

                // Shorten first clip
                context.timelineState.timeline.tracks[trackIndex].clips[clipIndex].timelineRange = TimeRange(
                    start: clip.timelineRange.start,
                    end: at
                )
                context.timelineState.timeline.tracks[trackIndex].clips[clipIndex].sourceRange = TimeRange(
                    start: clip.sourceRange.start,
                    end: clip.sourceRange.start + splitOffset
                )

                // Create second clip
                let newID = UUID()
                secondClipID = newID
                let secondClip = Clip(
                    id: newID,
                    assetID: clip.assetID,
                    timelineRange: TimeRange(start: at, end: clip.timelineRange.end),
                    sourceRange: TimeRange(start: clip.sourceRange.start + splitOffset, end: clip.sourceRange.end),
                    transform: clip.transform,
                    opacity: clip.opacity,
                    volume: clip.volume,
                    effects: clip.effects,
                    keyframes: clip.keyframes,
                    metadata: clip.metadata
                )
                context.timelineState.timeline.tracks[trackIndex].clips.append(secondClip)
                return
            }
        }
        throw CommandError.clipNotFound(clipID)
    }

    public func undo(context: EditingContext) throws {
        guard let originalClip, let secondClipID, let trackID else { return }
        guard let trackIndex = context.timelineState.timeline.tracks.firstIndex(where: { $0.id == trackID }) else { return }

        // Remove the second clip
        context.timelineState.timeline.tracks[trackIndex].clips.removeAll { $0.id == secondClipID }

        // Restore original clip
        if let clipIndex = context.timelineState.timeline.tracks[trackIndex].clips.firstIndex(where: { $0.id == clipID }) {
            context.timelineState.timeline.tracks[trackIndex].clips[clipIndex] = originalClip
        }
    }
}

// MARK: - SetMarkerCommand

public struct SetMarkerCommand: Command {
    public let name = "Set Marker"
    public let marker: Marker

    public init(at time: TimeInterval, label: String) {
        self.marker = Marker(time: time, label: label)
    }

    public mutating func execute(context: EditingContext) throws {
        context.timelineState.timeline.markers.append(marker)
        context.timelineState.timeline.markers.sort { $0.time < $1.time }
    }

    public func undo(context: EditingContext) throws {
        context.timelineState.timeline.markers.removeAll { $0.id == marker.id }
    }
}

// MARK: - CommandError

public enum CommandError: Error {
    case trackNotFound(UUID)
    case clipNotFound(UUID)
    case splitPointOutOfRange
}
