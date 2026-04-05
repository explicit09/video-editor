import Foundation
import AVFoundation
import Vision
import CoreImage

/// Auto-reframes video by tracking the main subject and generating
/// crop regions for different aspect ratios.
public struct AutoReframer: Sendable {

    public enum TargetAspectRatio: String, Sendable, CaseIterable {
        case vertical = "9:16"    // TikTok, Reels, Shorts
        case square = "1:1"       // Instagram feed
        case portrait = "4:5"     // Instagram portrait
        case standard = "16:9"    // YouTube
        case ultrawide = "21:9"   // Cinematic

        public var ratio: CGFloat {
            switch self {
            case .vertical: 9.0 / 16.0
            case .square: 1.0
            case .portrait: 4.0 / 5.0
            case .standard: 16.0 / 9.0
            case .ultrawide: 21.0 / 9.0
            }
        }
    }

    public struct ReframeResult: Sendable {
        /// Per-second crop regions (normalized 0-1 coordinates)
        public let cropRegions: [(time: TimeInterval, rect: CGRect)]
        public let targetAspectRatio: TargetAspectRatio
        public let sourceSize: CGSize
    }

    public init() {}

    /// Analyze video and generate crop regions for the target aspect ratio.
    /// Tracks faces/people to keep the main subject in frame.
    public func analyze(
        url: URL,
        targetRatio: TargetAspectRatio,
        sampleInterval: TimeInterval = 0.5,
        startTime: TimeInterval? = nil,
        endTime: TimeInterval? = nil
    ) async throws -> ReframeResult {
        let asset = AVURLAsset(url: url)
        let assetDuration = try await asset.load(.duration).seconds
        let duration = endTime ?? assetDuration
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw ReframeError.noVideoTrack
        }

        let sourceSize = try await videoTrack.load(.naturalSize)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 360) // Small for fast face detection
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)

        var cropRegions: [(time: TimeInterval, rect: CGRect)] = []
        var previousCenter = CGPoint(x: 0.5, y: 0.5) // Start centered

        var time: TimeInterval = startTime ?? 0
        while time < duration {
            let cmTime = CMTime(seconds: time, preferredTimescale: 600)

            // Generate frame
            guard let cgImage = try? generator.copyCGImage(at: cmTime, actualTime: nil) else {
                // Use previous crop region
                cropRegions.append((time: time, rect: cropRect(center: previousCenter, sourceSize: sourceSize, targetRatio: targetRatio)))
                time += sampleInterval
                continue
            }

            // Detect faces
            let faceCenter = await detectMainSubject(in: cgImage)
            let center = faceCenter ?? previousCenter

            // Smooth the center position to avoid jittery crops
            let smoothed = CGPoint(
                x: previousCenter.x * 0.6 + center.x * 0.4,
                y: previousCenter.y * 0.6 + center.y * 0.4
            )

            let rect = cropRect(center: smoothed, sourceSize: sourceSize, targetRatio: targetRatio)
            cropRegions.append((time: time, rect: rect))

            previousCenter = smoothed
            time += sampleInterval
        }

        return ReframeResult(
            cropRegions: cropRegions,
            targetAspectRatio: targetRatio,
            sourceSize: sourceSize
        )
    }

    /// Detect the main subject's center position using face detection.
    private func detectMainSubject(in image: CGImage) async -> CGPoint? {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])

        do {
            try handler.perform([request])
            guard let results = request.results, !results.isEmpty else { return nil }

            // Use the largest face as the main subject
            let mainFace = results.max(by: { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height })
            guard let face = mainFace else { return nil }

            // Return center of the face bounding box (in normalized coordinates)
            return CGPoint(
                x: face.boundingBox.midX,
                y: 1.0 - face.boundingBox.midY // Vision uses bottom-left origin
            )
        } catch {
            return nil
        }
    }

    /// Calculate the crop rectangle for a given center and target aspect ratio.
    private func cropRect(center: CGPoint, sourceSize: CGSize, targetRatio: TargetAspectRatio) -> CGRect {
        let sourceAspect = sourceSize.width / sourceSize.height
        let targetAspect = targetRatio.ratio

        let cropWidth: CGFloat
        let cropHeight: CGFloat

        if targetAspect < sourceAspect {
            // Target is taller (e.g., 9:16 from 16:9) — crop width
            cropHeight = 1.0
            cropWidth = targetAspect / sourceAspect
        } else {
            // Target is wider — crop height
            cropWidth = 1.0
            cropHeight = sourceAspect / targetAspect
        }

        // Center the crop on the subject, clamped to frame bounds
        let x = min(max(center.x - cropWidth / 2, 0), 1.0 - cropWidth)
        let y = min(max(center.y - cropHeight / 2, 0), 1.0 - cropHeight)

        return CGRect(x: x, y: y, width: cropWidth, height: cropHeight)
    }
}

public enum ReframeError: Error, LocalizedError {
    case noVideoTrack

    public var errorDescription: String? {
        switch self {
        case .noVideoTrack: "No video track found"
        }
    }
}
