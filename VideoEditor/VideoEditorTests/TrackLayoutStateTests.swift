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
        #expect(layoutState.compactTrackHeight == 56)
        #expect(layoutState.expandedTrackHeight == 84)
        #expect(layoutState.detailTrackHeight == 120)
        #expect(layoutState.height(for: Track(name: "V1", type: .video)) == 84)

        layoutState.toggleCollapse(trackID)

        #expect(layoutState.height(for: Track(id: trackID, name: "V1", type: .video)) == 28)
    }

    @MainActor
    @Test("cycling row height rotates through detailed and compact modes without collapsing the track")
    func cycleHeightUsesDedicatedRowModes() {
        let layoutState = TrackLayoutState()
        let trackID = UUID()

        #expect(layoutState.isCollapsed(trackID) == false)
        #expect(layoutState.rowHeightMode(for: trackID) == .standard)
        #expect(layoutState.height(for: trackID) == 84)

        layoutState.cycleHeight(for: trackID)
        #expect(layoutState.isCollapsed(trackID) == false)
        #expect(layoutState.rowHeightMode(for: trackID) == .expanded)
        #expect(layoutState.height(for: trackID) == 120)

        layoutState.cycleHeight(for: trackID)
        #expect(layoutState.isCollapsed(trackID) == false)
        #expect(layoutState.rowHeightMode(for: trackID) == .compact)
        #expect(layoutState.height(for: trackID) == 56)

        layoutState.cycleHeight(for: trackID)
        #expect(layoutState.rowHeightMode(for: trackID) == .standard)
        #expect(layoutState.height(for: trackID) == 84)
    }
}
