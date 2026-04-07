# Visual Scene Understanding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the AI editing assistant visual content comprehension by analyzing video frames at scene boundaries using Apple's on-device VLM, so it can reason about what's happening visually — not just what's being said.

**Architecture:** Extend the existing `LocalAnalysisPipeline` with a new stage that detects shot boundaries via pixel histogram diffing, then describes each scene using Apple's on-device VLM (macOS 26+). Results stored as `SceneSegment` objects on `MediaAnalysis.sceneDescriptions` (field already exists). Exposed to the AI via a new `get_visual_scenes` MCP tool and context builder updates.

**Tech Stack:** Swift 6, AVFoundation (frame extraction), Apple Vision/Foundation Models (on-device VLM), existing SQLite persistence

**Spec:** `docs/superpowers/specs/2026-04-07-visual-scene-understanding-design.md`

---

### File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `Packages/EditorCore/Sources/EditorCore/Analysis/ShotBoundaryDetector.swift` | Create | Pixel histogram shot boundary detection |
| `Packages/EditorCore/Sources/EditorCore/Analysis/SceneDescriber.swift` | Create | Apple on-device VLM frame description |
| `Packages/EditorCore/Sources/EditorCore/Analysis/VisualSceneAnalyzer.swift` | Create | Orchestrates shot detection + VLM description into `[SceneSegment]` |
| `Packages/EditorCore/Sources/EditorCore/Analysis/LocalAnalysisPipeline.swift` | Modify | Add visual scene analysis stage with progress |
| `Packages/EditorCore/Sources/EditorCore/Models/MediaAsset.swift` | Modify | Add `thumbnailPath` to `SceneSegment` |
| `Packages/AIServices/Sources/AIServices/Tools/AIToolRegistry.swift` | Modify | Add `get_visual_scenes` tool definition |
| `Packages/AIServices/Sources/AIServices/Context/AIContextBuilder.swift` | Modify | Add `visualSceneCount` to `AssetSummary` |
| `Packages/AIServices/Sources/AIServices/Providers/ClaudeProvider.swift` | Modify | Add `<visual_context>` to system prompt |
| `VideoEditor/App/AIChatController.swift` | Modify | Add `get_visual_scenes` tool handler |
| `VideoEditor/App/MCPServer.swift` | Modify | Add `get_visual_scenes` MCP handler |
| `Packages/EditorCore/Tests/EditorCoreTests/ShotBoundaryDetectorTests.swift` | Create | Tests for shot detection |
| `Packages/EditorCore/Tests/EditorCoreTests/VisualSceneAnalyzerTests.swift` | Create | Tests for scene analyzer orchestration |

---

### Task 1: Shot Boundary Detector

**Files:**
- Create: `Packages/EditorCore/Sources/EditorCore/Analysis/ShotBoundaryDetector.swift`
- Test: `Packages/EditorCore/Tests/EditorCoreTests/ShotBoundaryDetectorTests.swift`

- [ ] **Step 1: Write the failing test for shot boundary detection**

```swift
// ShotBoundaryDetectorTests.swift
import XCTest
@testable import EditorCore

final class ShotBoundaryDetectorTests: XCTestCase {

    func testDetectsNoBoundariesInStaticContent() async throws {
        // A single-color video has no shot changes
        let url = try createTestVideo(frames: 30, colors: [.red], fps: 30) // 1 second of solid red
        let detector = ShotBoundaryDetector()
        let boundaries = try await detector.detect(url: url, threshold: 0.3)
        XCTAssertTrue(boundaries.isEmpty, "Static content should have no shot boundaries")
    }

    func testDetectsBoundaryOnColorChange() async throws {
        // First half red, second half blue — one hard cut
        let url = try createTestVideo(frames: 60, colors: [.red, .blue], fps: 30) // 2 sec, cut at 1s
        let detector = ShotBoundaryDetector()
        let boundaries = try await detector.detect(url: url, threshold: 0.3)
        XCTAssertEqual(boundaries.count, 1)
        XCTAssertEqual(boundaries[0], 1.0, accuracy: 0.2) // Cut near 1 second
    }

    func testDetectsMultipleBoundaries() async throws {
        // Red -> Green -> Blue — two cuts
        let url = try createTestVideo(frames: 90, colors: [.red, .green, .blue], fps: 30)
        let detector = ShotBoundaryDetector()
        let boundaries = try await detector.detect(url: url, threshold: 0.3)
        XCTAssertEqual(boundaries.count, 2)
    }

    // MARK: - Test helpers

    private func createTestVideo(frames: Int, colors: [CGColor], fps: Int) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test_\(UUID().uuidString).mov")
        let width = 64
        let height = 64
        let framesPerColor = frames / colors.count

        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mov) else {
            throw NSError(domain: "test", code: 1)
        }

        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
            ]
        )
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        for i in 0..<frames {
            let colorIndex = min(i / framesPerColor, colors.count - 1)
            let color = colors[colorIndex]

            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 10_000_000)
            }

            var pixelBuffer: CVPixelBuffer?
            CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32ARGB, nil, &pixelBuffer)
            guard let buffer = pixelBuffer else { continue }

            CVPixelBufferLockBaseAddress(buffer, [])
            let context = CGContext(
                data: CVPixelBufferGetBaseAddress(buffer),
                width: width, height: height,
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
            )!
            context.setFillColor(color)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            CVPixelBufferUnlockBaseAddress(buffer, [])

            let time = CMTime(value: CMTimeValue(i), timescale: CMTimeScale(fps))
            adaptor.append(buffer, withPresentationTime: time)
        }

        input.markAsFinished()
        await writer.finishWriting()
        return url
    }
}
```

