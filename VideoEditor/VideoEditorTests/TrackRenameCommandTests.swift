import Foundation
import Testing
@testable import EditorCore

@Suite("Track Rename Command Tests")
struct TrackRenameCommandTests {

    @MainActor
    @Test("RenameTrack updates the track name and undo restores it")
    func renameTrackTogglesAndUndoRestores() throws {
        let track = Track(name: "V1", type: .video)
        let context = EditingContext(
            timelineState: TimelineState(timeline: Timeline(tracks: [track]))
        )

        var rename = RenameTrackCommand(trackID: track.id, name: "Main Cam")
        try rename.execute(context: context)

        #expect(context.timelineState.timeline.tracks[0].name == "Main Cam")

        try rename.undo(context: context)

        #expect(context.timelineState.timeline.tracks[0].name == "V1")
    }
}
