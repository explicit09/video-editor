import Foundation

// MARK: - TextAnimation

public enum TextAnimation: String, Codable, Sendable, Equatable {
    case none
    case fadeIn
    case pop
    case slideUp
}

// MARK: - TextOverlay

public struct TextOverlay: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public var text: String
    /// Time offset relative to the clip's start, in seconds.
    public var startTime: TimeInterval
    public var duration: TimeInterval
    /// Horizontal position as a fraction of frame width. 0.0 = left, 1.0 = right.
    public var positionX: Double
    /// Vertical position as a fraction of frame height. 0.0 = top, 1.0 = bottom.
    public var positionY: Double
    public var fontSize: Double
    /// Text color in CSS hex format, e.g. "#FFFFFF".
    public var colorHex: String
    /// Optional background pill color in CSS hex format.
    public var backgroundColorHex: String?
    public var animation: TextAnimation
    /// Duration of the entry animation in milliseconds.
    public var animationDurationMS: Double

    public init(
        id: UUID = UUID(),
        text: String,
        startTime: TimeInterval = 0,
        duration: TimeInterval = 3,
        positionX: Double = 0.5,
        positionY: Double = 0.8,
        fontSize: Double = 48,
        colorHex: String = "#FFFFFF",
        backgroundColorHex: String? = nil,
        animation: TextAnimation = .fadeIn,
        animationDurationMS: Double = 100
    ) {
        self.id = id
        self.text = text
        self.startTime = startTime
        self.duration = duration
        self.positionX = positionX
        self.positionY = positionY
        self.fontSize = fontSize
        self.colorHex = colorHex
        self.backgroundColorHex = backgroundColorHex
        self.animation = animation
        self.animationDurationMS = animationDurationMS
    }
}
