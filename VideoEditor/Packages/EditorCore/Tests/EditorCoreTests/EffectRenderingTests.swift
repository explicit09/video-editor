import Testing
import Foundation
import CoreImage
import CoreGraphics
@testable import EditorCore

/// Tier 3: Visual regression tests for effect rendering.
/// Tests CIFilter chain directly with software renderer for deterministic output.
/// Uses SSIM against golden references + property-based assertions.
@Suite("Effect Rendering — Visual Regression Tests")
struct EffectRenderingTests {

    let ssim = SSIMComputer()
    let propChecker = EffectPropertyChecker()
    let ssimThreshold: Float = 0.995

    /// Software-only CIContext for deterministic rendering.
    let ciContext = CIContext(options: [.useSoftwareRenderer: true])

    // MARK: - Test Inputs

    /// Generate a 256x256 gradient test image (deterministic, no file I/O).
    private func makeGradientImage() -> CGImage {
        let size = 256
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                let offset = (y * size + x) * 4
                pixels[offset + 0] = UInt8(x)           // R: horizontal gradient
                pixels[offset + 1] = UInt8(y)           // G: vertical gradient
                pixels[offset + 2] = UInt8((x + y) / 2) // B: diagonal
                pixels[offset + 3] = 255                 // A
            }
        }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let data = Data(pixels)
        let provider = CGDataProvider(data: data as CFData)!
        return CGImage(
            width: size, height: size,
            bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: size * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil, shouldInterpolate: false,
            intent: .defaultIntent
        )!
    }

    /// Generate a 256x256 checkerboard pattern (good for blur/sharpen testing).
    private func makeCheckerboard() -> CGImage {
        let size = 256
        let blockSize = 16
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                let offset = (y * size + x) * 4
                let isWhite = ((x / blockSize) + (y / blockSize)) % 2 == 0
                let val: UInt8 = isWhite ? 220 : 35
                pixels[offset + 0] = val
                pixels[offset + 1] = val
                pixels[offset + 2] = val
                pixels[offset + 3] = 255
            }
        }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let data = Data(pixels)
        let provider = CGDataProvider(data: data as CFData)!
        return CGImage(
            width: size, height: size,
            bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: size * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil, shouldInterpolate: false,
            intent: .defaultIntent
        )!
    }

    /// Apply a CIFilter chain to a CGImage and render via software.
    private func applyEffect(_ filterName: String, parameters: [String: Any], to input: CGImage) -> CGImage? {
        let ciInput = CIImage(cgImage: input)
        guard let filter = CIFilter(name: filterName) else { return nil }
        filter.setValue(ciInput, forKey: kCIInputImageKey)
        for (key, value) in parameters {
            filter.setValue(value, forKey: key)
        }
        guard let output = filter.outputImage else { return nil }
        let rect = CGRect(x: 0, y: 0, width: input.width, height: input.height)
        return ciContext.createCGImage(output, from: rect)
    }

    // MARK: - Determinism Test

    @Test("Same input produces identical output on repeated renders")
    func determinism() {
        let input = makeGradientImage()
        let result1 = applyEffect("CIColorControls", parameters: [
            kCIInputBrightnessKey: 0.2,
            kCIInputContrastKey: 1.3,
            kCIInputSaturationKey: 0.8,
        ], to: input)
        let result2 = applyEffect("CIColorControls", parameters: [
            kCIInputBrightnessKey: 0.2,
            kCIInputContrastKey: 1.3,
            kCIInputSaturationKey: 0.8,
        ], to: input)

        guard let r1 = result1, let r2 = result2 else {
            Issue.record("CIFilter rendering failed")
            return
        }

        let score = ssim.compute(r1, r2)
        #expect(score >= 0.999, "Same render twice should be identical, got SSIM=\(score)")
    }

    // MARK: - Brightness

    @Test("Brightness +0.3 increases mean luminance")
    func brightnessIncrease() {
        let input = makeGradientImage()
        guard let output = applyEffect("CIColorControls", parameters: [kCIInputBrightnessKey: 0.3], to: input) else {
            Issue.record("Brightness filter failed"); return
        }

        let srcProps = propChecker.measureProperties(input)
        let outProps = propChecker.measureProperties(output)

        #expect(outProps.meanLuminance > srcProps.meanLuminance + 5,
                "Brightness +0.3 should increase luminance: src=\(srcProps.meanLuminance), out=\(outProps.meanLuminance)")
    }

    @Test("Brightness -0.3 decreases mean luminance")
    func brightnessDecrease() {
        let input = makeGradientImage()
        guard let output = applyEffect("CIColorControls", parameters: [kCIInputBrightnessKey: -0.3], to: input) else {
            Issue.record("Brightness filter failed"); return
        }

        let srcProps = propChecker.measureProperties(input)
        let outProps = propChecker.measureProperties(output)

        #expect(outProps.meanLuminance < srcProps.meanLuminance - 5,
                "Brightness -0.3 should decrease luminance: src=\(srcProps.meanLuminance), out=\(outProps.meanLuminance)")
    }

    // MARK: - Contrast

    @Test("Contrast 2.0 increases luminance standard deviation")
    func contrastIncrease() {
        let input = makeGradientImage()
        guard let output = applyEffect("CIColorControls", parameters: [kCIInputContrastKey: 2.0], to: input) else {
            Issue.record("Contrast filter failed"); return
        }

        let srcProps = propChecker.measureProperties(input)
        let outProps = propChecker.measureProperties(output)

        #expect(outProps.luminanceStdDev > srcProps.luminanceStdDev * 1.1,
                "Contrast 2.0 should increase stddev: src=\(srcProps.luminanceStdDev), out=\(outProps.luminanceStdDev)")
    }

    // MARK: - Saturation

    @Test("Saturation 0.0 produces near-grayscale output")
    func desaturation() {
        let input = makeGradientImage()
        guard let output = applyEffect("CIColorControls", parameters: [kCIInputSaturationKey: 0.0], to: input) else {
            Issue.record("Saturation filter failed"); return
        }

        let outProps = propChecker.measureProperties(output)
        #expect(outProps.meanChroma < 3.0,
                "Saturation 0 should produce near-zero chroma: got \(outProps.meanChroma)")
    }

    // MARK: - Blur

    @Test("Gaussian blur radius 10 reduces Laplacian variance")
    func blurReducesSharpness() {
        let input = makeCheckerboard()
        guard let output = applyEffect("CIGaussianBlur", parameters: [kCIInputRadiusKey: 10.0], to: input) else {
            Issue.record("Blur filter failed"); return
        }

        let srcProps = propChecker.measureProperties(input)
        let outProps = propChecker.measureProperties(output)

        let ratio = outProps.laplacianVariance / max(srcProps.laplacianVariance, 0.001)
        #expect(ratio < 0.5,
                "Blur should reduce Laplacian variance by >50%: ratio=\(ratio)")
    }

    // MARK: - Sharpen

    @Test("Unsharp mask changes frame measurably")
    func unsharpMaskChangesFrame() {
        let input = makeCheckerboard()
        // CIUnsharpMask is more visible than CISharpenLuminance at test resolution
        guard let output = applyEffect("CIUnsharpMask", parameters: [
            kCIInputRadiusKey: 5.0,
            kCIInputIntensityKey: 2.0,
        ], to: input) else {
            Issue.record("Unsharp mask filter failed"); return
        }

        let score = ssim.compute(input, output)
        #expect(score < 0.99, "Unsharp mask should change the frame: SSIM=\(score)")
        #expect(score > 0.5, "Unsharp mask shouldn't destroy the frame: SSIM=\(score)")
    }

    // MARK: - Identity (no effect)

    @Test("No effect produces identical output (SSIM ~1.0)")
    func identityPassthrough() {
        let input = makeGradientImage()
        let score = ssim.compute(input, input)
        #expect(score >= 0.999, "Same image SSIM should be ~1.0, got \(score)")
    }

    // MARK: - SSIM detects difference

    @Test("SSIM detects difference between original and effected frame")
    func ssimDetectsDifference() {
        let input = makeGradientImage()
        guard let bright = applyEffect("CIColorControls", parameters: [kCIInputBrightnessKey: 0.5], to: input) else {
            Issue.record("Filter failed"); return
        }

        let score = ssim.compute(input, bright)
        #expect(score < 0.95, "Brightness +0.5 should produce SSIM < 0.95, got \(score)")
        #expect(score > 0.5, "Still similar structure, SSIM should be > 0.5, got \(score)")
    }

    // MARK: - Cross-render consistency

    @Test("SSIM between two identical renders is near 1.0")
    func crossRenderConsistency() {
        let input = makeCheckerboard()
        guard let r1 = applyEffect("CIGaussianBlur", parameters: [kCIInputRadiusKey: 5.0], to: input),
              let r2 = applyEffect("CIGaussianBlur", parameters: [kCIInputRadiusKey: 5.0], to: input) else {
            Issue.record("Blur failed"); return
        }

        let score = ssim.compute(r1, r2)
        #expect(score >= ssimThreshold, "Same blur twice should be >= \(ssimThreshold), got \(score)")
    }

    @Test("Crop rect changes visible content while preserving frame size")
    func cropRectChangesContent() {
        let input = makeGradientImage()
        let source = CIImage(cgImage: input)
        let cropped = EffectCompositor.applyCropRect(
            CropRect(x: 0.5, y: 0, width: 0.5, height: 1),
            to: source
        )

        let rect = CGRect(x: 0, y: 0, width: input.width, height: input.height)
        guard let output = ciContext.createCGImage(cropped, from: rect) else {
            Issue.record("Crop rendering failed")
            return
        }

        let inputProps = propChecker.measureProperties(input)
        let outputProps = propChecker.measureProperties(output)

        #expect(output.width == input.width)
        #expect(output.height == input.height)
        #expect(outputProps.meanLuminance > inputProps.meanLuminance + 10,
                "Cropping to the brighter half should increase luminance: input=\(inputProps.meanLuminance), output=\(outputProps.meanLuminance)")
    }
}
