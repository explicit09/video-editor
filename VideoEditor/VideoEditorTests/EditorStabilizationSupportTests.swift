import Testing
import Foundation
import EditorCore
@testable import VideoEditor

@Suite("Editor Stabilization Support Tests")
struct EditorStabilizationSupportTests {
    @Test("utility status badge metrics keep compact height for short labels")
    func utilityStatusBadgeMetricsUseCompactHeight() {
        let metrics = UtilityStatusBadgeMetrics.make(text: "AI", showsIcon: true)

        #expect(metrics.height == UtilityMetrics.controlHeight - 4)
        #expect(metrics.horizontalPadding == UtilitySpacing.sm)
    }

    @Test("utility status badge metrics handle longer toolbar labels without growing taller")
    func utilityStatusBadgeMetricsKeepFixedHeightForToolbarLabels() {
        let metrics = UtilityStatusBadgeMetrics.make(text: "EXPANDED", showsIcon: true)

        #expect(metrics.height == UtilityMetrics.controlHeight - 4)
        #expect(metrics.horizontalPadding == UtilitySpacing.sm)
    }

    @Test("utility segmented control metrics collapse labels on narrow widths")
    func utilitySegmentedControlMetricsCollapseLabels() {
        let metrics = UtilitySegmentedControlMetrics.make(
            availableWidth: 180,
            itemCount: 3
        )

        #expect(metrics.showsLabels == false)
        #expect(metrics.controlHeight == UtilityMetrics.controlHeight)
    }

    @Test("panel header collapses badges before clipping the primary action")
    func compactHeaderPriority() {
        let layout = CompactPanelHeaderLayout.make(
            availableWidth: 220,
            badgeCount: 2,
            showsPrimaryAction: true
        )

        #expect(layout.showsPrimaryAction)
        #expect(!layout.showsSecondaryBadges)
    }

    @Test("panel header metrics raise subtitle minimum height for long copy and actions")
    func utilityPanelHeaderMetricsExpandForLongSubtitles() {
        let metrics = UtilityPanelHeaderMetrics.make(
            availableWidth: 320,
            subtitle: "Search, ask questions, trigger edits, and keep the current context readable without clipping.",
            badgeCount: 1,
            showsPrimaryAction: true
        )

        #expect(metrics.compactLayout.showsPrimaryAction)
        #expect(metrics.minimumHeight > 48)
    }

