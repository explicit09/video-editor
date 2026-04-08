import Foundation

// MARK: - Clip (Reference + Instructions)

public struct Clip: Codable, Identifiable, Sendable {
    public let id: UUID
    public var assetID: UUID
    public var timelineRange: TimeRange
    public var sourceRange: TimeRange
    public var transform: Transform2D
    public var cropRect: CropRect
    public var opacity: Double
    public var volume: Double
    public var effects: [EffectInstance]
    public var audioEffects: AudioEffectChain?
    public var textOverlays: [TextOverlay]
    public var keyframes: KeyframeStore
    public var metadata: ClipMetadata
    /// Playback speed multiplier. 1.0 = normal, 0.5 = half speed, 2.0 = double speed.
    public var speed: Double
    /// Transition applied when entering this clip (from the previous clip or black).
    public var transitionIn: ClipTransition
    /// Links video+audio clip pairs. Edits to one propagate to all clips with the same linkGroupID.
    public var linkGroupID: UUID?
    /// Compositing blend mode for this clip.
    public var blendMode: BlendMode
    /// Clip-owned overlay presentation state used for PiP and similar layouts.
    public var overlayPresentation: OverlayPresentation

    public init(
        id: UUID = UUID(),
        assetID: UUID,
        timelineRange: TimeRange,
        sourceRange: TimeRange,
        transform: Transform2D = .identity,
        cropRect: CropRect = .fullFrame,
        opacity: Double = 1.0,
        volume: Double = 1.0,
        effects: [EffectInstance] = [],
        audioEffects: AudioEffectChain? = nil,
        textOverlays: [TextOverlay] = [],
        keyframes: KeyframeStore = KeyframeStore(),
        metadata: ClipMetadata = ClipMetadata(),
        speed: Double = 1.0,
        transitionIn: ClipTransition = .none,
        linkGroupID: UUID? = nil,
        blendMode: BlendMode = .normal,
        overlayPresentation: OverlayPresentation = .default
    ) {
        self.id = id
        self.assetID = assetID
        self.timelineRange = timelineRange
        self.sourceRange = sourceRange
        self.transform = transform
        self.cropRect = cropRect.clamped
        self.opacity = min(max(opacity, 0), 1)
        self.volume = max(volume, 0)
        self.effects = effects
        self.audioEffects = audioEffects
        self.textOverlays = textOverlays
        self.keyframes = keyframes
        self.metadata = metadata
        self.speed = max(speed, 0.1) // minimum 0.1x
        self.transitionIn = transitionIn
        self.linkGroupID = linkGroupID
        self.blendMode = blendMode
        self.overlayPresentation = overlayPresentation
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case assetID
        case timelineRange
        case sourceRange
        case transform
        case cropRect
        case opacity
        case volume
        case effects
        case audioEffects
        case textOverlays
        case keyframes
        case metadata
        case speed
        case transitionIn
        case linkGroupID
        case blendMode
        case overlayPresentation
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.assetID = try container.decode(UUID.self, forKey: .assetID)
        self.timelineRange = try container.decode(TimeRange.self, forKey: .timelineRange)
        self.sourceRange = try container.decode(TimeRange.self, forKey: .sourceRange)
        self.transform = try container.decode(Transform2D.self, forKey: .transform)
        self.cropRect = try container.decode(CropRect.self, forKey: .cropRect).clamped
        self.opacity = min(max(try container.decode(Double.self, forKey: .opacity), 0), 1)
        self.volume = max(try container.decode(Double.self, forKey: .volume), 0)
        self.effects = try container.decode([EffectInstance].self, forKey: .effects)
        self.audioEffects = try container.decodeIfPresent(AudioEffectChain.self, forKey: .audioEffects)
        self.textOverlays = try container.decodeIfPresent([TextOverlay].self, forKey: .textOverlays) ?? []
        self.keyframes = try container.decode(KeyframeStore.self, forKey: .keyframes)
        self.metadata = try container.decode(ClipMetadata.self, forKey: .metadata)
        self.speed = max(try container.decode(Double.self, forKey: .speed), 0.1)
        self.transitionIn = try container.decode(ClipTransition.self, forKey: .transitionIn)
        self.linkGroupID = try container.decodeIfPresent(UUID.self, forKey: .linkGroupID)
        self.blendMode = try container.decode(BlendMode.self, forKey: .blendMode)
        self.overlayPresentation = try container.decodeIfPresent(OverlayPresentation.self, forKey: .overlayPresentation) ?? .default
    }
}

