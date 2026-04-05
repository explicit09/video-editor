import SwiftUI
import AppKit
import EditorCore

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedWorkspace: EditorWorkspace = .edit
    @State private var showSettings = false
    @State private var showExportDialog = false
    @State private var editorTool: EditorTool = .selection
    @State private var editDockState = WorkspaceDockState(layout: PanelRegistry.editDefaultLayout)
    @State private var mediaDockState = WorkspaceDockState(layout: PanelRegistry.mediaDefaultLayout)
    @State private var transcriptDockState = WorkspaceDockState(layout: PanelRegistry.transcriptDefaultLayout)
    @State private var aiDockState = WorkspaceDockState(layout: PanelRegistry.aiDefaultLayout)
    @State private var deliverDockState = WorkspaceDockState(layout: PanelRegistry.deliverDefaultLayout)

    var body: some View {
        GeometryReader { geo in
            let layoutMode = editorLayoutMode(for: geo.size.width)
            let pageBarMetrics = WorkspacePageBarMetrics.make(containerWidth: geo.size.width)

            VStack(spacing: UtilitySpacing.sm) {
                topBar(layoutMode: layoutMode)

                WorkspacePageBar(
                    items: EditorWorkspace.allCases,
                    selection: Binding(
                        get: { selectedWorkspace },
                        set: { selectWorkspace($0) }
                    ),
                    metrics: pageBarMetrics,
                    title: { $0.rawValue },
                    icon: { $0.icon }
                )

                mainWorkspace(layoutMode: layoutMode)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, UtilitySpacing.lg)
            .padding(.top, UtilitySpacing.sm)
            .padding(.bottom, UtilitySpacing.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(appBackground)
        }
        .frame(minWidth: 1200, minHeight: 760)
        .focusable()
        .focusedSceneValue(\.restoreWorkspaceLayoutAction, restoreSelectedWorkspaceLayout)
        .focusedSceneValue(\.resetWorkspaceLayoutsAction, resetAllWorkspaceLayouts)
        .focusedSceneValue(\.revealAIPanelAction, revealAIPanelInSelectedWorkspace)
        .onKeyPress("j") { guard shouldHandleGlobalShortcut else { return .ignored }; stepBackward(); return .handled }
        .onKeyPress("k") { guard shouldHandleGlobalShortcut else { return .ignored }; appState.playbackEngine.togglePlayPause(); return .handled }
        .onKeyPress("l") { guard shouldHandleGlobalShortcut else { return .ignored }; stepForward(); return .handled }
        .onKeyPress(.leftArrow) { guard shouldHandleGlobalShortcut else { return .ignored }; stepFrame(forward: false); return .handled }
        .onKeyPress(.rightArrow) { guard shouldHandleGlobalShortcut else { return .ignored }; stepFrame(forward: true); return .handled }
        .onKeyPress("=") { guard shouldHandleGlobalShortcut else { return .ignored }; appState.timelineViewState.zoomIn(); return .handled }
        .onKeyPress("-") { guard shouldHandleGlobalShortcut else { return .ignored }; appState.timelineViewState.zoomOut(); return .handled }
        // Split at playhead
        .onKeyPress("s") { guard shouldHandleGlobalShortcut else { return .ignored }; splitAtPlayhead(); return .handled }
        // Add marker at playhead
        .onKeyPress("m") { guard shouldHandleGlobalShortcut else { return .ignored }; addMarkerAtPlayhead(); return .handled }
        // Select all clips (Cmd+A)
        .onKeyPress("a") {
            guard shouldHandleGlobalShortcut else { return .ignored }
            guard NSEvent.modifierFlags.contains(.command) else { return .ignored }
            selectAllClips(); return .handled
        }
        // Duplicate selected clips (Cmd+D)
        .onKeyPress("d") {
            guard shouldHandleGlobalShortcut else { return .ignored }
            guard NSEvent.modifierFlags.contains(.command) else { return .ignored }
            duplicateSelectedClips(); return .handled
        }
        // Toggle snap
        .onKeyPress("n") { guard shouldHandleGlobalShortcut else { return .ignored }; appState.timelineViewState.snapEnabled.toggle(); return .handled }
        // Toggle ripple
        .onKeyPress("r") { guard shouldHandleGlobalShortcut else { return .ignored }; appState.timelineViewState.rippleEnabled.toggle(); return .handled }
        // Copy (Cmd+C)
        .onKeyPress("c") {
            guard shouldHandleGlobalShortcut else { return .ignored }
            guard NSEvent.modifierFlags.contains(.command) else { return .ignored }
            appState.copySelectedClips(); return .handled
        }
        // Paste (Cmd+V)
        .onKeyPress("v") {
            guard shouldHandleGlobalShortcut else { return .ignored }
            guard NSEvent.modifierFlags.contains(.command) else { return .ignored }
            appState.pasteClips(); return .handled
        }
        .onKeyPress("1") { guard shouldHandleGlobalShortcut else { return .ignored }; editorTool = .selection; return .handled }
        .onKeyPress("2") { guard shouldHandleGlobalShortcut else { return .ignored }; editorTool = .blade; return .handled }
        .onKeyPress("3") { guard shouldHandleGlobalShortcut else { return .ignored }; editorTool = .trim; return .handled }
        .onKeyPress(.escape) { guard shouldHandleGlobalShortcut else { return .ignored }; editorTool = .selection; return .handled }
    }

    private var shouldHandleGlobalShortcut: Bool {
        EditorShortcutGuard.shouldHandleGlobalShortcut(isTextInputFocused: NSApp.keyWindow?.firstResponder is NSTextView)
    }

    private var appBackground: some View {
        LinearGradient(
            colors: [
                UtilityTheme.canvas,
                UtilityTheme.recessed,
                UtilityTheme.canvas,
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func stepForward() {
        let newTime = min(appState.playbackEngine.currentTime + 5, appState.playbackEngine.duration)
        appState.playbackEngine.seek(to: newTime)
        appState.timelineViewState.playheadPosition = newTime
    }

    private func stepBackward() {
        let newTime = max(appState.playbackEngine.currentTime - 5, 0)
        appState.playbackEngine.seek(to: newTime)
        appState.timelineViewState.playheadPosition = newTime
    }

    private func stepFrame(forward: Bool) {
        let frameDuration = 1.0 / 30.0
        let newTime = forward
            ? min(appState.playbackEngine.currentTime + frameDuration, appState.playbackEngine.duration)
            : max(appState.playbackEngine.currentTime - frameDuration, 0)
        appState.playbackEngine.seek(to: newTime)
        appState.timelineViewState.playheadPosition = newTime
    }

    private func splitAtPlayhead() {
        let playhead = appState.timelineViewState.playheadPosition
        let allClips = appState.timeline.tracks.flatMap(\.clips)
        let selectedClips = allClips.filter {
            appState.timelineViewState.selectedClipIDs.contains($0.id) && $0.timelineRange.contains(playhead)
        }

        if !selectedClips.isEmpty {
            let intents = selectedClips.map { EditorIntent.splitClip(clipID: $0.id, at: playhead) }
            try? appState.perform(intents.count == 1 ? intents[0] : .batch(intents))
        } else {
            // Batch blade: split ALL clips spanning the playhead
            let spanning = allClips.filter { $0.timelineRange.contains(playhead) }
            guard !spanning.isEmpty else { return }
            let intents = spanning.map { EditorIntent.splitClip(clipID: $0.id, at: playhead) }
            try? appState.perform(intents.count == 1 ? intents[0] : .batch(intents))
        }
    }

    private func addMarkerAtPlayhead() {
        let playhead = appState.timelineViewState.playheadPosition
        try? appState.perform(.setMarker(at: playhead, label: ""))
    }

    private func selectAllClips() {
        let allIDs = Set(appState.timeline.tracks.flatMap(\.clips).map(\.id))
        appState.timelineViewState.selectedClipIDs = allIDs
    }

    private func duplicateSelectedClips() {
        appState.duplicateSelection()
    }

    private func topBar(layoutMode: EditorLayoutMode) -> some View {
        HStack(spacing: CinematicSpacing.sm) {
            HStack(spacing: UtilitySpacing.sm) {
                RoundedRectangle(cornerRadius: UtilityRadius.sm)
                    .fill(UtilityTheme.accent)
                    .frame(width: 20, height: 20)
                    .overlay(
                        Image(systemName: "play.rectangle")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(UtilityTheme.accentText)
                    )

                VStack(alignment: .leading, spacing: UtilitySpacing.xxxs) {
                    Text("Unified Pro Editor")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(UtilityTheme.text)
                    Text(selectedWorkspace.rawValue.uppercased())
                        .font(.system(size: 10, weight: .medium))
                        .tracking(0.8)
                        .foregroundStyle(UtilityTheme.textMuted)
                }
            }

            Spacer(minLength: 20)

            if appState.aiChat.isProcessing {
                UtilityStatusBadge(
                    text: "AI ACTIVE",
                    icon: "sparkles",
                    style: .accent
                )
            }

            UtilityStatusBadge(
                text: layoutMode == .compact ? "COMPACT" : "EXPANDED",
                icon: layoutMode == .compact ? "rectangle.compress.vertical" : "rectangle.expand.vertical",
                style: .info
            )

            CinematicToolbarButton(
                icon: "sparkles.rectangle.stack",
                label: selectedWorkspaceHasAIPanel ? "Focus AI" : "Show AI",
                isActive: selectedWorkspaceHasAIPanel,
                action: revealAIPanelInSelectedWorkspace
            )

            CinematicToolbarButton(icon: "square.and.arrow.up", label: "Export") {
                showExportDialog = true
            }

            CinematicToolbarButton(icon: "gearshape", action: { showSettings = true })
        }
        .padding(.horizontal, UtilitySpacing.md)
        .frame(height: UtilityMetrics.topBarHeight)
        .utilitySurface(.chromeElevated, shadow: true)
        .sheet(isPresented: $showSettings) {
            SettingsSheet(isPresented: $showSettings)
        }
        .sheet(isPresented: $showExportDialog) {
            ExportDialog(isPresented: $showExportDialog)
        }
    }

    private func selectWorkspace(_ workspace: EditorWorkspace) {
        selectedWorkspace = workspace
    }

    @ViewBuilder
    private func mainWorkspace(layoutMode: EditorLayoutMode) -> some View {
        switch selectedWorkspace {
        case .edit:
            editorWorkspace(layoutMode: layoutMode)
        case .media:
            focusedMediaWorkspace(layoutMode: layoutMode)
        case .transcript:
            focusedTranscriptWorkspace(layoutMode: layoutMode)
        case .ai:
            focusedAIWorkspace(layoutMode: layoutMode)
        case .deliver:
            focusedDeliverWorkspace(layoutMode: layoutMode)
        }
    }

    private func editorWorkspace(layoutMode: EditorLayoutMode) -> some View {
        let registry = PanelRegistry.workspaceRegistry(
            layoutMode: layoutMode,
            selectedTool: $editorTool
        )

        return dockedWorkspace(
            workspaceID: PanelRegistry.editWorkspaceID,
            state: $editDockState,
            registry: registry
        )
    }

    private func focusedMediaWorkspace(layoutMode: EditorLayoutMode) -> some View {
        let registry = PanelRegistry.workspaceRegistry(
            layoutMode: layoutMode,
            selectedTool: $editorTool
        )

        return dockedWorkspace(
            workspaceID: PanelRegistry.mediaWorkspaceID,
            state: $mediaDockState,
            registry: registry
        )
    }

    private func focusedTranscriptWorkspace(layoutMode: EditorLayoutMode) -> some View {
        let registry = PanelRegistry.workspaceRegistry(
            layoutMode: layoutMode,
            selectedTool: $editorTool
        )

        return dockedWorkspace(
            workspaceID: PanelRegistry.transcriptWorkspaceID,
            state: $transcriptDockState,
            registry: registry
        )
    }

    private func focusedAIWorkspace(layoutMode: EditorLayoutMode) -> some View {
        let registry = PanelRegistry.workspaceRegistry(
            layoutMode: layoutMode,
            selectedTool: $editorTool
        )

        return dockedWorkspace(
            workspaceID: PanelRegistry.aiWorkspaceID,
            state: $aiDockState,
            registry: registry
        )
    }

    private func focusedDeliverWorkspace(layoutMode: EditorLayoutMode) -> some View {
        let registry = PanelRegistry.workspaceRegistry(
            layoutMode: layoutMode,
            selectedTool: $editorTool
        )

        return dockedWorkspace(
            workspaceID: PanelRegistry.deliverWorkspaceID,
            state: $deliverDockState,
            registry: registry
        )
    }

    private func dockedWorkspace(
        workspaceID: String,
        state: Binding<WorkspaceDockState>,
        registry: PanelRegistry
    ) -> some View {
        let projectBundleURL = appState.projectBundleURL
        let layoutBinding = Binding(
            get: { state.wrappedValue.layout },
            set: { state.wrappedValue.layout = $0 }
        )

        return DockHostView(layout: layoutBinding, registry: registry)
            .id("\(workspaceID)-\(projectBundleURL.path)")
            .onAppear {
                var nextState = state.wrappedValue
                WorkspaceDockPersistence.loadLayoutIfNeeded(
                    state: &nextState,
                    using: registry,
                    workspaceID: workspaceID,
                    for: projectBundleURL
                )
                state.wrappedValue = nextState
            }
            .onChange(of: projectBundleURL) { _, newBundleURL in
                var nextState = state.wrappedValue
                WorkspaceDockPersistence.loadLayoutIfNeeded(
                    state: &nextState,
                    using: registry,
                    workspaceID: workspaceID,
                    for: newBundleURL
                )
                state.wrappedValue = nextState
            }
            .onChange(of: state.wrappedValue.layout) { _, _ in
                do {
                    try WorkspaceDockPersistence.persist(
                        state.wrappedValue,
                        using: registry,
                        for: projectBundleURL
                    )
                } catch {
                    print("[ContentView] Failed to persist \(state.wrappedValue.layout.workspaceID) layout: \(error.localizedDescription)")
                }
            }
    }

    private func editorLayoutMode(for width: CGFloat) -> EditorLayoutMode {
        width < 1560 ? .compact : .expanded
    }

    private var selectedWorkspaceID: String {
        selectedWorkspace.workspaceID
    }

    private var selectedWorkspaceState: Binding<WorkspaceDockState> {
        switch selectedWorkspace {
        case .edit:
            $editDockState
        case .media:
            $mediaDockState
        case .transcript:
            $transcriptDockState
        case .ai:
            $aiDockState
        case .deliver:
            $deliverDockState
        }
    }

    private var persistenceRegistry: PanelRegistry {
        PanelRegistry.workspaceRegistry(
            layoutMode: .expanded,
            selectedTool: $editorTool
        )
    }

    private var selectedWorkspaceHasAIPanel: Bool {
        selectedWorkspaceState.wrappedValue.layout.root.containsPanel(.aiAssistant)
    }

    private func restoreSelectedWorkspaceLayout() {
        let registry = persistenceRegistry
        let workspaceID = selectedWorkspaceID
        let state = selectedWorkspaceState

        do {
            try WorkspaceDockPersistence.resetLayout(
                for: workspaceID,
                using: registry,
                for: appState.projectBundleURL
            )
        } catch {
            print("[ContentView] Failed to restore \(workspaceID) layout: \(error.localizedDescription)")
        }

        guard let defaultLayout = registry.defaultLayouts[workspaceID] else { return }

        var nextState = state.wrappedValue
        nextState.layout = defaultLayout
        state.wrappedValue = nextState
    }

    private func resetAllWorkspaceLayouts() {
        let registry = persistenceRegistry

        for workspaceID in registry.defaultLayouts.keys {
            do {
                try WorkspaceDockPersistence.resetLayout(
                    for: workspaceID,
                    using: registry,
                    for: appState.projectBundleURL
                )
            } catch {
                print("[ContentView] Failed to reset \(workspaceID) layout: \(error.localizedDescription)")
            }
        }

        editDockState.layout = PanelRegistry.editDefaultLayout
        mediaDockState.layout = PanelRegistry.mediaDefaultLayout
        transcriptDockState.layout = PanelRegistry.transcriptDefaultLayout
        aiDockState.layout = PanelRegistry.aiDefaultLayout
        deliverDockState.layout = PanelRegistry.deliverDefaultLayout
    }

    private func revealAIPanelInSelectedWorkspace() {
        let registry = persistenceRegistry
        let state = selectedWorkspaceState

        state.wrappedValue = WorkspaceDockPersistence.revealedState(
            byRevealing: .aiAssistant,
            in: state.wrappedValue,
            using: registry
        )
    }
}

private struct SettingsSheet: View {
    @Binding var isPresented: Bool
    @State private var anthropicKey: String = ""
    @State private var deepgramKey: String = ""
    @State private var saved = false

    var body: some View {
        VStack(spacing: 0) {
            UtilityPanelHeader(
                eyebrow: "CONFIGURATION",
                title: "Settings",
                subtitle: "Local keys for AI and transcription services",
                badgeCount: 0,
                showsPrimaryAction: false,
                trailingAccessory: { _ in
                    UtilityHeaderButton(icon: "xmark", action: { isPresented = false })
                }
            )

            VStack(alignment: .leading, spacing: CinematicSpacing.md) {
                settingsField(
                    label: "Anthropic API Key",
                    placeholder: "sk-ant-...",
                    value: $anthropicKey,
                    description: "Used for the AI copilot."
                )

                settingsField(
                    label: "Deepgram API Key",
                    placeholder: "Enter key...",
                    value: $deepgramKey,
                    description: "Used for transcription and search."
                )
            }
            .padding(CinematicSpacing.md)

            Spacer()

            HStack {
                if saved {
                    UtilityStatusBadge(text: "Saved - restart app", icon: "checkmark.circle.fill", style: .success)
                }
                Spacer()
                CinematicToolbarButton(icon: "square.and.arrow.down", label: "Save", isActive: true, action: saveKeys)
            }
            .padding(CinematicSpacing.md)
        }
        .frame(width: 500, height: 360)
        .panelSurface(.floating, strokeOpacity: 0.9, shadow: true)
        .onAppear { loadKeys() }
    }

    private func settingsField(label: String, placeholder: String, value: Binding<String>, description: String) -> some View {
        CinematicInspectorFieldRow(label: label) {
            VStack(alignment: .leading, spacing: 6) {
                SecureField(placeholder, text: value)
                    .textFieldStyle(.plain)
                    .font(.cinBody)
                    .padding(.horizontal, 10)
                    .frame(height: CinematicMetrics.fieldHeight)
                    .background(CinematicTheme.surfaceContainerLowest)
                    .clipShape(RoundedRectangle(cornerRadius: CinematicRadius.md))

                Text(description)
                    .font(.cinLabelRegular)
                    .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.68))
            }
        }
    }

    private func loadKeys() {
        let envURL = envFileURL()
        guard let contents = try? String(contentsOf: envURL, encoding: .utf8) else { return }
        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let eq = trimmed.firstIndex(of: "=") else { continue }
            let key = String(trimmed[..<eq])
            let val = String(trimmed[trimmed.index(after: eq)...])
            if key == "ANTHROPIC_API_KEY" { anthropicKey = val }
            if key == "DEEPGRAM_API_KEY" { deepgramKey = val }
        }
    }

    private func saveKeys() {
        var lines: [String] = []
        if !anthropicKey.isEmpty { lines.append("ANTHROPIC_API_KEY=\(anthropicKey)") }
        if !deepgramKey.isEmpty { lines.append("DEEPGRAM_API_KEY=\(deepgramKey)") }
        let content = lines.joined(separator: "\n") + "\n"

        let url = envFileURL()
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? content.write(to: url, atomically: true, encoding: .utf8)
        saved = true
    }

    private func envFileURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("VideoEditor/.env")
    }
}
