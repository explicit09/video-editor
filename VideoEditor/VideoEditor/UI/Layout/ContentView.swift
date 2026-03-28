import SwiftUI
import EditorCore

enum LeftPanelTab: String, CaseIterable, Hashable {
    case library = "Library"
    case transcript = "Transcript"
    case search = "Search"

    var icon: String {
        switch self {
        case .library: "photo.on.rectangle"
        case .transcript: "text.alignleft"
        case .search: "sparkle.magnifyingglass"
        }
    }
}

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

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedWorkspace: Workspace = .edit
    @State private var commandBarText = ""
    @State private var showSettings = false
    @State private var showExportDialog = false
    @State private var leftPanelTab: LeftPanelTab = .library
    @State private var rightRailTab: RightRailTab = .inspector
    @State private var isLeftPanelVisible = true
    @State private var isRightRailVisible = true
    @State private var editorTool: EditorTool = .selection

    enum Workspace: String, CaseIterable {
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
    }

    var body: some View {
        GeometryReader { geo in
            let layoutMode = editorLayoutMode(for: geo.size.width)

            VStack(spacing: CinematicSpacing.md) {
                topBar(layoutMode: layoutMode)

                HStack(alignment: .top, spacing: CinematicSpacing.md) {
                    sideNav

                    mainWorkspace(layoutMode: layoutMode)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, CinematicSpacing.md)
            .padding(.top, CinematicSpacing.xs)
            .padding(.bottom, CinematicSpacing.md)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(appBackground)
        }
        .frame(minWidth: 1200, minHeight: 760)
        .focusable()
        .onKeyPress("j") { stepBackward(); return .handled }
        .onKeyPress("k") { appState.playbackEngine.togglePlayPause(); return .handled }
        .onKeyPress("l") { stepForward(); return .handled }
        .onKeyPress(.leftArrow) { stepFrame(forward: false); return .handled }
        .onKeyPress(.rightArrow) { stepFrame(forward: true); return .handled }
        .onKeyPress("=") { appState.timelineViewState.zoomIn(); return .handled }
        .onKeyPress("-") { appState.timelineViewState.zoomOut(); return .handled }
        // Split at playhead
        .onKeyPress("s") { splitAtPlayhead(); return .handled }
        // Add marker at playhead
        .onKeyPress("m") { addMarkerAtPlayhead(); return .handled }
        // Select all clips (Cmd+A)
        .onKeyPress("a") {
            guard NSEvent.modifierFlags.contains(.command) else { return .ignored }
            selectAllClips(); return .handled
        }
        // Duplicate selected clips (Cmd+D)
        .onKeyPress("d") {
            guard NSEvent.modifierFlags.contains(.command) else { return .ignored }
            duplicateSelectedClips(); return .handled
        }
        // Toggle snap
        .onKeyPress("n") { appState.timelineViewState.snapEnabled.toggle(); return .handled }
        // Toggle ripple
        .onKeyPress("r") { appState.timelineViewState.rippleEnabled.toggle(); return .handled }
        // Copy (Cmd+C)
        .onKeyPress("c") {
            guard NSEvent.modifierFlags.contains(.command) else { return .ignored }
            appState.copySelectedClips(); return .handled
        }
        // Paste (Cmd+V)
        .onKeyPress("v") {
            guard NSEvent.modifierFlags.contains(.command) else { return .ignored }
            appState.pasteClips(); return .handled
        }
        .onKeyPress("1") { editorTool = .selection; return .handled }
        .onKeyPress("2") { editorTool = .blade; return .handled }
        .onKeyPress("3") { editorTool = .trim; return .handled }
        .onKeyPress(.escape) { editorTool = .selection; return .handled }
    }

    private var appBackground: some View {
        LinearGradient(
            colors: [
                CinematicTheme.surface,
                CinematicTheme.surfaceDim,
                CinematicTheme.surfaceGlass.opacity(0.55),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(CinematicTheme.primaryContainer.opacity(0.08))
                .frame(width: 320, height: 320)
                .blur(radius: 80)
                .offset(x: 120, y: -80)
        }
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
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: CinematicRadius.md)
                    .fill(
                        LinearGradient(
                            colors: [CinematicTheme.primaryContainer, CinematicTheme.tertiaryContainer.opacity(0.72)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 24, height: 24)
                    .overlay(
                        Image(systemName: "play.rectangle")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(CinematicTheme.onPrimaryContainer)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("Unified Pro Editor")
                        .font(.cinTitle)
                        .foregroundStyle(CinematicTheme.onSurface)
                    Text(selectedWorkspace.rawValue.uppercased())
                        .font(.cinLabelRegular)
                        .tracking(1.2)
                        .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.76))
                }
            }

            Spacer(minLength: 20)

            if appState.aiChat.isProcessing {
                CinematicStatusPill(
                    text: "AI ACTIVE",
                    icon: "sparkles",
                    tone: CinematicTheme.primary
                )
            }

            CinematicStatusPill(
                text: layoutMode == .compact ? "COMPACT" : "EXPANDED",
                icon: layoutMode == .compact ? "rectangle.compress.vertical" : "rectangle.expand.vertical",
                tone: CinematicTheme.aqua
            )

            HStack(spacing: 8) {
                CinematicToolbarButton(
                    icon: "sidebar.left",
                    isActive: isLeftPanelVisible,
                    action: { isLeftPanelVisible.toggle() }
                )

                CinematicToolbarButton(
                    icon: "sidebar.right",
                    isActive: isRightRailVisible,
                    action: { isRightRailVisible.toggle() }
                )
            }

            CinematicToolbarButton(icon: "square.and.arrow.up", label: "Export") {
                showExportDialog = true
            }

            CinematicToolbarButton(icon: "gearshape", action: { showSettings = true })
        }
        .padding(.horizontal, CinematicSpacing.md)
        .frame(height: CinematicMetrics.topBarHeight)
        .panelSurface(.floating, strokeOpacity: 0.82, shadow: true)
        .sheet(isPresented: $showSettings) {
            SettingsSheet(isPresented: $showSettings)
        }
        .sheet(isPresented: $showExportDialog) {
            ExportDialog(isPresented: $showExportDialog)
        }
    }

    private var sideNav: some View {
        VStack(spacing: CinematicSpacing.sm) {
            ForEach(Workspace.allCases, id: \.self) { workspace in
                sideNavItem(workspace)
            }

            Spacer(minLength: 0)

            CinematicToolbarButton(
                icon: "sparkles",
                label: "Ask AI",
                isActive: selectedWorkspace == .ai
            ) {
                selectWorkspace(.ai)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, CinematicSpacing.md)
        .frame(width: 92)
        .panelSurface(.elevated, strokeOpacity: 0.85)
    }

    private func sideNavItem(_ workspace: Workspace) -> some View {
        let isSelected = selectedWorkspace == workspace

        return Button {
            selectWorkspace(workspace)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: workspace.icon)
                    .font(.system(size: 16, weight: .semibold))
                Text(workspace.rawValue)
                    .font(.cinLabelRegular)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(isSelected ? CinematicTheme.onPrimaryContainer : CinematicTheme.onSurfaceVariant)
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .background(
                isSelected
                    ? AnyShapeStyle(
                        LinearGradient(
                            colors: [CinematicTheme.primaryContainer, CinematicTheme.tertiaryContainer.opacity(0.72)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    : AnyShapeStyle(CinematicTheme.surfaceContainerHighest.opacity(0.72))
            )
            .clipShape(RoundedRectangle(cornerRadius: CinematicRadius.lg))
        }
        .buttonStyle(.plain)
    }

    private func selectWorkspace(_ workspace: Workspace) {
        selectedWorkspace = workspace
        switch workspace {
        case .edit:
            rightRailTab = .inspector
        case .transcript:
            leftPanelTab = .transcript
            rightRailTab = .inspector
        case .media:
            leftPanelTab = .library
        case .ai:
            rightRailTab = .ai
        case .deliver:
            break
        }
    }

    @ViewBuilder
    private func mainWorkspace(layoutMode: EditorLayoutMode) -> some View {
        if appState.assets.isEmpty && appState.timeline.tracks.isEmpty && selectedWorkspace == .edit {
            EmptyStateView(commandBarText: $commandBarText, onSend: sendCommandBarMessage)
                .panelSurface(.elevated, strokeOpacity: 0.8)
        } else {
            switch selectedWorkspace {
            case .edit:
                editorWorkspace(layoutMode: layoutMode)
            case .media:
                focusedMediaWorkspace
            case .transcript:
                focusedTranscriptWorkspace(layoutMode: layoutMode)
            case .ai:
                focusedAIWorkspace(layoutMode: layoutMode)
            case .deliver:
                deliverWorkspace(layoutMode: layoutMode)
            }
        }
    }

    private func editorWorkspace(layoutMode: EditorLayoutMode) -> some View {
        HStack(alignment: .top, spacing: CinematicSpacing.md) {
            if isLeftPanelVisible {
                utilityPanel
                    .frame(width: layoutMode == .compact ? CinematicMetrics.compactSidebarWidth : CinematicMetrics.expandedSidebarWidth)
            }

            VStack(spacing: CinematicSpacing.md) {
                PreviewPanel(
                    player: appState.playbackEngine.player,
                    layoutMode: layoutMode,
                    isProcessing: appState.aiChat.isProcessing,
                    processingStatus: appState.aiChat.processingStatus,
                    currentTime: appState.playbackEngine.currentTime,
                    duration: appState.playbackEngine.duration,
                    clipCount: appState.timeline.tracks.flatMap(\.clips).count
                )

                transportBar
                commandDock

                TimelinePanel(tool: editorTool)
                    .frame(minHeight: layoutMode == .compact ? 260 : 320)
                    .panelSurface(.elevated, strokeOpacity: 0.86)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if isRightRailVisible {
                InspectorPanel(
                    selectedTab: $rightRailTab,
                    context: selectionInspectorContext,
                    layoutMode: layoutMode,
                    showsTabs: true
                )
                .frame(width: layoutMode == .compact ? CinematicMetrics.compactRightRailWidth : CinematicMetrics.expandedRightRailWidth)
            }
        }
    }

    private var utilityPanel: some View {
        VStack(spacing: 0) {
            CinematicPanelHeader(
                eyebrow: "EDITOR TOOLS",
                title: leftPanelTitle,
                subtitle: leftPanelSubtitle
            )
            .background(CinematicTheme.surfaceContainerHighest.opacity(0.72))

            HStack {
                CinematicSegmentedTabBar(
                    items: LeftPanelTab.allCases,
                    selection: $leftPanelTab,
                    label: { $0.rawValue },
                    icon: { $0.icon }
                )
                Spacer()
            }
            .padding(.horizontal, CinematicSpacing.md)
            .padding(.vertical, CinematicSpacing.sm)

            Group {
                switch leftPanelTab {
                case .library:
                    MediaBrowserPanel()
                case .transcript:
                    TranscriptPanel()
                case .search:
                    searchUtilityPanel
                }
            }
        }
        .panelSurface(.base, strokeOpacity: 0.9)
    }

    private var searchUtilityPanel: some View {
        VStack(spacing: 0) {
            if let query = appState.aiChat.lastSearchQuery,
               let results = appState.aiChat.lastSearchResults,
               !results.isEmpty {
                SearchResultsView(query: query, results: results)
            } else {
                CinematicEmptyStateBlock(
                    icon: "sparkle.magnifyingglass",
                    title: "Search your edit",
                    detail: "Use the AI rail to search transcripts or ask the editor to gather moments into a sequence."
                ) {
                    VStack(spacing: 8) {
                        CinematicStatusPill(text: "Open AI tab", icon: "sparkles", tone: CinematicTheme.primary)
                        CinematicStatusPill(text: "Search results appear here", icon: "rectangle.stack.person.crop", tone: CinematicTheme.aqua)
                    }
                }
            }
        }
        .background(CinematicTheme.surfaceContainerLow)
    }

    private var leftPanelTitle: String {
        switch leftPanelTab {
        case .library: "Library"
        case .transcript: "Transcript"
        case .search: "Search"
        }
    }

    private var leftPanelSubtitle: String {
        switch leftPanelTab {
        case .library: "Media sources, import, and drag to timeline"
        case .transcript: "Transcript access while editing"
        case .search: "AI search matches and quick sequence actions"
        }
    }

    private var transportBar: some View {
        HStack(spacing: CinematicSpacing.md) {
            Text(TimeFormatter.timecode(appState.playbackEngine.currentTime))
                .font(.cinTimecode)
                .foregroundStyle(CinematicTheme.onSurface)
                .frame(width: 118, alignment: .leading)

            HStack(spacing: 8) {
                CinematicToolbarButton(icon: "backward.end.fill") {
                    appState.playbackEngine.seek(to: 0)
                    appState.timelineViewState.playheadPosition = 0
                }

                CinematicToolbarButton(icon: appState.playbackEngine.isPlaying ? "pause.fill" : "play.fill", isActive: true) {
                    appState.playbackEngine.togglePlayPause()
                }

                CinematicToolbarButton(icon: "forward.end.fill") {
                    appState.playbackEngine.seek(to: appState.playbackEngine.duration)
                    appState.timelineViewState.playheadPosition = appState.playbackEngine.duration
                }
            }

            Spacer()

            HStack(spacing: 8) {
                CinematicSegmentedTabBar(
                    items: EditorTool.allCases,
                    selection: $editorTool,
                    label: { $0.rawValue },
                    icon: { $0.icon }
                )

                Rectangle()
                    .fill(CinematicTheme.outlineVariant.opacity(0.3))
                    .frame(width: 1, height: 20)

                editModePicker
            }
            .frame(maxWidth: 480)

            Spacer()

            Menu {
                ForEach([0.5, 1.0, 1.5, 2.0], id: \.self) { rate in
                    Button {
                        appState.playbackEngine.playbackRate = Float(rate)
                        if appState.playbackEngine.isPlaying {
                            appState.playbackEngine.player.rate = Float(rate)
                        }
                    } label: {
                        let label = rate == 1.0 ? "1x" : "\(rate == 0.5 ? "0.5" : rate == 1.5 ? "1.5" : "2")x"
                        if Float(rate) == appState.playbackEngine.playbackRate {
                            Label(label, systemImage: "checkmark")
                        } else {
                            Text(label)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "gauge.with.needle")
                        .font(.system(size: 12, weight: .semibold))
                    Text(speedLabel(for: appState.playbackEngine.playbackRate))
                        .font(.cinLabel)
                }
                .foregroundStyle(CinematicTheme.onSurface)
                .padding(.horizontal, 10)
                .frame(height: CinematicMetrics.controlHeight)
                .background(CinematicTheme.surfaceContainerHighest)
                .clipShape(Capsule())
            }
            .menuStyle(.button)

            CinematicToolbarButton(
                icon: appState.playbackEngine.loopEnabled ? "repeat" : "repeat",
                isActive: appState.playbackEngine.loopEnabled
            ) {
                appState.playbackEngine.loopEnabled.toggle()
            }
            .help(appState.playbackEngine.loopEnabled ? "Disable loop" : "Enable loop")

            Text(TimeFormatter.timecode(appState.playbackEngine.duration))
                .font(.cinTimecode)
                .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.64))
                .frame(width: 118, alignment: .trailing)
        }
        .padding(.horizontal, CinematicSpacing.md)
        .frame(height: 54)
        .panelSurface(.elevated, strokeOpacity: 0.84)
    }

    @ViewBuilder
    private var editModePicker: some View {
        @Bindable var viewState = appState.timelineViewState
        Menu {
            ForEach(TimelineViewState.EditMode.allCases, id: \.self) { mode in
                Button {
                    appState.timelineViewState.editMode = mode
                } label: {
                    Label(mode.rawValue, systemImage: mode.icon)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: appState.timelineViewState.editMode.icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(appState.timelineViewState.editMode.rawValue.prefix(3).uppercased())
                    .font(.cinLabel)
            }
            .foregroundStyle(CinematicTheme.onSurfaceVariant)
            .padding(.horizontal, 8)
            .frame(height: CinematicMetrics.controlHeight)
            .background(CinematicTheme.surfaceContainerHighest)
            .clipShape(Capsule())
        }
        .menuStyle(.button)
        .help("Edit mode: \(appState.timelineViewState.editMode.rawValue)")
    }

    private var commandDock: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .foregroundStyle(appState.aiChat.isProcessing ? CinematicTheme.primary : CinematicTheme.primary.opacity(0.68))
                .font(.system(size: 15))
                .symbolEffect(.pulse, isActive: appState.aiChat.isProcessing)

            TextField("Ask AI to search, rough cut, or transform the current edit…", text: $commandBarText)
                .textFieldStyle(.plain)
                .font(.cinBody)
                .foregroundStyle(CinematicTheme.onSurface)
                .onSubmit { sendCommandBarMessage() }
                .disabled(appState.aiChat.isProcessing)

            if appState.aiChat.isProcessing {
                ProgressView()
                    .scaleEffect(0.55)
                    .tint(CinematicTheme.primary)
            } else {
                Button(action: sendCommandBarMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(
                            commandBarText.trimmingCharacters(in: .whitespaces).isEmpty
                                ? CinematicTheme.onSurfaceVariant.opacity(0.3)
                                : CinematicTheme.primaryContainer
                        )
                }
                .buttonStyle(.plain)
                .disabled(commandBarText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
        .glassPanel(tint: CinematicTheme.surfaceGlass)
        .overlay(
            RoundedRectangle(cornerRadius: CinematicRadius.lg)
                .strokeBorder(CinematicTheme.panelStroke.opacity(0.82), lineWidth: 1)
        )
    }

    private var focusedMediaWorkspace: some View {
        MediaWorkspacePanel()
            .panelSurface(.elevated, strokeOpacity: 0.86)
    }

    private func focusedTranscriptWorkspace(layoutMode: EditorLayoutMode) -> some View {
        HStack(spacing: CinematicSpacing.md) {
            TranscriptPanel()
                .panelSurface(.elevated, strokeOpacity: 0.86)

            if isRightRailVisible {
                InspectorPanel(
                    selectedTab: $rightRailTab,
                    context: selectionInspectorContext,
                    layoutMode: layoutMode,
                    showsTabs: true
                )
                .frame(width: layoutMode == .compact ? CinematicMetrics.compactRightRailWidth : CinematicMetrics.expandedRightRailWidth)
            }
        }
    }

    private func focusedAIWorkspace(layoutMode: EditorLayoutMode) -> some View {
        InspectorPanel(
            selectedTab: $rightRailTab,
            context: selectionInspectorContext,
            layoutMode: layoutMode,
            showsTabs: false
        )
        .onAppear { rightRailTab = .ai }
        .frame(maxWidth: 760, maxHeight: .infinity)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func deliverWorkspace(layoutMode: EditorLayoutMode) -> some View {
        let trackCount = appState.timeline.tracks.count
        let clipCount = appState.clipCount
        let canExport = appState.canExportCurrentTimeline

        return HStack(spacing: CinematicSpacing.md) {
            VStack(spacing: CinematicSpacing.md) {
                CinematicCard(tone: .floating) {
                    VStack(alignment: .leading, spacing: CinematicSpacing.md) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Deliver")
                                    .font(.cinHeadline)
                                    .foregroundStyle(CinematicTheme.onSurface)
                                Text("Export presets, sequence summary, and output readiness")
                                    .font(.cinBody)
                                    .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.72))
                            }
                            Spacer()
                            CinematicStatusPill(
                                text: canExport ? "Ready" : "Needs Clips",
                                icon: canExport ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                                tone: canExport ? CinematicTheme.success : CinematicTheme.warning
                            )
                        }

                        HStack(spacing: CinematicSpacing.sm) {
                            summaryMetric(value: "\(trackCount)", label: "Tracks")
                            summaryMetric(value: "\(clipCount)", label: "Clips")
                            summaryMetric(value: TimeFormatter.duration(appState.timeline.duration), label: "Runtime")
                        }
                    }
                }

                CinematicCard {
                    VStack(alignment: .leading, spacing: CinematicSpacing.md) {
                        Text("Presets")
                            .font(.cinTitleSmall)
                            .foregroundStyle(CinematicTheme.onSurface)

                        HStack(spacing: 8) {
                            CinematicStatusPill(text: "YouTube 4K", icon: "play.rectangle.fill", tone: CinematicTheme.tertiary)
                            CinematicStatusPill(text: "YouTube 1080p", icon: "play.rectangle", tone: CinematicTheme.aqua)
                            CinematicStatusPill(text: "ProRes", icon: "film", tone: CinematicTheme.primary)
                        }

                        CinematicToolbarButton(icon: "square.and.arrow.up", label: "Open Export Dialog", isActive: true) {
                            showExportDialog = true
                        }
                        .disabled(!canExport)
                    }
                }

                // Export progress (shown during export)
                switch appState.exportEngine.state {
                case .exporting(let progress):
                    CinematicCard(tone: .elevated) {
                        VStack(alignment: .leading, spacing: CinematicSpacing.sm) {
                            HStack {
                                Text("Exporting...")
                                    .font(.cinTitleSmall)
                                    .foregroundStyle(CinematicTheme.onSurface)
                                Spacer()
                                Text("\(Int(progress * 100))%")
                                    .font(.cinTimecode)
                                    .foregroundStyle(CinematicTheme.primary)
                            }
                            ProgressView(value: Double(progress))
                                .tint(CinematicTheme.primary)
                            Button("Cancel Export") {
                                appState.exportEngine.cancel()
                            }
                            .buttonStyle(.plain)
                            .font(.cinLabelRegular)
                            .foregroundStyle(CinematicTheme.error)
                        }
                    }
                case .completed(let url):
                    CinematicCard(tone: .elevated) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(CinematicTheme.success)
                            Text("Export complete")
                                .font(.cinTitleSmall)
                                .foregroundStyle(CinematicTheme.success)
                            Spacer()
                            Button("Reveal in Finder") {
                                NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
                            }
                            .buttonStyle(.plain)
                            .font(.cinLabelRegular)
                            .foregroundStyle(CinematicTheme.primary)
                        }
                    }
                case .failed(let msg):
                    CinematicCard(tone: .elevated) {
                        HStack {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(CinematicTheme.error)
                            Text(msg)
                                .font(.cinBody)
                                .foregroundStyle(CinematicTheme.error)
                        }
                    }
                case .idle:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            if isRightRailVisible {
                InspectorPanel(
                    selectedTab: $rightRailTab,
                    context: .project,
                    layoutMode: layoutMode,
                    showsTabs: true
                )
                .frame(width: layoutMode == .compact ? CinematicMetrics.compactRightRailWidth : CinematicMetrics.expandedRightRailWidth)
            }
        }
    }

    private var selectionInspectorContext: SelectionInspectorContext {
        let selectedIDs = Array(appState.timelineViewState.selectedClipIDs)

        if selectedIDs.count == 1, let id = selectedIDs.first {
            return .clip(id)
        }

        if !selectedIDs.isEmpty {
            return .clips(selectedIDs)
        }

        if let trackID = appState.timelineViewState.selectedTrackID {
            return .track(trackID)
        }

        return .project
    }

    private func editorLayoutMode(for width: CGFloat) -> EditorLayoutMode {
        width < 1560 ? .compact : .expanded
    }

    private func summaryMetric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.cinHeadlineSmall)
                .foregroundStyle(CinematicTheme.onSurface)
            Text(label.uppercased())
                .font(.cinLabel)
                .tracking(1.2)
                .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.6))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }

    private func speedLabel(for rate: Float) -> String {
        switch rate {
        case 0.5: return "0.5x"
        case 1.0: return "1x"
        case 1.5: return "1.5x"
        case 2.0: return "2x"
        default: return String(format: "%.1fx", rate)
        }
    }

    private func sendCommandBarMessage() {
        let text = commandBarText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        commandBarText = ""
        rightRailTab = .ai
        Task {
            await appState.aiChat.send(message: text, appState: appState)
        }
    }
}

private struct SettingsSheet: View {
    @Binding var isPresented: Bool
    @State private var anthropicKey: String = ""
    @State private var deepgramKey: String = ""
    @State private var saved = false

    var body: some View {
        VStack(spacing: 0) {
            CinematicPanelHeader(
                eyebrow: "CONFIGURATION",
                title: "Settings",
                subtitle: "Local keys for AI and transcription services",
                trailingAccessory: {
                    CinematicToolbarButton(icon: "xmark", action: { isPresented = false })
                }
            )
            .background(CinematicTheme.surfaceContainerHighest.opacity(0.72))

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
                    CinematicStatusPill(text: "Saved - restart app", icon: "checkmark.circle.fill", tone: CinematicTheme.success)
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
