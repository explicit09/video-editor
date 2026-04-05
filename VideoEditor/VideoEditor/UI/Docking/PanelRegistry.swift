import SwiftUI

extension PanelID {
    static let effects: PanelID = "effects"
}

struct PanelDefinition {
    let id: PanelID
    let title: String
    let systemImage: String
    let allowedDropBehavior: DockDropBehavior
    let makeContent: () -> AnyView
}

@MainActor
struct PanelRegistry {
    let definitions: [PanelID: PanelDefinition]
    let defaultLayouts: [String: DockWorkspaceLayout]

    static let editWorkspaceID = "edit"

    static func edit(
        layoutMode: EditorLayoutMode,
        selectedTool: Binding<EditorTool>
    ) -> Self {
        let definitions: [PanelID: PanelDefinition] = [
            .projectBin: PanelDefinition(
                id: .projectBin,
                title: "Project Bin",
                systemImage: "photo.on.rectangle",
                allowedDropBehavior: .splitOrTabs,
                makeContent: { AnyView(MediaBrowserPanel()) }
            ),
            .effects: PanelDefinition(
                id: .effects,
                title: "Effects & Modes",
                systemImage: "slider.horizontal.3",
                allowedDropBehavior: .splitOrTabs,
                makeContent: { AnyView(EffectsPanel(selectedTool: selectedTool)) }
            ),
            .sourceMonitor: PanelDefinition(
                id: .sourceMonitor,
                title: "Source Monitor",
                systemImage: "film.stack",
                allowedDropBehavior: .splitOrTabs,
                makeContent: { AnyView(SourceMonitorPanel()) }
            ),
            .programMonitor: PanelDefinition(
                id: .programMonitor,
                title: "Program Monitor",
                systemImage: "play.rectangle",
                allowedDropBehavior: .splitOrTabs,
                makeContent: { AnyView(ProgramMonitorPanel()) }
            ),
            .timeline: PanelDefinition(
                id: .timeline,
                title: "Timeline",
                systemImage: "timeline.selection",
                allowedDropBehavior: .splitOrTabs,
                makeContent: { AnyView(TimelinePanel(tool: selectedTool.wrappedValue)) }
            ),
            .inspector: PanelDefinition(
                id: .inspector,
                title: "Inspector",
                systemImage: "slider.horizontal.3",
                allowedDropBehavior: .splitOrTabs,
                makeContent: {
                    AnyView(
                        EditInspectorPanel(layoutMode: layoutMode)
                    )
                }
            ),
        ]

        return Self(
            definitions: definitions,
            defaultLayouts: [
                editWorkspaceID: editDefaultLayout,
            ]
        )
    }

    static var editDefaultLayout: DockWorkspaceLayout {
        DockWorkspaceLayout(
            workspaceID: editWorkspaceID,
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
                        leading: .split(
                            axis: .horizontal,
                            ratio: 0.5,
                            leading: .panel(.sourceMonitor),
                            trailing: .panel(.programMonitor)
                        ),
                        trailing: .panel(.inspector)
                    )
                ),
                trailing: .panel(.timeline)
            )
        )
    }

    var allowedPanelIDs: Set<PanelID> {
        Set(definitions.keys)
    }

    func definition(for panelID: PanelID) -> PanelDefinition? {
        definitions[panelID]
    }

    func makeLayoutStore(baseURL: URL) -> WorkspaceLayoutStore {
        WorkspaceLayoutStore(
            defaults: defaultLayouts,
            fileManager: .default,
            baseURL: baseURL,
            allowedPanelIDs: allowedPanelIDs
        )
    }
}

private struct EditInspectorPanel: View {
    @Environment(AppState.self) private var appState
    let layoutMode: EditorLayoutMode

    var body: some View {
        InspectorPanel(
            selectedTab: .constant(.inspector),
            context: SelectionInspectorContext.resolve(
                selectedClipIDs: appState.timelineViewState.selectedClipIDs,
                selectedTrackID: appState.timelineViewState.selectedTrackID
            ),
            layoutMode: layoutMode,
            showsTabs: false
        )
    }
}
