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
    static let effects: PanelID = "effects"
    static let mediaWorkspace: PanelID = "media-workspace"
    static let transcript: PanelID = "transcript"
    static let aiAssistant: PanelID = "ai-assistant"
    static let deliver: PanelID = "deliver"
    static let thumbnailCompare: PanelID = "thumbnail-compare"
    static let carouselViewer: PanelID = "carousel-viewer"
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
    static let deliverDefaultLayout = DockWorkspaceLayout(
        workspaceID: "deliver",
        root: .split(
            axis: .horizontal,
            ratio: 0.66,
            leading: .panel(.programMonitor),
            trailing: .split(
                axis: .vertical,
                ratio: 0.76,
                leading: .panel(.deliver),
                trailing: .tabs(
                    activePanelID: .inspector,
                    panelIDs: [.inspector, .timeline]
                )
            )
        )
    )

    static func make() -> [String: DockWorkspaceLayout] {
        [
            "edit": DockWorkspaceLayout(
                workspaceID: "edit",
                root: .split(
                    axis: .vertical,
                    ratio: 0.64,
                    leading: .split(
                        axis: .horizontal,
                        ratio: 0.22,
                        leading: .tabs(
                            activePanelID: .projectBin,
                            panelIDs: [.projectBin, .effects]
                        ),
                        trailing: .split(
                            axis: .horizontal,
                            ratio: 0.78,
                            leading: .panel(.programMonitor),
                            trailing: .panel(.inspector)
                        )
                    ),
                    trailing: .panel(.timeline)
                )
            ),
            "deliver": deliverDefaultLayout,
        ]
    }

    static let knownPanelIDs: Set<PanelID> = [
        .projectBin,
        .sourceMonitor,
        .programMonitor,
        .timeline,
        .inspector,
        .effects,
        .mediaWorkspace,
        .transcript,
        .aiAssistant,
        .deliver,
        .thumbnailCompare,
        .carouselViewer,
    ]
}
