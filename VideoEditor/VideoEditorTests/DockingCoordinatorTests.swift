import Testing
import CoreGraphics
@testable import VideoEditor

@Suite("Docking Coordinator Tests")
@MainActor
struct DockingCoordinatorTests {
    @Test("drop target resolves tab insertion inside a tab strip")
    func tabInsertionTarget() {
        let coordinator = DockingCoordinator()
        let target = coordinator.resolveDropTarget(
            point: CGPoint(x: 120, y: 16),
            frame: CGRect(x: 0, y: 0, width: 240, height: 32),
            allowedBehavior: .tabs
        )

        #expect(target == .tabStack)
    }

    @Test("drop target resolves edge split when hovering near a panel edge")
    func edgeSplitTarget() {
        let coordinator = DockingCoordinator()
        let target = coordinator.resolveDropTarget(
            point: CGPoint(x: 8, y: 120),
            frame: CGRect(x: 0, y: 0, width: 320, height: 240),
            allowedBehavior: .splitOrTabs
        )

        #expect(target == .splitLeading)
    }

    @Test("drop target falls back to tab stack for interior split-or-tabs drops")
    func interiorTabFallbackTarget() {
        let coordinator = DockingCoordinator()
        let target = coordinator.resolveDropTarget(
            point: CGPoint(x: 160, y: 120),
            frame: CGRect(x: 0, y: 0, width: 320, height: 240),
            allowedBehavior: .splitOrTabs
        )

        #expect(target == .tabStack)
    }

    @Test("drop target rejects points outside the frame")
    func outOfBoundsTarget() {
        let coordinator = DockingCoordinator()
        let target = coordinator.resolveDropTarget(
            point: CGPoint(x: 321, y: 120),
            frame: CGRect(x: 0, y: 0, width: 320, height: 240),
            allowedBehavior: .splitOrTabs
        )

        #expect(target == nil)
    }

    @Test("small panes use the shared split extent instead of a fixed overlay floor")
    func smallPaneUsesSharedSplitExtent() {
        let frame = CGRect(x: 0, y: 0, width: 80, height: 80)
        let sharedExtent = DockDropGeometry.edgeExtent(for: frame)

        #expect(sharedExtent < 44)

        let coordinator = DockingCoordinator()
        let interiorTarget = coordinator.resolveDropTarget(
            point: CGPoint(x: 20, y: 40),
            frame: frame,
            allowedBehavior: .splitOrTabs
        )

        #expect(interiorTarget == .tabStack)
    }
}
