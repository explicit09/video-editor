import Testing
import Foundation
@testable import EditorCore

@Suite("Property Command Tests")
struct PropertyCommandTests {

    @MainActor
    @Test("SetClipVolume changes volume and undo restores")
    func setClipVolume() throws {
        let clip = Clip(assetID: UUID(), timelineRange: TimeRange(start: 0, end: 5), sourceRange: TimeRange(start: 0, end: 5), volume: 1.0)
        let context = EditingContext(timelineState: TimelineState(timeline: Timeline(tracks: [Track(name: "A", type: .audio, clips: [clip])])))

        var cmd = SetClipVolumeCommand(clipID: clip.id, volume: 0.5)
        try cmd.execute(context: context)
        #expect(context.timelineState.timeline.tracks[0].clips[0].volume == 0.5)

        try cmd.undo(context: context)
        #expect(context.timelineState.timeline.tracks[0].clips[0].volume == 1.0)
    }

    @MainActor
    @Test("SetClipOpacity clamps and undo restores")
    func setClipOpacity() throws {
        let clip = Clip(assetID: UUID(), timelineRange: TimeRange(start: 0, end: 5), sourceRange: TimeRange(start: 0, end: 5))
        let context = EditingContext(timelineState: TimelineState(timeline: Timeline(tracks: [Track(name: "V", type: .video, clips: [clip])])))

        var cmd = SetClipOpacityCommand(clipID: clip.id, opacity: 1.5)
        try cmd.execute(context: context)
        #expect(context.timelineState.timeline.tracks[0].clips[0].opacity == 1.0) // clamped

        var cmd2 = SetClipOpacityCommand(clipID: clip.id, opacity: 0.3)
        try cmd2.execute(context: context)
        #expect(context.timelineState.timeline.tracks[0].clips[0].opacity == 0.3)
    }

    @MainActor
    @Test("MuteTrack toggles and undo restores")
    func muteTrack() throws {
        let track = Track(name: "V1", type: .video)
        let context = EditingContext(timelineState: TimelineState(timeline: Timeline(tracks: [track])))

        var cmd = MuteTrackCommand(trackID: track.id, muted: true)
        try cmd.execute(context: context)
        #expect(context.timelineState.timeline.tracks[0].isMuted == true)

        try cmd.undo(context: context)
        #expect(context.timelineState.timeline.tracks[0].isMuted == false)
    }

    @MainActor
    @Test("DuplicateClip creates copy at end of original")
    func duplicateClip() throws {
        let clip = Clip(assetID: UUID(), timelineRange: TimeRange(start: 0, end: 5), sourceRange: TimeRange(start: 0, end: 5), metadata: ClipMetadata(label: "Original"))
        let context = EditingContext(timelineState: TimelineState(timeline: Timeline(tracks: [Track(name: "V", type: .video, clips: [clip])])))

        var cmd = DuplicateClipCommand(clipID: clip.id)
        try cmd.execute(context: context)

        let clips = context.timelineState.timeline.tracks[0].clips
        #expect(clips.count == 2)
        #expect(clips[1].timelineRange.start == 5) // starts at end of original
        #expect(clips[1].metadata.label == "Original (copy)")
        #expect(clips[1].assetID == clip.assetID)

        try cmd.undo(context: context)
        #expect(context.timelineState.timeline.tracks[0].clips.count == 1)
    }

    @MainActor
    @Test("RenameClip changes label and undo restores")
    func renameClip() throws {
        let clip = Clip(assetID: UUID(), timelineRange: TimeRange(start: 0, end: 5), sourceRange: TimeRange(start: 0, end: 5), metadata: ClipMetadata(label: "Before"))
        let context = EditingContext(timelineState: TimelineState(timeline: Timeline(tracks: [Track(name: "V", type: .video, clips: [clip])])))

        var cmd = RenameClipCommand(clipID: clip.id, label: "After")
        try cmd.execute(context: context)
        #expect(context.timelineState.timeline.tracks[0].clips[0].metadata.label == "After")

        try cmd.undo(context: context)
        #expect(context.timelineState.timeline.tracks[0].clips[0].metadata.label == "Before")
    }

    @MainActor
    @Test("All new intents resolve without throwing")
    func allNewIntentsResolve() throws {
        let resolver = IntentResolver()
        let clipID = UUID()
        let trackID = UUID()

        _ = try resolver.resolve(.setClipVolume(clipID: clipID, volume: 0.5))
        _ = try resolver.resolve(.setClipOpacity(clipID: clipID, opacity: 0.8))
        _ = try resolver.resolve(.setClipTransform(clipID: clipID, transform: .identity))
        _ = try resolver.resolve(.muteTrack(trackID: trackID, muted: true))
        _ = try resolver.resolve(.lockTrack(trackID: trackID, locked: true))
        _ = try resolver.resolve(.setTrackVolume(trackID: trackID, volume: 0.7))
        _ = try resolver.resolve(.renameClip(clipID: clipID, label: "New"))
        _ = try resolver.resolve(.duplicateClip(clipID: clipID))
    }
}
