import Foundation

/// Roll trim: adjusts the boundary between two adjacent clips.
/// The outgoing clip's end and incoming clip's start move together.
/// Total timeline duration doesn't change.
public struct RollTrimCommand: Command {
    public let name = "Roll Trim"
    public let leftClipID: UUID
    public let rightClipID: UUID
    public let newBoundary: TimeInterval
    public var affectedClipIDs: [UUID] { [leftClipID, rightClipID] }

    private var previousLeftEnd: TimeInterval?
    private var previousRightStart: TimeInterval?
    private var previousLeftSourceEnd: TimeInterval?
    private var previousRightSourceStart: TimeInterval?

    public init(leftClipID: UUID, rightClipID: UUID, newBoundary: TimeInterval) {
        self.leftClipID = leftClipID
        self.rightClipID = rightClipID
        self.newBoundary = newBoundary
    }

    public mutating func execute(context: EditingContext) throws {
        // Find both clips (must be on same track)
        for trackIndex in context.timelineState.timeline.tracks.indices {
            let clips = context.timelineState.timeline.tracks[trackIndex].clips
            guard let leftIdx = clips.firstIndex(where: { $0.id == leftClipID }),
                  let rightIdx = clips.firstIndex(where: { $0.id == rightClipID }) else {
                continue
            }

            let leftClip = clips[leftIdx]
            let rightClip = clips[rightIdx]

            // Validate: new boundary must be within both clips' source ranges
            guard newBoundary > leftClip.timelineRange.start,
                  newBoundary < rightClip.timelineRange.end else {
                throw CommandError.splitPointOutOfRange
            }

            // Store previous state
            previousLeftEnd = leftClip.timelineRange.end
            previousRightStart = rightClip.timelineRange.start
            previousLeftSourceEnd = leftClip.sourceRange.end
            previousRightSourceStart = rightClip.sourceRange.start

            // Calculate source deltas
            let leftDelta = newBoundary - leftClip.timelineRange.end
            let rightDelta = newBoundary - rightClip.timelineRange.start

            // Adjust left clip: extend/shorten end
            context.timelineState.timeline.tracks[trackIndex].clips[leftIdx].timelineRange = TimeRange(
                start: leftClip.timelineRange.start,
                end: newBoundary
            )
            context.timelineState.timeline.tracks[trackIndex].clips[leftIdx].sourceRange = TimeRange(
                start: leftClip.sourceRange.start,
                end: leftClip.sourceRange.end + leftDelta
            )

            // Adjust right clip: extend/shorten start
            context.timelineState.timeline.tracks[trackIndex].clips[rightIdx].timelineRange = TimeRange(
                start: newBoundary,
                end: rightClip.timelineRange.end
            )
            context.timelineState.timeline.tracks[trackIndex].clips[rightIdx].sourceRange = TimeRange(
                start: rightClip.sourceRange.start + rightDelta,
                end: rightClip.sourceRange.end
            )

            return
        }

        throw CommandError.clipNotFound(leftClipID)
    }

    public func undo(context: EditingContext) throws {
        guard let prevLeftEnd = previousLeftEnd,
              let prevRightStart = previousRightStart,
              let prevLeftSourceEnd = previousLeftSourceEnd,
              let prevRightSourceStart = previousRightSourceStart else { return }

        for trackIndex in context.timelineState.timeline.tracks.indices {
            guard let leftIdx = context.timelineState.timeline.tracks[trackIndex].clips.firstIndex(where: { $0.id == leftClipID }),
                  let rightIdx = context.timelineState.timeline.tracks[trackIndex].clips.firstIndex(where: { $0.id == rightClipID }) else {
                continue
            }

            let leftClip = context.timelineState.timeline.tracks[trackIndex].clips[leftIdx]
            let rightClip = context.timelineState.timeline.tracks[trackIndex].clips[rightIdx]

            context.timelineState.timeline.tracks[trackIndex].clips[leftIdx].timelineRange = TimeRange(
                start: leftClip.timelineRange.start, end: prevLeftEnd
            )
            context.timelineState.timeline.tracks[trackIndex].clips[leftIdx].sourceRange = TimeRange(
                start: leftClip.sourceRange.start, end: prevLeftSourceEnd
            )
            context.timelineState.timeline.tracks[trackIndex].clips[rightIdx].timelineRange = TimeRange(
                start: prevRightStart, end: rightClip.timelineRange.end
            )
            context.timelineState.timeline.tracks[trackIndex].clips[rightIdx].sourceRange = TimeRange(
                start: prevRightSourceStart, end: rightClip.sourceRange.end
            )
            return
        }
    }
}
