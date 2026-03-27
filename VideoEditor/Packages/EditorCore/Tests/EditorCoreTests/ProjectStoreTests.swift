import Testing
import Foundation
@testable import EditorCore

@Suite("Command Pipeline Tests")
struct CommandPipelineTests {

    @MainActor
    @Test("AddTrack via intent creates a track")
    func addTrackViaIntent() throws {
        let context = EditingContext()
        let resolver = IntentResolver()
        var cmd = try resolver.resolve(.addTrack(track: Track(name: "V1", type: .video)))
        try cmd.execute(context: context)

        #expect(context.timelineState.timeline.tracks.count == 1)
        #expect(context.timelineState.timeline.tracks[0].name == "V1")
    }

    @MainActor
    @Test("InsertClip via intent adds clip to track")
    func insertClipViaIntent() throws {
        let context = EditingContext()
        let track = Track(name: "V1", type: .video)
        let clip = Clip(
            assetID: UUID(),
            timelineRange: TimeRange(start: 0, end: 5),
            sourceRange: TimeRange(start: 0, end: 5),
            metadata: ClipMetadata(label: "Test")
        )

        // Add track first
        var addCmd = try IntentResolver().resolve(.addTrack(track: track))
        try addCmd.execute(context: context)

        // Insert clip
        var insertCmd = try IntentResolver().resolve(.insertClip(clip: clip, trackID: track.id))
        try insertCmd.execute(context: context)

        #expect(context.timelineState.timeline.tracks[0].clips.count == 1)
        #expect(context.timelineState.timeline.tracks[0].clips[0].metadata.label == "Test")
    }

    @MainActor
    @Test("Undo reverses AddTrack")
    func undoAddTrack() throws {
        let context = EditingContext()
        let history = CommandHistory()
        var cmd = AddTrackCommand(track: Track(name: "V1", type: .video))
        try history.execute(&cmd, context: context)

        #expect(context.timelineState.timeline.tracks.count == 1)

        try history.undo(context: context)
        #expect(context.timelineState.timeline.tracks.isEmpty)

        try history.redo(context: context)
        #expect(context.timelineState.timeline.tracks.count == 1)
    }

    @MainActor
    @Test("Undo reverses InsertClip")
    func undoInsertClip() throws {
        let context = EditingContext()
        let history = CommandHistory()
        let track = Track(name: "V1", type: .video)

        var addCmd = AddTrackCommand(track: track)
        try history.execute(&addCmd, context: context)

        let clip = Clip(
            assetID: UUID(),
            timelineRange: TimeRange(start: 0, end: 3),
            sourceRange: TimeRange(start: 0, end: 3)
        )
        var insertCmd = InsertClipCommand(clip: clip, trackID: track.id)
        try history.execute(&insertCmd, context: context)

        #expect(context.timelineState.timeline.tracks[0].clips.count == 1)

        try history.undo(context: context)
        #expect(context.timelineState.timeline.tracks[0].clips.isEmpty)
    }

    @MainActor
    @Test("MoveClip changes timeline range")
    func moveClip() throws {
        let context = EditingContext()
        let track = Track(name: "V1", type: .video)
        context.timelineState.timeline.tracks.append(track)

        let clip = Clip(
            assetID: UUID(),
            timelineRange: TimeRange(start: 0, end: 5),
            sourceRange: TimeRange(start: 0, end: 5)
        )
        context.timelineState.timeline.tracks[0].clips.append(clip)

        var cmd = MoveClipCommand(clipID: clip.id, newStart: 10, targetTrackID: track.id)
        try cmd.execute(context: context)

        let moved = context.timelineState.timeline.tracks[0].clips[0]
        #expect(moved.timelineRange.start == 10)
        #expect(moved.timelineRange.duration == 5)

        try cmd.undo(context: context)
        let restored = context.timelineState.timeline.tracks[0].clips[0]
        #expect(restored.timelineRange.start == 0)
    }

    @MainActor
    @Test("SplitClip creates two clips")
    func splitClip() throws {
        let context = EditingContext()
        let track = Track(name: "V1", type: .video)
        context.timelineState.timeline.tracks.append(track)

        let clip = Clip(
            assetID: UUID(),
            timelineRange: TimeRange(start: 0, end: 10),
            sourceRange: TimeRange(start: 0, end: 10)
        )
        context.timelineState.timeline.tracks[0].clips.append(clip)

        var cmd = SplitClipCommand(clipID: clip.id, at: 4)
        try cmd.execute(context: context)

        let clips = context.timelineState.timeline.tracks[0].clips
        #expect(clips.count == 2)
        #expect(clips[0].timelineRange.end == 4)
        #expect(clips[1].timelineRange.start == 4)
        #expect(clips[1].timelineRange.end == 10)

        try cmd.undo(context: context)
        #expect(context.timelineState.timeline.tracks[0].clips.count == 1)
        #expect(context.timelineState.timeline.tracks[0].clips[0].timelineRange.end == 10)
    }

    @MainActor
    @Test("DeleteClips removes and undoes correctly")
    func deleteClips() throws {
        let context = EditingContext()
        let track = Track(name: "V1", type: .video)
        context.timelineState.timeline.tracks.append(track)

        let clip1 = Clip(assetID: UUID(), timelineRange: TimeRange(start: 0, end: 3), sourceRange: TimeRange(start: 0, end: 3))
        let clip2 = Clip(assetID: UUID(), timelineRange: TimeRange(start: 3, end: 6), sourceRange: TimeRange(start: 0, end: 3))
        context.timelineState.timeline.tracks[0].clips = [clip1, clip2]

        var cmd = DeleteClipsCommand(clipIDs: [clip1.id])
        try cmd.execute(context: context)
        #expect(context.timelineState.timeline.tracks[0].clips.count == 1)

        try cmd.undo(context: context)
        #expect(context.timelineState.timeline.tracks[0].clips.count == 2)
    }

    @MainActor
    @Test("All intents resolve without throwing")
    func allIntentsResolve() throws {
        let resolver = IntentResolver()
        let trackID = UUID()
        let clipID = UUID()

        let intents: [EditorIntent] = [
            .addTrack(track: Track(type: .video)),
            .removeTrack(trackID: trackID),
            .insertClip(clip: Clip(assetID: UUID(), timelineRange: TimeRange(start: 0, end: 1), sourceRange: TimeRange(start: 0, end: 1)), trackID: trackID),
            .deleteClips(clipIDs: [clipID]),
            .moveClip(clipID: clipID, newStart: 5, trackID: trackID),
            .trimClip(clipID: clipID, newSourceRange: TimeRange(start: 0, end: 3)),
            .splitClip(clipID: clipID, at: 2),
            .setMarker(at: 5, label: "Mark"),
            .deleteMarker(markerID: UUID()),
        ]

        for intent in intents {
            let _ = try resolver.resolve(intent)
        }
    }
}
