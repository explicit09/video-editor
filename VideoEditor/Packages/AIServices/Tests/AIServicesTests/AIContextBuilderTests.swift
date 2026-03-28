import Testing
import Foundation
@testable import AIServices
@testable import EditorCore

@Suite("AI Context Builder Tests")
struct AIContextBuilderTests {

    @MainActor
    @Test("Minimal context omits expensive asset, clip, and action payloads")
    func minimalContextOmitsDetailedPayloads() {
        let clip = makeClip()
        let track = Track(name: "V1", type: .video, clips: [clip])
        let asset = makeAsset(id: clip.assetID)
        let builder = AIContextBuilder()

        let context = builder.buildContext(
            timeline: Timeline(tracks: [track]),
            assets: [asset],
            playheadPosition: 12,
            selectedClipIDs: [clip.id],
            recentActions: [ActionEvent(commandName: "Insert Clip", source: .user)],
            level: .minimal
        )

        #expect(context.timeline.trackCount == 1)
        #expect(context.timeline.markerCount == 0)
        #expect(context.timeline.tracks[0].clipCount == 1)
        #expect(context.timeline.tracks[0].clips == nil)
        #expect(context.assets == nil)
        #expect(context.recentActions == nil)
        #expect(context.selectedClipIDs == [clip.id.uuidString])
    }

    @MainActor
    @Test("Full context includes clip transcript, asset analysis flags, and recent actions")
    func fullContextIncludesDetailedPayloads() {
        let clip = makeClip()
        let track = Track(name: "Dialogue", type: .video, clips: [clip])
        let asset = makeAsset(id: clip.assetID)
        let action = ActionEvent(
            commandName: "Split Clip",
            clipIDs: [clip.id],
            trackIDs: [track.id],
            parameters: ["splitAt": "4.0"],
            source: .ai
        )
        let builder = AIContextBuilder()

        let context = builder.buildContext(
            timeline: Timeline(tracks: [track], markers: [Marker(time: 8, label: "Question")]),
            assets: [asset],
            playheadPosition: 4,
            selectedClipIDs: [clip.id],
            recentActions: [action],
            level: .full
        )

        #expect(context.assets?.count == 1)
        #expect(context.assets?[0].name == "Interview.mov")
        #expect(context.assets?[0].hasTranscript == true)
        #expect(context.assets?[0].silenceRangeCount == 1)
        #expect(context.assets?[0].shotBoundaryCount == 1)

        #expect(context.timeline.tracks[0].clips?.count == 1)
        #expect(context.timeline.tracks[0].clips?[0].assetName == "Interview.mov")
        #expect(context.timeline.tracks[0].clips?[0].transcript == "Hello there")
        #expect(context.timeline.tracks[0].clips?[0].isSelected == true)
        #expect(context.timeline.tracks[0].clips?[0].effectCount == 1)

        #expect(context.recentActions?.count == 1)
        #expect(context.recentActions?[0].commandName == "Split Clip")
        #expect(context.recentActions?[0].source == "ai")
        #expect(context.recentActions?[0].parameters["splitAt"] == "4.0")
        #expect(context.toJSON().contains("\"Interview.mov\""))
    }

    private func makeClip() -> Clip {
        Clip(
            assetID: UUID(),
            timelineRange: TimeRange(start: 3, end: 9),
            sourceRange: TimeRange(start: 12, end: 18),
            effects: [EffectInstance(type: "Blur")],
            metadata: ClipMetadata(
                label: "Greeting",
                tags: ["interview", "intro"],
                transcriptSegment: TranscriptSegment(text: "Hello there"),
                sceneType: "close-up"
            )
        )
    }

    private func makeAsset(id: UUID) -> MediaAsset {
        MediaAsset(
            id: id,
            name: "Interview.mov",
            sourceURL: URL(fileURLWithPath: "/tmp/interview.mov"),
            type: .video,
            duration: 42,
            analysis: MediaAnalysis(
                transcript: [TranscriptWord(word: "Hello", lemma: "hello", start: 0, end: 0.5)],
                shotBoundaries: [8],
                silenceRanges: [TimeRange(start: 2, end: 2.5)]
            )
        )
    }
}
