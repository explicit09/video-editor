import Foundation
import CoreImage

/// Video noise reduction using CIFilter pipeline.
/// Reduces digital noise/grain from low-light footage.
public struct VideoDenoiser: Sendable {

    /// Apply noise reduction to a single frame.
    /// Uses CINoiseReduction for spatial denoising.
    public static func denoise(
        image: CIImage,
        level: Double = 0.5, // 0-1, how aggressive
        sharpness: Double = 0.4 // 0-1, how much to sharpen after
    ) -> CIImage {
        var result = image

        // Noise reduction
        result = result.applyingFilter("CINoiseReduction", parameters: [
            "inputNoiseLevel": level * 0.05, // Scale to CIFilter range
            "inputSharpness": sharpness,
        ])

        return result
    }

    /// Apply temporal noise reduction by blending with previous frame.
    /// More effective than spatial-only but requires frame history.
    public static func temporalDenoise(
        current: CIImage,
        previous: CIImage?,
        blendFactor: Double = 0.3 // How much of previous frame to blend
    ) -> CIImage {
        guard let previous else {
            return denoise(image: current)
        }

        // Blend current with previous for temporal smoothing
        let blended = current.applyingFilter("CIDissolveTransition", parameters: [
            "inputTargetImage": previous,
            "inputTime": blendFactor,
        ])

        // Apply spatial denoise on top
        return denoise(image: blended, level: 0.3)
    }
}