// MARK: - TimeRange

public struct TimeRange: Codable, Sendable, Equatable {
    public var start: TimeInterval
    public var end: TimeInterval

    public var duration: TimeInterval { end - start }

    public init(start: TimeInterval, end: TimeInterval) {
        self.start = max(start, 0)
        self.end = max(end, self.start)
    }

    public init(start: TimeInterval, duration: TimeInterval) {
        self.start = max(start, 0)
        self.end = self.start + max(duration, 0)
    }

    /// An empty range at time zero.
    public static let empty = TimeRange(start: 0, end: 0)

    public func contains(_ time: TimeInterval) -> Bool {
        time >= start && time < end
    }

    public func overlaps(_ other: TimeRange) -> Bool {
        start < other.end && end > other.start
    }
}

// MARK: - TrimEdge

public enum TrimEdge: String, Codable, Sendable {
    case head  // trim the start
    case tail  // trim the end
}

// MARK: - CropRect

public struct CropRect: Codable, Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(
        x: Double = 0,
        y: Double = 0,
        width: Double = 1,
        height: Double = 1
    ) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public static let fullFrame = CropRect()

    public var isFullFrame: Bool {
        clamped == .fullFrame
    }

    public var clamped: CropRect {
        let clampedX = min(max(x, 0), 1)
        let clampedY = min(max(y, 0), 1)
        let clampedWidth = min(max(width, 0.05), 1 - clampedX)
        let clampedHeight = min(max(height, 0.05), 1 - clampedY)
        return CropRect(
            x: clampedX,
            y: clampedY,
            width: clampedWidth,
            height: clampedHeight
        )
    }
}

// MARK: - Transform2D

public struct Transform2D: Codable, Sendable, Equatable {
    public var positionX: Double
    public var positionY: Double
    public var scaleX: Double
    public var scaleY: Double
    public var rotation: Double
    public var anchorX: Double
    public var anchorY: Double

    public init(
        positionX: Double = 0,
        positionY: Double = 0,
        scaleX: Double = 1,
        scaleY: Double = 1,
        rotation: Double = 0,
        anchorX: Double = 0.5,
        anchorY: Double = 0.5
    ) {
        self.positionX = positionX
        self.positionY = positionY
        self.scaleX = scaleX
        self.scaleY = scaleY
        self.rotation = rotation
        self.anchorX = anchorX
        self.anchorY = anchorY
    }

    public static let identity = Transform2D()
}

// MARK: - ClipTransition

public struct ClipTransition: Codable, Sendable, Equatable {
    public var type: TransitionType
    public var duration: TimeInterval

    public init(type: TransitionType = .none, duration: TimeInterval = 0.5) {
        self.type = type
        self.duration = max(duration, 0)
    }

    public static let none = ClipTransition(type: .none, duration: 0)
}

public enum TransitionType: String, Codable, Sendable, CaseIterable {
    case none
    case crossDissolve
    case fadeToBlack
    case fadeFromBlack
    case wipeLeft
    case wipeRight
}

// MARK: - ClipMetadata (AI-enrichable)

public struct ClipMetadata: Codable, Sendable {
    public var label: String?
    public var tags: [String]
    public var transcriptSegment: TranscriptSegment?
    public var sceneType: String?

