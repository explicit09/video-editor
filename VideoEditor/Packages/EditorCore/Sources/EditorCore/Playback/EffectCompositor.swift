import Foundation
import AVFoundation
import CoreImage

/// Custom AVVideoCompositing that applies CIFilter effects per-frame.
/// Used by CompositionBuilder when clips have effects, transforms, or opacity.
public final class EffectCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {

    // Required properties
    public var sourcePixelBufferAttributes: [String: any Sendable]? {
        [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    }

    public var requiredPixelBufferAttributesForRenderContext: [String: any Sendable] {
        [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    }

    private let ciContext = CIContext(options: [.workingColorSpace: CGColorSpaceCreateDeviceRGB()])
    private var renderContext: AVVideoCompositionRenderContext?

    public func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        renderContext = newRenderContext
    }

    public func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        // Handle transition instructions (two sources)
        if let transInstruction = request.videoCompositionInstruction as? TransitionInstruction {
            handleTransition(request, instruction: transInstruction)
            return
        }

        guard let instruction = request.videoCompositionInstruction as? EffectInstruction else {
            request.finish(with: NSError(domain: "EffectCompositor", code: -1))
            return
        }

        // Get the source frame
        guard let trackID = instruction.requiredSourceTrackIDs?.first as? CMPersistentTrackID,
              let sourceBuffer = request.sourceFrame(byTrackID: trackID) else {
            // No source — return empty frame
            if let outputBuffer = renderContext?.newPixelBuffer() {
                request.finish(withComposedVideoFrame: outputBuffer)
            } else {
                request.finish(with: NSError(domain: "EffectCompositor", code: -2))
            }
            return
        }

        var image = CIImage(cvPixelBuffer: sourceBuffer)
        image = Self.applyCropRect(instruction.cropRect, to: image)

        // Apply effects in order
        for effect in instruction.effects {
            image = applyEffect(effect, to: image)
        }

        // Apply opacity
        if instruction.opacity < 1.0 {
            image = image.applyingFilter("CIColorMatrix", parameters: [
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(instruction.opacity)),
            ])
        }

        // Apply transform
        if instruction.transform != .identity {
            let t = instruction.transform
            var affine = CGAffineTransform.identity
            // Move to anchor point, apply transform, move back
            let renderSize = renderContext?.size ?? CGSize(width: 1920, height: 1080)
            let anchorX = renderSize.width * CGFloat(t.anchorX)
            let anchorY = renderSize.height * CGFloat(t.anchorY)

            affine = affine.translatedBy(x: anchorX, y: anchorY)
            affine = affine.rotated(by: CGFloat(t.rotation) * .pi / 180)
            affine = affine.scaledBy(x: CGFloat(t.scaleX), y: CGFloat(t.scaleY))
            affine = affine.translatedBy(x: -anchorX, y: -anchorY)
            affine = affine.translatedBy(x: CGFloat(t.positionX), y: CGFloat(t.positionY))

            image = image.transformed(by: affine)
        }

        // Render subtitles if present
        if !instruction.subtitles.isEmpty {
            let time = request.compositionTime.seconds
            let renderSize = renderContext?.size ?? CGSize(width: 1920, height: 1080)
            image = SubtitleRenderer.render(
                subtitles: instruction.subtitles,
                at: time,
                onto: image,
                renderSize: renderSize
            )
        }

        // Apply blend mode (composites against black background for single-clip)
        if instruction.blendMode != .normal {
            let renderSize = renderContext?.size ?? CGSize(width: 1920, height: 1080)
            let background = CIImage(color: .black).cropped(to: CGRect(origin: .zero, size: renderSize))
            if let blendFilter = CIFilter(name: instruction.blendMode.ciFilterName) {
                blendFilter.setValue(background, forKey: kCIInputBackgroundImageKey)
                blendFilter.setValue(image, forKey: kCIInputImageKey)
                if let blended = blendFilter.outputImage {
                    image = blended
                }
            }
        }

        // Render to output buffer
        guard let outputBuffer = renderContext?.newPixelBuffer() else {
            request.finish(with: NSError(domain: "EffectCompositor", code: -3))
            return
        }

