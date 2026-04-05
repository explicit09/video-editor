import Foundation

struct PanelID: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(stringLiteral value: String) {
        self.rawValue = value
    }

    static let projectBin: PanelID = "project-bin"
    static let sourceMonitor: PanelID = "source-monitor"
    static let programMonitor: PanelID = "program-monitor"
    static let timeline: PanelID = "timeline"
    static let inspector: PanelID = "inspector"
}

enum DockAxis: String, Codable, Sendable {
    case horizontal
    case vertical
}

indirect enum DockLayoutNode: Codable, Equatable, Sendable {
    case panel(PanelID)
    case tabs(activePanelID: PanelID, panelIDs: [PanelID])
    case split(axis: DockAxis, ratio: Double, leading: DockLayoutNode, trailing: DockLayoutNode)
}

struct DockWorkspaceLayout: Codable, Equatable, Sendable {
    let workspaceID: String
    let root: DockLayoutNode
}

enum WorkspaceDefaultLayouts {
    static func make() -> [String: DockWorkspaceLayout] {
        [
            "edit": DockWorkspaceLayout(
                workspaceID: "edit",
                root: .split(
                    axis: .vertical,
                    ratio: 0.64,
                    leading: .split(
                        axis: .horizontal,
                        ratio: 0.5,
                        leading: .tabs(
                            activePanelID: .sourceMonitor,
                            panelIDs: [.projectBin, .sourceMonitor]
                        ),
                        trailing: .panel(.programMonitor)
                    ),
                    trailing: .panel(.timeline)
                )
            )
        ]
    }

    static let knownPanelIDs: Set<PanelID> = [
        .projectBin,
        .sourceMonitor,
        .programMonitor,
        .timeline,
        .inspector,
    ]
}
