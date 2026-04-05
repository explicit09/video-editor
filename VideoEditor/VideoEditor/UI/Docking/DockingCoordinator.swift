import CoreGraphics
import SwiftUI

enum DockDropBehavior: Equatable {
    case tabs
    case splitOrTabs
}

enum DockDropTarget: Equatable {
    case tabStack
    case splitLeading
    case splitTrailing
    case splitTop
    case splitBottom
}

@MainActor
final class DockingCoordinator: ObservableObject {
    @Published var activeDropTarget: DockDropTarget?
    @Published var draggedPanelID: PanelID?

    func beginDrag(panelID: PanelID) {
        draggedPanelID = panelID
    }

    func endDrag() {
        draggedPanelID = nil
        activeDropTarget = nil
    }

    func updateDropTarget(
        point: CGPoint,
        frame: CGRect,
        allowedBehavior: DockDropBehavior
    ) {
        activeDropTarget = resolveDropTarget(
            point: point,
            frame: frame,
            allowedBehavior: allowedBehavior
        )
    }

    func resolveDropTarget(
        point: CGPoint,
        frame: CGRect,
        allowedBehavior: DockDropBehavior
    ) -> DockDropTarget? {
        let edgeInset = min(frame.width, frame.height) * 0.18
        let tabStripHeight = min(frame.height, 36)
        let isInTabStrip = CGRect(
            x: frame.minX,
            y: frame.minY,
            width: frame.width,
            height: tabStripHeight
        ).contains(point)

        if allowedBehavior == .tabs {
            return isInTabStrip ? .tabStack : nil
        }

        if point.x <= frame.minX + edgeInset { return .splitLeading }
        if point.x >= frame.maxX - edgeInset { return .splitTrailing }
        if point.y <= frame.minY + edgeInset { return .splitTop }
        if point.y >= frame.maxY - edgeInset { return .splitBottom }
        return isInTabStrip ? .tabStack : nil
    }
}
