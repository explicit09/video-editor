import SwiftUI
import EditorCore
import AIServices

enum RightRailTab: String, CaseIterable, Hashable {
    case inspector = "Inspector"
    case ai = "AI Copilot"

    var icon: String {
        switch self {
        case .inspector: "slider.horizontal.3"
        case .ai: "sparkles"
        }
    }
}

enum SelectionInspectorContext: Equatable {
    case project
    case track(UUID)
    case clip(UUID)
    case clips([UUID])
}

struct InspectorPanel: View {
    @Environment(AppState.self) private var appState
    @Binding var selectedTab: RightRailTab
    let context: SelectionInspectorContext
    var layoutMode: EditorLayoutMode = .expanded
    var showsTabs = true

    @State private var inputText = ""

    var body: some View {
        VStack(spacing: 0) {
            CinematicPanelHeader(
                eyebrow: railEyebrow,
                title: railTitle,
                subtitle: railSubtitle,
                trailingAccessory: {
                    HStack(spacing: 8) {
                        if appState.aiChat.isProcessing && selectedTab == .ai {
                            ProgressView()
                                .scaleEffect(0.6)
                                .tint(CinematicTheme.primary)
                        }

                        if selectedTab == .ai {
                            CinematicToolbarButton(icon: "trash", isDestructive: false) {
                                appState.aiChat.clearHistory()
                            }
                            .disabled(appState.aiChat.messages.isEmpty)
                        }
                    }
                }
            )
            .background(CinematicTheme.surfaceContainerHighest.opacity(0.68))

            if showsTabs {
                HStack {
                    CinematicSegmentedTabBar(
                        items: RightRailTab.allCases,
                        selection: $selectedTab,
                        label: { $0.rawValue },
                        icon: { $0.icon }
                    )
                    Spacer()
                }
                .padding(.horizontal, CinematicSpacing.md)
                .padding(.bottom, CinematicSpacing.sm)
                .padding(.top, 2)
            }

            Group {
                switch selectedTab {
                case .inspector:
                    inspectorContent
                case .ai:
                    aiContent
                }
            }
        }
        .panelSurface(.base, strokeOpacity: 0.9)
    }

    private var railEyebrow: String {
        switch selectedTab {
        case .inspector: "CONTEXT"
        case .ai: "ASSISTANT"
        }
    }

    private var railTitle: String {
        switch selectedTab {
        case .inspector:
            switch context {
            case .project:
                return "Project Inspector"
            case .track:
                return "Track Inspector"
            case .clip:
                return "Clip Inspector"
            case .clips:
                return "Multi-Selection"
            }
        case .ai:
            return "AI Copilot"
        }
    }

    private var railSubtitle: String {
        switch selectedTab {
        case .inspector:
            switch context {
            case .project:
                return "Project summary and timeline context"
            case .track(let id):
                return resolvedTrack(id)?.name ?? "Selected track details"
            case .clip(let id):
                return resolvedClip(id)?.metadata.label ?? "Selected clip details"
            case .clips(let ids):
                return "\(ids.count) clips selected"
            }
        case .ai:
            return appState.aiChat.processingStatus ?? "Search, ask questions, and trigger edits"
        }
    }

