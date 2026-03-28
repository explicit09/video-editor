import Foundation
import Vision
import CoreImage

/// AI-powered masking using Vision framework person segmentation.
/// Isolates people from backgrounds without green screen.
public struct PersonMasker: Sendable {

    public init() {}

    /// Generate a person segmentation mask for a single frame.
    /// Returns a CIImage mask (white = person, black = background).
    public static func generateMask(for image: CGImage) -> CIImage? {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .balanced // .accurate for export, .fast for preview
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try? handler.perform([request])

        guard let result = request.results?.first else {
            return nil
        }

        return CIImage(cvPixelBuffer: result.pixelBuffer)
    }

    /// Apply person mask to isolate subject from background.
    /// Returns the person on transparent background.
    public static func isolatePerson(image: CIImage, cgImage: CGImage) -> CIImage? {
        guard let mask = generateMask(for: cgImage) else { return image }

        // Scale mask to match image size
        let scaleX = image.extent.width / mask.extent.width
        let scaleY = image.extent.height / mask.extent.height
        let scaledMask = mask.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        // Apply mask: blend image with transparent using mask
        return image.applyingFilter("CIBlendWithMask", parameters: [
            "inputBackgroundImage": CIImage(color: .clear).cropped(to: image.extent),
            "inputMaskImage": scaledMask,
        ])
    }

    /// Replace background behind person with a solid color.
    public static func replaceBackground(
        image: CIImage,
        cgImage: CGImage,
        backgroundColor: CIColor
    ) -> CIImage? {
        guard let mask = generateMask(for: cgImage) else { return image }

        let scaleX = image.extent.width / mask.extent.width
        let scaleY = image.extent.height / mask.extent.height
        let scaledMask = mask.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        let background = CIImage(color: backgroundColor).cropped(to: image.extent)

        return image.applyingFilter("CIBlendWithMask", parameters: [
            "inputBackgroundImage": background,
            "inputMaskImage": scaledMask,
        ])
    }

    /// Replace background with another image/video frame.
    public static func replaceBackground(
        image: CIImage,
        cgImage: CGImage,
        backgroundImage: CIImage
    ) -> CIImage? {
        guard let mask = generateMask(for: cgImage) else { return image }

        let scaleX = image.extent.width / mask.extent.width
        let scaleY = image.extent.height / mask.extent.height
        let scaledMask = mask.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        let scaledBg = backgroundImage.cropped(to: image.extent)

        return image.applyingFilter("CIBlendWithMask", parameters: [
            "inputBackgroundImage": scaledBg,
            "inputMaskImage": scaledMask,
        ])
    }
}
