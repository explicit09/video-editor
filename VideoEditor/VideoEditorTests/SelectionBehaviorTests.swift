import Foundation
import Testing
@testable import EditorCore
@testable import VideoEditor

@Suite("Selection Behavior Tests")
struct SelectionBehaviorTests {
    @MainActor
    @Test("normal clip selection keeps focus on the clicked clip even when clips are linked")
    func singleSelectionDoesNotPromoteToLinkedGroup() {
        let appState = AppState()
        let fixture = LinkedClipFixture.make()
        appState.context.timelineState.timeline = fixture.timeline

        appState.toggleClipSelection(fixture.videoClip.id, extend: false)

        #expect(appState.timelineViewState.selectedClipIDs == [fixture.videoClip.id])
        #expect(appState.timelineViewState.selectedTrackID == fixture.videoTrack.id)
    }

    @MainActor
    @Test("extend selection can still select a linked clip group explicitly")
    func extendSelectionAddsLinkedGroup() {
        let appState = AppState()
        let fixture = LinkedClipFixture.make()
        appState.context.timelineState.timeline = fixture.timeline

        appState.toggleClipSelection(fixture.videoClip.id, extend: true)

        #expect(appState.timelineViewState.selectedClipIDs == [fixture.videoClip.id, fixture.audioClip.id])
        #expect(appState.timelineViewState.selectedTrackID == fixture.videoTrack.id)
    }

    @Test("single clip selection resolves inspector context to clip instead of batch")
    func inspectorContextUsesSingleClipPosture() {
        let clipID = UUID()
        let context = SelectionInspectorContext.resolve(
            selectedClipIDs: [clipID],
            selectedTrackID: UUID()
        )

        #expect(context == .clip(clipID))
    }
}

private struct LinkedClipFixture {
    let timeline: Timeline
    let videoTrack: Track
    let audioTrack: Track
    let videoClip: Clip
    let audioClip: Clip

    static func make() -> Self {
        let assetID = UUID()
        let groupID = UUID()
        let videoClip = Clip(
            assetID: assetID,
            timelineRange: TimeRange(start: 0, end: 5),
            sourceRange: TimeRange(start: 0, end: 5),
            linkGroupID: groupID
        )
        let audioClip = Clip(
            assetID: assetID,
            timelineRange: TimeRange(start: 0, end: 5),
            sourceRange: TimeRange(start: 0, end: 5),
            linkGroupID: groupID
        )
        let videoTrack = Track(name: "Video", type: .video, clips: [videoClip])
        let audioTrack = Track(name: "Audio", type: .audio, clips: [audioClip])

        return Self(
            timeline: Timeline(tracks: [videoTrack, audioTrack]),
            videoTrack: videoTrack,
            audioTrack: audioTrack,
            videoClip: videoClip,
            audioClip: audioClip
        )
    }
}