        let renderSize = renderContext?.size ?? CGSize(width: 1920, height: 1080)
        ciContext.render(image, to: outputBuffer, bounds: CGRect(origin: .zero, size: renderSize), colorSpace: CGColorSpaceCreateDeviceRGB())
        request.finish(withComposedVideoFrame: outputBuffer)
    }

    public func cancelAllPendingVideoCompositionRequests() {
        // No-op: synchronous processing
    }

    static func applyCropRect(_ cropRect: CropRect, to image: CIImage) -> CIImage {
        let clampedCrop = cropRect.clamped
        guard !clampedCrop.isFullFrame else { return image }

        let extent = image.extent.integral
        let cropBounds = CGRect(
            x: extent.minX + (extent.width * clampedCrop.x),
            y: extent.minY + (extent.height * clampedCrop.y),
            width: extent.width * clampedCrop.width,
            height: extent.height * clampedCrop.height
        ).intersection(extent)

        guard !cropBounds.isEmpty else { return image }

        let cropped = image.cropped(to: cropBounds)
        let normalized = cropped.transformed(
            by: CGAffineTransform(translationX: -cropBounds.minX, y: -cropBounds.minY)
        )
        let scaled = normalized.transformed(
            by: CGAffineTransform(
                scaleX: extent.width / cropBounds.width,
                y: extent.height / cropBounds.height
            )
        )
        return scaled.transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
    }

    // MARK: - Transition Handling

    private func handleTransition(_ request: AVAsynchronousVideoCompositionRequest, instruction: TransitionInstruction) {
        let renderSize = renderContext?.size ?? CGSize(width: 1920, height: 1080)

        // Calculate transition progress (0 = start, 1 = end)
        let elapsed = CMTimeSubtract(request.compositionTime, instruction.timeRange.start)
        let progress = CGFloat(elapsed.seconds / instruction.timeRange.duration.seconds)

        // Get source frames
        let fromImage: CIImage
        if let fromBuffer = request.sourceFrame(byTrackID: instruction.fromTrackID) {
            fromImage = CIImage(cvPixelBuffer: fromBuffer)
        } else {
            fromImage = CIImage(color: .black).cropped(to: CGRect(origin: .zero, size: renderSize))
        }

        let toImage: CIImage
        if let toBuffer = request.sourceFrame(byTrackID: instruction.toTrackID) {
            toImage = CIImage(cvPixelBuffer: toBuffer)
        } else {
            toImage = CIImage(color: .black).cropped(to: CGRect(origin: .zero, size: renderSize))
        }

        // Blend based on transition type
        let result: CIImage
        switch instruction.transitionType {
        case .crossDissolve:
            result = fromImage.applyingFilter("CIDissolveTransition", parameters: [
                "inputTargetImage": toImage,
                "inputTime": progress,
            ])
        case .fadeToBlack:
            let black = CIImage(color: .black).cropped(to: fromImage.extent)
            result = fromImage.applyingFilter("CIDissolveTransition", parameters: [
                "inputTargetImage": black,
                "inputTime": progress,
            ])
        case .fadeFromBlack:
            let black = CIImage(color: .black).cropped(to: toImage.extent)
            result = black.applyingFilter("CIDissolveTransition", parameters: [
                "inputTargetImage": toImage,
                "inputTime": progress,
            ])
        case .wipeLeft:
            let wipeX = renderSize.width * (1 - progress)
            let fromCropped = fromImage.cropped(to: CGRect(x: 0, y: 0, width: wipeX, height: renderSize.height))
            let toCropped = toImage.cropped(to: CGRect(x: wipeX, y: 0, width: renderSize.width - wipeX, height: renderSize.height))
            result = fromCropped.composited(over: toCropped)
        case .wipeRight:
            let wipeX = renderSize.width * progress
            let toCropped = toImage.cropped(to: CGRect(x: 0, y: 0, width: wipeX, height: renderSize.height))
            let fromCropped = fromImage.cropped(to: CGRect(x: wipeX, y: 0, width: renderSize.width - wipeX, height: renderSize.height))
            result = toCropped.composited(over: fromCropped)
        case .none:
            result = toImage
        }

        guard let outputBuffer = renderContext?.newPixelBuffer() else {
            request.finish(with: NSError(domain: "EffectCompositor", code: -4))
            return
        }

        ciContext.render(result, to: outputBuffer, bounds: CGRect(origin: .zero, size: renderSize), colorSpace: CGColorSpaceCreateDeviceRGB())
        request.finish(withComposedVideoFrame: outputBuffer)
    }

    // MARK: - Effect Application

    private func applyEffect(_ effect: EffectInstance, to image: CIImage) -> CIImage {
        guard effect.isEnabled else { return image }

        switch effect.type {
        case "colorCorrection":
            return applyColorCorrection(effect.parameters, to: image)
        case "lut":
            guard let lutPath = effect.stringParameters["path"],
                  let filter = LUTLoader.cachedFilter(at: lutPath) else {
                return image
            }
            filter.setValue(image, forKey: kCIInputImageKey)
            return filter.outputImage ?? image
        case "blur":
            let radius = effect.parameters["radius"] ?? 10
            return image.applyingFilter("CIGaussianBlur", parameters: ["inputRadius": radius])
        case "sharpen":
            let sharpness = effect.parameters["sharpness"] ?? 0.4
            return image.applyingFilter("CISharpenLuminance", parameters: ["inputSharpness": sharpness])
        default:
            return image
        }
    }

    private func applyColorCorrection(_ params: [String: Double], to image: CIImage) -> CIImage {
        var result = image

        let brightness = params["brightness"] ?? 0
        let contrast = params["contrast"] ?? 1
        let saturation = params["saturation"] ?? 1

        result = result.applyingFilter("CIColorControls", parameters: [
            "inputBrightness": brightness,
            "inputContrast": contrast,
            "inputSaturation": saturation,
        ])

        // Temperature (approximate via CITemperatureAndTint)
        if let temperature = params["temperature"], temperature != 6500 {
            let neutral = CIVector(x: CGFloat(temperature), y: 0)
            result = result.applyingFilter("CITemperatureAndTint", parameters: [
                "inputNeutral": neutral,
            ])
        }

        return result
    }
}

