import Foundation
import CoreGraphics
import Accelerate

/// Measures visual properties of frames to verify effects actually rendered.
/// Compares composition frame against source frame — the effect should have
/// changed the image in the expected direction.
public struct EffectPropertyChecker: Sendable {

    public struct EffectCheckResult: Sendable {
        public let effectType: String
        public let passed: Bool
        public let detail: String
    }

    public init() {}

    /// Check that the applied effects actually changed the frame as expected.
    /// Returns nil if no effects to check, or a list of per-effect results.
    public func check(
        compositionFrame: CGImage,
        sourceFrame: CGImage,
        effects: [EffectInstance]
    ) -> [EffectCheckResult] {
        guard !effects.isEmpty else { return [] }

        let compProps = measureProperties(compositionFrame)
        let srcProps = measureProperties(sourceFrame)

        return effects.map { effect in
            checkEffect(effect, compProps: compProps, srcProps: srcProps)
        }
    }

    // MARK: - Frame Properties

    struct FrameProperties {
        let meanLuminance: Float      // 0-255, average brightness
        let luminanceStdDev: Float    // Standard deviation of brightness
        let laplacianVariance: Float  // Sharpness measure (higher = sharper)
        let meanChroma: Float         // Average color saturation
    }

    func measureProperties(_ image: CGImage) -> FrameProperties {
        let size = 128
        guard let grayscale = toGrayscaleFloats(image, size: size) else {
            return FrameProperties(meanLuminance: 0, luminanceStdDev: 0, laplacianVariance: 0, meanChroma: 0)
        }

        let n = vDSP_Length(size * size)

        // Mean luminance
        var mean: Float = 0
        vDSP_meanv(grayscale, 1, &mean, n)

        // Luminance standard deviation
        var meanSq: Float = 0
        var squared = [Float](repeating: 0, count: size * size)
        vDSP_vsq(grayscale, 1, &squared, 1, n)
        vDSP_meanv(squared, 1, &meanSq, n)
        let variance = max(meanSq - mean * mean, 0)
        let stdDev = sqrt(variance)

        // Laplacian variance (sharpness)
        let laplacianVar = computeLaplacianVariance(grayscale, width: size, height: size)

        // Chroma (from original color image)
        let chroma = measureChroma(image, size: size)

        return FrameProperties(
            meanLuminance: mean,
            luminanceStdDev: stdDev,
            laplacianVariance: laplacianVar,
            meanChroma: chroma
        )
    }

    // MARK: - Per-Effect Checks

    private func checkEffect(
        _ effect: EffectInstance,
        compProps: FrameProperties,
        srcProps: FrameProperties
    ) -> EffectCheckResult {
        switch effect.type {
        case "colorCorrection":
            return checkColorCorrection(effect, compProps: compProps, srcProps: srcProps)
        case "blur":
            return checkBlur(effect, compProps: compProps, srcProps: srcProps)
        case "sharpen":
            return checkSharpen(compProps: compProps, srcProps: srcProps)
        default:
            // Unknown effect — just check frame isn't identical to source
            let lumDelta = abs(compProps.meanLuminance - srcProps.meanLuminance)
            let sharpDelta = abs(compProps.laplacianVariance - srcProps.laplacianVariance)
            let changed = lumDelta > 1.0 || sharpDelta > 0.5
            return EffectCheckResult(
                effectType: effect.type,
                passed: changed,
                detail: changed ? "frame modified" : "frame unchanged — effect may not have rendered"
            )
        }
    }

    private func checkColorCorrection(
        _ effect: EffectInstance,
        compProps: FrameProperties,
        srcProps: FrameProperties
    ) -> EffectCheckResult {
        let brightness = effect.parameters["brightness"] ?? 0
        let contrast = effect.parameters["contrast"] ?? 1
        let saturation = effect.parameters["saturation"] ?? 1

        var issues: [String] = []

        // Brightness: composition should be brighter/darker than source
        if abs(brightness) > 0.02 {
            let lumDelta = compProps.meanLuminance - srcProps.meanLuminance
            let expectedDirection = brightness > 0 ? "brighter" : "darker"
            let actuallyChanged = brightness > 0 ? lumDelta > 0.5 : lumDelta < -0.5
            if !actuallyChanged {
                issues.append("brightness \(expectedDirection) not detected (delta=\(String(format: "%.1f", lumDelta)))")
            }
        }

        // Contrast: higher contrast = higher luminance std dev
        if abs(contrast - 1.0) > 0.05 {
            let stdDevRatio = srcProps.luminanceStdDev > 0.1 ? compProps.luminanceStdDev / srcProps.luminanceStdDev : 1
            let expectedDirection = contrast > 1 ? "increased" : "decreased"
            let actuallyChanged = contrast > 1 ? stdDevRatio > 1.02 : stdDevRatio < 0.98
            if !actuallyChanged {
                issues.append("contrast \(expectedDirection) not detected (ratio=\(String(format: "%.2f", stdDevRatio)))")
            }
        }

        // Saturation: 0 = grayscale (chroma near 0), higher = more colorful
        if abs(saturation - 1.0) > 0.05 {
            let chromaDelta = compProps.meanChroma - srcProps.meanChroma
            let expectedDirection = saturation > 1 ? "increased" : "decreased"
            let actuallyChanged = saturation > 1 ? chromaDelta > 0.5 : chromaDelta < -0.5
            if !actuallyChanged && srcProps.meanChroma > 2.0 {
                issues.append("saturation \(expectedDirection) not detected (delta=\(String(format: "%.1f", chromaDelta)))")
            }
        }

        if issues.isEmpty {
            return EffectCheckResult(effectType: "colorCorrection", passed: true, detail: "brightness/contrast/saturation verified")
        }
        return EffectCheckResult(effectType: "colorCorrection", passed: false, detail: issues.joined(separator: "; "))
    }

