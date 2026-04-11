// ThumbnailConfig.swift
import Foundation
import CoreGraphics

public enum ThumbnailLayout: String, Sendable {
    case splitPanel = "split_panel"
    case centered = "centered"
    case textHeavy = "text_heavy"
}

public struct ThumbnailBrand: Sendable {
    public let primaryBackground: CGColor
    public let secondaryBackground: CGColor
    public let accentGold: CGColor
    public let textPrimary: CGColor
    public let textAccent: CGColor
    public let logoImage: CGImage?

    public init(
        primaryBackground: CGColor,
        secondaryBackground: CGColor,
        accentGold: CGColor,
        textPrimary: CGColor,
        textAccent: CGColor,
        logoImage: CGImage?
    ) {
        self.primaryBackground = primaryBackground
        self.secondaryBackground = secondaryBackground
        self.accentGold = accentGold
        self.textPrimary = textPrimary
        self.textAccent = textAccent
        self.logoImage = logoImage
    }

    public static func parseHex(_ hex: String) -> CGColor {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard h.count == 6, let val = UInt32(h, radix: 16) else {
            return CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        }
        let r = CGFloat((val >> 16) & 0xFF) / 255.0
        let g = CGFloat((val >> 8) & 0xFF) / 255.0
        let b = CGFloat(val & 0xFF) / 255.0
        return CGColor(red: r, green: g, blue: b, alpha: 1)
    }
}

public struct ThumbnailConfig: Sendable {
    public let title: String
    public let subtitle: String?
    public let layout: ThumbnailLayout
    public let hostPhotos: [Data]
    public let brand: ThumbnailBrand
    public let backgroundImage: Data?  // Optional background image data (PNG/JPEG)

    public init(
        title: String,
        subtitle: String? = nil,
        layout: ThumbnailLayout = .splitPanel,
        hostPhotos: [Data] = [],
        brand: ThumbnailBrand,
        backgroundImage: Data? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.layout = layout
        self.hostPhotos = hostPhotos
        self.brand = brand
        self.backgroundImage = backgroundImage
    }
}
