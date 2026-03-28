import Testing
import Foundation
@testable import EditorCore

@Suite("Snap Utils Tests")
struct SnapUtilsTests {

    @Test("Snap finds the nearest point within threshold")
    func snapFindsNearestPoint() {
        let snapped = SnapUtils.snap(time: 5.08, to: [0, 5, 5.1, 10], threshold: 0.15)
        #expect(snapped == 5.1)
    }

    @Test("Snap returns nil when all points are outside the threshold")
    func snapReturnsNilOutsideThreshold() {
        let snapped = SnapUtils.snap(time: 5.3, to: [0, 5, 10], threshold: 0.1)
        #expect(snapped == nil)
    }

    @Test("snapPoints returns sorted unique points and respects excluded clip IDs")
    func snapPointsAreSortedUniqueAndExcludeClips() {
        let includedClip = Clip(
            assetID: UUID(),
            timelineRange: TimeRange(start: 0, end: 5),
            sourceRange: TimeRange(start: 0, end: 5)
        )
        let excludedClip = Clip(
            assetID: UUID(),
            timelineRange: TimeRange(start: 8, end: 12),
            sourceRange: TimeRange(start: 0, end: 4)
        )
        let timeline = Timeline(
            tracks: [Track(name: "V1", type: .video, clips: [includedClip, excludedClip])],
            markers: [Marker(time: 5, label: "Cut"), Marker(time: 15, label: "Outro")]
        )

        let points = SnapUtils.snapPoints(
            from: timeline,
            playhead: 5,
            excludeClipIDs: [excludedClip.id]
        )

        #expect(points == [0, 5, 15])
    }
}
