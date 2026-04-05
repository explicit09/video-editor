import Foundation
import AVFoundation
import Vision
import CoreImage

/// Scores video frames for thumbnail quality.
/// Evaluates: face presence, expression visibility, focus, composition.
public struct ThumbnailScorer: Sendable {

    public struct ScoredFrame: Sendable {
        public let time: TimeInterval
        public let score: Double
        public let hasFace: Bool
        public let faceSize: Double // 0-1 relative to frame
        public let brightness: Double
        public let sharpness: Double
    }

    public init() {}

    /// Analyze video and return the top N best thumbnail candidates.
    /// Use `start`/`end` to limit the scan range (in seconds).
    public func findBestThumbnails(
        url: URL,
        count: Int = 5,
        sampleInterval: TimeInterval = 2.0,
        start: TimeInterval? = nil,
        end: TimeInterval? = nil
    ) async -> [ScoredFrame] {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration).seconds, duration > 0 else {
            return []
        }

        let scanStart = max(start ?? 1.0, 1.0)
        let scanEnd = min(end ?? duration, duration) - 1.0

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 360) // Analyze at lower res for speed

        var frames: [ScoredFrame] = []
        var time: TimeInterval = scanStart

        while time < scanEnd {
            let cmTime = CMTime(seconds: time, preferredTimescale: 600)
            guard let cgImage = try? generator.copyCGImage(at: cmTime, actualTime: nil) else {
                time += sampleInterval
                continue
            }

            let scored = await scoreFrame(cgImage, at: time)
            frames.append(scored)
            time += sampleInterval
        }

        // Return top N by score
        return Array(frames.sorted { $0.score > $1.score }.prefix(count))
    }

    /// Score a single frame for thumbnail quality.
    private func scoreFrame(_ image: CGImage, at time: TimeInterval) async -> ScoredFrame {
        var score: Double = 0
        var hasFace = false
        var faceSize: Double = 0
        var brightness: Double = 0.5
        var sharpness: Double = 0.5

        // 1. Face detection (biggest scoring factor)
        let faceRequest = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try? handler.perform([faceRequest])

        if let faces = faceRequest.results, !faces.isEmpty {
            hasFace = true
            let largestFace = faces.max(by: { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height })
            if let face = largestFace {
                faceSize = Double(face.boundingBox.width * face.boundingBox.height)
                // Score: face present (+40), large face (+20 scaled by size)
                score += 40
                score += 20 * min(faceSize * 4, 1.0) // Bonus for larger faces
            }
        }

        // 2. Brightness analysis
        let ciImage = CIImage(cgImage: image)
        let extent = ciImage.extent
        if extent.width > 0, extent.height > 0 {
            // Sample center region brightness
            let centerRect = CGRect(
                x: extent.width * 0.25, y: extent.height * 0.25,
                width: extent.width * 0.5, height: extent.height * 0.5
            )
            let cropped = ciImage.cropped(to: centerRect)

            // Use CIAreaAverage to get mean brightness
            let avgFilter = CIFilter(name: "CIAreaAverage", parameters: [
                kCIInputImageKey: cropped,
                "inputExtent": CIVector(cgRect: centerRect),
            ])
            if let outputImage = avgFilter?.outputImage {
                let context = CIContext()
                var pixel = [UInt8](repeating: 0, count: 4)
                context.render(outputImage, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
                brightness = Double(pixel[0]) / 255.0

                // Score: penalize too dark (<0.2) or too bright (>0.8)
                if brightness >= 0.2 && brightness <= 0.8 {
                    score += 15 // Good exposure
                } else if brightness >= 0.1 && brightness <= 0.9 {
                    score += 5 // Acceptable
                }
                // else: 0 bonus for bad exposure
            }
        }

        // 3. Sharpness (Laplacian variance as proxy)
        // Higher variance = sharper image
        sharpness = estimateSharpness(image)
        score += sharpness * 25 // Up to 25 points for sharp frames

        return ScoredFrame(
            time: time,
            score: score,
            hasFace: hasFace,
            faceSize: faceSize,
            brightness: brightness,
            sharpness: sharpness
        )
    }

    /// Estimate image sharpness using pixel variance.
    private func estimateSharpness(_ image: CGImage) -> Double {
        // Simple approach: compare adjacent pixels
        // High difference = sharp, low difference = blurry
        guard let data = image.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else { return 0.5 }

        let width = image.width
        let height = image.height
        let bytesPerPixel = image.bitsPerPixel / 8
        let bytesPerRow = image.bytesPerRow

        var totalDiff: Double = 0
        let sampleStep = 4 // Sample every 4th pixel for speed

        var samples = 0
        for y in stride(from: 1, to: height - 1, by: sampleStep) {
            for x in stride(from: 1, to: width - 1, by: sampleStep) {
                let idx = y * bytesPerRow + x * bytesPerPixel
                let left = Int(ptr[idx - bytesPerPixel])
                let right = Int(ptr[idx + bytesPerPixel])
                let current = Int(ptr[idx])
                totalDiff += Double(abs(current - left) + abs(current - right))
                samples += 1
            }
        }

        guard samples > 0 else { return 0.5 }
        let avgDiff = totalDiff / Double(samples) / 510.0 // Normalize to 0-1
        return min(avgDiff * 4, 1.0) // Scale up
    }
}
