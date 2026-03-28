import Testing
import Foundation
@testable import EditorCore

@Suite("Command Edge Case Tests")
struct CommandEdgeCaseTests {

    @MainActor
    @Test("MoveClip moves clips across tracks and undo restores the original layout")
    func moveClipAcrossTracksAndUndo() throws {
        let sourceClip = makeClip(start: 2, end: 4, label: "Move Me")
        let sourceSibling = makeClip(start: 5, end: 7, label: "Stay Put")
        let targetClip = makeClip(start: 10, end: 12, label: "Target")

        let sourceTrack = Track(name: "V1", type: .video, clips: [sourceSibling, sourceClip])
        let targetTrack = Track(name: "V2", type: .video, clips: [targetClip])

        let context = EditingContext(
            timelineState: TimelineState(
                timeline: Timeline(tracks: [sourceTrack, targetTrack])
            )
        )

        var command = MoveClipCommand(clipID: sourceClip.id, newStart: 7, targetTrackID: targetTrack.id)
        try command.execute(context: context)

        let updatedSourceTrack = context.timelineState.timeline.tracks[0]
        let updatedTargetTrack = context.timelineState.timeline.tracks[1]

        #expect(updatedSourceTrack.clips.map(\.id) == [sourceSibling.id])
        #expect(updatedTargetTrack.clips.map(\.id) == [sourceClip.id, targetClip.id])
        #expect(updatedTargetTrack.clips[0].timelineRange == TimeRange(start: 7, end: 9))

        try command.undo(context: context)

        let restoredSourceTrack = context.timelineState.timeline.tracks[0]
        let restoredTargetTrack = context.timelineState.timeline.tracks[1]

        #expect(restoredSourceTrack.clips.map(\.id) == [sourceSibling.id, sourceClip.id])
        #expect(restoredSourceTrack.clips[1].timelineRange == TimeRange(start: 2, end: 4))
        #expect(restoredTargetTrack.clips.map(\.id) == [targetClip.id])
    }

    @MainActor
    @Test("SplitClip rejects split points at the clip boundaries")
    func splitClipRejectsBoundaryPoints() {
        let clip = makeClip(start: 0, end: 10, label: "Boundary")

        let startContext = EditingContext(
            timelineState: TimelineState(
                timeline: Timeline(tracks: [Track(name: "V1", type: .video, clips: [clip])])
            )
        )
        var splitAtStart = SplitClipCommand(clipID: clip.id, at: 0)

        do {
            try splitAtStart.execute(context: startContext)
            Issue.record("Expected split at the clip start to fail")
        } catch CommandError.splitPointOutOfRange {
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        let endContext = EditingContext(
            timelineState: TimelineState(
                timeline: Timeline(tracks: [Track(name: "V1", type: .video, clips: [clip])])
            )
        )
        var splitAtEnd = SplitClipCommand(clipID: clip.id, at: 10)

        do {
            try splitAtEnd.execute(context: endContext)
            Issue.record("Expected split at the clip end to fail")
        } catch CommandError.splitPointOutOfRange {
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @MainActor
    @Test("SplitClip keeps the new clip adjacent to the original and undo restores ordering")
    func splitClipPreservesTrackOrder() throws {
        let clipToSplit = makeClip(start: 0, end: 10, label: "Split Me")
        let laterClip = makeClip(start: 12, end: 16, label: "Later")

        let context = EditingContext(
            timelineState: TimelineState(
                timeline: Timeline(tracks: [Track(name: "V1", type: .video, clips: [clipToSplit, laterClip])])
            )
        )

        var command = SplitClipCommand(clipID: clipToSplit.id, at: 4)
        try command.execute(context: context)

        let clips = context.timelineState.timeline.tracks[0].clips
        #expect(clips.count == 3)
        #expect(clips[0].id == clipToSplit.id)
        #expect(clips[0].timelineRange == TimeRange(start: 0, end: 4))
        #expect(clips[1].id != clipToSplit.id)
        #expect(clips[1].id != laterClip.id)
        #expect(clips[1].timelineRange == TimeRange(start: 4, end: 10))
        #expect(clips[2].id == laterClip.id)

        try command.undo(context: context)

        let restoredClips = context.timelineState.timeline.tracks[0].clips
        #expect(restoredClips.map(\.id) == [clipToSplit.id, laterClip.id])
        #expect(restoredClips[0].timelineRange == TimeRange(start: 0, end: 10))
    }

    @MainActor
    @Test("DeleteClips undo restores original clip ordering")
    func deleteClipsUndoRestoresOrder() throws {
        let firstClip = makeClip(start: 0, end: 2, label: "First")
        let middleClip = makeClip(start: 2, end: 4, label: "Middle")
        let lastClip = makeClip(start: 4, end: 6, label: "Last")

        let context = EditingContext(
            timelineState: TimelineState(
                timeline: Timeline(
                    tracks: [Track(name: "V1", type: .video, clips: [firstClip, middleClip, lastClip])]
                )
            )
        )

        var command = DeleteClipsCommand(clipIDs: [firstClip.id, lastClip.id])
        try command.execute(context: context)

        #expect(context.timelineState.timeline.tracks[0].clips.map(\.id) == [middleClip.id])

        try command.undo(context: context)

        #expect(context.timelineState.timeline.tracks[0].clips.map(\.id) == [firstClip.id, middleClip.id, lastClip.id])
    }

    private func makeClip(start: TimeInterval, end: TimeInterval, label: String) -> Clip {
        Clip(
            assetID: UUID(),
            timelineRange: TimeRange(start: start, end: end),
            sourceRange: TimeRange(start: 0, end: end - start),
            metadata: ClipMetadata(label: label)
        )
    }
}
