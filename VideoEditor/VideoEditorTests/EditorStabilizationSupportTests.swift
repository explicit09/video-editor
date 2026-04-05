import Testing
import Foundation
import EditorCore
@testable import VideoEditor

@Suite("Editor Stabilization Support Tests")
struct EditorStabilizationSupportTests {
    @Test("Edit workspace chrome embeds utility panel instead of using left rail")
    func editWorkspaceChromeEmbedsUtilityPanelInsteadOfUsingLeftRail() {
        let chrome = EditWorkspaceChrome.make(isUtilityPanelVisible: true)

        #expect(!chrome.showsLeftRail)
        #expect(chrome.showsEmbeddedUtilityPanel)
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
