import Foundation
import AVFoundation
import CoreGraphics

/// Detects shot boundaries in video by comparing per-frame luminance histograms.
/// A boundary is recorded when consecutive frames differ beyond a threshold.
public struct ShotBoundaryDetector: Sendable {

    public init() {}

    /// Detect shot boundaries in a video file.
    /// - Parameters:
    ///   - url: Video file URL
    ///   - threshold: Normalized L1 histogram difference (0..1) that triggers a boundary (default 0.3)
    ///   - sampleInterval: Time between sampled frames in seconds (default 0.5)
    /// - Returns: Array of timestamps (in seconds) where shot boundaries occur
    public func detect(
        url: URL,
        threshold: Double = 0.3,
        sampleInterval: TimeInterval = 0.5
    ) async throws -> [TimeInterval] {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let totalSeconds = CMTimeGetSeconds(duration)

        guard totalSeconds > 0 else { return [] }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        // Use low resolution for speed
        generator.maximumSize = CGSize(width: 160, height: 90)
        generator.requestedTimeToleranceBefore = CMTime(seconds: sampleInterval / 2, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter  = CMTime(seconds: sampleInterval / 2, preferredTimescale: 600)

        // Build list of sample times
        var times: [CMTime] = []
        var t: TimeInterval = 0
        while t <= totalSeconds {
            times.append(CMTime(seconds: t, preferredTimescale: 600))
            t += sampleInterval
        }

        // Collect (time, histogram) pairs
        var samples: [(TimeInterval, [Int])] = []
        for requestedTime in times {
            do {
                let image: CGImage = try await withCheckedThrowingContinuation { continuation in
                    generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: requestedTime)]) {
                        _, cgImage, _, _, error in
                        if let error {
                            continuation.resume(throwing: error)
                        } else if let cgImage {
                            continuation.resume(returning: cgImage)
                        } else {
                            continuation.resume(throwing: ShotBoundaryDetectorError.frameGenerationFailed)
                        }
                    }
                }
                let histogram = computeHistogram(image)
                samples.append((CMTimeGetSeconds(requestedTime), histogram))
            } catch {
                // Skip frames that fail to decode (e.g. beyond end of media)
                continue
            }
        }

        // Compare consecutive histograms
        var boundaries: [TimeInterval] = []
        for i in 1..<samples.count {
            let (time, hist) = samples[i]
            let (_, prevHist) = samples[i - 1]
            let diff = histogramDifference(prevHist, hist)
            if diff > threshold {
                boundaries.append(time)
            }
        }

        return boundaries
    }

    // MARK: - Private Helpers

    /// Compute a 64-bin luminance histogram from a CGImage.
    private func computeHistogram(_ image: CGImage) -> [Int] {
        let width = image.width
        let height = image.height
        let pixelCount = width * height
        var histogram = [Int](repeating: 0, count: 64)

        guard pixelCount > 0 else { return histogram }

        // Render into a raw RGBA buffer
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var rawBytes = [UInt8](repeating: 0, count: pixelCount * bytesPerPixel)

        guard let ctx = CGContext(
            data: &rawBytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return histogram }

        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        for pixelIndex in 0..<pixelCount {
            let base = pixelIndex * bytesPerPixel
            let r = Double(rawBytes[base])
            let g = Double(rawBytes[base + 1])
            let b = Double(rawBytes[base + 2])
            let luminance = 0.299 * r + 0.587 * g + 0.114 * b  // 0..255
            let bin = min(Int(luminance / 256.0 * 64.0), 63)
            histogram[bin] += 1
        }

        return histogram
    }

    /// Compute normalized L1 difference between two 64-bin histograms.
    /// Returns a value in 0..1, where 0 = identical and 1 = completely different.
    private func histogramDifference(_ a: [Int], _ b: [Int]) -> Double {
        let sumA = a.reduce(0, +)
        let sumB = b.reduce(0, +)
        guard sumA > 0, sumB > 0 else { return 0 }

        var diff = 0.0
        for i in 0..<min(a.count, b.count) {
            let na = Double(a[i]) / Double(sumA)
            let nb = Double(b[i]) / Double(sumB)
            diff += abs(na - nb)
        }
        // L1 of normalized histograms ranges 0..2; normalize to 0..1
        return diff / 2.0
    }
}

// MARK: - Error

public enum ShotBoundaryDetectorError: Error, LocalizedError {
    case frameGenerationFailed

    public var errorDescription: String? {
        switch self {
        case .frameGenerationFailed: "Failed to generate video frame"
        }
    }
}
