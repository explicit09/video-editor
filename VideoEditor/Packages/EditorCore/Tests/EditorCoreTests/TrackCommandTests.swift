import Testing
import Foundation
@testable import EditorCore

@Suite("Track Command Tests")
struct TrackCommandTests {

    @MainActor
    @Test("AddTrack inserts at the requested index and undo removes the same track")
    func addTrackInsertsAtRequestedIndex() throws {
        let first = Track(name: "V1", type: .video)
        let second = Track(name: "A1", type: .audio)
        let inserted = Track(name: "V2", type: .video)

        let context = EditingContext(
            timelineState: TimelineState(
                timeline: Timeline(tracks: [first, second])
            )
        )

        var command = AddTrackCommand(track: inserted, insertionIndex: 1)
        try command.execute(context: context)

        #expect(context.timelineState.timeline.tracks.map(\.id) == [first.id, inserted.id, second.id])

        try command.undo(context: context)
        #expect(context.timelineState.timeline.tracks.map(\.id) == [first.id, second.id])
    }

    @MainActor
    @Test("AddTrack command redoes into the same insertion index through history")
    func addTrackRedoPreservesRequestedIndex() throws {
        let first = Track(name: "V1", type: .video)
        let second = Track(name: "A1", type: .audio)
        let inserted = Track(name: "A2", type: .audio)

        let context = EditingContext(
            timelineState: TimelineState(
                timeline: Timeline(tracks: [first, second])
            )
        )
        let history = CommandHistory()

        var command = AddTrackCommand(track: inserted, insertionIndex: 1)
        try history.execute(&command, context: context)
        #expect(context.timelineState.timeline.tracks.map(\.id) == [first.id, inserted.id, second.id])

        try history.undo(context: context)
        #expect(context.timelineState.timeline.tracks.map(\.id) == [first.id, second.id])

        try history.redo(context: context)
        #expect(context.timelineState.timeline.tracks.map(\.id) == [first.id, inserted.id, second.id])
    }

    @MainActor
    @Test("ReorderTrack moves a track and undo restores the original order")
    func reorderTrackMovesAndUndoes() throws {
        let first = Track(name: "V1", type: .video)
        let second = Track(name: "A1", type: .audio)
        let third = Track(name: "V2", type: .video)

        let context = EditingContext(
            timelineState: TimelineState(
                timeline: Timeline(tracks: [first, second, third])
            )
        )

        var command = ReorderTrackCommand(trackID: first.id, newIndex: 2)
        try command.execute(context: context)
        #expect(context.timelineState.timeline.tracks.map(\.id) == [second.id, third.id, first.id])

        try command.undo(context: context)
        #expect(context.timelineState.timeline.tracks.map(\.id) == [first.id, second.id, third.id])
    }
}
