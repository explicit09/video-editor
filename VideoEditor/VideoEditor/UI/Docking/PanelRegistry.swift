import SwiftUI

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
    static let mediaWorkspaceID = "media"
    static let transcriptWorkspaceID = "transcript"
    static let aiWorkspaceID = "ai"
    static let deliverWorkspaceID = "deliver"

    static func workspaceRegistry(
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
            .mediaWorkspace: PanelDefinition(
                id: .mediaWorkspace,
                title: "Media Workspace",
                systemImage: "square.grid.2x2",
                allowedDropBehavior: .splitOrTabs,
                makeContent: { AnyView(MediaWorkspacePanel()) }
            ),
            .transcript: PanelDefinition(
                id: .transcript,
                title: "Transcript",
                systemImage: "text.alignleft",
                allowedDropBehavior: .splitOrTabs,
                makeContent: { AnyView(TranscriptPanel()) }
            ),
            .aiAssistant: PanelDefinition(
                id: .aiAssistant,
                title: "AI Copilot",
                systemImage: "sparkles",
                allowedDropBehavior: .splitOrTabs,
                makeContent: { AnyView(DockAIPanel(layoutMode: layoutMode)) }
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
                        DockInspectorPanel(layoutMode: layoutMode)
                    )
                }
            ),
            .deliver: PanelDefinition(
                id: .deliver,
                title: "Deliver",
                systemImage: "square.and.arrow.up",
                allowedDropBehavior: .splitOrTabs,
                makeContent: { AnyView(DeliverPanel()) }
            ),
            .thumbnailCompare: PanelDefinition(
                id: .thumbnailCompare,
                title: "Thumbnails",
                systemImage: "photo.on.rectangle.angled",
                allowedDropBehavior: .splitOrTabs,
                makeContent: { AnyView(ThumbnailComparePanel()) }
            ),
            .carouselViewer: PanelDefinition(
                id: .carouselViewer,
                title: "Carousels",
                systemImage: "rectangle.stack",
                allowedDropBehavior: .splitOrTabs,
                makeContent: { AnyView(CarouselViewerPanel()) }
            ),
        ]

        return Self(
            definitions: definitions,
            defaultLayouts: [
                editWorkspaceID: editDefaultLayout,
                mediaWorkspaceID: mediaDefaultLayout,
                transcriptWorkspaceID: transcriptDefaultLayout,
                aiWorkspaceID: aiDefaultLayout,
                deliverWorkspaceID: deliverDefaultLayout,
            ]
        )
    }

    static func edit(
        layoutMode: EditorLayoutMode,
        selectedTool: Binding<EditorTool>
    ) -> Self {
        workspaceRegistry(
            layoutMode: layoutMode,
            selectedTool: selectedTool
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
                        leading: .tabs(
                            activePanelID: .programMonitor,
                            panelIDs: [.programMonitor, .thumbnailCompare, .carouselViewer]
                        ),
                        trailing: .panel(.inspector)
                    )
                ),
                trailing: .panel(.timeline)
            )
        )
    }

    static var mediaDefaultLayout: DockWorkspaceLayout {
        DockWorkspaceLayout(
            workspaceID: mediaWorkspaceID,
            root: .split(
                axis: .horizontal,
                ratio: 0.7,
                leading: .panel(.mediaWorkspace),
                trailing: .split(
                    axis: .vertical,
                    ratio: 0.58,
                    leading: .panel(.sourceMonitor),
                    trailing: .tabs(
                        activePanelID: .inspector,
                        panelIDs: [.inspector, .timeline, .projectBin]
                    )
                )
            )
        )
    }

    static var transcriptDefaultLayout: DockWorkspaceLayout {
        DockWorkspaceLayout(
            workspaceID: transcriptWorkspaceID,
            root: .split(
                axis: .vertical,
                ratio: 0.68,
                leading: .split(
                    axis: .horizontal,
                    ratio: 0.64,
                    leading: .panel(.transcript),
                    trailing: .panel(.programMonitor)
                ),
                trailing: .split(
                    axis: .horizontal,
                    ratio: 0.72,
                    leading: .panel(.timeline),
                    trailing: .panel(.inspector)
                )
            )
        )
    }

    static var aiDefaultLayout: DockWorkspaceLayout {
        DockWorkspaceLayout(
            workspaceID: aiWorkspaceID,
            root: .split(
                axis: .vertical,
                ratio: 0.72,
                leading: .split(
                    axis: .horizontal,
                    ratio: 0.64,
                    leading: .panel(.aiAssistant),
                    trailing: .panel(.programMonitor)
                ),
                trailing: .split(
                    axis: .horizontal,
                    ratio: 0.72,
                    leading: .panel(.timeline),
                    trailing: .tabs(
                        activePanelID: .transcript,
                        panelIDs: [.transcript, .inspector]
                    )
                )
            )
        )
    }

    static var deliverDefaultLayout: DockWorkspaceLayout {
        WorkspaceDefaultLayouts.deliverDefaultLayout
    }

    var allowedPanelIDs: Set<PanelID> {
        Set(definitions.keys)
    }

    func definition(for panelID: PanelID) -> PanelDefinition? {
        definitions[panelID]
    }

    func revealingPanel(_ panelID: PanelID, in layout: DockWorkspaceLayout) -> DockWorkspaceLayout {
        layout.revealingPanel(
            panelID,
            preferredTargets: preferredRevealTargets(for: panelID, workspaceID: layout.workspaceID)
        )
    }

    func makeLayoutStore(baseURL: URL) -> WorkspaceLayoutStore {
        WorkspaceLayoutStore(
            defaults: defaultLayouts,
            fileManager: .default,
            baseURL: baseURL,
            allowedPanelIDs: allowedPanelIDs
        )
    }

    private func preferredRevealTargets(for panelID: PanelID, workspaceID: String) -> [PanelID] {
        guard panelID == .aiAssistant else {
            return [panelID]
        }

        switch workspaceID {
        case Self.editWorkspaceID:
            return [.inspector, .programMonitor, .timeline]
        case Self.mediaWorkspaceID:
            return [.inspector, .timeline, .projectBin]
        case Self.transcriptWorkspaceID:
            return [.inspector, .transcript, .programMonitor]
        case Self.aiWorkspaceID:
            return [.aiAssistant, .transcript, .programMonitor]
        case Self.deliverWorkspaceID:
            return [.inspector, .deliver, .programMonitor]
        default:
            return [.inspector, .programMonitor, .timeline]
        }
    }
}

private struct DockInspectorPanel: View {
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

private struct DockAIPanel: View {
    @Environment(AppState.self) private var appState
    let layoutMode: EditorLayoutMode

    var body: some View {
        InspectorPanel(
            selectedTab: .constant(.ai),
            context: SelectionInspectorContext.resolve(
                selectedClipIDs: appState.timelineViewState.selectedClipIDs,
                selectedTrackID: appState.timelineViewState.selectedTrackID
            ),
            layoutMode: layoutMode,
            showsTabs: false
        )
    }
}
