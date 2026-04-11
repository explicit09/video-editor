// PhotoCutout.swift
import Foundation
import CoreImage
import CoreGraphics

public struct PhotoCutout: Sendable {

    /// Remove background from a photo and feather the edges.
    /// Returns a CIImage of the person with transparent background and soft edges.
    public static func cutout(photo: Data, featherRadius: CGFloat = 8) throws -> CIImage {
        guard let ciPhoto = CIImage(data: photo) else {
            throw PhotoCutoutError.invalidImageData
        }
        guard let cgPhoto = CIContext().createCGImage(ciPhoto, from: ciPhoto.extent) else {
            throw PhotoCutoutError.invalidImageData
        }

        // Generate person mask using Vision framework
        guard let mask = PersonMasker.generateMask(for: cgPhoto) else {
            throw PhotoCutoutError.maskGenerationFailed
        }

        // Feather the mask edges with gaussian blur
        let featheredMask: CIImage
        if featherRadius > 0 {
            let blurred = mask.applyingGaussianBlur(sigma: Double(featherRadius))
            // Crop back to original extent (blur expands the image)
            featheredMask = blurred.cropped(to: mask.extent)
        } else {
            featheredMask = mask
        }

        // Scale mask to match photo dimensions if needed
        let photoExtent = ciPhoto.extent
        let maskExtent = featheredMask.extent
        let scaleX = photoExtent.width / maskExtent.width
        let scaleY = photoExtent.height / maskExtent.height
        let scaledMask = featheredMask
            .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
            .transformed(by: CGAffineTransform(translationX: photoExtent.origin.x, y: photoExtent.origin.y))

        // Apply mask to photo: blend photo over transparent background using mask
        let result = ciPhoto.applyingFilter("CIBlendWithMask", parameters: [
            "inputBackgroundImage": CIImage(color: .clear).cropped(to: photoExtent),
            "inputMaskImage": scaledMask,
        ])

        return result.cropped(to: photoExtent)
    }
}

public enum PhotoCutoutError: Error {
    case invalidImageData
    case maskGenerationFailed
    case filterNotAvailable
    case compositionFailed
}
