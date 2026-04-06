import Foundation

// MARK: - Overlay Presentation

public struct OverlayPresentation: Codable, Equatable, Sendable {
    public var mode: OverlayPresentationMode
    public var border: OverlayBorderStyle
    public var shadow: OverlayShadowStyle
    public var cornerRadius: Double
    public var maskShape: OverlayMaskShape
    public var snapsToSafeMargins: Bool
    public var entranceAnimation: OverlayAnimationPreset
    public var exitAnimation: OverlayAnimationPreset

    public init(
        mode: OverlayPresentationMode = .inline,
        border: OverlayBorderStyle = .hidden,
        shadow: OverlayShadowStyle = .none,
        cornerRadius: Double = 0,
        maskShape: OverlayMaskShape = .rectangle,
        snapsToSafeMargins: Bool = true,
        entranceAnimation: OverlayAnimationPreset = .none,
        exitAnimation: OverlayAnimationPreset = .none
    ) {
        self.mode = mode
        self.border = border
        self.shadow = shadow
        self.cornerRadius = max(cornerRadius, 0)
        self.maskShape = maskShape
        self.snapsToSafeMargins = snapsToSafeMargins
        self.entranceAnimation = entranceAnimation
        self.exitAnimation = exitAnimation
    }

    public static let `default` = OverlayPresentation(
        mode: .inline,
        border: .hidden,
        shadow: .none,
        cornerRadius: 0,
        maskShape: .rectangle,
        snapsToSafeMargins: true,
        entranceAnimation: .none,
        exitAnimation: .none
    )
}

public enum OverlayPresentationMode: String, Codable, Sendable {
    case inline
    case pip
}

public struct OverlayBorderStyle: Codable, Equatable, Sendable {
    public var isVisible: Bool
    public var width: Double
    public var colorHex: String

    public init(isVisible: Bool = false, width: Double = 0, colorHex: String = "#FFFFFF") {
        self.isVisible = isVisible
        self.width = max(width, 0)
        self.colorHex = colorHex
    }

    public static let hidden = OverlayBorderStyle()
}

public enum OverlayShadowStyle: String, Codable, Sendable {
    case none
    case light
    case medium
    case heavy
}

public enum OverlayMaskShape: String, Codable, Sendable {
    case rectangle
    case roundedRect
    case circle
}

public enum OverlayAnimationPreset: String, Codable, Sendable {
    case none
    case fadeIn
    case fadeOut
    case scaleIn
    case scaleOut
    case slideIn
    case slideOut
}

public enum OverlayPiPPreset: String, Codable, Sendable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
}