    public init(
        label: String? = nil,
        tags: [String] = [],
        transcriptSegment: TranscriptSegment? = nil,
        sceneType: String? = nil
    ) {
        self.label = label
        self.tags = tags
        self.transcriptSegment = transcriptSegment
        self.sceneType = sceneType
    }
}

// MARK: - TranscriptSegment

public struct TranscriptSegment: Codable, Sendable {
    public var text: String
    public var words: [TranscriptWord]

    public init(text: String, words: [TranscriptWord] = []) {
        self.text = text
        self.words = words
    }
}

public struct TranscriptWord: Codable, Sendable {
    public var word: String
    public var lemma: String?
    public var start: TimeInterval
    public var end: TimeInterval
    public var confidence: Double

    public init(word: String, lemma: String? = nil, start: TimeInterval, end: TimeInterval, confidence: Double = 1.0) {
        self.word = word
        self.lemma = lemma
        self.start = start
        self.end = end
        self.confidence = confidence
    }
}

// MARK: - Effect & Keyframe stubs

public struct EffectInstance: Codable, Sendable, Identifiable {
    public let id: UUID
    public var type: String
    public var parameters: [String: Double]
    public var stringParameters: [String: String]
    public var isEnabled: Bool

    public init(id: UUID = UUID(), type: String, parameters: [String: Double] = [:], stringParameters: [String: String] = [:], isEnabled: Bool = true) {
        self.id = id
        self.type = type
        self.parameters = parameters
        self.stringParameters = stringParameters
        self.isEnabled = isEnabled
    }
}

extension EffectInstance {
    /// Create a basic color correction effect.
    public static func colorCorrection(
        brightness: Double = 0,      // -1.0 to 1.0
        contrast: Double = 1.0,      // 0.0 to 4.0
        saturation: Double = 1.0,    // 0.0 to 3.0
        temperature: Double = 6500   // Kelvin, 2000-10000
    ) -> EffectInstance {
        EffectInstance(
            type: "colorCorrection",
            parameters: [
                "brightness": brightness,
                "contrast": contrast,
                "saturation": saturation,
                "temperature": temperature,
            ]
        )
    }

    public static func lut(path: String) -> EffectInstance {
        EffectInstance(
            type: typeLUT,
            stringParameters: ["path": path]
        )
    }

    public static func videoDenoise(level: Double = 0.5, sharpness: Double = 0.4) -> EffectInstance {
        EffectInstance(
            type: typeVideoDenoise,
            parameters: [
                "level": level,
                "sharpness": sharpness,
            ]
        )
    }

    public static func chromaKey(targetHue: Double = 0.33, tolerance: Double = 0.1) -> EffectInstance {
        EffectInstance(
            type: typeChromaKey,
            parameters: [
                "targetHue": targetHue,
                "tolerance": tolerance,
            ]
        )
    }

    public static func vignette(intensity: Double = 0.5, feather: Double = 0.7) -> EffectInstance {
        EffectInstance(type: typeVignette, parameters: ["intensity": intensity, "feather": feather])
    }

    /// Known effect type constants.
    public static let typeColorCorrection = "colorCorrection"
    public static let typeLUT = "lut"
    public static let typeBlur = "blur"
    public static let typeSharpen = "sharpen"
    public static let typeVideoDenoise = "videoDenoise"
    public static let typeChromaKey = "chromaKey"
    public static let typeVignette = "vignette"
}

public struct KeyframeStore: Codable, Sendable {
    public var tracks: [String: [Keyframe]]

    public init(tracks: [String: [Keyframe]] = [:]) {
        self.tracks = tracks
    }
}

public struct Keyframe: Codable, Sendable {
    public var time: TimeInterval
    public var value: Double
    public var interpolation: KeyframeInterpolation

    public init(time: TimeInterval, value: Double, interpolation: KeyframeInterpolation = .linear) {
        self.time = time
        self.value = value
        self.interpolation = interpolation
    }
}

public enum KeyframeInterpolation: String, Codable, Sendable {
    case linear
    case hold
    case easeIn
    case easeOut
    case easeInOut
}