    private func checkBlur(
        _ effect: EffectInstance,
        compProps: FrameProperties,
        srcProps: FrameProperties
    ) -> EffectCheckResult {
        let radius = effect.parameters["radius"] ?? 0
        guard radius > 1 else {
            return EffectCheckResult(effectType: "blur", passed: true, detail: "radius too small to detect")
        }

        // Blur reduces Laplacian variance (high-frequency content)
        guard srcProps.laplacianVariance > 0.1 else {
            return EffectCheckResult(effectType: "blur", passed: true, detail: "source too flat to measure blur")
        }

        let ratio = compProps.laplacianVariance / srcProps.laplacianVariance
        // Blur with radius 10+ should reduce Laplacian variance by at least 20%
        let passed = ratio < 0.9
        return EffectCheckResult(
            effectType: "blur",
            passed: passed,
            detail: passed
                ? "sharpness reduced by \(Int((1 - ratio) * 100))%"
                : "sharpness not reduced (ratio=\(String(format: "%.2f", ratio))) — blur may not have rendered"
        )
    }

    private func checkSharpen(compProps: FrameProperties, srcProps: FrameProperties) -> EffectCheckResult {
        guard srcProps.laplacianVariance > 0.1 else {
            return EffectCheckResult(effectType: "sharpen", passed: true, detail: "source too flat to measure sharpening")
        }

        let ratio = compProps.laplacianVariance / srcProps.laplacianVariance
        let passed = ratio > 1.05
        return EffectCheckResult(
            effectType: "sharpen",
            passed: passed,
            detail: passed
                ? "sharpness increased by \(Int((ratio - 1) * 100))%"
                : "sharpness not increased (ratio=\(String(format: "%.2f", ratio))) — sharpen may not have rendered"
        )
    }

    // MARK: - Image Processing Helpers

    private func toGrayscaleFloats(_ image: CGImage, size: Int) -> [Float]? {
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

    private func computeLaplacianVariance(_ grayscale: [Float], width: Int, height: Int) -> Float {
        // 3x3 Laplacian kernel: [0,1,0; 1,-4,1; 0,1,0]
        let kernel: [Float] = [0, 1, 0, 1, -4, 1, 0, 1, 0]
        var output = [Float](repeating: 0, count: width * height)

        // Manual convolution (safe for test sizes)
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                var sum: Float = 0
                for ky in -1...1 {
                    for kx in -1...1 {
                        let pixel = grayscale[(y + ky) * width + (x + kx)]
                        let k = kernel[(ky + 1) * 3 + (kx + 1)]
                        sum += pixel * k
                    }
                }
                output[y * width + x] = sum
            }
        }

        // Variance of the Laplacian
        let n = vDSP_Length(width * height)
        var mean: Float = 0
        vDSP_meanv(output, 1, &mean, n)
        var squared = [Float](repeating: 0, count: width * height)
        vDSP_vsq(output, 1, &squared, 1, n)
        var meanSq: Float = 0
        vDSP_meanv(squared, 1, &meanSq, n)
        return max(meanSq - mean * mean, 0)
    }

    private func measureChroma(_ image: CGImage, size: Int) -> Float {
        // Extract RGB, compute chroma as max(R,G,B) - min(R,G,B) per pixel, then average
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixels, width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: size * 4,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return 0 }
        context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))

        var totalChroma: Float = 0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let r = Float(pixels[i])
            let g = Float(pixels[i + 1])
            let b = Float(pixels[i + 2])
            let maxC = max(r, max(g, b))
            let minC = min(r, min(g, b))
            totalChroma += maxC - minC
        }
        return totalChroma / Float(size * size)
    }
}
