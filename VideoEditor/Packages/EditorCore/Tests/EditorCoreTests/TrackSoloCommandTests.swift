import Foundation
import Testing
@testable import EditorCore

@Suite("Track Solo Command Tests")
struct TrackSoloCommandTests {

    @MainActor
    @Test("SoloTrack toggles solo state and undo restores it")
    func soloTrackTogglesAndUndoRestores() throws {
        let track = Track(name: "V1", type: .video)
        let context = EditingContext(
            timelineState: TimelineState(timeline: Timeline(tracks: [track]))
        )

        var soloOn = SoloTrackCommand(trackID: track.id, soloed: true)
        try soloOn.execute(context: context)

        #expect(context.timelineState.timeline.tracks[0].isSoloed)

        var soloOff = SoloTrackCommand(trackID: track.id, soloed: false)
        try soloOff.execute(context: context)

        #expect(!context.timelineState.timeline.tracks[0].isSoloed)

        try soloOff.undo(context: context)

        #expect(context.timelineState.timeline.tracks[0].isSoloed)
    }
}
