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

    static func resolve(
        selectedClipIDs: Set<UUID>,
        selectedTrackID: UUID?
    ) -> Self {
        let orderedClipIDs = selectedClipIDs.sorted { $0.uuidString < $1.uuidString }

        if orderedClipIDs.count == 1, let clipID = orderedClipIDs.first {
            return .clip(clipID)
        }

        if !orderedClipIDs.isEmpty {
            return .clips(orderedClipIDs)
        }

        if let selectedTrackID {
            return .track(selectedTrackID)
        }

        return .project
    }
}

struct InspectorPanel: View {
    @Environment(AppState.self) private var appState
    @Binding var selectedTab: RightRailTab
    let context: SelectionInspectorContext
    var layoutMode: EditorLayoutMode = .expanded
    var showsTabs = true

    @State private var inputText = ""
    @State private var trackNameDraft = ""
    @FocusState private var isTrackNameFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            UtilityPanelHeader(
                eyebrow: railEyebrow,
                title: railTitle,
                subtitle: railSubtitle,
                badgeCount: selectedTab == .ai && appState.aiChat.isProcessing ? 1 : 0,
                showsPrimaryAction: selectedTab == .ai,
                trailingAccessory: { layout in
                    HStack(spacing: 8) {
                        if selectedTab == .ai && layout.showsSecondaryBadges && appState.aiChat.isProcessing {
                            UtilityHeaderBadge(
                                text: appState.aiChat.processingStatus ?? "Thinking",
                                systemImage: "sparkles",
                                style: .info
                            )
                        }

                        if selectedTab == .ai {
                            UtilityHeaderButton(icon: "trash", action: {
                                appState.aiChat.clearHistory()
                            })
                            .disabled(appState.aiChat.messages.isEmpty)
                        }
                    }
                }
            )

