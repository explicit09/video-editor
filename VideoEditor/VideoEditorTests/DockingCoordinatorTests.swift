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
}
