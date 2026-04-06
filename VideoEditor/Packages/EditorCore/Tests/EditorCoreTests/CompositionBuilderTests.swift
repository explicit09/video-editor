import Testing
import Foundation
import AVFoundation
import CoreImage
import CoreGraphics
@testable import EditorCore

@Suite("Composition Builder Tests")
struct CompositionBuilderTests {
    private final class WriterBox: @unchecked Sendable {
        let writer: AVAssetWriter

        init(_ writer: AVAssetWriter) {
            self.writer = writer
        }
    }

    let ciContext = CIContext(options: [.useSoftwareRenderer: true])

    private func makeSplitPixelBuffer(width: Int, height: Int) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        ]

        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw NSError(domain: "CompositionBuilderTests", code: Int(status))
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw NSError(domain: "CompositionBuilderTests", code: -1)
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        for y in 0..<height {
            let row = baseAddress.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
            for x in 0..<width {
                let offset = x * 4
                let isBrightHalf = x >= width / 2
                let value: UInt8 = isBrightHalf ? 255 : 0
                row[offset + 0] = value
                row[offset + 1] = value
                row[offset + 2] = value
                row[offset + 3] = 255
            }
        }

        return pixelBuffer
    }

    private func writeSplitVideo(width: Int = 64, height: Int = 64, frameCount: Int = 30) async throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("composition-builder-\(UUID().uuidString)")
            .appendingPathExtension("mov")

        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let outputSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: outputSettings)
        input.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
            ]
        )

        guard writer.canAdd(input) else {
            throw NSError(domain: "CompositionBuilderTests", code: -2)
        }
        writer.add(input)

        guard writer.startWriting() else {
            throw writer.error ?? NSError(domain: "CompositionBuilderTests", code: -3)
        }
        writer.startSession(atSourceTime: .zero)

        let frameDuration = CMTime(value: 1, timescale: 30)
        for index in 0..<frameCount {
            while !input.isReadyForMoreMediaData {
                await Task.yield()
            }

            let pixelBuffer = try makeSplitPixelBuffer(width: width, height: height)
            let presentationTime = CMTimeMultiply(frameDuration, multiplier: Int32(index))
            guard adaptor.append(pixelBuffer, withPresentationTime: presentationTime) else {
                throw writer.error ?? NSError(domain: "CompositionBuilderTests", code: -4)
            }
        }

        input.markAsFinished()
        let writerBox = WriterBox(writer)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            writer.finishWriting {
                if writerBox.writer.status == .completed {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: writerBox.writer.error ?? NSError(domain: "CompositionBuilderTests", code: -5))
                }
            }
        }

        return url
    }

    private func meanLuminance(of image: CGImage) -> Double {
        let extent = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let averageFilter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: CIImage(cgImage: image),
            kCIInputExtentKey: CIVector(cgRect: extent),
        ])!
        let output = averageFilter.outputImage!
        var pixel = [UInt8](repeating: 0, count: 4)
        ciContext.render(
            output,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        return (0.2126 * Double(pixel[0])) + (0.7152 * Double(pixel[1])) + (0.0722 * Double(pixel[2]))
    }

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

    @Test("Preview mode keeps HD and smaller sources on full-resolution media")
    func previewKeepsHDMediaOnSource() {
        let sourceURL = URL(fileURLWithPath: "/tmp/source.mp4")
        let proxyURL = URL(fileURLWithPath: "/tmp/proxy.mov")
        let asset = MediaAsset(
            name: "Demo",
            sourceURL: sourceURL,
            proxyURL: proxyURL,
            type: .video,
            width: 1920,
            height: 1080
        )

        let resolved = CompositionBuilder.resolvedMediaURL(
            for: asset,
            mode: .preview,
            fileExists: { path in path == proxyURL.path }
        )

        #expect(resolved == sourceURL)
    }

    @Test("Preview mode uses proxy media for sources above 1080p when it exists")
    func previewUsesProxyFor4KWhenAvailable() {
        let sourceURL = URL(fileURLWithPath: "/tmp/source.mp4")
        let proxyURL = URL(fileURLWithPath: "/tmp/proxy.mov")
        let asset = MediaAsset(
            name: "Demo 4K",
            sourceURL: sourceURL,
            proxyURL: proxyURL,
            type: .video,
            width: 3840,
            height: 2160
        )

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

    @Test("Cropped clips use the custom compositor and render the cropped region")
    func croppedClipUsesCustomCompositor() async throws {
        let sourceURL = try await writeSplitVideo()
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let assetID = UUID()
        let clip = Clip(
            assetID: assetID,
            timelineRange: TimeRange(start: 0, duration: 1),
            sourceRange: TimeRange(start: 0, duration: 1),
            cropRect: CropRect(x: 0.5, y: 0, width: 0.5, height: 1)
        )
        let timeline = Timeline(tracks: [Track(name: "V1", type: .video, clips: [clip])])
        let asset = MediaAsset(
            id: assetID,
            name: "Split",
            sourceURL: sourceURL,
            type: .video,
            duration: 1,
            width: 64,
            height: 64
        )

        let result = await CompositionBuilder().build(from: timeline, assets: [asset], urlMode: .preview)
        let videoComposition = try #require(result.videoComposition)

        #expect(videoComposition.customVideoCompositorClass == EffectCompositor.self)
        #expect(videoComposition.instructions.first is EffectInstruction)

        let generator = AVAssetImageGenerator(asset: result.composition)
        generator.videoComposition = videoComposition
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        let frame = try generator.copyCGImage(at: CMTime(seconds: 0.5, preferredTimescale: 600), actualTime: nil)
        #expect(meanLuminance(of: frame) > 220, "Expected cropped render to favor the bright half")
    }

    @Test("Overlay instructions keep higher tracks above lower tracks and preserve clip presentation")
    func overlayInstructionOrdersHigherTracksAboveLowerTracks() async throws {
        let sourceURL = try await writeSplitVideo()
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let baseAssetID = UUID()
        let overlayAssetID = UUID()
        let baseClip = Clip(
            assetID: baseAssetID,
            timelineRange: TimeRange(start: 0, duration: 1),
            sourceRange: TimeRange(start: 0, duration: 1),
            overlayPresentation: .default
        )
        let overlayPresentation = OverlayPresentation(
            mode: .pip,
            border: .visible(width: 4, colorHex: "#FFFFFF"),
            shadow: .medium,
            cornerRadius: 18,
            maskShape: .roundedRect,
            snapsToSafeMargins: true,
            entranceAnimation: .scaleIn,
            exitAnimation: .fadeOut
        )
        let overlayClip = Clip(
            assetID: overlayAssetID,
            timelineRange: TimeRange(start: 0, duration: 1),
            sourceRange: TimeRange(start: 0, duration: 1),
            transform: .init(scaleX: 0.5, scaleY: 0.5),
            overlayPresentation: overlayPresentation
        )
        let timeline = Timeline(tracks: [
            Track(name: "Video 1", type: .video, clips: [baseClip]),
            Track(name: "Video 2", type: .video, clips: [overlayClip]),
        ])
        let assets = [
            MediaAsset(
                id: baseAssetID,
                name: "Base",
                sourceURL: sourceURL,
                type: .video,
                duration: 1,
                width: 64,
                height: 64
            ),
            MediaAsset(
                id: overlayAssetID,
                name: "Overlay",
                sourceURL: sourceURL,
                type: .video,
                duration: 1,
                width: 64,
                height: 64
            ),
        ]

        let result = await CompositionBuilder().build(from: timeline, assets: assets, urlMode: .preview)
        let instruction = try #require(result.videoComposition?.instructions.first as? OverlayInstruction)

        #expect(instruction.layers.map(\.trackOrder) == [0, 1])
        #expect(instruction.layers.map(\.presentation) == [baseClip.overlayPresentation, overlayPresentation])
    }
}