            if showsTabs {
                HStack {
                    UtilitySegmentedControl(
                        items: RightRailTab.allCases,
                        selection: $selectedTab,
                        availableWidth: 220,
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
                    UtilityStatusBadge(text: "\(appState.timeline.tracks.flatMap(\.clips).count) clips", icon: "rectangle.stack")
                        UtilityStatusBadge(text: "\(appState.commandHistory.canUndo ? "Undo ready" : "History clean")", icon: "arrow.uturn.backward", style: .info)
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
                    UtilityStatusBadge(
                        text: appState.playbackEngine.isPlaying ? "Playing" : "Idle",
                        icon: appState.playbackEngine.isPlaying ? "play.fill" : "pause.fill",
                        style: appState.playbackEngine.isPlaying ? .success : .warning
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
                        TextField("Track name", text: $trackNameDraft)
                        .textFieldStyle(.plain)
                        .font(.cinBody)
                        .focused($isTrackNameFocused)
                        .padding(.horizontal, 10)
                        .frame(height: CinematicMetrics.fieldHeight)
                        .background(CinematicTheme.surfaceContainerLowest)
                        .clipShape(RoundedRectangle(cornerRadius: CinematicRadius.md))
                        .onAppear {
                            trackNameDraft = track.name
                        }
                        .onSubmit {
                            commitTrackRename(track)
                        }
                        .onChange(of: isTrackNameFocused) { _, focused in
                            if !focused {
                                commitTrackRenameIfNeeded(track)
                            }
                        }
                        .onChange(of: track.name) { _, newValue in
                            if !isTrackNameFocused && trackNameDraft != newValue {
                                trackNameDraft = newValue
                            }
                        }
                        .onDisappear {
                            commitTrackRenameIfNeeded(track)
                        }
                    }

                    HStack(spacing: 8) {
                        CinematicToolbarButton(
                            icon: "target",
                            label: viewStateTargetLabel(for: track),
                            isActive: appState.timelineViewState.armedTrackID == track.id
                        ) {
                            appState.timelineViewState.toggleArmedTrack(track.id)
                        }

                        trackTogglePill(
                            icon: track.type == .audio ? "speaker.wave.2.fill" : "eye.fill",
                            label: track.isMuted ? "Muted" : "Active",
                            isOn: !track.isMuted
                        ) {
                            try? appState.perform(.muteTrack(trackID: track.id, muted: !track.isMuted))
                        }

                        trackTogglePill(
                            icon: track.isLocked ? "lock.fill" : "lock.open.fill",
                            label: track.isLocked ? "Locked" : "Unlocked",
                            isOn: track.isLocked
                        ) {
                            try? appState.perform(.lockTrack(trackID: track.id, locked: !track.isLocked))
                        }

                        trackTogglePill(
                            icon: "headphones",
                            label: track.isSoloed ? "Solo" : "Normal",
                            isOn: track.isSoloed
                        ) {
                            try? appState.perform(.soloTrack(trackID: track.id, soloed: !track.isSoloed))
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
                            appState.addTrack(of: track.type, positionedAfter: track.id)
                        }

                        if track.clips.isEmpty && !track.isLocked {
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

    private func viewStateTargetLabel(for track: Track) -> String {
        appState.timelineViewState.armedTrackID == track.id ? "Armed" : "Target"
    }

    private func commitTrackRename(_ track: Track) {
        let trimmed = trackNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextName = trimmed.isEmpty ? defaultTrackName(for: track) : trimmed
        trackNameDraft = nextName
        appState.renameTrack(id: track.id, to: nextName)
        isTrackNameFocused = false
    }

    private func commitTrackRenameIfNeeded(_ track: Track) {
        let trimmed = trackNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextName = trimmed.isEmpty ? defaultTrackName(for: track) : trimmed
        guard nextName != track.name else { return }
        commitTrackRename(track)
    }

    private func defaultTrackName(for track: Track) -> String {
        track.name.isEmpty ? "\(track.type.rawValue.capitalized) Track" : track.name
    }

    private func clipInspector(_ clip: Clip) -> some View {
        let asset = appState.assets.first(where: { $0.id == clip.assetID })
        let currentClip = resolvedClip(clip.id) ?? clip
        let track = appState.timeline.tracks.first { track in
            track.clips.contains(where: { $0.id == clip.id })
        }
        let neighbors = adjacentClips(for: clip.id)
        let frameStep = 1.0 / max(appState.context.timelineState.projectSettings.frameRate, 1)

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

            CinematicCard {
                VStack(alignment: .leading, spacing: CinematicSpacing.md) {
                    Text("Edit")
                        .font(.cinTitleSmall)
                        .foregroundStyle(CinematicTheme.onSurface)

                    CinematicInspectorFieldRow(label: "Slip") {
                        HStack(spacing: 8) {
                            editNudgeButton("-1f") {
                                try? appState.perform(.slipClip(clipID: currentClip.id, delta: -frameStep))
                            }
                            editNudgeButton("+1f") {
                                try? appState.perform(.slipClip(clipID: currentClip.id, delta: frameStep))
                            }
                            editNudgeButton("-1s") {
                                try? appState.perform(.slipClip(clipID: currentClip.id, delta: -1))
                            }
                            editNudgeButton("+1s") {
                                try? appState.perform(.slipClip(clipID: currentClip.id, delta: 1))
                            }
                        }
                    }

                    CinematicInspectorFieldRow(label: "Roll") {
                        HStack(spacing: 8) {
                            editNudgeButton("Earlier") {
                                guard let left = neighbors.left else { return }
                                try? appState.perform(
                                    .rollTrim(
                                        leftClipID: left.id,
                                        rightClipID: currentClip.id,
                                        newBoundary: currentClip.timelineRange.start - frameStep
                                    )
                                )
                            }
                            .disabled(neighbors.left == nil)

                            editNudgeButton("Later") {
                                guard let right = neighbors.right else { return }
                                try? appState.perform(
                                    .rollTrim(
                                        leftClipID: currentClip.id,
                                        rightClipID: right.id,
                                        newBoundary: currentClip.timelineRange.end + frameStep
                                    )
                                )
                            }
                            .disabled(neighbors.right == nil)
                        }
                    }
                }
            }

            // Volume & Opacity controls
            CinematicCard {
                VStack(alignment: .leading, spacing: CinematicSpacing.md) {
                    Text("Properties")
                        .font(.cinTitleSmall)
                        .foregroundStyle(CinematicTheme.onSurface)

                    CinematicInspectorFieldRow(label: "Volume") {
                        HStack(spacing: 8) {
                            Image(systemName: "speaker.wave.2")
                                .font(.system(size: 11))
                                .foregroundStyle(CinematicTheme.onSurfaceVariant)
                            Slider(value: Binding(
                                get: { resolvedClip(clip.id)?.volume ?? clip.volume },
                                set: { try? appState.perform(.setClipVolume(clipID: clip.id, volume: $0)) }
                            ), in: 0...2)
                            .tint(CinematicTheme.primary)
                            Text("\(Int((resolvedClip(clip.id)?.volume ?? clip.volume) * 100))%")
                                .font(.cinLabelRegular)
                                .monospacedDigit()
                                .foregroundStyle(CinematicTheme.onSurfaceVariant)
                                .frame(width: 36, alignment: .trailing)
                        }
                    }

                    CinematicInspectorFieldRow(label: "Opacity") {
                        HStack(spacing: 8) {
                            Image(systemName: "circle.lefthalf.filled")
                                .font(.system(size: 11))
                                .foregroundStyle(CinematicTheme.onSurfaceVariant)
                            Slider(value: Binding(
                                get: { resolvedClip(clip.id)?.opacity ?? clip.opacity },
                                set: { try? appState.perform(.setClipOpacity(clipID: clip.id, opacity: $0)) }
                            ), in: 0...1)
                            .tint(CinematicTheme.tertiary)
                            Text("\(Int((resolvedClip(clip.id)?.opacity ?? clip.opacity) * 100))%")
                                .font(.cinLabelRegular)
                                .monospacedDigit()
                                .foregroundStyle(CinematicTheme.onSurfaceVariant)
                                .frame(width: 36, alignment: .trailing)
                        }
                    }
                }
            }

            // Transform controls
            CinematicCard {
                VStack(alignment: .leading, spacing: CinematicSpacing.md) {
                    Text("Transform")
                        .font(.cinTitleSmall)
                        .foregroundStyle(CinematicTheme.onSurface)

                    let transform = resolvedClip(clip.id)?.transform ?? clip.transform

                    transformSlider(label: "Position X", value: transform.positionX, range: -1000...1000) { val in
                        var t = transform; t.positionX = val
                        try? appState.perform(.setClipTransform(clipID: clip.id, transform: t))
                    }
                    transformSlider(label: "Position Y", value: transform.positionY, range: -1000...1000) { val in
                        var t = transform; t.positionY = val
                        try? appState.perform(.setClipTransform(clipID: clip.id, transform: t))
                    }
                    transformSlider(label: "Scale X", value: transform.scaleX, range: 0.1...4.0) { val in
                        var t = transform; t.scaleX = val
                        try? appState.perform(.setClipTransform(clipID: clip.id, transform: t))
                    }
                    transformSlider(label: "Scale Y", value: transform.scaleY, range: 0.1...4.0) { val in
                        var t = transform; t.scaleY = val
                        try? appState.perform(.setClipTransform(clipID: clip.id, transform: t))
                    }
                    transformSlider(label: "Rotation", value: transform.rotation, range: -360...360) { val in
                        var t = transform; t.rotation = val
                        try? appState.perform(.setClipTransform(clipID: clip.id, transform: t))
                    }

                    Button("Reset Transform") {
                        try? appState.perform(.setClipTransform(clipID: clip.id, transform: .identity))
                    }
                    .font(.cinLabelRegular)
                    .foregroundStyle(CinematicTheme.primary)
                    .buttonStyle(.plain)
                }
            }

            if track?.type != .audio {
                OverlayPresentationSection(
                    clip: currentClip,
                    applyPreset: { preset in
                        try? appState.perform(.applyClipPiPPreset(clipID: clip.id, preset: preset))
                    },
                    updatePresentation: { presentation in
                        try? appState.perform(.setClipOverlayPresentation(clipID: clip.id, presentation: presentation))
                    }
                )
            }

            if track?.type != .audio {
                CinematicCard {
                    VStack(alignment: .leading, spacing: CinematicSpacing.md) {
                        Text("Crop")
                            .font(.cinTitleSmall)
                            .foregroundStyle(CinematicTheme.onSurface)

                        let cropRect = resolvedClip(clip.id)?.cropRect ?? clip.cropRect

                        cropSlider(label: "X", value: cropRect.x) { val in
                            try? appState.perform(
                                .setClipCrop(
                                    clipID: clip.id,
                                    cropRect: CropRect(
                                        x: val,
                                        y: cropRect.y,
                                        width: cropRect.width,
                                        height: cropRect.height
                                    )
                                )
                            )
                        }
                        cropSlider(label: "Y", value: cropRect.y) { val in
                            try? appState.perform(
                                .setClipCrop(
                                    clipID: clip.id,
                                    cropRect: CropRect(
                                        x: cropRect.x,
                                        y: val,
                                        width: cropRect.width,
                                        height: cropRect.height
                                    )
                                )
                            )
                        }
                        cropSlider(label: "Width", value: cropRect.width) { val in
                            try? appState.perform(
                                .setClipCrop(
                                    clipID: clip.id,
                                    cropRect: CropRect(
                                        x: cropRect.x,
                                        y: cropRect.y,
                                        width: val,
                                        height: cropRect.height
                                    )
                                )
                            )
                        }
                        cropSlider(label: "Height", value: cropRect.height) { val in
                            try? appState.perform(
                                .setClipCrop(
                                    clipID: clip.id,
                                    cropRect: CropRect(
                                        x: cropRect.x,
                                        y: cropRect.y,
                                        width: cropRect.width,
                                        height: val
                                    )
                                )
                            )
                        }

                        Button("Reset Crop") {
                            try? appState.perform(.setClipCrop(clipID: clip.id, cropRect: .fullFrame))
                        }
                        .font(.cinLabelRegular)
                        .foregroundStyle(CinematicTheme.primary)
                        .buttonStyle(.plain)
                    }
                }
            }

            // Effects
            CinematicCard {
                VStack(alignment: .leading, spacing: CinematicSpacing.md) {
                    HStack {
                        Text("Effects")
                            .font(.cinTitleSmall)
                            .foregroundStyle(CinematicTheme.onSurface)
                        Spacer()
                        effectsAddMenu(clipID: clip.id)
                    }

                    let currentClip = resolvedClip(clip.id) ?? clip
                    if currentClip.effects.isEmpty {
                        Text("No effects applied")
                            .font(.cinLabelRegular)
                            .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.5))
                    } else {
                        ForEach(currentClip.effects) { effect in
                            effectRow(effect: effect, clipID: clip.id)
                        }
                    }
                }
            }

            // Speed & Blend Mode
            CinematicCard {
                VStack(alignment: .leading, spacing: CinematicSpacing.md) {
                    Text("Playback")
                        .font(.cinTitleSmall)
                        .foregroundStyle(CinematicTheme.onSurface)

                    CinematicInspectorFieldRow(label: "Speed") {
                        HStack(spacing: 8) {
                            Image(systemName: "gauge.with.needle")
                                .font(.system(size: 11))
                                .foregroundStyle(CinematicTheme.onSurfaceVariant)
                            Slider(value: Binding(
                                get: { resolvedClip(clip.id)?.speed ?? clip.speed },
                                set: { try? appState.perform(.setClipSpeed(clipID: clip.id, speed: $0)) }
                            ), in: 0.1...4.0)
                            .tint(CinematicTheme.tertiary)
                            Text("\(String(format: "%.1f", resolvedClip(clip.id)?.speed ?? clip.speed))x")
                                .font(.cinLabelRegular)
                                .monospacedDigit()
                                .foregroundStyle(CinematicTheme.onSurfaceVariant)
                                .frame(width: 36, alignment: .trailing)
                        }
                    }

                    CinematicInspectorFieldRow(label: "Blend") {
                        Picker("", selection: Binding(
                            get: { resolvedClip(clip.id)?.blendMode ?? clip.blendMode },
                            set: { try? appState.perform(.setClipBlendMode(clipID: clip.id, blendMode: $0)) }
                        )) {
                            ForEach(BlendMode.allCases, id: \.self) { mode in
                                Text(mode.rawValue.localizedCapitalized).tag(mode)
                            }
                        }
                        .labelsHidden()
                    }
                }
            }

            if track?.type != .audio {
                CinematicCard {
                    VStack(alignment: .leading, spacing: CinematicSpacing.md) {
                        Text("Transition")
                            .font(.cinTitleSmall)
                            .foregroundStyle(CinematicTheme.onSurface)

                        let currentTransition = resolvedClip(clip.id)?.transitionIn ?? clip.transitionIn

                        CinematicInspectorFieldRow(label: "Type") {
                            Picker("", selection: Binding(
                                get: { currentTransition.type },
                                set: { newType in
                                    let nextDuration = newType == .none ? 0 : max(currentTransition.duration, 0.1)
                                    try? appState.perform(
                                        .setClipTransition(
                                            clipID: clip.id,
                                            transition: ClipTransition(type: newType, duration: nextDuration)
                                        )
                                    )
                                }
                            )) {
                                ForEach(TransitionType.allCases, id: \.self) { type in
                                    Text(transitionName(for: type)).tag(type)
                                }
                            }
                            .labelsHidden()
                        }

                        if currentTransition.type != .none {
                            CinematicInspectorFieldRow(label: "Duration") {
                                HStack(spacing: 8) {
                                    Slider(value: Binding(
                                        get: { currentTransition.duration },
                                        set: { newDuration in
                                            try? appState.perform(
                                                .setClipTransition(
                                                    clipID: clip.id,
                                                    transition: ClipTransition(
                                                        type: currentTransition.type,
                                                        duration: newDuration
                                                    )
                                                )
                                            )
                                        }
                                    ), in: 0.1...2.0)
                                    .tint(CinematicTheme.primary)

                                    Text(String(format: "%.1fs", currentTransition.duration))
                                        .font(.cinLabelRegular)
                                        .monospacedDigit()
                                        .foregroundStyle(CinematicTheme.onSurfaceVariant)
                                        .frame(width: 42, alignment: .trailing)
                                }
                            }
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
                            UtilityStatusBadge(
                                text: asset.type.rawValue.capitalized,
                                icon: asset.type == .audio ? "waveform" : asset.type == .video ? "film" : "photo",
                                style: asset.type == .audio ? .success : .info
                            )
                            if let codec = asset.codec {
                                UtilityStatusBadge(text: codec.uppercased(), icon: "cpu", style: .neutral)
                            }
                        }
                    }
                }
            }
        }
    }

    private func transformSlider(label: String, value: Double, range: ClosedRange<Double>, onChange: @escaping (Double) -> Void) -> some View {
        CinematicInspectorFieldRow(label: label) {
            HStack(spacing: 6) {
                Slider(value: Binding(get: { value }, set: { onChange($0) }), in: range)
                    .tint(CinematicTheme.aqua)
                Text(String(format: "%.1f", value))
                    .font(.cinLabelRegular)
                    .monospacedDigit()
                    .foregroundStyle(CinematicTheme.onSurfaceVariant)
                    .frame(width: 40, alignment: .trailing)
            }
        }
    }

    private func cropSlider(label: String, value: Double, onChange: @escaping (Double) -> Void) -> some View {
        CinematicInspectorFieldRow(label: label) {
            HStack(spacing: 6) {
                Slider(value: Binding(get: { value }, set: { onChange($0) }), in: 0...1)
                    .tint(CinematicTheme.success)
                Text(String(format: "%.2f", value))
                    .font(.cinLabelRegular)
                    .monospacedDigit()
                    .foregroundStyle(CinematicTheme.onSurfaceVariant)
                    .frame(width: 40, alignment: .trailing)
            }
        }
    }

    private func effectsAddMenu(clipID: UUID) -> some View {
        Menu {
            Button("Color Correction") {
                let effect = EffectInstance(type: "colorCorrection", parameters: ["brightness": 0, "contrast": 1, "saturation": 1])
                try? appState.perform(.setClipEffect(clipID: clipID, effect: effect))
            }
            Button("Blur") {
                let effect = EffectInstance(type: "blur", parameters: ["radius": 5])
                try? appState.perform(.setClipEffect(clipID: clipID, effect: effect))
            }
            Button("Sharpen") {
                let effect = EffectInstance(type: "sharpen", parameters: ["sharpness": 0.5])
                try? appState.perform(.setClipEffect(clipID: clipID, effect: effect))
            }
        } label: {
            Image(systemName: "plus.circle")
                .font(.system(size: 14))
                .foregroundStyle(CinematicTheme.primary)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
    }

    private func effectRow(effect: EffectInstance, clipID: UUID) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "sparkle")
                    .font(.system(size: 10))
                    .foregroundStyle(CinematicTheme.tertiary)
                Text(effect.type.localizedCapitalized)
                    .font(.cinLabelRegular)
                    .foregroundStyle(CinematicTheme.onSurface)
                Spacer()
                Button {
                    try? appState.perform(.removeClipEffect(clipID: clipID, effectID: effect.id))
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(CinematicTheme.error.opacity(0.7))
                }
                .buttonStyle(.plain)
            }

            // Show parameter sliders
            ForEach(effect.parameters.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                HStack(spacing: 6) {
                    Text(key)
                        .font(.cinLabelRegular)
                        .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.7))
                        .frame(width: 70, alignment: .trailing)
                    Slider(value: Binding(
                        get: { value },
                        set: { newVal in
                            var updatedEffect = effect
                            updatedEffect.parameters[key] = newVal
                            try? appState.perform(.setClipEffect(clipID: clipID, effect: updatedEffect))
                        }
                    ), in: parameterRange(for: key))
                    .tint(CinematicTheme.tertiary)
                    Text(String(format: "%.2f", value))
                        .font(.cinLabelRegular)
                        .monospacedDigit()
                        .foregroundStyle(CinematicTheme.onSurfaceVariant)
                        .frame(width: 40, alignment: .trailing)
                }
            }
        }
        .padding(8)
        .background(CinematicTheme.surfaceContainerLowest)
        .clipShape(RoundedRectangle(cornerRadius: CinematicRadius.md))
    }

    private func parameterRange(for key: String) -> ClosedRange<Double> {
        switch key {
        case "brightness": -1.0...1.0
        case "contrast": 0.0...4.0
        case "saturation": 0.0...4.0
        case "temperature": 2000...10000
        case "radius": 0.0...100.0
        case "sharpness": 0.0...2.0
        default: 0.0...1.0
        }
    }

    private func transitionName(for type: TransitionType) -> String {
        switch type {
        case .none: "None"
        case .crossDissolve: "Cross Dissolve"
        case .fadeToBlack: "Fade To Black"
        case .fadeFromBlack: "Fade From Black"
        case .wipeLeft: "Wipe Left"
        case .wipeRight: "Wipe Right"
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

    private func adjacentClips(for clipID: UUID) -> (left: Clip?, right: Clip?) {
        for track in appState.timeline.tracks {
            guard let clipIndex = track.clips.firstIndex(where: { $0.id == clipID }) else { continue }
            let left = clipIndex > 0 ? track.clips[clipIndex - 1] : nil
            let right = track.clips.indices.contains(clipIndex + 1) ? track.clips[clipIndex + 1] : nil
            return (left, right)
        }
        return (nil, nil)
    }

    private func editNudgeButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.cinLabelRegular)
                .foregroundStyle(CinematicTheme.onSurface)
                .padding(.horizontal, 10)
                .frame(height: CinematicMetrics.controlHeight)
                .background(CinematicTheme.surfaceContainerHighest)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
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
            Text(LocalizedStringKey(message.content.replacingOccurrences(of: "%", with: "%%")))
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
