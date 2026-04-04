import Testing
import Foundation
@testable import EditorCore

@Suite("Composition Builder Tests")
struct CompositionBuilderTests {

    @Test("Preview mode falls back to source media when the proxy file is missing")
    func previewFallsBackToSourceWhenProxyMissing() {
        let sourceURL = URL(fileURLWithPath: "/tmp/source.mp4")
        let proxyURL = URL(fileURLWithPath: "/tmp/missing-proxy.mov")
        let asset = MediaAsset(name: "Demo", sourceURL: sourceURL, proxyURL: proxyURL, type: .video)

        let resolved = CompositionBuilder.resolvedMediaURL(
            for: asset,
            mode: .preview,
            fileExists: { path in path == sourceURL.path }
        )

        #expect(resolved == sourceURL)
    }

    @Test("Preview mode uses proxy media when it exists")
    func previewUsesProxyWhenAvailable() {
        let sourceURL = URL(fileURLWithPath: "/tmp/source.mp4")
        let proxyURL = URL(fileURLWithPath: "/tmp/proxy.mov")
        let asset = MediaAsset(name: "Demo", sourceURL: sourceURL, proxyURL: proxyURL, type: .video)

        let resolved = CompositionBuilder.resolvedMediaURL(
            for: asset,
            mode: .preview,
            fileExists: { path in path == proxyURL.path }
        )

        #expect(resolved == proxyURL)
    }

    @Test("Export mode always uses the source media")
    func exportAlwaysUsesSource() {
        let sourceURL = URL(fileURLWithPath: "/tmp/source.mp4")
        let proxyURL = URL(fileURLWithPath: "/tmp/proxy.mov")
        let asset = MediaAsset(name: "Demo", sourceURL: sourceURL, proxyURL: proxyURL, type: .video)

        let resolved = CompositionBuilder.resolvedMediaURL(
            for: asset,
            mode: .export,
            fileExists: { _ in true }
        )

        #expect(resolved == sourceURL)
    }

    @Test("Preview mode keeps audio on the source media")
    func previewAudioUsesSource() {
        let sourceURL = URL(fileURLWithPath: "/tmp/source.mp4")
        let proxyURL = URL(fileURLWithPath: "/tmp/proxy.mov")
        let asset = MediaAsset(name: "Demo", sourceURL: sourceURL, proxyURL: proxyURL, type: .video)

        let resolved = CompositionBuilder.resolvedAudioURL(
            for: asset,
            mode: .preview
        )

        #expect(resolved == sourceURL)
    }

    @Test("Composition builder ignores sub-renderable fragments")
    func ignoresSubRenderableFragments() {
        let tinyClip = Clip(
            assetID: UUID(),
            timelineRange: TimeRange(start: 0, duration: 0.01),
            sourceRange: TimeRange(start: 0, duration: 0.01)
        )
        let normalClip = Clip(
            assetID: UUID(),
            timelineRange: TimeRange(start: 0, duration: 1),
            sourceRange: TimeRange(start: 0, duration: 1)
        )

        #expect(!CompositionBuilder.shouldBuildClip(tinyClip))
        #expect(CompositionBuilder.shouldBuildClip(normalClip))
    }

    @Test("Composition builder maps caption words into composition time for standard clips")
    func mapsCaptionWordsIntoCompositionTime() {
        let assetID = UUID()
        let clip = Clip(
            assetID: assetID,
            timelineRange: TimeRange(start: 10, duration: 6),
            sourceRange: TimeRange(start: 4, duration: 6),
            speed: 2.0
        )
        let asset = MediaAsset(
            id: assetID,
            name: "Captioned",
            sourceURL: URL(fileURLWithPath: "/tmp/captioned.mp4"),
            type: .video,
            analysis: MediaAnalysis(
                transcript: [
                    TranscriptWord(word: "ignore", start: 3.0, end: 3.4),
                    TranscriptWord(word: "hello", start: 4.5, end: 5.0),
                    TranscriptWord(word: "world", start: 8.0, end: 8.5),
                    TranscriptWord(word: "trimmed", start: 9.8, end: 10.4)
                ]
            )
        )

        let words = CompositionBuilder.captionWords(for: clip, asset: asset)

        #expect(words.map(\.word) == ["hello", "world", "trimmed"])
        #expect(words[0].start == 10.25)
        #expect(words[0].end == 10.5)
        #expect(words[1].start == 12.0)
        #expect(words[1].end == 12.25)
        #expect(words[2].start == 12.9)
        #expect(words[2].end == 13.0)
    }
}
