import Foundation

// MARK: - InsertClipCommand

public struct InsertClipCommand: Command {
    public let name = "Insert Clip"
    public let clip: Clip
    public let trackID: UUID
    public var affectedClipIDs: [UUID] { [clip.id] }
    public var affectedTrackIDs: [UUID] { [trackID] }

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
    public var affectedClipIDs: [UUID] { clipIDs }
    private var removedClips: [(clip: Clip, trackID: UUID, clipIndex: Int)] = []

    public init(clipIDs: [UUID]) {
        self.clipIDs = clipIDs
    }

    public mutating func execute(context: EditingContext) throws {
        removedClips = []
        for trackIndex in context.timelineState.timeline.tracks.indices {
            let trackID = context.timelineState.timeline.tracks[trackIndex].id
            for (clipIndex, clip) in context.timelineState.timeline.tracks[trackIndex].clips.enumerated() where clipIDs.contains(clip.id) {
                removedClips.append((clip: clip, trackID: trackID, clipIndex: clipIndex))
            }
            context.timelineState.timeline.tracks[trackIndex].clips.removeAll { clipIDs.contains($0.id) }
        }
    }

    public func undo(context: EditingContext) throws {
        // Restore in order of original index (lowest first) so positions stay correct
        let sorted = removedClips.sorted { $0.clipIndex < $1.clipIndex }
        for entry in sorted {
            guard let trackIndex = context.timelineState.timeline.tracks.firstIndex(where: { $0.id == entry.trackID }) else { continue }
            let insertAt = min(entry.clipIndex, context.timelineState.timeline.tracks[trackIndex].clips.count)
            context.timelineState.timeline.tracks[trackIndex].clips.insert(entry.clip, at: insertAt)
        }
    }
}

// MARK: - MoveClipCommand

public struct MoveClipCommand: Command {
    public let name = "Move Clip"
    public let clipID: UUID
    public let newStart: TimeInterval
    public let targetTrackID: UUID
    public var affectedClipIDs: [UUID] { [clipID] }
    public var affectedTrackIDs: [UUID] {
        guard let previousTrackID, previousTrackID != targetTrackID else { return [targetTrackID] }
        return [previousTrackID, targetTrackID]
    }
    public var metadata: [String: String] { ["newStart": String(newStart)] }
    private var previousRange: TimeRange?
    private var previousTrackID: UUID?
    private var previousClipIndex: Int?

    public init(clipID: UUID, newStart: TimeInterval, targetTrackID: UUID) {
        self.clipID = clipID
        self.newStart = newStart
        self.targetTrackID = targetTrackID
    }

    public mutating func execute(context: EditingContext) throws {
        guard let sourceTrackIndex = context.timelineState.timeline.tracks.firstIndex(where: { track in
            track.clips.contains(where: { $0.id == clipID })
        }) else {
            throw CommandError.clipNotFound(clipID)
        }
        guard let targetTrackIndex = context.timelineState.timeline.tracks.firstIndex(where: { $0.id == targetTrackID }) else {
            throw CommandError.trackNotFound(targetTrackID)
        }
        guard let clipIndex = context.timelineState.timeline.tracks[sourceTrackIndex].clips.firstIndex(where: { $0.id == clipID }) else {
            throw CommandError.clipNotFound(clipID)
        }

        let clip = context.timelineState.timeline.tracks[sourceTrackIndex].clips[clipIndex]
        previousRange = clip.timelineRange
        previousTrackID = context.timelineState.timeline.tracks[sourceTrackIndex].id
        previousClipIndex = clipIndex

        var movedClip = clip
        movedClip.timelineRange = TimeRange(start: newStart, duration: clip.timelineRange.duration)

        context.timelineState.timeline.tracks[sourceTrackIndex].clips.remove(at: clipIndex)

        let insertionIndex = Self.insertionIndex(for: movedClip, in: context.timelineState.timeline.tracks[targetTrackIndex].clips)
        context.timelineState.timeline.tracks[targetTrackIndex].clips.insert(movedClip, at: insertionIndex)
    }

    public func undo(context: EditingContext) throws {
        guard let previousRange, let previousTrackID, let previousClipIndex else { return }
        guard let currentTrackIndex = context.timelineState.timeline.tracks.firstIndex(where: { track in
            track.clips.contains(where: { $0.id == clipID })
        }), let currentClipIndex = context.timelineState.timeline.tracks[currentTrackIndex].clips.firstIndex(where: { $0.id == clipID }) else {
            return
        }

        var restoredClip = context.timelineState.timeline.tracks[currentTrackIndex].clips.remove(at: currentClipIndex)
        restoredClip.timelineRange = previousRange

        guard let destinationTrackIndex = context.timelineState.timeline.tracks.firstIndex(where: { $0.id == previousTrackID }) else {
            let insertAt = min(currentClipIndex, context.timelineState.timeline.tracks[currentTrackIndex].clips.count)
            context.timelineState.timeline.tracks[currentTrackIndex].clips.insert(restoredClip, at: insertAt)
            return
        }

        let insertAt = min(previousClipIndex, context.timelineState.timeline.tracks[destinationTrackIndex].clips.count)
        context.timelineState.timeline.tracks[destinationTrackIndex].clips.insert(restoredClip, at: insertAt)
    }

    private static func insertionIndex(for clip: Clip, in clips: [Clip]) -> Int {
        clips.firstIndex {
            if $0.timelineRange.start != clip.timelineRange.start {
                return $0.timelineRange.start > clip.timelineRange.start
            }
            return $0.timelineRange.end > clip.timelineRange.end
        } ?? clips.count
    }
}

// MARK: - TrimClipCommand

public struct TrimClipCommand: Command {
    public let name = "Trim Clip"
    public let clipID: UUID
    public let newSourceRange: TimeRange
    public var affectedClipIDs: [UUID] { [clipID] }
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
    public var affectedClipIDs: [UUID] { [clipID] + (secondClipID.map { [$0] } ?? []) }
    public var metadata: [String: String] { ["splitAt": String(at)] }
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

                guard at > clip.timelineRange.start && at < clip.timelineRange.end else {
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
                context.timelineState.timeline.tracks[trackIndex].clips.insert(secondClip, at: clipIndex + 1)
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
