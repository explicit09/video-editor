import SwiftUI
import UniformTypeIdentifiers

struct DockHostView: View {
    @Binding var layout: DockWorkspaceLayout
    let registry: PanelRegistry
    @StateObject private var coordinator = DockingCoordinator()

    var body: some View {
        DockNodeView(
            node: rootBinding,
            registry: registry,
            coordinator: coordinator,
            onDropPanel: applyDrop
        )
        .padding(UtilitySpacing.xxxs)
        .utilitySurface(.chrome, radius: UtilityRadius.md)
    }

    private var rootBinding: Binding<DockLayoutNode> {
        Binding(
            get: { layout.root },
            set: { newRoot in
                layout = DockWorkspaceLayout(
                    workspaceID: layout.workspaceID,
                    root: newRoot
                )
            }
        )
    }

    private func applyDrop(
        draggedPanelID: PanelID,
        targetPanelID: PanelID,
        target: DockDropTarget
    ) {
        layout = layout.applyingDrop(
            draggedPanelID: draggedPanelID,
            onto: targetPanelID,
            target: target
        )
    }
}

private struct DockNodeView: View {
    @Binding var node: DockLayoutNode
    let registry: PanelRegistry
    @ObservedObject var coordinator: DockingCoordinator
    let onDropPanel: (PanelID, PanelID, DockDropTarget) -> Void

    private let dividerThickness: CGFloat = 8

