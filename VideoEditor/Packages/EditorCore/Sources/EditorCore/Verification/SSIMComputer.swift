import Foundation
import CoreGraphics
import Accelerate

/// Computes Structural Similarity Index (SSIM) between two images.
/// Uses the Wang et al. algorithm with 11x11 Gaussian window.
/// Score range: 0.0 (completely different) to 1.0 (identical).
public struct SSIMComputer: Sendable {

    // Constants for 8-bit images (L = 255)
    private let c1: Float = 6.5025     // (0.01 * 255)^2
    private let c2: Float = 58.5225    // (0.03 * 255)^2
    private let targetSize = 256

    public init() {}

    /// Compute SSIM between two CGImages. Both are resized to 256x256 grayscale.
    /// Returns MSSIM (mean SSIM over all local windows).
    public func compute(_ imageA: CGImage, _ imageB: CGImage) -> Float {
        guard let a = toGrayscale(imageA),
              let b = toGrayscale(imageB) else { return 0 }

        let n = targetSize * targetSize

        // Compute local means using box filter (approximation of Gaussian for speed)
        let windowSize = 11
        let muA = boxFilter(a, width: targetSize, height: targetSize, windowSize: windowSize)
        let muB = boxFilter(b, width: targetSize, height: targetSize, windowSize: windowSize)

        // mu^2
        var muA2 = [Float](repeating: 0, count: n)
        var muB2 = [Float](repeating: 0, count: n)
        var muAB = [Float](repeating: 0, count: n)
        vDSP_vmul(muA, 1, muA, 1, &muA2, 1, vDSP_Length(n))
        vDSP_vmul(muB, 1, muB, 1, &muB2, 1, vDSP_Length(n))
        vDSP_vmul(muA, 1, muB, 1, &muAB, 1, vDSP_Length(n))

        // sigma^2 = E[X^2] - E[X]^2
        var a2 = [Float](repeating: 0, count: n)
        var b2 = [Float](repeating: 0, count: n)
        var ab = [Float](repeating: 0, count: n)
        vDSP_vmul(a, 1, a, 1, &a2, 1, vDSP_Length(n))
        vDSP_vmul(b, 1, b, 1, &b2, 1, vDSP_Length(n))
        vDSP_vmul(a, 1, b, 1, &ab, 1, vDSP_Length(n))

        let sigmaA2_raw = boxFilter(a2, width: targetSize, height: targetSize, windowSize: windowSize)
        let sigmaB2_raw = boxFilter(b2, width: targetSize, height: targetSize, windowSize: windowSize)
        let sigmaAB_raw = boxFilter(ab, width: targetSize, height: targetSize, windowSize: windowSize)

        // sigma^2 = E[X^2] - mu^2
        var sigmaA2 = [Float](repeating: 0, count: n)
        var sigmaB2 = [Float](repeating: 0, count: n)
        var sigmaAB = [Float](repeating: 0, count: n)
        vDSP_vsub(muA2, 1, sigmaA2_raw, 1, &sigmaA2, 1, vDSP_Length(n))
        vDSP_vsub(muB2, 1, sigmaB2_raw, 1, &sigmaB2, 1, vDSP_Length(n))
        vDSP_vsub(muAB, 1, sigmaAB_raw, 1, &sigmaAB, 1, vDSP_Length(n))

        // SSIM = (2*muA*muB + C1)(2*sigmaAB + C2) / (muA^2 + muB^2 + C1)(sigmaA^2 + sigmaB^2 + C2)
        var ssimMap = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let numerator = (2 * muA[i] * muB[i] + c1) * (2 * sigmaAB[i] + c2)
            let denominator = (muA2[i] + muB2[i] + c1) * (sigmaA2[i] + sigmaB2[i] + c2)
            ssimMap[i] = denominator > 0 ? numerator / denominator : 1.0
        }

        // Mean SSIM
        var mssim: Float = 0
        vDSP_meanv(ssimMap, 1, &mssim, vDSP_Length(n))
        return max(0, min(1, mssim))
    }

    // MARK: - Helpers

    /// Convert CGImage to 256x256 grayscale float array (0-255 range).
    private func toGrayscale(_ image: CGImage) -> [Float]? {
        let size = targetSize
        let colorSpace = CGColorSpaceCreateDeviceGray()
        var pixels = [UInt8](repeating: 0, count: size * size)
        guard let context = CGContext(
            data: &pixels, width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: size,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        return pixels.map { Float($0) }
    }

    /// Simple box filter (mean filter) as approximation of Gaussian window.
    private func boxFilter(_ input: [Float], width: Int, height: Int, windowSize: Int) -> [Float] {
        let half = windowSize / 2
        var output = [Float](repeating: 0, count: width * height)
        let area = Float(windowSize * windowSize)

        for y in 0..<height {
            for x in 0..<width {
                var sum: Float = 0
                let yMin = max(0, y - half)
                let yMax = min(height - 1, y + half)
                let xMin = max(0, x - half)
                let xMax = min(width - 1, x + half)

                for wy in yMin...yMax {
                    for wx in xMin...xMax {
                        sum += input[wy * width + wx]
                    }
                }
                output[y * width + x] = sum / area
            }
        }
        return output
    }
}