// MARK: - EffectInstruction

/// Custom instruction that carries per-clip effect data to the compositor.
public final class EffectInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {
    public let timeRange: CMTimeRange
    public let enablePostProcessing = false
    public let containsTweening = false
    public let requiredSourceTrackIDs: [NSValue]?
    public let passthroughTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid

    public let effects: [EffectInstance]
    public let opacity: Float
    public let transform: Transform2D
    public let cropRect: CropRect
    public let blendMode: BlendMode
    public let subtitles: [SubtitleRenderer.SubtitleEntry]

    public init(
        timeRange: CMTimeRange,
        sourceTrackID: CMPersistentTrackID,
        effects: [EffectInstance],
        opacity: Float = 1.0,
        transform: Transform2D = .identity,
        cropRect: CropRect = .fullFrame,
        blendMode: BlendMode = .normal,
        subtitles: [SubtitleRenderer.SubtitleEntry] = []
    ) {
        self.timeRange = timeRange
        self.requiredSourceTrackIDs = [NSNumber(value: sourceTrackID)]
        self.effects = effects
        self.opacity = opacity
        self.transform = transform
        self.cropRect = cropRect
        self.blendMode = blendMode
        self.subtitles = subtitles
        super.init()
    }
}

// MARK: - TransitionInstruction

/// Carries transition data for blending two clips during overlap.
public final class TransitionInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {
    public let timeRange: CMTimeRange
    public let enablePostProcessing = false
    public let containsTweening = true
    public let requiredSourceTrackIDs: [NSValue]?
    public let passthroughTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid

    public let fromTrackID: CMPersistentTrackID
    public let toTrackID: CMPersistentTrackID
    public let transitionType: TransitionType

    public init(
        timeRange: CMTimeRange,
        fromTrackID: CMPersistentTrackID,
        toTrackID: CMPersistentTrackID,
        transitionType: TransitionType
    ) {
        self.timeRange = timeRange
        self.fromTrackID = fromTrackID
        self.toTrackID = toTrackID
        self.transitionType = transitionType
        self.requiredSourceTrackIDs = [NSNumber(value: fromTrackID), NSNumber(value: toTrackID)]
        super.init()
    }
}
