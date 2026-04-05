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

enum DockDropGeometry {
    static let tabStripHeight: CGFloat = CinematicMetrics.panelHeaderHeight
    static let edgeInsetRatio: CGFloat = 0.18

    static func edgeInset(for frame: CGRect) -> CGFloat {
        min(frame.width, frame.height) * edgeInsetRatio
    }

    static func tabStripFrame(in frame: CGRect) -> CGRect {
        CGRect(
            x: frame.minX,
            y: frame.minY,
            width: frame.width,
            height: min(frame.height, tabStripHeight)
        )
    }
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
        guard frame.contains(point) else { return nil }

        let edgeInset = DockDropGeometry.edgeInset(for: frame)
        let isInTabStrip = DockDropGeometry.tabStripFrame(in: frame).contains(point)

        if allowedBehavior == .tabs {
            return isInTabStrip ? .tabStack : nil
        }

        if point.x <= frame.minX + edgeInset { return .splitLeading }
        if point.x >= frame.maxX - edgeInset { return .splitTrailing }
        if point.y <= frame.minY + edgeInset { return .splitTop }
        if point.y >= frame.maxY - edgeInset { return .splitBottom }
        return .tabStack
    }
}
