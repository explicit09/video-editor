import Foundation
import CoreImage

/// Green screen / chroma key removal using CIFilter.
/// Removes a specified color from video frames and makes it transparent.
public struct ChromaKey: Sendable {

    /// Apply chroma key removal to an image.
    /// - Parameters:
    ///   - image: Source CIImage
    ///   - hue: Target hue to remove (0-1, green ≈ 0.33)
    ///   - tolerance: How much hue variation to include (default 0.1)
    /// - Returns: Image with the target color made transparent
    public static func apply(
        to image: CIImage,
        targetHue: Double = 0.33, // Green
        tolerance: Double = 0.1
    ) -> CIImage {
        // Use CIColorMatrix to create a simple chroma key
        // A proper implementation would use a custom CIKernel
        let minHue = targetHue - tolerance
        let maxHue = targetHue + tolerance

        // CIChromaKeyFilter approach using CIColorClamp + CIBlendWithMask
        guard let chromaFilter = ChromaKeyFilter(hue: targetHue, tolerance: tolerance) else {
            return image
        }

        chromaFilter.inputImage = image
        return chromaFilter.outputImage ?? image
    }
}

/// Custom CIFilter for chroma key (green screen removal).
private class ChromaKeyFilter: CIFilter {
    var inputImage: CIImage?
    let hue: Double
    let tolerance: Double

    init?(hue: Double, tolerance: Double) {
        self.hue = hue
        self.tolerance = tolerance
        super.init()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var outputImage: CIImage? {
        guard let input = inputImage else { return nil }

        // Create a color cube that maps the target hue to transparent
        let size = 64
        var cubeData = [Float]()

        for z in 0..<size {
            let blue = Float(z) / Float(size - 1)
            for y in 0..<size {
                let green = Float(y) / Float(size - 1)
                for x in 0..<size {
                    let red = Float(x) / Float(size - 1)

                    // Convert RGB to HSV to check hue
                    let h = rgbToHue(r: red, g: green, b: blue)
                    let s = rgbToSaturation(r: red, g: green, b: blue)

                    let isTarget = abs(Double(h) - hue) < tolerance && s > 0.3

                    if isTarget {
                        cubeData.append(contentsOf: [0, 0, 0, 0]) // Transparent
                    } else {
                        cubeData.append(contentsOf: [red, green, blue, 1.0])
                    }
                }
            }
        }

        let data = cubeData.withUnsafeBufferPointer { Data(buffer: $0) }

        let filter = CIFilter(name: "CIColorCubeWithColorSpace")!
        filter.setValue(size, forKey: "inputCubeDimension")
        filter.setValue(data, forKey: "inputCubeData")
        filter.setValue(CGColorSpaceCreateDeviceRGB(), forKey: "inputColorSpace")
        filter.setValue(input, forKey: kCIInputImageKey)

        return filter.outputImage
    }

    private func rgbToHue(r: Float, g: Float, b: Float) -> Float {
        let maxVal = max(r, g, b)
        let minVal = min(r, g, b)
        let delta = maxVal - minVal

        guard delta > 0.001 else { return 0 }

        var h: Float
        if maxVal == r {
            h = (g - b) / delta
        } else if maxVal == g {
            h = 2 + (b - r) / delta
        } else {
            h = 4 + (r - g) / delta
        }

        h /= 6
        if h < 0 { h += 1 }
        return h
    }

    private func rgbToSaturation(r: Float, g: Float, b: Float) -> Float {
        let maxVal = max(r, g, b)
        let minVal = min(r, g, b)
        guard maxVal > 0.001 else { return 0 }
        return (maxVal - minVal) / maxVal
    }
}