Note: You'll need `import AVFoundation` and `import CoreGraphics` in the test file.

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd VideoEditor/Packages/EditorCore && swift test --filter ShotBoundaryDetectorTests 2>&1 | tail -20
```

Expected: Compilation error — `ShotBoundaryDetector` not defined.

- [ ] **Step 3: Implement ShotBoundaryDetector**

```swift
// ShotBoundaryDetector.swift
import Foundation
import AVFoundation
import CoreImage

/// Detects shot boundaries by comparing pixel histograms of consecutive frames.
/// Returns timestamps where the visual content changes significantly (hard cuts).
public struct ShotBoundaryDetector: Sendable {

    public init() {}

    /// Detect shot boundaries in a video file.
    /// - Parameters:
    ///   - url: Video file URL
    ///   - threshold: Histogram difference threshold (0.0-1.0). Higher = fewer boundaries. Default 0.3.
    ///   - sampleInterval: Seconds between sampled frames. Default 0.5.
    /// - Returns: Array of timestamps (seconds) where shot boundaries were detected.
    public func detect(
        url: URL,
        threshold: Double = 0.3,
        sampleInterval: TimeInterval = 0.5
    ) async throws -> [TimeInterval] {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 160, height: 90) // Low res for speed

        var boundaries: [TimeInterval] = []
        var previousHistogram: [Int]?
        var time: TimeInterval = 0

        while time < duration {
            let cmTime = CMTime(seconds: time, preferredTimescale: 600)
            guard let cgImage = try? await generator.image(at: cmTime).image else {
                time += sampleInterval
                continue
            }

            let histogram = computeHistogram(cgImage)

            if let prev = previousHistogram {
                let diff = histogramDifference(prev, histogram)
                if diff > threshold {
                    boundaries.append(time)
                }
            }

            previousHistogram = histogram
            time += sampleInterval
        }

