import Foundation
import Testing
@testable import EditorCore
@testable import VideoEditor

@Suite("Track Layout State Tests")
struct TrackLayoutStateTests {

    @MainActor
    @Test("track layout state exposes compact and expanded row heights")
    func compactAndExpandedHeights() {
        let layoutState = TrackLayoutState()
        let trackID = UUID()

        #expect(layoutState.collapsedTrackHeight == 28)
        #expect(layoutState.expandedTrackHeight == 84)
        #expect(layoutState.height(for: Track(name: "V1", type: .video)) == 84)

        layoutState.toggleCollapse(trackID)

        #expect(layoutState.height(for: Track(id: trackID, name: "V1", type: .video)) == 28)
    }
}
