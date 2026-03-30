import Testing
import Foundation
@testable import EditorCore

@Suite("Timeline Editing Support Tests")
struct TimelineEditingSupportTests {

    @Test("Selection normalizer removes stale clips and track anchors")
    func selectionNormalizerRemovesStaleState() {
        let keptClip = Clip(
            assetID: UUID(),
            timelineRange: TimeRange(start: 0, duration: 2),
            sourceRange: TimeRange(start: 0, duration: 2)
        )
        let track = Track(name: "V1", type: .video, clips: [keptClip])
        let timeline = Timeline(tracks: [track])

        let normalized = TimelineSelectionNormalizer.normalize(
            selection: TimelineSelectionSnapshot(
                selectedClipIDs: [keptClip.id, UUID()],
                selectedTrackID: UUID(),
                lastSelectedClipID: UUID()
            ),
            in: timeline
        )

        #expect(normalized.selectedClipIDs == [keptClip.id])
        #expect(normalized.selectedTrackID == track.id)
        #expect(normalized.lastSelectedClipID == keptClip.id)
    }

    @Test("Selection normalizer clears last selected clip when selection is empty")
    func selectionNormalizerClearsAnchorWithoutSelection() {
        let timeline = Timeline(tracks: [Track(name: "A1", type: .audio)])

        let normalized = TimelineSelectionNormalizer.normalize(
            selection: TimelineSelectionSnapshot(
                selectedClipIDs: [UUID()],
                selectedTrackID: timeline.tracks[0].id,
                lastSelectedClipID: UUID()
            ),
            in: timeline
        )

        #expect(normalized.selectedClipIDs.isEmpty)
        #expect(normalized.selectedTrackID == timeline.tracks[0].id)
        #expect(normalized.lastSelectedClipID == nil)
    }

    @Test("Drop resolver prefers same-type unlocked destination lane")
    func dropResolverPrefersMatchingUnlockedLane() {
        let video1 = TimelineTrackLayoutEntry(id: UUID(), type: .video, isLocked: false, height: 76)
        let audio = TimelineTrackLayoutEntry(id: UUID(), type: .audio, isLocked: false, height: 76)
        let video2 = TimelineTrackLayoutEntry(id: UUID(), type: .video, isLocked: false, height: 28)

        let target = TimelineDropResolver.targetTrackID(
            currentIndex: 0,
            verticalOffset: 170,
            movingTrackType: .video,
            tracks: [video1, audio, video2],
            clipGap: 6
        )

        #expect(target == video2.id)
    }

    @Test("Drop resolver rejects locked matching lane and falls back")
    func dropResolverRejectsLockedMatchingLane() {
        let video1 = TimelineTrackLayoutEntry(id: UUID(), type: .video, isLocked: false, height: 76)
        let lockedVideo2 = TimelineTrackLayoutEntry(id: UUID(), type: .video, isLocked: true, height: 76)

        let target = TimelineDropResolver.targetTrackID(
            currentIndex: 0,
            verticalOffset: 120,
            movingTrackType: .video,
            tracks: [video1, lockedVideo2],
            clipGap: 6
        )

        #expect(target == video1.id)
    }

    @Test("Trim resolver clamps clip to next neighbor")
    func trimResolverClampsToNextNeighbor() {
        let clip = Clip(
            assetID: UUID(),
            timelineRange: TimeRange(start: 0, duration: 4),
            sourceRange: TimeRange(start: 0, duration: 4)
        )
        let nextClip = Clip(
            assetID: UUID(),
            timelineRange: TimeRange(start: 5, duration: 2),
            sourceRange: TimeRange(start: 0, duration: 2)
        )

        let proposal = ClipTrimResolver.proposal(
            for: clip,
            proposedSourceRange: TimeRange(start: 0, duration: 8),
            in: [clip, nextClip]
        )

        #expect(proposal.timelineRange.start == 0)
        #expect(proposal.timelineRange.end == 5)
        #expect(proposal.sourceRange.duration == 5)
    }

    @Test("Linked sibling trim preserves relative source deltas")
    func linkedSiblingTrimAppliesDeltas() {
        let siblingRange = ClipTrimResolver.linkedSiblingSourceRange(
            primaryOriginalSourceRange: TimeRange(start: 10, end: 20),
            primaryProposedSourceRange: TimeRange(start: 12, end: 18),
            siblingSourceRange: TimeRange(start: 30, end: 40)
        )

        #expect(siblingRange.start == 32)
        #expect(siblingRange.end == 38)
    }
}