    private var inspectorContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CinematicSpacing.md) {
                switch context {
                case .project:
                    projectInspector
                case .track(let id):
                    if let track = resolvedTrack(id) {
                        trackInspector(track)
                    } else {
                        missingSelectionState
                    }
                case .clip(let id):
                    if let clip = resolvedClip(id) {
                        clipInspector(clip)
                    } else {
                        missingSelectionState
                    }
                case .clips(let ids):
                    multiSelectionInspector(ids)
                }
            }
            .padding(CinematicSpacing.md)
        }
    }

    private var aiContent: some View {
        VStack(spacing: 0) {
            if let query = appState.aiChat.lastSearchQuery,
               let results = appState.aiChat.lastSearchResults,
               !results.isEmpty {
                SearchResultsView(query: query, results: results)
                    .frame(maxHeight: 280)
            }

            messageList
            aiInputBar
        }
    }

    private var projectInspector: some View {
        VStack(alignment: .leading, spacing: CinematicSpacing.md) {
            summaryCard
            CinematicCard {
                VStack(alignment: .leading, spacing: CinematicSpacing.md) {
                    Text("Selection")
                        .font(.cinTitleSmall)
                        .foregroundStyle(CinematicTheme.onSurface)

                    CinematicInspectorFieldRow(label: "Tracks") {
                        Text("\(appState.timeline.tracks.count) active lanes")
                            .font(.cinBody)
                            .foregroundStyle(CinematicTheme.onSurface)
                    }

                    CinematicInspectorFieldRow(label: "Assets") {
                        Text("\(appState.assets.count) imported sources")
                            .font(.cinBody)
                            .foregroundStyle(CinematicTheme.onSurface)
                    }

                    CinematicInspectorFieldRow(label: "Duration") {
                        Text(TimeFormatter.durationHMS(appState.timeline.duration))
                            .font(.cinTimecode)
                            .foregroundStyle(CinematicTheme.onSurface)
                    }
                }
            }

            CinematicCard {
                VStack(alignment: .leading, spacing: CinematicSpacing.sm) {
                    Text("Quick Actions")
                        .font(.cinTitleSmall)
                        .foregroundStyle(CinematicTheme.onSurface)

                    HStack(spacing: 8) {
                        CinematicStatusPill(text: "\(appState.timeline.tracks.flatMap(\.clips).count) clips", icon: "rectangle.stack", tone: CinematicTheme.tertiary)
                        CinematicStatusPill(text: "\(appState.commandHistory.canUndo ? "Undo ready" : "History clean")", icon: "arrow.uturn.backward", tone: CinematicTheme.aqua)
                    }
                }
            }
        }
    }

    private var summaryCard: some View {
        CinematicCard(tone: .floating) {
            VStack(alignment: .leading, spacing: CinematicSpacing.sm) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Editor State")
                            .font(.cinHeadlineSmall)
                            .foregroundStyle(CinematicTheme.onSurface)
                        Text("Current timeline overview")
                            .font(.cinLabelRegular)
                            .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.72))
                    }
                    Spacer()
                    CinematicStatusPill(
                        text: appState.playbackEngine.isPlaying ? "Playing" : "Idle",
                        icon: appState.playbackEngine.isPlaying ? "play.fill" : "pause.fill",
                        tone: appState.playbackEngine.isPlaying ? CinematicTheme.success : CinematicTheme.warning
                    )
                }

                HStack(spacing: CinematicSpacing.sm) {
                    summaryMetric(value: "\(appState.timeline.tracks.count)", label: "Tracks")
                    summaryMetric(value: "\(appState.timeline.tracks.flatMap(\.clips).count)", label: "Clips")
                    summaryMetric(value: TimeFormatter.duration(appState.timeline.duration), label: "Runtime")
                }
            }
        }
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

    private func trackInspector(_ track: Track) -> some View {
        VStack(alignment: .leading, spacing: CinematicSpacing.md) {
            CinematicCard {
                VStack(alignment: .leading, spacing: CinematicSpacing.md) {
                    Text("Track")
                        .font(.cinTitleSmall)
                        .foregroundStyle(CinematicTheme.onSurface)

                    CinematicInspectorFieldRow(label: "Name") {
                        TextField("Track name", text: Binding(
                            get: { resolvedTrack(track.id)?.name ?? track.name },
                            set: { newValue in
                                appState.updateTrack(id: track.id) { $0.name = newValue }
                            }
                        ))
                        .textFieldStyle(.plain)
                        .font(.cinBody)
                        .padding(.horizontal, 10)
                        .frame(height: CinematicMetrics.fieldHeight)
                        .background(CinematicTheme.surfaceContainerLowest)
                        .clipShape(RoundedRectangle(cornerRadius: CinematicRadius.md))
                    }

                    HStack(spacing: 8) {
                        trackTogglePill(
                            icon: track.type == .audio ? "speaker.wave.2.fill" : "eye.fill",
                            label: track.isMuted ? "Muted" : "Active",
                            isOn: !track.isMuted
                        ) {
                            appState.updateTrack(id: track.id) { $0.isMuted.toggle() }
                        }

                        trackTogglePill(
                            icon: track.isLocked ? "lock.fill" : "lock.open.fill",
                            label: track.isLocked ? "Locked" : "Unlocked",
                            isOn: track.isLocked
                        ) {
                            appState.updateTrack(id: track.id) { $0.isLocked.toggle() }
                        }
                    }

                    CinematicInspectorFieldRow(label: "Type") {
                        Text(track.type.rawValue.capitalized)
                            .font(.cinBody)
                            .foregroundStyle(CinematicTheme.onSurface)
                    }

                    CinematicInspectorFieldRow(label: "Clips") {
                        Text("\(track.clips.count)")
                            .font(.cinBody)
                            .foregroundStyle(CinematicTheme.onSurface)
                    }

                    CinematicInspectorFieldRow(label: "Range") {
                        Text(trackRangeText(track))
                            .font(.cinBody)
                            .foregroundStyle(CinematicTheme.onSurface)
                    }
                }
            }

            CinematicCard {
                VStack(alignment: .leading, spacing: CinematicSpacing.sm) {
                    Text("Lane Actions")
                        .font(.cinTitleSmall)
                        .foregroundStyle(CinematicTheme.onSurface)

                    HStack(spacing: 8) {
                        CinematicToolbarButton(icon: "plus", label: "Add \(track.type.rawValue.capitalized)") {
                            appState.addTrack(of: track.type)
                        }

                        if track.clips.isEmpty {
                            CinematicToolbarButton(icon: "trash", label: "Remove", isDestructive: true) {
                                try? appState.perform(.removeTrack(trackID: track.id))
                            }
                        }
                    }
                }
            }
        }
    }

    private func trackTogglePill(icon: String, label: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(label)
                    .font(.cinLabelRegular)
            }
            .foregroundStyle(isOn ? CinematicTheme.onPrimaryContainer : CinematicTheme.onSurfaceVariant)
            .padding(.horizontal, 12)
            .frame(height: CinematicMetrics.controlHeight)
            .background(isOn ? CinematicTheme.primaryContainer : CinematicTheme.surfaceContainerHighest)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func clipInspector(_ clip: Clip) -> some View {
        let asset = appState.assets.first(where: { $0.id == clip.assetID })
        let track = appState.timeline.tracks.first { track in
            track.clips.contains(where: { $0.id == clip.id })
        }

        return VStack(alignment: .leading, spacing: CinematicSpacing.md) {
            CinematicCard {
                VStack(alignment: .leading, spacing: CinematicSpacing.md) {
                    Text("Clip")
                        .font(.cinTitleSmall)
                        .foregroundStyle(CinematicTheme.onSurface)

                    CinematicInspectorFieldRow(label: "Label") {
                        TextField("Clip label", text: Binding(
                            get: { resolvedClip(clip.id)?.metadata.label ?? clip.metadata.label ?? "" },
                            set: { newValue in
                                appState.updateClip(id: clip.id) { $0.metadata.label = newValue }
                            }
                        ))
                        .textFieldStyle(.plain)
                        .font(.cinBody)
                        .padding(.horizontal, 10)
                        .frame(height: CinematicMetrics.fieldHeight)
                        .background(CinematicTheme.surfaceContainerLowest)
                        .clipShape(RoundedRectangle(cornerRadius: CinematicRadius.md))
                    }

                    CinematicInspectorFieldRow(label: "Asset") {
                        Text(asset?.name ?? clip.assetID.uuidString)
                            .font(.cinBody)
                            .foregroundStyle(CinematicTheme.onSurface)
                            .lineLimit(1)
                    }

                    HStack(spacing: CinematicSpacing.sm) {
                        metricField(label: "Timeline In", value: TimeFormatter.durationHMS(clip.timelineRange.start))
                        metricField(label: "Duration", value: TimeFormatter.durationHMS(clip.timelineRange.duration))
                    }

                    HStack(spacing: CinematicSpacing.sm) {
                        metricField(label: "Source In", value: TimeFormatter.durationHMS(clip.sourceRange.start))
                        metricField(label: "Source Out", value: TimeFormatter.durationHMS(clip.sourceRange.end))
                    }

                    if let track {
                        CinematicInspectorFieldRow(label: "Track") {
                            Text(track.name)
                                .font(.cinBody)
                                .foregroundStyle(CinematicTheme.onSurface)
                        }
                    }
                }
            }

            if let asset {
                CinematicCard {
                    VStack(alignment: .leading, spacing: CinematicSpacing.sm) {
                        Text("Source Metadata")
                            .font(.cinTitleSmall)
                            .foregroundStyle(CinematicTheme.onSurface)

                        HStack(spacing: 8) {
                            CinematicStatusPill(text: asset.type.rawValue.capitalized, icon: asset.type == .audio ? "waveform" : asset.type == .video ? "film" : "photo", tone: asset.type == .audio ? CinematicTheme.success : CinematicTheme.tertiary)
                            if let codec = asset.codec {
                                CinematicStatusPill(text: codec.uppercased(), icon: "cpu", tone: CinematicTheme.aqua)
                            }
                        }
                    }
                }
            }
        }
    }

    private func metricField(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.cinLabel)
                .tracking(1.1)
                .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.6))
            Text(value)
                .font(.cinTimecode)
                .foregroundStyle(CinematicTheme.onSurface)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func multiSelectionInspector(_ ids: [UUID]) -> some View {
        let selectedClips = ids.compactMap(resolvedClip)
        return VStack(alignment: .leading, spacing: CinematicSpacing.md) {
            CinematicCard {
                VStack(alignment: .leading, spacing: CinematicSpacing.sm) {
                    Text("Batch Selection")
                        .font(.cinTitleSmall)
                        .foregroundStyle(CinematicTheme.onSurface)
                    Text("\(selectedClips.count) clips selected across \(Set(selectedClips.map(\.assetID)).count) sources")
                        .font(.cinBody)
                        .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.72))
                }
            }

            CinematicCard {
                VStack(alignment: .leading, spacing: CinematicSpacing.sm) {
                    Text("Selection Actions")
                        .font(.cinTitleSmall)
                        .foregroundStyle(CinematicTheme.onSurface)

                    HStack(spacing: 8) {
                        CinematicToolbarButton(icon: "trash", label: "Delete", isDestructive: true) {
                            try? appState.perform(.deleteClips(clipIDs: ids))
                            appState.timelineViewState.clearSelection()
                        }

                        CinematicToolbarButton(icon: "xmark", label: "Clear") {
                            appState.timelineViewState.clearSelection()
                        }
                    }
                }
            }
        }
    }

    private var missingSelectionState: some View {
        CinematicEmptyStateBlock(
            icon: "questionmark.square.dashed",
            title: "Selection not available",
            detail: "The selected item could not be resolved from the current timeline state."
        )
        .frame(minHeight: 320)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if appState.aiChat.messages.isEmpty && !appState.aiChat.isProcessing {
                        CinematicEmptyStateBlock(
                            icon: "sparkles",
                            title: "Ask AI to work with this edit",
                            detail: "Search, summarize, or ask for clip operations without leaving the editor."
                        ) {
                            VStack(spacing: 8) {
                                suggestionPill("\"Find the section about pricing\"")
                                suggestionPill("\"Create a rough cut from the best moments\"")
                                suggestionPill("\"Remove silent gaps from selected clips\"")
                            }
                        }
                        .frame(minHeight: layoutMode == .compact ? 280 : 360)
                    }

                    ForEach(appState.aiChat.messages) { msg in
                        ChatBubble(message: msg)
                            .id(msg.id)
                    }

                    if let status = appState.aiChat.processingStatus {
                        processingIndicator(status)
                            .id("processing-status")
                    } else if appState.aiChat.isProcessing {
                        processingIndicator("Thinking...")
                            .id("processing-status")
                    }
                }
                .padding(CinematicSpacing.md)
            }
            .onChange(of: appState.aiChat.messages.count) {
                if let last = appState.aiChat.messages.last {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func suggestionPill(_ text: String) -> some View {
        Text(text)
            .font(.cinLabelRegular)
            .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.7))
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(CinematicTheme.surfaceContainerHighest.opacity(0.68))
            .clipShape(Capsule())
    }

    private func processingIndicator(_ status: String) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.55)
                .tint(CinematicTheme.primary)
            Text(status)
                .font(.cinLabelRegular)
                .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.76))
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(CinematicTheme.surfaceContainerLowest)
        .clipShape(RoundedRectangle(cornerRadius: CinematicRadius.md))
    }

    private var aiInputBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 12))
                .foregroundStyle(CinematicTheme.primary.opacity(0.76))

            TextField("Ask AI to search, edit, or explain...", text: $inputText)
                .textFieldStyle(.plain)
                .font(.cinBody)
                .foregroundStyle(CinematicTheme.onSurface)
                .onSubmit { sendMessage() }

            Button(action: sendMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(
                        inputText.trimmingCharacters(in: .whitespaces).isEmpty
                            ? CinematicTheme.onSurfaceVariant.opacity(0.3)
                            : CinematicTheme.primaryContainer
                    )
            }
            .buttonStyle(.plain)
            .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || appState.aiChat.isProcessing)
        }
        .padding(.horizontal, 12)
        .frame(height: 52)
        .background(CinematicTheme.surfaceContainerHighest.opacity(0.72))
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        inputText = ""
        Task {
            await appState.aiChat.send(message: text, appState: appState)
        }
    }

    private func resolvedTrack(_ id: UUID) -> Track? {
        appState.timeline.tracks.first(where: { $0.id == id })
    }

    private func resolvedClip(_ id: UUID) -> Clip? {
        appState.timeline.tracks.flatMap(\.clips).first(where: { $0.id == id })
    }

    private func trackRangeText(_ track: Track) -> String {
        guard let start = track.clips.map(\.timelineRange.start).min(),
              let end = track.clips.map(\.timelineRange.end).max() else {
            return "Empty"
        }
        return "\(TimeFormatter.durationHMS(start)) - \(TimeFormatter.durationHMS(end))"
    }
}

struct ChatBubble: View {
    let message: AIChatController.ChatMessage

    var body: some View {
        VStack(alignment: alignment == .trailing ? .trailing : .leading, spacing: 4) {
            Text(message.content)
                .font(.cinBody)
                .foregroundStyle(CinematicTheme.onSurface)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(bubbleBackground)
                .clipShape(RoundedRectangle(cornerRadius: CinematicRadius.lg))

            ForEach(message.toolResults.indices, id: \.self) { index in
                let result = message.toolResults[index]
                HStack(spacing: 5) {
                    Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(result.success ? CinematicTheme.success : CinematicTheme.error)
                        .font(.system(size: 10))
                    Text(result.toolName)
                        .font(.cinLabelRegular)
                        .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.7))
                }
                .padding(.leading, 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment)
    }

    private var alignment: Alignment {
        message.role == .user ? .trailing : .leading
    }

    private var bubbleBackground: Color {
        switch message.role {
        case .user:
            return CinematicTheme.primaryContainer.opacity(0.18)
        case .assistant:
            return CinematicTheme.surfaceContainerHighest
        case .system:
            return CinematicTheme.errorContainer.opacity(0.2)
        }
    }
}
