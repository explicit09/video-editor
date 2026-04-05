import Foundation

struct WorkspaceLayoutStore {
    let defaults: [String: DockWorkspaceLayout]
    let fileManager: FileManager
    let baseURL: URL

    func loadLayout(for workspaceID: String) throws -> DockWorkspaceLayout {
        let url = layoutURL(for: workspaceID)

        guard fileManager.fileExists(atPath: url.path) else {
            return try defaultLayout(for: workspaceID)
        }

        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode(DockWorkspaceLayout.self, from: data)
        return isValid(decoded) ? decoded : try defaultLayout(for: workspaceID)
    }

    func save(_ layout: DockWorkspaceLayout) throws {
        try fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true, attributes: nil)

        let data = try JSONEncoder().encode(layout)
        try data.write(to: layoutURL(for: layout.workspaceID), options: [.atomic])
    }

    private func defaultLayout(for workspaceID: String) throws -> DockWorkspaceLayout {
        guard let layout = defaults[workspaceID] else {
            throw WorkspaceLayoutStoreError.missingDefaultLayout(workspaceID: workspaceID)
        }
        return layout
    }

    private func layoutURL(for workspaceID: String) -> URL {
        baseURL.appendingPathComponent("\(workspaceID).json")
    }

    private func isValid(_ layout: DockWorkspaceLayout) -> Bool {
        isValid(layout.root)
    }

    private func isValid(_ node: DockLayoutNode) -> Bool {
        switch node {
        case let .panel(panelID):
            return WorkspaceDefaultLayouts.knownPanelIDs.contains(panelID)
        case let .tabs(activePanelID, panelIDs):
            return !panelIDs.isEmpty
                && panelIDs.contains(activePanelID)
                && panelIDs.allSatisfy(WorkspaceDefaultLayouts.knownPanelIDs.contains)
        case let .split(axis: _, ratio: ratio, leading: leading, trailing: trailing):
            guard ratio.isFinite, ratio > 0, ratio < 1 else { return false }
            return isValid(leading) && isValid(trailing)
        }
    }
}

enum WorkspaceLayoutStoreError: Error, Equatable {
    case missingDefaultLayout(workspaceID: String)
}
