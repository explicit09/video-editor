import Testing
import Foundation
import EditorCore
@testable import VideoEditor

@Suite("Editor Stabilization Support Tests")
struct EditorStabilizationSupportTests {

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
}