    @Test("AI panel reveal inserts the panel into the inspector stack when missing from edit")
    @MainActor
    func revealAIPanelInsertsIntoEditWorkspace() {
        let registry = PanelRegistry.workspaceRegistry(
            layoutMode: .expanded,
            selectedTool: .constant(.selection)
        )

        let revealed = registry.revealingPanel(.aiAssistant, in: PanelRegistry.editDefaultLayout)
        let expected = DockWorkspaceLayout(
            workspaceID: PanelRegistry.editWorkspaceID,
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
                        trailing: .tabs(
                            activePanelID: .aiAssistant,
                            panelIDs: [.inspector, .aiAssistant]
                        )
                    )
                ),
                trailing: .panel(.timeline)
            )
        )

        #expect(revealed.root.containsPanel(.aiAssistant))
        #expect(revealed == expected)
    }

    @Test("AI panel reveal selects an existing AI tab instead of duplicating it")
    @MainActor
    func revealAIPanelSelectsExistingTab() {
        let registry = PanelRegistry.workspaceRegistry(
            layoutMode: .expanded,
            selectedTool: .constant(.selection)
        )
        let layout = DockWorkspaceLayout(
            workspaceID: PanelRegistry.mediaWorkspaceID,
            root: .split(
                axis: .horizontal,
                ratio: 0.7,
                leading: .panel(.mediaWorkspace),
                trailing: .tabs(
                    activePanelID: .inspector,
                    panelIDs: [.inspector, .aiAssistant, .timeline]
                )
            )
        )

        let revealed = registry.revealingPanel(.aiAssistant, in: layout)

        guard case let .split(_, _, _, trailing) = revealed.root else {
            Issue.record("Expected media root to remain a split layout")
            return
        }

        guard case let .tabs(activePanelID, panelIDs) = trailing else {
            Issue.record("Expected existing tab stack to stay intact")
            return
        }

        #expect(activePanelID == .aiAssistant)
        #expect(panelIDs == [.inspector, .aiAssistant, .timeline])
    }

    @Test("Workspace page bar metrics prefer compact top bar on desktop widths")
    func workspacePageBarMetricsPreferTopBarOnDesktopWidths() {
        let metrics = WorkspacePageBarMetrics.make(containerWidth: 1440)

        #expect(metrics.barHeight == 36)
        #expect(metrics.showsLabels)
    }

    @Test("Workspace page bar metrics collapse labels on narrow widths")
    func workspacePageBarMetricsCollapseLabelsOnNarrowWidths() {
        let metrics = WorkspacePageBarMetrics.make(containerWidth: 640)

        #expect(metrics.barHeight == 32)
        #expect(!metrics.showsLabels)
    }

    @Test("editor workspace metadata aligns with persisted workspace IDs")
    @MainActor
    func editorWorkspaceMetadataAlignsWithPersistedWorkspaceIDs() {
        #expect(EditorWorkspace.edit.workspaceID == PanelRegistry.editWorkspaceID)
        #expect(EditorWorkspace.media.workspaceID == PanelRegistry.mediaWorkspaceID)
        #expect(EditorWorkspace.transcript.workspaceID == PanelRegistry.transcriptWorkspaceID)
        #expect(EditorWorkspace.ai.workspaceID == PanelRegistry.aiWorkspaceID)
        #expect(EditorWorkspace.deliver.workspaceID == PanelRegistry.deliverWorkspaceID)
    }

    @Test("workspace dock persistence loads each bundle only once per state")
    @MainActor
    func workspaceDockPersistenceLoadsEachBundleOnlyOncePerState() throws {
        let registry = PanelRegistry.workspaceRegistry(
            layoutMode: .expanded,
            selectedTool: .constant(.selection)
        )
        let bundleURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let persistedLayout = DockWorkspaceLayout(
            workspaceID: PanelRegistry.editWorkspaceID,
            root: .panel(.timeline)
        )
        let replacementLayout = DockWorkspaceLayout(
            workspaceID: PanelRegistry.editWorkspaceID,
            root: .panel(.inspector)
        )
        let store = registry.makeLayoutStore(
            baseURL: WorkspaceDockPersistence.workspaceLayoutsBaseURL(for: bundleURL)
        )

        try store.save(persistedLayout)

        var state = WorkspaceDockState(layout: PanelRegistry.editDefaultLayout)
        WorkspaceDockPersistence.loadLayoutIfNeeded(
            state: &state,
            using: registry,
            workspaceID: PanelRegistry.editWorkspaceID,
            for: bundleURL
        )

        #expect(state.layout == persistedLayout)

        try store.save(replacementLayout)

        WorkspaceDockPersistence.loadLayoutIfNeeded(
            state: &state,
            using: registry,
            workspaceID: PanelRegistry.editWorkspaceID,
            for: bundleURL
        )

        #expect(state.layout == persistedLayout)
    }

    @Test("workspace dock persistence reveals the AI panel without changing the workspace ID")
    @MainActor
    func workspaceDockPersistenceRevealsAIPanel() {
        let registry = PanelRegistry.workspaceRegistry(
            layoutMode: .expanded,
            selectedTool: .constant(.selection)
        )
        let state = WorkspaceDockState(layout: PanelRegistry.editDefaultLayout)

        let revealed = WorkspaceDockPersistence.revealedState(
            byRevealing: .aiAssistant,
            in: state,
            using: registry
        )

        #expect(revealed.layout.workspaceID == PanelRegistry.editWorkspaceID)
        #expect(revealed.layout.root.containsPanel(.aiAssistant))
    }

    @Test("Waveform state resolver prefers cached profiles")
    func waveformStateResolverPrefersCachedProfiles() {
        let asset = MediaAsset(
            name: "Clip",
            sourceURL: URL(fileURLWithPath: "/tmp/clip.mov"),
            type: .video,
            analysis: MediaAnalysis(loudnessProfile: [0.1, 0.2, 0.3])
        )

        let state = WaveformLoadStateResolver.resolve(
            for: asset,
            hasAudioTrack: true,
            extractionInFlight: false
        )

        #expect(state == .ready([0.1, 0.2, 0.3]))
    }

    @Test("Waveform state resolver distinguishes no-audio video from loading audio video")
    func waveformStateResolverDistinguishesVideoStates() {
        let asset = MediaAsset(
            name: "Video",
            sourceURL: URL(fileURLWithPath: "/tmp/video.mov"),
            type: .video
        )

        #expect(
            WaveformLoadStateResolver.resolve(
                for: asset,
                hasAudioTrack: false,
                extractionInFlight: false
            ) == .noAudio
        )
        #expect(
            WaveformLoadStateResolver.resolve(
                for: asset,
                hasAudioTrack: true,
                extractionInFlight: true
            ) == .loading
        )
    }

    @Test("Track display state pruner drops removed track IDs")
    func trackDisplayStatePrunerDropsRemovedTracks() {
        let keptID = UUID()
        let removedID = UUID()

        let pruned = TimelineTrackDisplayStatePruner.prune(
            TimelineTrackDisplayState(
                trackHeights: [keptID: 76, removedID: 104],
                collapsedTrackIDs: [keptID, removedID]
            ),
            validTrackIDs: [keptID]
        )

        #expect(pruned.trackHeights == [keptID: 76])
        #expect(pruned.collapsedTrackIDs == [keptID])
    }

    @Test("Shortcut guard blocks handlers while typing")
    func shortcutGuardBlocksTextInput() {
        #expect(EditorShortcutGuard.shouldHandleGlobalShortcut(isTextInputFocused: false))
        #expect(!EditorShortcutGuard.shouldHandleGlobalShortcut(isTextInputFocused: true))
    }

    @Test("Transcript analysis support flags sparse transcripts for structural tools")
    func transcriptAnalysisSupportFlagsSparseTranscripts() {
        let words = [
            TranscriptWord(word: "Hey", start: 31.0, end: 31.2),
            TranscriptWord(word: "there.", start: 31.2, end: 31.5),
            TranscriptWord(word: "Imagine", start: 32.0, end: 32.2),
            TranscriptWord(word: "this", start: 32.2, end: 32.4),
        ]

        let assessment = TranscriptAnalysisSupport.assessCoverage(
            words: words,
            assetDuration: 38.7
        )

        #expect(assessment.wordCount == 4)
        #expect(assessment.isSparseForStructuralAnalysis)
        #expect(abs(assessment.speakingSpan - 1.4) < 0.0001)
    }

    @Test("Transcript analysis support preserves hour-scale timestamps")
    func transcriptAnalysisSupportPreservesHourScaleTimestamps() {
        #expect(TranscriptAnalysisSupport.formatTimestamp(32) == "0:32")
        #expect(TranscriptAnalysisSupport.formatTimestamp(3723) == "1:02:03")
    }

    @Test("Transcript analysis support builds sentence transcript with timestamps")
    func transcriptAnalysisSupportBuildsSentenceTranscript() {
        let transcript = TranscriptAnalysisSupport.buildTimestampedTranscript(from: [
            TranscriptWord(word: "Hello", start: 0, end: 0.2),
            TranscriptWord(word: "world.", start: 0.2, end: 0.5),
            TranscriptWord(word: "Second", start: 2.0, end: 2.2),
            TranscriptWord(word: "thought", start: 2.2, end: 2.4),
        ])

        #expect(transcript == "[0:00] Hello world.\n[0:02] Second thought\n")
    }

    @Test("Timeline insertion start resolver keeps linked media aligned across track ends")
    func timelineInsertionStartResolverKeepsLinkedMediaAligned() {
        #expect(
            TimelineInsertionStartResolver.resolve(
                explicitStart: nil,
                primaryTrackEnd: 1,
                companionTrackEnd: 2.5
            ) == 2.5
        )
        #expect(
            TimelineInsertionStartResolver.resolve(
                explicitStart: 4,
                primaryTrackEnd: 1,
                companionTrackEnd: 2.5
            ) == 4
        )
    }

    @Test("Silence keep range builder drops tiny tail fragments")
    func silenceKeepRangeBuilderDropsTinyTailFragments() {
        let keepRanges = SilenceKeepRangeBuilder.keepRanges(
            for: TimeRange(start: 0, end: 10),
            silenceRanges: [
                TimeRange(start: 2, end: 3),
                TimeRange(start: 9.995, end: 10)
            ],
            minimumSilenceDuration: 0.001
        )

        #expect(keepRanges == [
            TimeRange(start: 0, end: 2),
            TimeRange(start: 3, end: 9.995),
        ])
    }

    @Test("Silence keep range builder drops micro speech blips between silences")
    func silenceKeepRangeBuilderDropsMicroSpeechBlips() {
        let keepRanges = SilenceKeepRangeBuilder.keepRanges(
            for: TimeRange(start: 0, end: 5),
            silenceRanges: [
                TimeRange(start: 0.8, end: 1.5),
                TimeRange(start: 1.58, end: 2.3),
            ],
            minimumSilenceDuration: 0.5
        )

        #expect(keepRanges == [
            TimeRange(start: 0, end: 0.8),
            TimeRange(start: 2.3, end: 5),
        ])
    }

    @Test("Timeline fragment pruner removes sub-renderable leftovers and sorts survivors")
    func timelineFragmentPrunerRemovesTinyFragments() {
        let removedClipID = UUID()
        let keptLateClipID = UUID()
        let keptEarlyClipID = UUID()
        let track = Track(
            name: "Video",
            type: .video,
            clips: [
                Clip(
                    id: keptLateClipID,
                    assetID: UUID(),
                    timelineRange: TimeRange(start: 5, duration: 2),
                    sourceRange: TimeRange(start: 5, duration: 2)
                ),
                Clip(
                    id: removedClipID,
                    assetID: UUID(),
                    timelineRange: TimeRange(start: 7, duration: 0.01),
                    sourceRange: TimeRange(start: 7, duration: 0.01)
                ),
                Clip(
                    id: keptEarlyClipID,
                    assetID: UUID(),
                    timelineRange: TimeRange(start: 1, duration: 1),
                    sourceRange: TimeRange(start: 1, duration: 1)
                ),
            ]
        )

        let result = TimelineFragmentPruner.prune(
            Timeline(tracks: [track]),
            minimumDuration: 0.02
        )

        #expect(result.removedClipIDs == [removedClipID])
        #expect(result.timeline.tracks[0].clips.map(\.id) == [keptEarlyClipID, keptLateClipID])
    }

    @Test("Screenshot window resolver falls back to key visible windows")
    func screenshotWindowResolverFallsBackToKeyWindow() {
        let selected = MCPScreenshotWindowResolver.selectWindowNumber(
            from: [
                MCPScreenshotWindowCandidate(
                    windowNumber: 11,
                    isMain: false,
                    isKey: false,
                    isVisible: false,
                    isMiniaturized: false
                ),
                MCPScreenshotWindowCandidate(
                    windowNumber: 22,
                    isMain: false,
                    isKey: true,
                    isVisible: true,
                    isMiniaturized: false
                ),
            ]
        )

        #expect(selected == 22)
    }

    @Test("Screenshot window resolver avoids miniaturized windows when visible ones exist")
    func screenshotWindowResolverAvoidsMiniaturizedWindows() {
        let selected = MCPScreenshotWindowResolver.selectWindowNumber(
            from: [
                MCPScreenshotWindowCandidate(
                    windowNumber: 10,
                    isMain: false,
                    isKey: false,
                    isVisible: false,
                    isMiniaturized: true
                ),
                MCPScreenshotWindowCandidate(
                    windowNumber: 30,
                    isMain: false,
                    isKey: false,
                    isVisible: true,
                    isMiniaturized: false
                ),
            ]
        )

        #expect(selected == 30)
    }
}
