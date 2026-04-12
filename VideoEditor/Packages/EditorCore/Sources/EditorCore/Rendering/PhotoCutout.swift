// PhotoCutout.swift
import Foundation
import CoreImage
import CoreGraphics
import Vision

public struct PhotoCutout: Sendable {

    /// Remove background from a photo with high-quality segmentation and feathered edges.
    /// Uses Vision's .accurate quality level for clean edges suitable for thumbnails/export.
    /// Returns a CIImage of the person with transparent background and soft edge blend.
    public static func cutout(photo: Data, featherRadius: CGFloat = 6) throws -> CIImage {
        guard let ciPhoto = CIImage(data: photo) else {
            throw PhotoCutoutError.invalidImageData
        }
        guard let cgPhoto = CIContext().createCGImage(ciPhoto, from: ciPhoto.extent) else {
            throw PhotoCutoutError.invalidImageData
        }

        // Generate high-quality person mask using Vision framework
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .accurate  // Highest quality for export/thumbnails
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8

        let handler = VNImageRequestHandler(cgImage: cgPhoto, options: [:])
        try handler.perform([request])

        guard let result = request.results?.first else {
            throw PhotoCutoutError.maskGenerationFailed
        }

        var mask = CIImage(cvPixelBuffer: result.pixelBuffer)

        // Scale mask to match photo dimensions
        let photoExtent = ciPhoto.extent
        let maskExtent = mask.extent
        let scaleX = photoExtent.width / maskExtent.width
        let scaleY = photoExtent.height / maskExtent.height
        mask = mask
            .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
            .transformed(by: CGAffineTransform(translationX: photoExtent.origin.x, y: photoExtent.origin.y))

        // Feather: slight gaussian blur on the mask edges for natural blend
        // This softens only the boundary, not the whole mask
        if featherRadius > 0 {
            mask = mask.applyingGaussianBlur(sigma: Double(featherRadius))
                .cropped(to: photoExtent)
        }

        // Apply mask: person on transparent background
        let result2 = ciPhoto.applyingFilter("CIBlendWithMask", parameters: [
            "inputBackgroundImage": CIImage(color: .clear).cropped(to: photoExtent),
            "inputMaskImage": mask,
        ])

        return result2.cropped(to: photoExtent)
    }
}

public enum PhotoCutoutError: Error {
    case invalidImageData
    case maskGenerationFailed
    case filterNotAvailable
    case compositionFailed
}
