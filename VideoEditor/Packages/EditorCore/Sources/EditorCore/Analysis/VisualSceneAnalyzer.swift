import Foundation
import AVFoundation
import CoreGraphics
import ImageIO

/// Orchestrates shot boundary detection, frame extraction, and VLM description
/// to produce scene-level visual understanding of a video.
public struct VisualSceneAnalyzer: Sendable {
    private let shotDetector = ShotBoundaryDetector()
    private let describer = SceneDescriber()

    public init() {}

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

        // Build contiguous time ranges from boundaries.
        // If no boundaries detected (e.g. static talking-head podcast), fall back to
        // fixed-interval segmentation so the VLM can still describe what's happening
        // at regular intervals throughout the video.
        let sceneRanges: [TimeRange]
        if boundaries.isEmpty {
            let interval: TimeInterval = 60.0 // one scene per minute for static content
            sceneRanges = buildFixedIntervalRanges(duration: duration, interval: interval)
        } else {
            sceneRanges = buildSceneRanges(boundaries: boundaries, duration: duration)
        }

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

    /// Fixed-interval fallback for visually static content (podcasts, talking heads).
    private func buildFixedIntervalRanges(duration: TimeInterval, interval: TimeInterval) -> [TimeRange] {
        var ranges: [TimeRange] = []
        var start: TimeInterval = 0
        while start < duration {
            let end = min(start + interval, duration)
            ranges.append(TimeRange(start: start, end: end))
            start = end
        }
        return ranges
    }

    private func buildSceneRanges(boundaries: [TimeInterval], duration: TimeInterval) -> [TimeRange] {
        var ranges: [TimeRange] = []
        var start: TimeInterval = 0

        for boundary in boundaries.sorted() {
            if boundary > start {
                ranges.append(TimeRange(start: start, end: boundary))
            }
            start = boundary
        }

        if start < duration {
            ranges.append(TimeRange(start: start, end: duration))
        }

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
