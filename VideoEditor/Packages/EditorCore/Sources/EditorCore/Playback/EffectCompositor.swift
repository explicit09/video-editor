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
    private let renderContextLock = NSLock()
    private var _renderContext: AVVideoCompositionRenderContext?
    private var renderContext: AVVideoCompositionRenderContext? {
        renderContextLock.lock()
        defer { renderContextLock.unlock() }
        return _renderContext
    }

    public func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        renderContextLock.lock()
        _renderContext = newRenderContext
        renderContextLock.unlock()
    }

    public func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        // Handle transition instructions (two sources)
        if let transInstruction = request.videoCompositionInstruction as? TransitionInstruction {
            handleTransition(request, instruction: transInstruction)
            return
        }

        // Handle multi-track overlay instructions
        if let overlayInstruction = request.videoCompositionInstruction as? OverlayInstruction {
            handleOverlay(request, instruction: overlayInstruction)
            return
        }

        guard let instruction = request.videoCompositionInstruction as? EffectInstruction else {
            request.finish(with: NSError(domain: "EffectCompositor", code: -1))
            return
        }

        // Get the source frame
        guard let trackID = instruction.requiredSourceTrackIDs?.first as? CMPersistentTrackID,
              let sourceBuffer = request.sourceFrame(byTrackID: trackID) else {
            // No source — render explicit black frame (not uninitialized buffer)
            let renderSize = renderContext?.size ?? CGSize(width: 1920, height: 1080)
            var image = CIImage(color: .black).cropped(to: CGRect(origin: .zero, size: renderSize))

            // Still render overlay on black gaps (overlay should appear even with no video)
            if let overlay = instruction.broadcastOverlay, overlay.isEnabled {
                let time = request.compositionTime.seconds
                if let overlayImage = BroadcastOverlayRenderer.render(config: overlay, at: time, renderSize: renderSize) {
                    image = overlayImage.composited(over: image)
                }
            }

            if let outputBuffer = renderContext?.newPixelBuffer() {
                ciContext.render(image, to: outputBuffer)
                request.finish(withComposedVideoFrame: outputBuffer)
            } else {
                request.finish(with: NSError(domain: "EffectCompositor", code: -2))
            }
            return
        }

        var image = CIImage(cvPixelBuffer: sourceBuffer)

        // Short-form layout recomposition — BEFORE effects
        // Restructures 16:9 source into 9:16 with speakers stacked
        if let sfConfig = instruction.shortFormConfig, sfConfig.isEnabled {
            let renderSize = renderContext?.size ?? CGSize(width: 1080, height: 1920)
            // Map timeline time → source time for face position lookups
            let sourceTime = request.compositionTime.seconds + sfConfig.sourceTimeOffset
            image = ShortFormLayoutRenderer.recompose(
                source: image, config: sfConfig, at: sourceTime, renderSize: renderSize
            )
        } else {
            image = Self.applyCropRect(instruction.cropRect, to: image)
        }

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

        // Render subtitles / captions
        let isShortForm = instruction.shortFormConfig?.isEnabled == true
        let sfCaptionWords = instruction.shortFormConfig?.captionWords ?? []

        // Collect word-level data for styled captions.
        // NOTE: 16:9 captions require CompositionBuilder to populate captionWords on
        // EffectInstruction, which currently only happens via shortFormConfig. Threading
        // transcript words through CompositionBuilder for 16:9 is a larger change.
        var allCaptionWords = instruction.captionWords
        if allCaptionWords.isEmpty && !sfCaptionWords.isEmpty {
            let sourceOffset = instruction.shortFormConfig?.sourceTimeOffset ?? 0
            allCaptionWords = sfCaptionWords.map {
                TranscriptWord(word: $0.word, lemma: $0.lemma, start: $0.start - sourceOffset, end: $0.end - sourceOffset, confidence: $0.confidence)
            }
        }

        // Use CaptionStyler when we have word-level data and captions are enabled
        let captionStyle = instruction.captionStyle
        if captionStyle != .none && !allCaptionWords.isEmpty {
            let time = request.compositionTime.seconds
            let renderSize = renderContext?.size ?? CGSize(width: 1920, height: 1080)
            let fontSize = isShortForm ? renderSize.height * 0.028 : max(renderSize.height * 0.04, 18)

            // Find visible words for this time (window of ~5 words around active)
            let activeIdx = CaptionStyler.activeWordIndex(at: time, words: allCaptionWords)
            if let idx = activeIdx {
                // Compute word progress (0-1 within active word)
                let activeWord = allCaptionWords[idx]
                let wordDuration = activeWord.end - activeWord.start
                let wordProgress = wordDuration > 0 ? Float((time - activeWord.start) / wordDuration) : 0

                // For hormozi, show only active word; for others, window of ~5
                let windowStart: Int
                let windowEnd: Int
                if captionStyle == .hormozi {
                    windowStart = idx
                    windowEnd = idx + 1
                } else {
                    windowStart = max(0, idx - 2)
                    windowEnd = min(allCaptionWords.count, idx + 3)
                }
                let visibleWords = Array(allCaptionWords[windowStart..<windowEnd])
                let text = visibleWords.map(\.word).joined(separator: " ")
                let localActiveIdx = idx - windowStart

                if let captionImage = CaptionStyler.renderCaption(
                    text: text,
                    activeWordIndex: localActiveIdx,
                    style: captionStyle,
                    size: renderSize,
                    fontSize: fontSize,
                    wordProgress: wordProgress
                ) {
                    let ciCaption = CIImage(cgImage: captionImage)
                    image = ciCaption.composited(over: image)
                }

                // Progress bar for short-form
                if isShortForm, let firstWord = allCaptionWords.first, let lastWord = allCaptionWords.last {
                    let totalProgress = Float((time - firstWord.start) / (lastWord.end - firstWord.start))
                    if let barImage = CaptionStyler.renderProgressBar(
                        progress: max(0, min(1, totalProgress)),
                        size: renderSize,
                        barColor: CGColor(red: 1, green: 1, blue: 1, alpha: 0.9)
                    ) {
                        let ciBar = CIImage(cgImage: barImage)
                        image = ciBar.composited(over: image)
                    }
                }
            }
        } else if captionStyle != .none {
            // Fallback: standard SubtitleRenderer for grouped text
            var subtitleEntries = instruction.subtitles
            if subtitleEntries.isEmpty && !allCaptionWords.isEmpty {
                subtitleEntries = SubtitleRenderer.groupWordsIntoSubtitles(allCaptionWords, wordsPerLine: 5)
            }

            if !subtitleEntries.isEmpty {
                let time = request.compositionTime.seconds
                let renderSize = renderContext?.size ?? CGSize(width: 1920, height: 1080)
                let captionMargin: CGFloat? = isShortForm ? renderSize.height * 0.03 : nil
                let captionFontSize: CGFloat? = isShortForm ? renderSize.height * 0.028 : nil

                image = SubtitleRenderer.render(
                    subtitles: subtitleEntries,
                    at: time,
                    onto: image,
                    renderSize: renderSize,
                    bottomMarginOverride: captionMargin,
                    fontSizeOverride: captionFontSize
                )
            }
        }

        // Render broadcast overlay if configured
        if let overlay = instruction.broadcastOverlay, overlay.isEnabled {
            let time = request.compositionTime.seconds
            let renderSize = renderContext?.size ?? CGSize(width: 1920, height: 1080)
            if let overlayImage = BroadcastOverlayRenderer.render(
                config: overlay, at: time, renderSize: renderSize
            ) {
                image = overlayImage.composited(over: image)
            }
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

    // MARK: - Overlay Handling (Multi-Track)

    private func handleOverlay(_ request: AVAsynchronousVideoCompositionRequest, instruction: OverlayInstruction) {
        let renderSize = renderContext?.size ?? CGSize(width: 1920, height: 1080)
        let renderRect = CGRect(origin: .zero, size: renderSize)

        // Start with black background
        var composited = CIImage(color: .black).cropped(to: renderRect)

        // Composite layers bottom-to-top
        for layer in instruction.layers {
            guard let sourceBuffer = request.sourceFrame(byTrackID: layer.trackID) else {
                continue // Skip layers with no frame at this time
            }

            var layerImage = CIImage(cvPixelBuffer: sourceBuffer)

            // Apply crop
            layerImage = Self.applyCropRect(layer.cropRect, to: layerImage)

            // Apply per-layer effects
            for effect in layer.effects {
                layerImage = applyEffect(effect, to: layerImage)
            }

            // Apply transform
            if layer.transform != .identity {
                let t = layer.transform
                var affine = CGAffineTransform.identity
                let anchorX = renderSize.width * CGFloat(t.anchorX)
                let anchorY = renderSize.height * CGFloat(t.anchorY)
                affine = affine.translatedBy(x: anchorX, y: anchorY)
                affine = affine.rotated(by: CGFloat(t.rotation) * .pi / 180)
                affine = affine.scaledBy(x: CGFloat(t.scaleX), y: CGFloat(t.scaleY))
                affine = affine.translatedBy(x: -anchorX, y: -anchorY)
                affine = affine.translatedBy(x: CGFloat(t.positionX), y: CGFloat(t.positionY))
                layerImage = layerImage.transformed(by: affine)
            }

            // Apply opacity via alpha
            if layer.opacity < 1.0 {
                layerImage = layerImage.applyingFilter("CIColorMatrix", parameters: [
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(layer.opacity)),
                ])
            }

            // Composite using blend mode
            if layer.blendMode != .normal {
                if let blendFilter = CIFilter(name: layer.blendMode.ciFilterName) {
                    blendFilter.setValue(composited, forKey: kCIInputBackgroundImageKey)
                    blendFilter.setValue(layerImage, forKey: kCIInputImageKey)
                    if let blended = blendFilter.outputImage {
                        composited = blended
                        continue
                    }
                }
            }

            // Default: source-over compositing
            composited = layerImage.composited(over: composited)
        }

        // Render broadcast overlay if configured
        if let overlay = instruction.broadcastOverlay, overlay.isEnabled {
            let time = request.compositionTime.seconds
            if let overlayImage = BroadcastOverlayRenderer.render(config: overlay, at: time, renderSize: renderSize) {
                composited = overlayImage.composited(over: composited)
            }
        }

        guard let outputBuffer = renderContext?.newPixelBuffer() else {
            request.finish(with: NSError(domain: "EffectCompositor", code: -5))
            return
        }

        ciContext.render(composited, to: outputBuffer, bounds: renderRect, colorSpace: CGColorSpaceCreateDeviceRGB())
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
    public let broadcastOverlay: BroadcastOverlayConfig?
    public let shortFormConfig: ShortFormConfig?
    public let captionStyle: CaptionStyler.CaptionStyle
    public let captionWords: [TranscriptWord]

    public init(
        timeRange: CMTimeRange,
        sourceTrackID: CMPersistentTrackID,
        effects: [EffectInstance],
        opacity: Float = 1.0,
        transform: Transform2D = .identity,
        cropRect: CropRect = .fullFrame,
        blendMode: BlendMode = .normal,
        subtitles: [SubtitleRenderer.SubtitleEntry] = [],
        broadcastOverlay: BroadcastOverlayConfig? = nil,
        shortFormConfig: ShortFormConfig? = nil,
        captionStyle: CaptionStyler.CaptionStyle = .standard,
        captionWords: [TranscriptWord] = []
    ) {
        self.timeRange = timeRange
        self.requiredSourceTrackIDs = [NSNumber(value: sourceTrackID)]
        self.effects = effects
        self.opacity = opacity
        self.transform = transform
        self.cropRect = cropRect
        self.blendMode = blendMode
        self.subtitles = subtitles
        self.broadcastOverlay = broadcastOverlay
        self.shortFormConfig = shortFormConfig
        self.captionStyle = captionStyle
        self.captionWords = captionWords
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

// MARK: - OverlayInstruction

/// Represents a single layer in a multi-track overlay composition.
public struct OverlayLayer: Sendable {
    public let trackID: CMPersistentTrackID
    public let opacity: Float
    public let transform: Transform2D
    public let cropRect: CropRect
    public let blendMode: BlendMode
    public let effects: [EffectInstance]

    public init(
        trackID: CMPersistentTrackID,
        opacity: Float = 1.0,
        transform: Transform2D = .identity,
        cropRect: CropRect = .fullFrame,
        blendMode: BlendMode = .normal,
        effects: [EffectInstance] = []
    ) {
        self.trackID = trackID
        self.opacity = opacity
        self.transform = transform
        self.cropRect = cropRect
        self.blendMode = blendMode
        self.effects = effects
    }
}

/// Instruction for compositing multiple video tracks (overlay).
/// Layers are ordered bottom-to-top (index 0 = background).
public final class OverlayInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {
    public let timeRange: CMTimeRange
    public let enablePostProcessing = false
    public let containsTweening = false
    public let requiredSourceTrackIDs: [NSValue]?
    public let passthroughTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid

    public let layers: [OverlayLayer]
    public let broadcastOverlay: BroadcastOverlayConfig?
    public let shortFormConfig: ShortFormConfig?
    public let captionStyle: CaptionStyler.CaptionStyle
    public let captionWords: [TranscriptWord]

    public init(
        timeRange: CMTimeRange,
        layers: [OverlayLayer],
        broadcastOverlay: BroadcastOverlayConfig? = nil,
        shortFormConfig: ShortFormConfig? = nil,
        captionStyle: CaptionStyler.CaptionStyle = .standard,
        captionWords: [TranscriptWord] = []
    ) {
        self.timeRange = timeRange
        self.layers = layers
        self.requiredSourceTrackIDs = layers.map { NSNumber(value: $0.trackID) }
        self.broadcastOverlay = broadcastOverlay
        self.shortFormConfig = shortFormConfig
        self.captionStyle = captionStyle
        self.captionWords = captionWords
        super.init()
    }
}
