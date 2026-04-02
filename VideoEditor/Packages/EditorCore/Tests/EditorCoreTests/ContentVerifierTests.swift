import Foundation
import Testing
@testable import EditorCore

@Suite("Content Verifier Tests")
struct ContentVerifierTests {

    @Test("Source audio comparison is skipped for mixed audio output")
    func skipsMixedAudioComparison() {
        let context = ContentVerifier.AudioVerificationContext(
            assetType: .video,
            trackType: .video,
            activeAudioClipCount: 2
        )

        #expect(context.shouldCompareSourceAudio == false)
    }

    @Test("Source audio comparison is skipped for image clips")
    func skipsImageAudioComparison() {
        let context = ContentVerifier.AudioVerificationContext(
            assetType: .image,
            trackType: .video,
            activeAudioClipCount: 0
        )

        #expect(context.shouldCompareSourceAudio == false)
    }

    @Test("Source audio comparison remains enabled for isolated audio clips")
    func keepsIsolatedAudioComparison() {
        let context = ContentVerifier.AudioVerificationContext(
            assetType: .audio,
            trackType: .audio,
            activeAudioClipCount: 1
        )

        #expect(context.shouldCompareSourceAudio == true)
    }

    @Test("Source video comparison is skipped for transformed clips")
    func skipsVideoComparisonForTransforms() {
        let context = ContentVerifier.VisualVerificationContext(
            assetType: .video,
            trackType: .video,
            clip: Clip(
                assetID: UUID(),
                timelineRange: TimeRange(start: 0, duration: 5),
                sourceRange: TimeRange(start: 0, duration: 5),
                transform: Transform2D(positionX: 20)
            )
        )

        #expect(context.shouldCompareSourceVideo == false)
    }

    @Test("Source video comparison is skipped for visually modified clips")
    func skipsVideoComparisonForVisualModifiers() {
        let context = ContentVerifier.VisualVerificationContext(
            assetType: .video,
            trackType: .video,
            clip: Clip(
                assetID: UUID(),
                timelineRange: TimeRange(start: 0, duration: 5),
                sourceRange: TimeRange(start: 0, duration: 5),
                cropRect: CropRect(x: 0.1, y: 0, width: 0.8, height: 1),
                opacity: 0.8,
                effects: [EffectInstance(type: EffectInstance.typeBlur, parameters: ["radius": 2])]
            )
        )

        #expect(context.shouldCompareSourceVideo == false)
    }

    @Test("Source video comparison remains enabled for unmodified clips")
    func keepsVideoComparisonForPlainVideo() {
        let context = ContentVerifier.VisualVerificationContext(
            assetType: .video,
            trackType: .video,
            clip: Clip(
                assetID: UUID(),
                timelineRange: TimeRange(start: 0, duration: 5),
                sourceRange: TimeRange(start: 0, duration: 5)
            )
        )

        #expect(context.shouldCompareSourceVideo == true)
    }

    @Test("Source video comparison is skipped for audio-track checkpoints")
    func skipsVideoComparisonForAudioTrackCheckpoints() {
        let context = ContentVerifier.VisualVerificationContext(
            assetType: .video,
            trackType: .audio,
            clip: Clip(
                assetID: UUID(),
                timelineRange: TimeRange(start: 0, duration: 5),
                sourceRange: TimeRange(start: 0, duration: 5)
            )
        )

        #expect(context.shouldCompareSourceVideo == false)
    }

    @Test("Audio mismatch is ignored when the source is effectively silent")
    func skipsAudioMismatchWhenSourceIsSilent() {
        #expect(ContentVerifier.shouldFailAudioMismatch(ncc: 0.0, sourceRMS: 0.0, threshold: 0.7) == false)
        #expect(ContentVerifier.shouldFailAudioMismatch(ncc: 0.0, sourceRMS: 0.004, threshold: 0.7) == false)
        #expect(ContentVerifier.shouldFailAudioMismatch(ncc: 0.0, sourceRMS: 0.02, threshold: 0.7) == true)
    }

    @Test("Silent composition only fails when the source is actually audible")
    func failsSilentCompositionOnlyWhenSourceHasAudio() {
        #expect(ContentVerifier.shouldFailSilentComposition(compositionRMS: 0.0, sourceRMS: 0.0) == false)
        #expect(ContentVerifier.shouldFailSilentComposition(compositionRMS: 0.0, sourceRMS: 0.02) == true)
        #expect(ContentVerifier.shouldFailSilentComposition(compositionRMS: 0.02, sourceRMS: 0.02) == false)
    }

    @Test("Black frame only fails when the source frame has content")
    func failsBlackFrameOnlyWhenSourceIsNotBlack() {
        #expect(ContentVerifier.shouldFailBlackFrame(frameValid: false, sourceFrameValid: false) == false)
        #expect(ContentVerifier.shouldFailBlackFrame(frameValid: false, sourceFrameValid: true) == true)
        #expect(ContentVerifier.shouldFailBlackFrame(frameValid: true, sourceFrameValid: true) == false)
    }
}
