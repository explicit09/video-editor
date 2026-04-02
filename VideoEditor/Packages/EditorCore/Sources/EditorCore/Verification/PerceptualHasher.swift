import Foundation
import AVFoundation
import CoreGraphics
import Accelerate

/// Perceptual hash (pHash) for video frame comparison.
/// Produces a 64-bit hash; hamming distance < 10 = same frame.
public struct PerceptualHasher: Sendable {

    public init() {}

    /// Extract a frame from a composition at the given time and compute its pHash.
    public func hash(composition: AVAsset, at time: TimeInterval, videoComposition: AVVideoComposition? = nil) async -> UInt64 {
        guard let cgImage = extractFrame(from: composition, at: time, videoComposition: videoComposition) else { return 0 }
        return computeHash(cgImage)
    }

    /// Extract a frame from a source file and compute its pHash.
    public func hash(sourceURL: URL, at time: TimeInterval) async -> UInt64 {
        guard let cgImage = extractFrame(from: AVURLAsset(url: sourceURL), at: time) else { return 0 }
        return computeHash(cgImage)
    }

    /// Hamming distance between two hashes. Lower = more similar.
    public func distance(_ a: UInt64, _ b: UInt64) -> Int {
        (a ^ b).nonzeroBitCount
    }

    /// Check if a frame is not black (has meaningful visual content).
    public func frameIsValid(composition: AVAsset, at time: TimeInterval, videoComposition: AVVideoComposition? = nil) async -> Bool {
        guard let cgImage = extractFrame(from: composition, at: time, videoComposition: videoComposition) else { return false }
        return !isBlack(cgImage)
    }

    /// Check if a source frame is not black (has meaningful visual content).
    public func frameIsValid(sourceURL: URL, at time: TimeInterval) async -> Bool {
        guard let cgImage = extractFrame(from: AVURLAsset(url: sourceURL), at: time) else { return false }
        return !isBlack(cgImage)
    }

    // MARK: - Frame Extraction

    /// Public accessor for ContentVerifier's effect checking.
    public func extractFramePublic(from asset: AVAsset, at time: TimeInterval, videoComposition: AVVideoComposition? = nil) -> CGImage? {
        extractFrame(from: asset, at: time, videoComposition: videoComposition)
    }

    private func extractFrame(from asset: AVAsset, at time: TimeInterval, videoComposition: AVVideoComposition? = nil) -> CGImage? {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)
        generator.maximumSize = CGSize(width: 128, height: 128)
        if let vc = videoComposition {
            generator.videoComposition = vc
        }
        return try? generator.copyCGImage(at: CMTime(seconds: time, preferredTimescale: 600), actualTime: nil)
    }

    // MARK: - pHash Algorithm

    /// Compute perceptual hash: resize to 32x32 grayscale, DCT, median threshold → 64-bit hash.
    private func computeHash(_ image: CGImage) -> UInt64 {
        let size = 32
        guard let grayscale = toGrayscale(image, size: size) else { return 0 }

        // Apply DCT to the 32x32 grayscale image
        let dctValues = dct2D(grayscale, width: size, height: size)

        // Take top-left 8x8 DCT coefficients (low frequencies)
        var lowFreq = [Float](repeating: 0, count: 64)
        for y in 0..<8 {
            for x in 0..<8 {
                lowFreq[y * 8 + x] = dctValues[y * size + x]
            }
        }

        // Skip DC component (index 0) for median — it dominates
        let acValues = Array(lowFreq.dropFirst())
        let sorted = acValues.sorted()
        let median = sorted[sorted.count / 2]

        // Build hash: 1 if above median, 0 if below
        var hash: UInt64 = 0
        for i in 0..<64 {
            if lowFreq[i] > median {
                hash |= (1 << i)
            }
        }

        return hash
    }

    /// Convert CGImage to 32x32 grayscale float array.
    private func toGrayscale(_ image: CGImage, size: Int) -> [Float]? {
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let bytesPerRow = size
        var pixels = [UInt8](repeating: 0, count: size * size)

        guard let context = CGContext(
            data: &pixels,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))

        return pixels.map { Float($0) }
    }

    /// Simple row-wise 1D DCT applied to a 2D signal (approximate 2D DCT).
    private func dct2D(_ input: [Float], width: Int, height: Int) -> [Float] {
        var result = [Float](repeating: 0, count: width * height)

        // Row-wise DCT
        var temp = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            let rowStart = y * width
            var row = Array(input[rowStart..<(rowStart + width)])
            var dctRow = [Float](repeating: 0, count: width)
            dct1D(&row, output: &dctRow, n: width)
            for x in 0..<width {
                temp[y * width + x] = dctRow[x]
            }
        }

        // Column-wise DCT
        for x in 0..<width {
            var col = [Float](repeating: 0, count: height)
            for y in 0..<height { col[y] = temp[y * width + x] }
            var dctCol = [Float](repeating: 0, count: height)
            dct1D(&col, output: &dctCol, n: height)
            for y in 0..<height { result[y * width + x] = dctCol[y] }
        }

        return result
    }

    /// Type II DCT (naive implementation, fine for 32-element arrays).
    private func dct1D(_ input: inout [Float], output: inout [Float], n: Int) {
        let scale = sqrt(2.0 / Float(n))
        for k in 0..<n {
            var sum: Float = 0
            for i in 0..<n {
                sum += input[i] * cos(Float.pi * Float(k) * (2 * Float(i) + 1) / (2 * Float(n)))
            }
            output[k] = sum * scale
        }
    }

    /// Check if an image is mostly black.
    private func isBlack(_ image: CGImage) -> Bool {
        guard let data = image.dataProvider?.data, let ptr = CFDataGetBytePtr(data) else { return true }
        let bpp = image.bitsPerPixel / 8
        guard bpp > 0 else { return true }
        let total = image.width * image.height
        var bright = 0
        let step = max(total / 200, 1)
        for i in stride(from: 0, to: min(total * bpp, CFDataGetLength(data)), by: step * bpp) {
            let sum = Int(ptr[i]) + Int(ptr[min(i + 1, CFDataGetLength(data) - 1)]) + Int(ptr[min(i + 2, CFDataGetLength(data) - 1)])
            if sum > 30 { bright += 1 }
        }
        return bright < 20
    }
}
