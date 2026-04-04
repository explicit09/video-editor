import Testing
import Foundation
@testable import EditorCore

@Suite("Track Lock Command Tests")
struct TrackLockCommandTests {

    @MainActor
    @Test("InsertClip rejects edits on locked tracks")
    func insertClipRejectsLockedTrack() {
        let track = Track(name: "A1", type: .audio, isLocked: true)
        let clip = makeClip(start: 0, end: 2, label: "Locked Insert")
        let context = EditingContext(
            timelineState: TimelineState(timeline: Timeline(tracks: [track]))
        )

        var command = InsertClipCommand(clip: clip, trackID: track.id)

        do {
            try command.execute(context: context)
            Issue.record("Expected insert into a locked track to fail")
        } catch CommandError.trackLocked(let lockedTrackID) {
            #expect(lockedTrackID == track.id)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(context.timelineState.timeline.tracks[0].clips.isEmpty)
    }

    @MainActor
    @Test("InsertClip preserves timeline ordering within a track")
    func insertClipPreservesTrackOrdering() throws {
        let earlyClip = makeClip(start: 2, end: 4, label: "Early")
        let lateClip = makeClip(start: 8, end: 10, label: "Late")
        let insertedClip = makeClip(start: 5, end: 7, label: "Inserted")
        let track = Track(name: "V1", type: .video, clips: [earlyClip, lateClip])
        let context = EditingContext(
            timelineState: TimelineState(timeline: Timeline(tracks: [track]))
        )

        var command = InsertClipCommand(clip: insertedClip, trackID: track.id)
        try command.execute(context: context)

        #expect(context.timelineState.timeline.tracks[0].clips.map { $0.id } == [earlyClip.id, insertedClip.id, lateClip.id])
    }

    @MainActor
    @Test("MoveClip rejects moves from a locked source track")
    func moveClipRejectsLockedSourceTrack() {
        let lockedClip = makeClip(start: 1, end: 3, label: "Locked Clip")
        let lockedTrack = Track(name: "V1", type: .video, clips: [lockedClip], isLocked: true)
        let openTrack = Track(name: "V2", type: .video)
        let context = EditingContext(
            timelineState: TimelineState(timeline: Timeline(tracks: [lockedTrack, openTrack]))
        )

        var command = MoveClipCommand(clipID: lockedClip.id, newStart: 5, targetTrackID: openTrack.id)

        do {
            try command.execute(context: context)
            Issue.record("Expected move from a locked source track to fail")
        } catch CommandError.trackLocked(let lockedTrackID) {
            #expect(lockedTrackID == lockedTrack.id)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(context.timelineState.timeline.tracks[0].clips.map { $0.id } == [lockedClip.id])
        #expect(context.timelineState.timeline.tracks[1].clips.isEmpty)
    }

    @MainActor
    @Test("MoveClip rejects moves onto a locked target track")
    func moveClipRejectsLockedTargetTrack() {
        let clip = makeClip(start: 1, end: 3, label: "Mover")
        let openTrack = Track(name: "V1", type: .video, clips: [clip])
        let lockedTrack = Track(name: "V2", type: .video, isLocked: true)
        let context = EditingContext(
            timelineState: TimelineState(timeline: Timeline(tracks: [openTrack, lockedTrack]))
        )

        var command = MoveClipCommand(clipID: clip.id, newStart: 5, targetTrackID: lockedTrack.id)

        do {
            try command.execute(context: context)
            Issue.record("Expected move onto a locked target track to fail")
        } catch CommandError.trackLocked(let lockedTrackID) {
            #expect(lockedTrackID == lockedTrack.id)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(context.timelineState.timeline.tracks[0].clips[0].timelineRange == TimeRange(start: 1, end: 3))
        #expect(context.timelineState.timeline.tracks[1].clips.isEmpty)
    }

    @MainActor
    @Test("DeleteClips rejects deletions that touch a locked track")
    func deleteClipsRejectsLockedTrackSelection() {
        let lockedClip = makeClip(start: 0, end: 2, label: "Locked")
        let openClip = makeClip(start: 2, end: 4, label: "Open")
        let lockedTrack = Track(name: "A1", type: .audio, clips: [lockedClip], isLocked: true)
        let openTrack = Track(name: "A2", type: .audio, clips: [openClip])
        let context = EditingContext(
            timelineState: TimelineState(timeline: Timeline(tracks: [lockedTrack, openTrack]))
        )

        var command = DeleteClipsCommand(clipIDs: [lockedClip.id, openClip.id])

        do {
            try command.execute(context: context)
            Issue.record("Expected deletion involving a locked track to fail")
        } catch CommandError.trackLocked(let lockedTrackID) {
            #expect(lockedTrackID == lockedTrack.id)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(context.timelineState.timeline.tracks[0].clips.map { $0.id } == [lockedClip.id])
        #expect(context.timelineState.timeline.tracks[1].clips.map { $0.id } == [openClip.id])
    }

    @MainActor
    @Test("Trim and property commands reject edits on locked tracks")
    func clipEditsRejectLockedTracks() {
        let clip = makeClip(start: 0, end: 8, label: "Locked")
        let track = Track(name: "V1", type: .video, clips: [clip], isLocked: true)
        let context = EditingContext(
            timelineState: TimelineState(timeline: Timeline(tracks: [track]))
        )

        var trim = TrimClipCommand(clipID: clip.id, newSourceRange: TimeRange(start: 1, end: 7))

        do {
            try trim.execute(context: context)
            Issue.record("Expected trim on a locked track to fail")
        } catch CommandError.trackLocked(let lockedTrackID) {
            #expect(lockedTrackID == track.id)
        } catch {
            Issue.record("Unexpected error during trim: \(error)")
        }

        var rename = RenameClipCommand(clipID: clip.id, label: "Renamed")

        do {
            try rename.execute(context: context)
            Issue.record("Expected rename on a locked track to fail")
        } catch CommandError.trackLocked(let lockedTrackID) {
            #expect(lockedTrackID == track.id)
        } catch {
            Issue.record("Unexpected error during rename: \(error)")
        }

        let storedClip = context.timelineState.timeline.tracks[0].clips[0]
        #expect(storedClip.timelineRange == TimeRange(start: 0, end: 8))
        #expect(storedClip.metadata.label == "Locked")
    }

    @MainActor
    @Test("RemoveTrack rejects removing a locked track")
    func removeTrackRejectsLockedTrack() {
        let track = Track(name: "Locked Lane", type: .audio, isLocked: true)
        let context = EditingContext(
            timelineState: TimelineState(timeline: Timeline(tracks: [track]))
        )

        var command = RemoveTrackCommand(trackID: track.id)

        do {
            try command.execute(context: context)
            Issue.record("Expected removing a locked track to fail")
        } catch CommandError.trackLocked(let lockedTrackID) {
            #expect(lockedTrackID == track.id)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(context.timelineState.timeline.tracks.map(\.id) == [track.id])
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