    var body: some View {
        switch node {
        case let .panel(panelID):
            DockLeafContainer(
                targetPanelID: panelID,
                allowedBehavior: registry.definition(for: panelID)?.allowedDropBehavior ?? .splitOrTabs,
                coordinator: coordinator,
                onDropPanel: onDropPanel
            ) {
                VStack(spacing: 0) {
                    DockPanelHeaderView(
                        definition: registry.definition(for: panelID),
                        panelID: panelID,
                        onBeginDrag: {
                            coordinator.beginDrag(panelID: panelID)
                        }
                    )

                    panelContent(for: panelID)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        case let .tabs(activePanelID, panelIDs):
            DockLeafContainer(
                targetPanelID: activePanelID,
                allowedBehavior: registry.definition(for: activePanelID)?.allowedDropBehavior ?? .splitOrTabs,
                coordinator: coordinator,
                onDropPanel: onDropPanel
            ) {
                VStack(spacing: 0) {
                    DockTabStripView(
                        panelIDs: panelIDs,
                        activePanelID: activePanelID,
                        onSelectPanel: { panelID in
                            node = .tabs(activePanelID: panelID, panelIDs: panelIDs)
                        },
                        onBeginDrag: { panelID in
                            coordinator.beginDrag(panelID: panelID)
                        }
                    )
                    panelContent(for: activePanelID)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        case let .split(axis, ratio, leading, trailing):
            GeometryReader { geometry in
                let availableExtent = max(
                    axis == .horizontal ? geometry.size.width : geometry.size.height,
                    dividerThickness + 1
                )
                let minimumExtent = min(240, max((availableExtent - dividerThickness) / 2, 120))
                let minimumRatio = min(max(minimumExtent / max(availableExtent - dividerThickness, 1), 0.15), 0.48)
                let clampedRatio = min(max(ratio, minimumRatio), 1 - minimumRatio)
                let leadingExtent = max(minimumExtent, (availableExtent - dividerThickness) * clampedRatio)
                let trailingExtent = max(minimumExtent, availableExtent - dividerThickness - leadingExtent)

                Group {
                    if axis == .horizontal {
                        HStack(spacing: 0) {
                            DockNodeView(
                                node: leadingBinding(
                                    axis: axis,
                                    ratio: clampedRatio,
                                    leading: leading,
                                    trailing: trailing
                                ),
                                registry: registry,
                                coordinator: coordinator,
                                onDropPanel: onDropPanel
                            )
                            .frame(width: leadingExtent)

                            divider(axis: axis, size: geometry.size)

                            DockNodeView(
                                node: trailingBinding(
                                    axis: axis,
                                    ratio: clampedRatio,
                                    leading: leading,
                                    trailing: trailing
                                ),
                                registry: registry,
                                coordinator: coordinator,
                                onDropPanel: onDropPanel
                            )
                            .frame(width: trailingExtent)
                        }
                    } else {
                        VStack(spacing: 0) {
                            DockNodeView(
                                node: leadingBinding(
                                    axis: axis,
                                    ratio: clampedRatio,
                                    leading: leading,
                                    trailing: trailing
                                ),
                                registry: registry,
                                coordinator: coordinator,
                                onDropPanel: onDropPanel
                            )
                            .frame(height: leadingExtent)

                            divider(axis: axis, size: geometry.size)

                            DockNodeView(
                                node: trailingBinding(
                                    axis: axis,
                                    ratio: clampedRatio,
                                    leading: leading,
                                    trailing: trailing
                                ),
                                registry: registry,
                                coordinator: coordinator,
                                onDropPanel: onDropPanel
                            )
                            .frame(height: trailingExtent)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func panelContent(for panelID: PanelID) -> some View {
        if let definition = registry.definition(for: panelID) {
            definition.makeContent()
        } else {
            VStack(spacing: UtilitySpacing.sm) {
                Image(systemName: "questionmark.square.dashed")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(UtilityTheme.textMuted)
                Text("Panel unavailable")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(UtilityTheme.text)
                Text(panelID.rawValue)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(UtilityTheme.textMuted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(UtilityTheme.panel)
        }
    }

    private func divider(axis: DockAxis, size: CGSize) -> some View {
        Rectangle()
            .fill(UtilityTheme.stroke.opacity(0.9))
            .frame(
                width: axis == .horizontal ? dividerThickness : size.width,
                height: axis == .horizontal ? size.height : dividerThickness
            )
            .overlay(
                Rectangle()
                    .fill(UtilityTheme.chromeElevated)
                    .frame(
                        width: axis == .horizontal ? 2 : size.width,
                        height: axis == .horizontal ? size.height : 2
                    )
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        updateRatio(axis: axis, translation: value.translation, size: size)
                    }
            )
    }

    private func updateRatio(axis: DockAxis, translation: CGSize, size: CGSize) {
        guard case let .split(currentAxis, currentRatio, leading, trailing) = node else { return }
        let extent = max(axis == .horizontal ? size.width : size.height, dividerThickness + 1)
        let delta = axis == .horizontal ? translation.width : translation.height
        let nextRatio = currentRatio + (delta / max(extent - dividerThickness, 1))
        let minimumExtent = min(240, max((extent - dividerThickness) / 2, 120))
        let minimumRatio = min(max(minimumExtent / max(extent - dividerThickness, 1), 0.15), 0.48)

        node = .split(
            axis: currentAxis,
            ratio: min(max(nextRatio, minimumRatio), 1 - minimumRatio),
            leading: leading,
            trailing: trailing
        )
    }

    private func leadingBinding(
        axis: DockAxis,
        ratio: Double,
        leading: DockLayoutNode,
        trailing: DockLayoutNode
    ) -> Binding<DockLayoutNode> {
        Binding(
            get: { leading },
            set: { newLeading in
                node = .split(axis: axis, ratio: ratio, leading: newLeading, trailing: trailing)
            }
        )
    }

    private func trailingBinding(
        axis: DockAxis,
        ratio: Double,
        leading: DockLayoutNode,
        trailing: DockLayoutNode
    ) -> Binding<DockLayoutNode> {
        Binding(
            get: { trailing },
            set: { newTrailing in
                node = .split(axis: axis, ratio: ratio, leading: leading, trailing: newTrailing)
            }
        )
    }
}

private struct DockPanelHeaderView: View {
    let definition: PanelDefinition?
    let panelID: PanelID
    let onBeginDrag: () -> Void

    var body: some View {
        HStack(spacing: UtilitySpacing.sm) {
            Image(systemName: definition?.systemImage ?? "square.on.square")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(UtilityTheme.textMuted)

            Text(definition?.title ?? fallbackTitle)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(UtilityTheme.text)
                .lineLimit(1)

            Spacer(minLength: 0)

            HStack(spacing: 3) {
                Image(systemName: "line.3.horizontal")
                Image(systemName: "line.3.horizontal")
            }
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(UtilityTheme.textMuted)
            .padding(.horizontal, UtilitySpacing.xs)
            .frame(height: UtilityMetrics.controlHeight - 4)
            .background(UtilityTheme.chrome)
            .clipShape(Capsule())
        }
        .padding(.horizontal, UtilitySpacing.md)
        .frame(height: DockDropGeometry.tabStripHeight)
        .background(CinematicTheme.surfaceContainerHigh)
        .contentShape(Rectangle())
        .onDrag {
            onBeginDrag()
            return NSItemProvider(object: panelID.rawValue as NSString)
        }
        .help("Drag to redock \(definition?.title ?? fallbackTitle)")
    }

    private var fallbackTitle: String {
        panelID.rawValue
            .split(separator: "-")
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}

private struct DockLeafContainer<Content: View>: View {
    let targetPanelID: PanelID
    let allowedBehavior: DockDropBehavior
    @ObservedObject var coordinator: DockingCoordinator
    let onDropPanel: (PanelID, PanelID, DockDropTarget) -> Void
    @ViewBuilder var content: Content

    @State private var isDropTargeted = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                DockDropOverlayView(target: isDropTargeted ? coordinator.activeDropTarget : nil)
            }
            .clipShape(RoundedRectangle(cornerRadius: UtilityRadius.sm))
            .onDrop(
                of: [UTType.text],
                delegate: DockPanelDropDelegate(
                    targetPanelID: targetPanelID,
                    allowedBehavior: allowedBehavior,
                    coordinator: coordinator,
                    frame: CGRect(origin: .zero, size: geometry.size),
                    isTargeted: $isDropTargeted,
                    onDropPanel: onDropPanel
                )
            )
        }
        .utilitySurface(.recessed, radius: UtilityRadius.sm)
    }
}

private struct DockPanelDropDelegate: DropDelegate {
    let targetPanelID: PanelID
    let allowedBehavior: DockDropBehavior
    let coordinator: DockingCoordinator
    let frame: CGRect
    @Binding var isTargeted: Bool
    let onDropPanel: (PanelID, PanelID, DockDropTarget) -> Void

    func dropEntered(info: DropInfo) {
        isTargeted = true
        coordinator.updateDropTarget(
            point: info.location,
            frame: frame,
            allowedBehavior: allowedBehavior
        )
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        isTargeted = true
        coordinator.updateDropTarget(
            point: info.location,
            frame: frame,
            allowedBehavior: allowedBehavior
        )
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
        coordinator.activeDropTarget = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        defer {
            isTargeted = false
            coordinator.endDrag()
        }

        guard let draggedPanelID = coordinator.draggedPanelID,
              let target = coordinator.activeDropTarget else {
            return false
        }

        onDropPanel(draggedPanelID, targetPanelID, target)
        return true
    }
}

extension DockWorkspaceLayout {
    func applyingDrop(
        draggedPanelID: PanelID,
        onto targetPanelID: PanelID,
        target: DockDropTarget
    ) -> Self {
        guard draggedPanelID != targetPanelID else { return self }

        let prunedRoot = root.removingPanel(draggedPanelID) ?? root
        let insertedRoot = prunedRoot.insertingPanel(
            draggedPanelID,
            onto: targetPanelID,
            target: target
        ) ?? prunedRoot

        return Self(workspaceID: workspaceID, root: insertedRoot)
    }

    func revealingPanel(
        _ panelID: PanelID,
        preferredTargets: [PanelID]
    ) -> Self {
        if root.containsPanel(panelID) {
            let selectedRoot = root.selectingPanel(panelID) ?? root
            return Self(workspaceID: workspaceID, root: selectedRoot)
        }

        guard let targetPanelID = preferredTargets.first(where: root.containsPanel) ?? root.firstPanelID else {
            return self
        }

        let insertedRoot = root.insertingPanel(panelID, onto: targetPanelID, target: .tabStack) ?? root
        let selectedRoot = insertedRoot.selectingPanel(panelID) ?? insertedRoot
        return Self(workspaceID: workspaceID, root: selectedRoot)
    }
}

extension DockLayoutNode {
    func containsPanel(_ panelID: PanelID) -> Bool {
        switch self {
        case let .panel(id):
            return id == panelID
        case let .tabs(_, panelIDs):
            return panelIDs.contains(panelID)
        case let .split(_, _, leading, trailing):
            return leading.containsPanel(panelID) || trailing.containsPanel(panelID)
        }
    }

    var firstPanelID: PanelID? {
        switch self {
        case let .panel(panelID):
            return panelID
        case let .tabs(_, panelIDs):
            return panelIDs.first
        case let .split(_, _, leading, trailing):
            return leading.firstPanelID ?? trailing.firstPanelID
        }
    }

    func removingPanel(_ panelID: PanelID) -> DockLayoutNode? {
        switch self {
        case let .panel(id):
            return id == panelID ? nil : self
        case let .tabs(activePanelID, panelIDs):
            let remaining = panelIDs.filter { $0 != panelID }
            if remaining.isEmpty {
                return nil
            }
            if remaining.count == 1, let first = remaining.first {
                return .panel(first)
            }
            let nextActive = remaining.contains(activePanelID) ? activePanelID : (remaining.first ?? activePanelID)
            return .tabs(activePanelID: nextActive, panelIDs: remaining)
        case let .split(axis, ratio, leading, trailing):
            let newLeading = leading.removingPanel(panelID)
            let newTrailing = trailing.removingPanel(panelID)

            switch (newLeading, newTrailing) {
            case let (.some(newLeading), .some(newTrailing)):
                return .split(axis: axis, ratio: ratio, leading: newLeading, trailing: newTrailing)
            case let (.some(newLeading), .none):
                return newLeading
            case let (.none, .some(newTrailing)):
                return newTrailing
            case (.none, .none):
                return nil
            }
        }
    }

    func selectingPanel(_ panelID: PanelID) -> DockLayoutNode? {
        switch self {
        case let .panel(id):
            return id == panelID ? self : nil
        case let .tabs(_, panelIDs):
            guard panelIDs.contains(panelID) else { return nil }
            return .tabs(activePanelID: panelID, panelIDs: panelIDs)
        case let .split(axis, ratio, leading, trailing):
            if let selectedLeading = leading.selectingPanel(panelID) {
                return .split(axis: axis, ratio: ratio, leading: selectedLeading, trailing: trailing)
            }

            if let selectedTrailing = trailing.selectingPanel(panelID) {
                return .split(axis: axis, ratio: ratio, leading: leading, trailing: selectedTrailing)
            }

            return nil
        }
    }

    func insertingPanel(
        _ panelID: PanelID,
        onto targetPanelID: PanelID,
        target: DockDropTarget
    ) -> DockLayoutNode? {
        switch self {
        case let .panel(existingPanelID):
            guard existingPanelID == targetPanelID else { return self }
            return dockWrappedNode(self, inserting: panelID, target: target)

        case let .tabs(activePanelID, panelIDs):
            guard panelIDs.contains(targetPanelID) else { return self }
            switch target {
            case .tabStack:
                let updatedPanelIDs = panelIDs.contains(panelID) ? panelIDs : panelIDs + [panelID]
                return .tabs(activePanelID: panelID, panelIDs: updatedPanelIDs)
            default:
                return dockWrappedNode(
                    .tabs(activePanelID: activePanelID, panelIDs: panelIDs),
                    inserting: panelID,
                    target: target
                )
            }

        case let .split(axis, ratio, leading, trailing):
            if leading.containsPanel(targetPanelID) {
                return .split(
                    axis: axis,
                    ratio: ratio,
                    leading: leading.insertingPanel(panelID, onto: targetPanelID, target: target) ?? leading,
                    trailing: trailing
                )
            }

            if trailing.containsPanel(targetPanelID) {
                return .split(
                    axis: axis,
                    ratio: ratio,
                    leading: leading,
                    trailing: trailing.insertingPanel(panelID, onto: targetPanelID, target: target) ?? trailing
                )
            }

            return self
        }
    }

    private func dockWrappedNode(
        _ existingNode: DockLayoutNode,
        inserting panelID: PanelID,
        target: DockDropTarget
    ) -> DockLayoutNode {
        switch target {
        case .tabStack:
            if case let .panel(existingPanelID) = existingNode {
                return .tabs(activePanelID: panelID, panelIDs: [existingPanelID, panelID])
            }
            return existingNode
        case .splitLeading:
            return .split(axis: .horizontal, ratio: 0.28, leading: .panel(panelID), trailing: existingNode)
        case .splitTrailing:
            return .split(axis: .horizontal, ratio: 0.72, leading: existingNode, trailing: .panel(panelID))
        case .splitTop:
            return .split(axis: .vertical, ratio: 0.28, leading: .panel(panelID), trailing: existingNode)
        case .splitBottom:
            return .split(axis: .vertical, ratio: 0.72, leading: existingNode, trailing: .panel(panelID))
        }
    }
}
