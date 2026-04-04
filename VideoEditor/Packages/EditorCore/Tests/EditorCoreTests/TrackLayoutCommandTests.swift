import Testing
import Foundation
@testable import EditorCore

@Suite("Track Layout Command Tests")
struct TrackLayoutCommandTests {

    @MainActor
    @Test("InsertClip shifts forward to avoid overlapping an existing clip")
    func insertClipAvoidsOverlap() throws {
        let existing = makeClip(start: 0, end: 5, label: "Existing")
        let inserted = makeClip(start: 3, end: 7, label: "Inserted")
        let track = Track(name: "V1", type: .video, clips: [existing])
        let context = EditingContext(
            timelineState: TimelineState(timeline: Timeline(tracks: [track]))
        )

        var command = InsertClipCommand(clip: inserted, trackID: track.id)
        try command.execute(context: context)

        let clips = context.timelineState.timeline.tracks[0].clips
        #expect(clips.count == 2)
        #expect(clips[1].timelineRange == TimeRange(start: 5, end: 9))
    }

    @MainActor
    @Test("MoveClip shifts forward when the requested slot is occupied")
    func moveClipAvoidsOverlap() throws {
        let moving = makeClip(start: 0, end: 4, label: "Moving")
        let occupied = makeClip(start: 6, end: 9, label: "Occupied")
        let track = Track(name: "V1", type: .video, clips: [moving, occupied])
        let context = EditingContext(
            timelineState: TimelineState(timeline: Timeline(tracks: [track]))
        )

        var command = MoveClipCommand(clipID: moving.id, newStart: 5, targetTrackID: track.id)
        try command.execute(context: context)

        let clips = context.timelineState.timeline.tracks[0].clips
        #expect(clips.map { $0.id } == [occupied.id, moving.id])
        #expect(clips[1].timelineRange == TimeRange(start: 9, end: 13))

        try command.undo(context: context)
        let restored = context.timelineState.timeline.tracks[0].clips
        #expect(restored.map { $0.id } == [moving.id, occupied.id])
        #expect(restored[0].timelineRange == TimeRange(start: 0, end: 4))
    }

    @MainActor
    @Test("DuplicateClip shifts forward past occupied space")
    func duplicateClipAvoidsOverlap() throws {
        let original = makeClip(start: 0, end: 4, label: "Original")
        let following = makeClip(start: 4, end: 8, label: "Following")
        let track = Track(name: "V1", type: .video, clips: [original, following])
        let context = EditingContext(
            timelineState: TimelineState(timeline: Timeline(tracks: [track]))
        )

        var command = DuplicateClipCommand(clipID: original.id)
        try command.execute(context: context)

        let clips = context.timelineState.timeline.tracks[0].clips
        #expect(clips.count == 3)
        #expect(clips[2].timelineRange == TimeRange(start: 8, end: 12))
    }

    @MainActor
    @Test("TrimClip tail extension clamps to the next clip boundary")
    func trimClipClampsToNextClip() throws {
        let leading = Clip(
            assetID: UUID(),
            timelineRange: TimeRange(start: 0, end: 5),
            sourceRange: TimeRange(start: 0, end: 5)
        )
        let following = makeClip(start: 6, end: 10, label: "Following")
        let track = Track(name: "V1", type: .video, clips: [leading, following])
        let context = EditingContext(
            timelineState: TimelineState(timeline: Timeline(tracks: [track]))
        )

        var command = TrimClipCommand(clipID: leading.id, newSourceRange: TimeRange(start: 0, end: 8))
        try command.execute(context: context)

        let trimmed = context.timelineState.timeline.tracks[0].clips[0]
        #expect(trimmed.timelineRange == TimeRange(start: 0, end: 6))
        #expect(trimmed.sourceRange == TimeRange(start: 0, end: 6))
    }

    @MainActor
    @Test("TrimClip head extension clamps to the previous clip boundary")
    func trimClipClampsToPreviousClip() throws {
        let previous = makeClip(start: 0, end: 4, label: "Previous")
        let target = Clip(
            assetID: UUID(),
            timelineRange: TimeRange(start: 5, end: 10),
            sourceRange: TimeRange(start: 2, end: 7)
        )
        let track = Track(name: "V1", type: .video, clips: [previous, target])
        let context = EditingContext(
            timelineState: TimelineState(timeline: Timeline(tracks: [track]))
        )

        var command = TrimClipCommand(clipID: target.id, newSourceRange: TimeRange(start: 0, end: 7))
        try command.execute(context: context)

        let trimmed = context.timelineState.timeline.tracks[0].clips[1]
        #expect(trimmed.timelineRange == TimeRange(start: 4, end: 10))
        #expect(trimmed.sourceRange == TimeRange(start: 1, end: 7))
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
