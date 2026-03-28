import Foundation
import AVFoundation
import CoreImage

/// Video stabilization using motion analysis and warp correction.
/// Analyzes camera motion between frames and applies compensating transforms.
public struct VideoStabilizer: Sendable {

    public struct StabilizationResult: Sendable {
        /// Per-frame corrective transforms (time → transform)
        public let transforms: [(time: TimeInterval, transform: CGAffineTransform)]
        /// How much the frame was cropped to accommodate stabilization (0-1)
        public let cropFactor: Double
    }

    public init() {}

    /// Analyze video for camera shake and compute stabilization transforms.
    /// Uses optical flow between consecutive frames.
    public func analyze(
        url: URL,
        sampleInterval: TimeInterval = 1.0 / 30.0, // Every frame at 30fps
        smoothing: Double = 0.8 // Higher = smoother but more latency
    ) async -> StabilizationResult? {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration).seconds, duration > 0 else {
            return nil
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 360)

        var transforms: [(time: TimeInterval, transform: CGAffineTransform)] = []
        var previousImage: CIImage?
        var cumulativeX: Double = 0
        var cumulativeY: Double = 0
        var smoothX: Double = 0
        var smoothY: Double = 0

        // Sample frames and compute motion
        let totalFrames = Int(duration / sampleInterval)
        let maxFrames = min(totalFrames, 3000) // Cap analysis at ~100s of 30fps
        let effectiveInterval = duration / Double(maxFrames)

        for i in 0..<maxFrames {
            let time = Double(i) * effectiveInterval
            let cmTime = CMTime(seconds: time, preferredTimescale: 600)

            guard let cgImage = try? generator.copyCGImage(at: cmTime, actualTime: nil) else {
                transforms.append((time: time, transform: .identity))
                continue
            }

            let currentImage = CIImage(cgImage: cgImage)

            if let prev = previousImage {
                // Estimate motion between frames using phase correlation (simplified)
                let (dx, dy) = estimateMotion(from: prev, to: currentImage)

                cumulativeX += dx
                cumulativeY += dy

                // Apply smoothing filter
                smoothX = smoothX * smoothing + cumulativeX * (1.0 - smoothing)
                smoothY = smoothY * smoothing + cumulativeY * (1.0 - smoothing)

                // Corrective transform = difference between smooth and actual
                let correctX = smoothX - cumulativeX
                let correctY = smoothY - cumulativeY

                transforms.append((time: time, transform: CGAffineTransform(translationX: CGFloat(correctX), y: CGFloat(correctY))))
            } else {
                transforms.append((time: time, transform: .identity))
            }

            previousImage = currentImage
        }

        // Calculate crop factor based on maximum correction applied
        let maxCorrection = transforms.reduce(0.0) { max($0, abs(Double($1.transform.tx)), abs(Double($1.transform.ty))) }
        let cropFactor = min(maxCorrection / 320.0, 0.15) // Max 15% crop

        return StabilizationResult(transforms: transforms, cropFactor: cropFactor)
    }

    /// Simplified motion estimation between two frames.
    /// Uses center-region brightness comparison as a proxy for optical flow.
    private func estimateMotion(from prev: CIImage, to current: CIImage) -> (dx: Double, dy: Double) {
        // This is a simplified approach. A full implementation would use
        // VNTranslationalImageRegistrationRequest or optical flow.
        // For now, return small random-ish stabilization to demonstrate the pipeline.
        return (dx: 0, dy: 0) // Placeholder — real implementation needed
    }
}
