import SwiftUI

enum EditorLayoutMode: Hashable {
    case compact
    case expanded
}

enum EditorTool: String, CaseIterable, Hashable {
    case selection = "Select"
    case blade = "Blade"
    case trim = "Trim"

    var icon: String {
        switch self {
        case .selection: "cursorarrow"
        case .blade: "scissors"
        case .trim: "arrow.left.and.right.righttriangle.left.righttriangle.right"
        }
    }
}

@MainActor
enum EditorWorkspace: String, CaseIterable {
    case edit = "Edit"
    case transcript = "Transcript"
    case media = "Media"
    case ai = "AI"
    case deliver = "Deliver"

    var icon: String {
        switch self {
        case .edit: "timeline.selection"
        case .transcript: "text.alignleft"
        case .media: "photo.on.rectangle"
        case .ai: "sparkles"
        case .deliver: "square.and.arrow.up"
        }
    }

    var workspaceID: String {
        switch self {
        case .edit:
            PanelRegistry.editWorkspaceID
        case .media:
            PanelRegistry.mediaWorkspaceID
        case .transcript:
            PanelRegistry.transcriptWorkspaceID
        case .ai:
            PanelRegistry.aiWorkspaceID
        case .deliver:
            PanelRegistry.deliverWorkspaceID
        }
    }
}

struct EditLayoutLoadTracker {
    private(set) var loadedBundleURL: URL?

    mutating func markLoadedIfNeeded(for bundleURL: URL) -> Bool {
        guard loadedBundleURL != bundleURL else { return false }
        loadedBundleURL = bundleURL
        return true
    }
}

struct WorkspaceDockState {
    var layout: DockWorkspaceLayout
    var loadTracker = EditLayoutLoadTracker()
}

@MainActor
enum WorkspaceLayoutMigration {
    static func normalizeLoadedLayout(
        _ layout: DockWorkspaceLayout,
        using registry: PanelRegistry
    ) -> DockWorkspaceLayout {
        guard layout.workspaceID == PanelRegistry.editWorkspaceID,
              layout.root.containsPanel(.sourceMonitor) else {
            return layout
        }

        guard let sanitizedRoot = layout.root.removingPanel(.sourceMonitor) else {
            return registry.defaultLayouts[layout.workspaceID] ?? layout
        }

        let sanitizedLayout = DockWorkspaceLayout(
            workspaceID: layout.workspaceID,
            root: sanitizedRoot
        )

        guard sanitizedLayout.root.containsPanel(.programMonitor) else {
            return registry.defaultLayouts[layout.workspaceID] ?? sanitizedLayout
        }

        return sanitizedLayout
    }
}

@MainActor
enum WorkspaceDockPersistence {
    static func workspaceLayoutsBaseURL(for bundleURL: URL) -> URL {
        bundleURL.appendingPathComponent("WorkspaceLayouts", isDirectory: true)
    }

    static func loadLayoutIfNeeded(
        state: inout WorkspaceDockState,
        using registry: PanelRegistry,
        workspaceID: String,
        for bundleURL: URL
    ) {
        guard state.loadTracker.markLoadedIfNeeded(for: bundleURL) else { return }

        do {
            let loadedLayout = try registry
                .makeLayoutStore(baseURL: workspaceLayoutsBaseURL(for: bundleURL))
                .loadLayout(for: workspaceID)
            state.layout = WorkspaceLayoutMigration.normalizeLoadedLayout(
                loadedLayout,
                using: registry
            )
        } catch {
            state.layout = registry.defaultLayouts[workspaceID] ?? state.layout
        }
    }

    static func persist(
        _ state: WorkspaceDockState,
        using registry: PanelRegistry,
        for bundleURL: URL
    ) throws {
        guard state.loadTracker.loadedBundleURL == bundleURL else { return }

        try registry
            .makeLayoutStore(baseURL: workspaceLayoutsBaseURL(for: bundleURL))
            .save(state.layout)
    }

    static func resetLayout(
        for workspaceID: String,
        using registry: PanelRegistry,
        for bundleURL: URL
    ) throws {
        try registry
            .makeLayoutStore(baseURL: workspaceLayoutsBaseURL(for: bundleURL))
            .resetLayout(for: workspaceID)
    }

    static func revealedState(
        byRevealing panelID: PanelID,
        in state: WorkspaceDockState,
        using registry: PanelRegistry
    ) -> WorkspaceDockState {
        var nextState = state
        nextState.layout = registry.revealingPanel(panelID, in: state.layout)
        return nextState
    }
}

private struct RestoreWorkspaceLayoutActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct ResetWorkspaceLayoutsActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct RevealAIPanelActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var restoreWorkspaceLayoutAction: (() -> Void)? {
        get { self[RestoreWorkspaceLayoutActionKey.self] }
        set { self[RestoreWorkspaceLayoutActionKey.self] = newValue }
    }

    var resetWorkspaceLayoutsAction: (() -> Void)? {
        get { self[ResetWorkspaceLayoutsActionKey.self] }
        set { self[ResetWorkspaceLayoutsActionKey.self] = newValue }
    }

    var revealAIPanelAction: (() -> Void)? {
        get { self[RevealAIPanelActionKey.self] }
        set { self[RevealAIPanelActionKey.self] = newValue }
    }
}