        return boundaries
    }

    // MARK: - Histogram computation

    /// Compute a simple luminance histogram (64 bins) from a CGImage.
    private func computeHistogram(_ image: CGImage) -> [Int] {
        let width = image.width
        let height = image.height
        let totalPixels = width * height
        guard totalPixels > 0 else { return Array(repeating: 0, count: 64) }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        var pixelData = [UInt8](repeating: 0, count: bytesPerRow * height)

        guard let context = CGContext(
            data: &pixelData,
            width: width, height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return Array(repeating: 0, count: 64)
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Build 64-bin luminance histogram
        var histogram = [Int](repeating: 0, count: 64)
        for i in stride(from: 0, to: pixelData.count, by: bytesPerPixel) {
            let r = Double(pixelData[i])
            let g = Double(pixelData[i + 1])
            let b = Double(pixelData[i + 2])
            let luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
            let bin = min(Int(luminance * 64), 63)
            histogram[bin] += 1
        }

        return histogram
    }

    /// Compute normalized difference between two histograms (0.0 = identical, 1.0 = completely different).
    private func histogramDifference(_ a: [Int], _ b: [Int]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 1.0 }
        let totalA = Double(a.reduce(0, +))
        let totalB = Double(b.reduce(0, +))
        guard totalA > 0, totalB > 0 else { return 1.0 }

        var diff: Double = 0
        for i in 0..<a.count {
            let normA = Double(a[i]) / totalA
            let normB = Double(b[i]) / totalB
            diff += abs(normA - normB)
        }
        // diff ranges 0..2, normalize to 0..1
        return diff / 2.0
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd VideoEditor/Packages/EditorCore && swift test --filter ShotBoundaryDetectorTests 2>&1 | tail -20
```

Expected: All 3 tests pass.

- [ ] **Step 5: Commit**

```bash
cd VideoEditor && git add Packages/EditorCore/Sources/EditorCore/Analysis/ShotBoundaryDetector.swift Packages/EditorCore/Tests/EditorCoreTests/ShotBoundaryDetectorTests.swift && git commit -m "feat(analysis): add shot boundary detector using pixel histogram diffing"
```

---

### Task 2: Scene Describer (Apple On-Device VLM)

**Files:**
- Create: `Packages/EditorCore/Sources/EditorCore/Analysis/SceneDescriber.swift`

This component wraps Apple's on-device VLM to generate natural language descriptions of video frames. Because the on-device VLM requires macOS 26+ and Apple Silicon, this component uses `#available` checks and fails gracefully on unsupported systems.

- [ ] **Step 1: Write SceneDescriber**

```swift
// SceneDescriber.swift
import Foundation
import AVFoundation
import FoundationModels

/// Describes video frames using Apple's on-device VLM.
/// Requires macOS 26+ and Apple Silicon. Falls back to empty descriptions on unsupported systems.
public struct SceneDescriber: Sendable {

    public init() {}

    /// Check if on-device VLM is available on this system.
    public var isAvailable: Bool {
        if #available(macOS 26, *) {
            return LanguageModel.isAvailable
        }
        return false
    }

    /// Describe a single video frame using the on-device VLM.
    /// - Parameters:
    ///   - image: CGImage to describe
    ///   - context: Optional context hint (e.g., "This is from a podcast recording")
    /// - Returns: Natural language description, or empty string if VLM unavailable.
    public func describe(image: CGImage, context: String? = nil) async -> String {
        guard #available(macOS 26, *) else { return "" }
        return await describeWithVLM(image: image, context: context)
    }

    /// Describe multiple frames in batch, with progress reporting.
    /// - Parameters:
    ///   - frames: Array of (timestamp, CGImage) pairs
    ///   - context: Optional context hint
    ///   - progress: Progress callback (0.0 to 1.0)
    /// - Returns: Array of (timestamp, description) pairs in same order.
    public func describeBatch(
        frames: [(time: TimeInterval, image: CGImage)],
        context: String? = nil,
        progress: @escaping @Sendable (Double) -> Void
    ) async -> [(time: TimeInterval, description: String)] {
        guard !frames.isEmpty else { return [] }

        var results: [(time: TimeInterval, description: String)] = []

        for (index, frame) in frames.enumerated() {
            let description = await describe(image: frame.image, context: context)
            results.append((time: frame.time, description: description))
            progress(Double(index + 1) / Double(frames.count))
        }

        return results
    }

    // MARK: - Private

    @available(macOS 26, *)
    private func describeWithVLM(image: CGImage, context: String?) -> String {
        // Use Apple's on-device LanguageModel for vision
        // The exact API shape depends on Apple's FoundationModels framework
        // This will be refined once macOS 26 SDK is available
        do {
            let session = LanguageModelSession()
            let prompt = """
            Describe what is happening in this video frame. Focus on:
            - People: count, actions, expressions, gestures
            - Setting: location, lighting, atmosphere
            - Composition: shot type (close-up, medium, wide), camera angle
            - Mood: emotional tone of the scene
            Keep it to 1-2 sentences.
            """
            let response = try await session.respond(to: prompt, with: .init(images: [image]))
            return response.content
        } catch {
            return ""
        }
    }
}
```

Note: The `FoundationModels` import and `LanguageModelSession` API will need to match Apple's actual SDK when building against macOS 26. The structure above follows Apple's announced API shape. Adjust method signatures to match the actual SDK.

- [ ] **Step 2: Verify the file compiles**

```bash
cd VideoEditor/Packages/EditorCore && swift build 2>&1 | tail -10
```

If `FoundationModels` is not available in the current SDK, wrap the import and VLM code in `#if canImport(FoundationModels)` and provide a stub fallback:

```swift
#if canImport(FoundationModels)
import FoundationModels
#endif
```

And in `describeWithVLM`:
```swift
#if canImport(FoundationModels)
    // VLM implementation
#else
    return ""
#endif
```

- [ ] **Step 3: Commit**

```bash
cd VideoEditor && git add Packages/EditorCore/Sources/EditorCore/Analysis/SceneDescriber.swift && git commit -m "feat(analysis): add SceneDescriber wrapping Apple on-device VLM"
```

---

### Task 3: Update SceneSegment Model

**Files:**
- Modify: `Packages/EditorCore/Sources/EditorCore/Models/MediaAsset.swift:100-110`

The existing `SceneSegment` needs a `thumbnailPath` field for storing the representative frame.

- [ ] **Step 1: Add thumbnailPath to SceneSegment**

In `MediaAsset.swift`, update the `SceneSegment` struct:

```swift
public struct SceneSegment: Codable, Sendable {
    public var range: TimeRange
    public var description: String
    public var label: String?
    public var thumbnailPath: String?

    public init(range: TimeRange, description: String, label: String? = nil, thumbnailPath: String? = nil) {
        self.range = range
        self.description = description
        self.label = label
        self.thumbnailPath = thumbnailPath
    }
}
```

- [ ] **Step 2: Verify it compiles**

```bash
cd VideoEditor/Packages/EditorCore && swift build 2>&1 | tail -10
```

Expected: Build succeeds. The new parameter has a default value so existing call sites are unaffected.

- [ ] **Step 3: Commit**

```bash
cd VideoEditor && git add Packages/EditorCore/Sources/EditorCore/Models/MediaAsset.swift && git commit -m "feat(models): add thumbnailPath to SceneSegment"
```

---

### Task 4: Visual Scene Analyzer (Orchestrator)

**Files:**
- Create: `Packages/EditorCore/Sources/EditorCore/Analysis/VisualSceneAnalyzer.swift`
- Test: `Packages/EditorCore/Tests/EditorCoreTests/VisualSceneAnalyzerTests.swift`

This orchestrates `ShotBoundaryDetector` + `SceneDescriber` + frame extraction into `[SceneSegment]`.

- [ ] **Step 1: Write failing test for the orchestrator**

```swift
// VisualSceneAnalyzerTests.swift
import XCTest
@testable import EditorCore

final class VisualSceneAnalyzerTests: XCTestCase {

    func testProducesSceneSegmentsFromVideo() async throws {
        // Create a 3-second video with 3 distinct color scenes (red, green, blue)
        let url = try TestVideoGenerator.createTestVideo(
            frames: 90, colors: [.red, .green, .blue], fps: 30
        )
        let analyzer = VisualSceneAnalyzer()
        let cacheDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_scenes_\(UUID().uuidString)")

        let scenes = try await analyzer.analyze(url: url, thumbnailCacheDir: cacheDir) { _ in }

        // Should have 3 scenes (one per color block)
        XCTAssertEqual(scenes.count, 3)

        // Scenes should cover the full duration without gaps
        XCTAssertEqual(scenes.first?.range.start, 0.0, accuracy: 0.5)

        // Each scene should have a description (may be empty if VLM unavailable)
        for scene in scenes {
            XCTAssertTrue(scene.range.duration > 0, "Scene duration should be positive")
        }

        // Thumbnails should be saved
        for scene in scenes {
            if let path = scene.thumbnailPath {
                XCTAssertTrue(FileManager.default.fileExists(atPath: path), "Thumbnail should exist at \(path)")
            }
        }

        // Cleanup
        try? FileManager.default.removeItem(at: cacheDir)
    }

    func testSingleSceneVideoProducesOneSegment() async throws {
        // 2 seconds of solid red — no shot changes
        let url = try TestVideoGenerator.createTestVideo(
            frames: 60, colors: [.red], fps: 30
        )
        let analyzer = VisualSceneAnalyzer()
        let cacheDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_scenes_\(UUID().uuidString)")

        let scenes = try await analyzer.analyze(url: url, thumbnailCacheDir: cacheDir) { _ in }

        XCTAssertEqual(scenes.count, 1)
        XCTAssertEqual(scenes[0].range.start, 0.0, accuracy: 0.1)

        try? FileManager.default.removeItem(at: cacheDir)
    }
}
```

Move the `createTestVideo` helper from Task 1's test into a shared `TestVideoGenerator` struct:

```swift
// Add to the test file or a shared test utility
import AVFoundation
import CoreGraphics

enum TestVideoGenerator {
    static func createTestVideo(frames: Int, colors: [CGColor], fps: Int) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test_\(UUID().uuidString).mov")
        let width = 64
        let height = 64
        let framesPerColor = frames / colors.count

        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
            ]
        )
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        for i in 0..<frames {
            let colorIndex = min(i / framesPerColor, colors.count - 1)
            let color = colors[colorIndex]

            while !input.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.01)
            }

            var pixelBuffer: CVPixelBuffer?
            CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32ARGB, nil, &pixelBuffer)
            guard let buffer = pixelBuffer else { continue }

            CVPixelBufferLockBaseAddress(buffer, [])
            let context = CGContext(
                data: CVPixelBufferGetBaseAddress(buffer),
                width: width, height: height,
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
            )!
            context.setFillColor(color)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            CVPixelBufferUnlockBaseAddress(buffer, [])

            let time = CMTime(value: CMTimeValue(i), timescale: CMTimeScale(fps))
            adaptor.append(buffer, withPresentationTime: time)
        }

        input.markAsFinished()
        await writer.finishWriting()
        return url
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd VideoEditor/Packages/EditorCore && swift test --filter VisualSceneAnalyzerTests 2>&1 | tail -20
```

Expected: Compilation error — `VisualSceneAnalyzer` not defined.

- [ ] **Step 3: Implement VisualSceneAnalyzer**

```swift
// VisualSceneAnalyzer.swift
import Foundation
import AVFoundation

/// Orchestrates shot boundary detection, frame extraction, and VLM description
/// to produce scene-level visual understanding of a video.
public struct VisualSceneAnalyzer: Sendable {

    private let shotDetector = ShotBoundaryDetector()
    private let describer = SceneDescriber()

    public init() {}

    /// Analyze a video and produce scene segments with descriptions.
    /// - Parameters:
    ///   - url: Video file URL (use proxy for speed on 4K+ content)
    ///   - thumbnailCacheDir: Directory to save representative frame thumbnails
    ///   - progress: Progress callback (0.0 to 1.0)
    /// - Returns: Array of SceneSegments covering the full video duration.
    public func analyze(
        url: URL,
        thumbnailCacheDir: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> [SceneSegment] {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        guard duration > 0 else { return [] }

        // Stage 1: Detect shot boundaries (0% - 30%)
        progress(0.05)
        let boundaries = try await shotDetector.detect(url: url, threshold: 0.3, sampleInterval: 0.5)
        progress(0.30)

        // Build time ranges from boundaries
        let sceneRanges = buildSceneRanges(boundaries: boundaries, duration: duration)

        // Stage 2: Extract representative frames (30% - 50%)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 360)

        try? FileManager.default.createDirectory(at: thumbnailCacheDir, withIntermediateDirectories: true)

        var frames: [(time: TimeInterval, image: CGImage, thumbnailPath: String?)] = []

        for (index, range) in sceneRanges.enumerated() {
            let midpoint = (range.start + range.end) / 2.0
            let cmTime = CMTime(seconds: midpoint, preferredTimescale: 600)

            var thumbnailPath: String? = nil
            if let cgImage = try? await generator.image(at: cmTime).image {
                // Save thumbnail
                let filename = "scene_\(index).jpg"
                let thumbURL = thumbnailCacheDir.appendingPathComponent(filename)
                if saveThumbnail(cgImage, to: thumbURL) {
                    thumbnailPath = thumbURL.path
                }
                frames.append((time: midpoint, image: cgImage, thumbnailPath: thumbnailPath))
            } else {
                frames.append((time: midpoint, image: createPlaceholderImage(), thumbnailPath: nil))
            }

            progress(0.30 + 0.20 * Double(index + 1) / Double(sceneRanges.count))
        }

        // Stage 3: Describe scenes with VLM (50% - 100%)
        let descriptions: [(time: TimeInterval, description: String)]
        if describer.isAvailable {
            descriptions = await describer.describeBatch(
                frames: frames.map { ($0.time, $0.image) },
                context: nil,
                progress: { p in progress(0.50 + 0.50 * p) }
            )
        } else {
            // VLM unavailable — use empty descriptions
            descriptions = frames.map { ($0.time, "") }
            progress(1.0)
        }

        // Combine into SceneSegments
        var scenes: [SceneSegment] = []
        for (index, range) in sceneRanges.enumerated() {
            let description = index < descriptions.count ? descriptions[index].description : ""
            let thumbnailPath = index < frames.count ? frames[index].thumbnailPath : nil

            scenes.append(SceneSegment(
                range: range,
                description: description,
                label: nil,
                thumbnailPath: thumbnailPath
            ))
        }

        return scenes
    }

    // MARK: - Private

    /// Convert shot boundary timestamps into contiguous time ranges.
    private func buildSceneRanges(boundaries: [TimeInterval], duration: TimeInterval) -> [TimeRange] {
        var ranges: [TimeRange] = []
        var start: TimeInterval = 0

        for boundary in boundaries.sorted() {
            if boundary > start {
                ranges.append(TimeRange(start: start, end: boundary))
            }
            start = boundary
        }

        // Final scene from last boundary to end
        if start < duration {
            ranges.append(TimeRange(start: start, end: duration))
        }

        // If no boundaries detected, whole video is one scene
        if ranges.isEmpty {
            ranges.append(TimeRange(start: 0, end: duration))
        }

        return ranges
    }

    private func saveThumbnail(_ image: CGImage, to url: URL) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil) else {
            return false
        }
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.7]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        return CGImageDestinationFinalize(destination)
    }

    private func createPlaceholderImage() -> CGImage {
        let size = 64
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil, width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: size * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1.0))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        return context.makeImage()!
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd VideoEditor/Packages/EditorCore && swift test --filter VisualSceneAnalyzerTests 2>&1 | tail -20
```

Expected: Both tests pass. VLM descriptions will be empty strings since we're likely not on macOS 26, but the pipeline still produces valid SceneSegments.

- [ ] **Step 5: Commit**

```bash
cd VideoEditor && git add Packages/EditorCore/Sources/EditorCore/Analysis/VisualSceneAnalyzer.swift Packages/EditorCore/Tests/EditorCoreTests/VisualSceneAnalyzerTests.swift && git commit -m "feat(analysis): add VisualSceneAnalyzer orchestrating shot detection + VLM description"
```

---

### Task 5: Integrate into LocalAnalysisPipeline

**Files:**
- Modify: `Packages/EditorCore/Sources/EditorCore/Analysis/LocalAnalysisPipeline.swift`

- [ ] **Step 1: Add visual scene analysis stage to the pipeline**

In `LocalAnalysisPipeline.swift`, add a `VisualSceneAnalyzer` instance and a new analysis stage after the existing visual analysis:

```swift
public actor LocalAnalysisPipeline {
    private let silenceDetector = SilenceDetector()
    private let visualAnalyzer = VisualAnalyzer()
    private let sceneAnalyzer = VisualSceneAnalyzer()
    private var inProgress: Set<UUID> = []
    private var paused = false
```

Then in the `analyze` method, add a third stage after the existing visual analysis block (after line 53 `progress("Visual analysis complete", 0.9)`):

```swift
        // 3. Scene-level visual understanding (VLM descriptions) — only for video
        if asset.type == .video {
            progress("Analyzing scenes...", 0.6)
            let sceneCacheDir = bundleURL
                .appendingPathComponent("analysis/visual_scenes")
                .appendingPathComponent(asset.id.uuidString)

            let scenes = try? await sceneAnalyzer.analyze(
                url: mediaURL,
                thumbnailCacheDir: sceneCacheDir
            ) { p in
                progress("Analyzing scenes...", 0.6 + 0.3 * p)
            }

            if let scenes = scenes, !scenes.isEmpty {
                await mediaManager.updateAsset(id: asset.id) { asset in
                    var analysis = asset.analysis ?? MediaAnalysis()
                    analysis.sceneDescriptions = scenes
                    asset.analysis = analysis
                }
            }
            progress("Scene analysis complete", 0.95)
        }
```

Also adjust the earlier progress values so they fit the new three-stage pipeline:
- Silence: 0.0 - 0.2
- Visual analysis (faces/OCR): 0.2 - 0.5
- Scene analysis (VLM): 0.5 - 0.95
- Done: 1.0

Update the progress calls for stages 1 and 2:

```swift
        // 1. Silence detection
        progress("Detecting silence...", 0.05)
        let silenceRanges = (try? await silenceDetector.detect(url: mediaURL)) ?? []

        await mediaManager.updateAsset(id: asset.id) { asset in
            var analysis = asset.analysis ?? MediaAnalysis()
            analysis.silenceRanges = silenceRanges.map { TimeRange(start: $0.start, end: $0.end) }
            asset.analysis = analysis
        }
        progress("Silence detected", 0.2)

        // 2. Visual analysis (faces, scenes, OCR) — only for video
        if asset.type == .video {
            progress("Analyzing video frames...", 0.25)
            let visualResult = try? await visualAnalyzer.analyze(url: mediaURL, sampleInterval: 2.0)

            if let visual = visualResult {
                await mediaManager.updateAsset(id: asset.id) { asset in
                    var analysis = asset.analysis ?? MediaAnalysis()
                    analysis.shotBoundaries = visual.shotTypes.map(\.start)
                    asset.analysis = analysis
                }
                persistVisualAnalysis(visual, assetID: asset.id, bundleURL: bundleURL)
            }
            progress("Visual analysis complete", 0.5)
        }
```

- [ ] **Step 2: Verify it compiles**

```bash
cd VideoEditor/Packages/EditorCore && swift build 2>&1 | tail -10
```

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
cd VideoEditor && git add Packages/EditorCore/Sources/EditorCore/Analysis/LocalAnalysisPipeline.swift && git commit -m "feat(pipeline): add scene-level visual analysis stage to LocalAnalysisPipeline"
```

---

### Task 6: Add get_visual_scenes Tool Definition

**Files:**
- Modify: `Packages/AIServices/Sources/AIServices/Tools/AIToolRegistry.swift`

- [ ] **Step 1: Add the tool definition**

In `AIToolRegistry.swift`, add a new static property after `getTranscript` (around line 99):

```swift
    public static let getVisualScenes = AIToolDefinition(
        name: "get_visual_scenes",
        description: "Get visual scene descriptions for an asset. Returns scene boundaries with natural language descriptions of what's visually happening (people, actions, setting, mood). Only available after visual analysis completes on import.",
        parameters: .object([
            "asset_id": .init(type: "string", description: "UUID of the asset to get visual scenes for"),
            "start_time": .init(type: "number", description: "Optional: only return scenes after this time (seconds)"),
            "end_time": .init(type: "number", description: "Optional: only return scenes before this time (seconds)"),
        ], required: ["asset_id"])
    )
```

Then add `getVisualScenes` to the `allTools` array. Insert it after `getTranscript` (line 52):

```swift
        getTranscript,
        getVisualScenes,
        transcribeAsset,
```

- [ ] **Step 2: Verify it compiles**

```bash
cd VideoEditor/Packages/AIServices && swift build 2>&1 | tail -10
```

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
cd VideoEditor && git add Packages/AIServices/Sources/AIServices/Tools/AIToolRegistry.swift && git commit -m "feat(tools): add get_visual_scenes tool definition to AIToolRegistry"
```

---

### Task 7: Add Tool Handlers (AIChatController + MCPServer)

**Files:**
- Modify: `VideoEditor/App/AIChatController.swift`
- Modify: `VideoEditor/App/MCPServer.swift`

- [ ] **Step 1: Add handler in AIChatController**

In `AIChatController.swift`, after the `get_transcript` handler block (around line 327), add:

```swift
            if toolCall.name == "get_visual_scenes" {
                processingStatus = "Reading visual scenes..."
                let result = await handleGetVisualScenes(args: args, appState: appState)
                return .init(toolName: toolCall.name, success: true, message: result)
            }
```

Then add the handler method in the same file (near the other handle methods):

```swift
    private func handleGetVisualScenes(args: [String: Any], appState: AppState) async -> String {
        guard let assetIDStr = args["asset_id"] as? String,
              let assetID = UUID(uuidString: assetIDStr),
              let asset = appState.assets.first(where: { $0.id == assetID }) else {
            return "Error: asset not found"
        }

        guard let scenes = asset.analysis?.sceneDescriptions, !scenes.isEmpty else {
            return "No visual scenes available for '\(asset.name)'. Visual analysis may not have completed yet."
        }

        let startTime = args["start_time"] as? Double
        let endTime = args["end_time"] as? Double

        let filtered = scenes.filter { scene in
            if let start = startTime, scene.range.end < start { return false }
            if let end = endTime, scene.range.start > end { return false }
            return true
        }

        var output = "Visual scenes for '\(asset.name)' (\(filtered.count) scenes):\n"
        for (i, scene) in filtered.enumerated() {
            let start = String(format: "%.1f", scene.range.start)
            let end = String(format: "%.1f", scene.range.end)
            let desc = scene.description.isEmpty ? "(no description — VLM unavailable)" : scene.description
            output += "\(i+1). [\(start)s - \(end)s] \(desc)"
            if let label = scene.label { output += " [\(label)]" }
            output += "\n"
        }
        return output
    }
```

- [ ] **Step 2: Add handler in MCPServer**

In `MCPServer.swift`, after the `get_transcript` handler (around line 809), add:

```swift
        if name == "get_visual_scenes" {
            return await handleGetVisualScenes(arguments, appState: appState)
        }
```

Then add the handler method:

```swift
    private func handleGetVisualScenes(_ arguments: [String: Any], appState: AppState) async -> String {
        guard let assetIDStr = arguments["asset_id"] as? String,
              let assetID = UUID(uuidString: assetIDStr),
              let asset = await appState.assets.first(where: { $0.id == assetID }) else {
            return "Error: asset not found"
        }

        guard let scenes = asset.analysis?.sceneDescriptions, !scenes.isEmpty else {
            return "No visual scenes available for '\(asset.name)'. Visual analysis may not have completed yet."
        }

        let startTime = arguments["start_time"] as? Double
        let endTime = arguments["end_time"] as? Double

        let filtered = scenes.filter { scene in
            if let start = startTime, scene.range.end < start { return false }
            if let end = endTime, scene.range.start > end { return false }
            return true
        }

        var output = "Visual scenes for '\(asset.name)' (\(filtered.count) scenes):\n"
        for (i, scene) in filtered.enumerated() {
            let start = String(format: "%.1f", scene.range.start)
            let end = String(format: "%.1f", scene.range.end)
            let desc = scene.description.isEmpty ? "(no description — VLM unavailable)" : scene.description
            output += "\(i+1). [\(start)s - \(end)s] \(desc)"
            if let label = scene.label { output += " [\(label)]" }
            output += "\n"
        }
        return output
    }
```

- [ ] **Step 3: Verify the full app compiles**

```bash
cd VideoEditor && xcodegen generate && xcodebuild -scheme VideoEditor -destination 'platform=macOS' build 2>&1 | tail -20
```

Expected: Build succeeds.

- [ ] **Step 4: Commit**

```bash
cd VideoEditor && git add VideoEditor/App/AIChatController.swift VideoEditor/App/MCPServer.swift && git commit -m "feat(tools): add get_visual_scenes handlers to AIChatController and MCPServer"
```

---

### Task 8: Update AIContextBuilder

**Files:**
- Modify: `Packages/AIServices/Sources/AIServices/Context/AIContextBuilder.swift`

- [ ] **Step 1: Add visualSceneCount to AssetSummary**

In `AIContextBuilder.swift`, update the `AssetSummary` struct (line 143) to include scene count:

```swift
    public struct AssetSummary: Codable, Sendable {
        public let id: String
        public let name: String
        public let type: String
        public let duration: TimeInterval
        public let hasTranscript: Bool
        public let silenceRangeCount: Int
        public let hasAnalysis: Bool
        public let visualSceneCount: Int
    }
```

Then update the `AssetSummary` construction in `buildContext` (line 42-52):

```swift
        let assetSummaries = level == .minimal ? nil : assets.map { asset in
            AIContext.AssetSummary(
                id: asset.id.uuidString,
                name: asset.name,
                type: asset.type.rawValue,
                duration: asset.duration,
                hasTranscript: asset.analysis?.transcript != nil,
                silenceRangeCount: asset.analysis?.silenceRanges?.count ?? 0,
                hasAnalysis: asset.analysis != nil,
                visualSceneCount: asset.analysis?.sceneDescriptions?.count ?? 0
            )
        }
```

- [ ] **Step 2: Verify it compiles**

```bash
cd VideoEditor/Packages/AIServices && swift build 2>&1 | tail -10
```

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
cd VideoEditor && git add Packages/AIServices/Sources/AIServices/Context/AIContextBuilder.swift && git commit -m "feat(context): add visualSceneCount to AI context AssetSummary"
```

---

### Task 9: Update System Prompt

**Files:**
- Modify: `Packages/AIServices/Sources/AIServices/Providers/ClaudeProvider.swift`

- [ ] **Step 1: Add visual_context section to system prompt**

In `ClaudeProvider.swift`, add a `<visual_context>` block after the `</context_guide>` closing tag (after line 186):

```swift
        <visual_context>
        - Assets with visualSceneCount > 0 have scene-level visual descriptions available.
        - Call get_visual_scenes to see what's happening visually at each point in the video.
        - Use visual scenes together with transcripts for content-aware editing decisions.
        - Prefer cutting at scene boundaries when possible — they mark natural visual transitions.
        - When matching B-roll, consider visual mood and setting, not just transcript topic.
        - Visual scenes describe: people (count, actions, expressions), setting, composition, mood.
        </visual_context>
```

- [ ] **Step 2: Verify it compiles**

```bash
cd VideoEditor/Packages/AIServices && swift build 2>&1 | tail -10
```

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
cd VideoEditor && git add Packages/AIServices/Sources/AIServices/Providers/ClaudeProvider.swift && git commit -m "feat(prompt): add visual_context guidance to AI system prompt"
```

---

### Task 10: Full Integration Test

**Files:**
- No new files — verify everything works end-to-end

- [ ] **Step 1: Run all EditorCore tests**

```bash
cd VideoEditor/Packages/EditorCore && swift test 2>&1 | tail -30
```

Expected: All tests pass, including the new `ShotBoundaryDetectorTests` and `VisualSceneAnalyzerTests`.

- [ ] **Step 2: Run all AIServices tests**

```bash
cd VideoEditor/Packages/AIServices && swift test 2>&1 | tail -30
```

Expected: All tests pass (or pre-existing failures only — no new failures).

- [ ] **Step 3: Build the full app**

```bash
cd VideoEditor && xcodegen generate && xcodebuild -scheme VideoEditor -destination 'platform=macOS' build 2>&1 | tail -20
```

Expected: Build succeeds.

- [ ] **Step 4: Verify MCP tool listing includes get_visual_scenes**

Start the app, then:

```bash
curl -s -X POST http://localhost:8420/mcp -H 'Content-Type: application/json' -d '{"jsonrpc":"2.0","method":"tools/list","id":1}' | python3 -m json.tool | grep -A2 "get_visual_scenes"
```

Expected: `get_visual_scenes` appears in the tool list with its description and parameters.

- [ ] **Step 5: Commit any fixes**

If any fixes were needed during integration testing:

```bash
cd VideoEditor && git add -A && git commit -m "fix: integration test fixes for visual scene understanding"
```
