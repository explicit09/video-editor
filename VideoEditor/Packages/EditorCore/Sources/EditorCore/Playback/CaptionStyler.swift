import Foundation
import CoreGraphics
import CoreText

/// Generates styled caption frames with word-by-word highlighting.
/// Supports multiple caption styles popular on social media.
public struct CaptionStyler: Sendable {

    public enum CaptionStyle: String, Sendable, CaseIterable {
        case standard     // White text, black background pill
        case karaoke      // Word-by-word highlight (current word in accent color)
        case bold         // Large bold text, no background
        case outline      // White text with black outline
        case gradient     // Text with gradient color
    }

    public struct CaptionFrame: Sendable {
        public let text: String
        public let activeWordIndex: Int? // For karaoke-style highlighting
        public let style: CaptionStyle
    }

    /// Determine which word is active at a given time.
    public static func activeWordIndex(
        at time: TimeInterval,
        words: [TranscriptWord]
    ) -> Int? {
        words.firstIndex(where: { time >= $0.start && time < $0.end })
    }

    /// Render a styled caption as a CGImage.
    public static func renderCaption(
        text: String,
        activeWordIndex: Int?,
        style: CaptionStyle,
        size: CGSize,
        fontSize: CGFloat = 40
    ) -> CGImage? {
        let scale: CGFloat = 2
        let width = Int(size.width * scale)
        let height = Int(size.height * scale)
        let scaledFontSize = fontSize * scale

        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.clear(CGRect(x: 0, y: 0, width: width, height: height))

        let words = text.components(separatedBy: " ")
        let bottomMargin: CGFloat = size.height * 0.08 * scale
        let textY = bottomMargin

        switch style {
        case .standard:
            renderStandard(context: context, text: text, fontSize: scaledFontSize,
                          width: CGFloat(width), textY: textY)

        case .karaoke:
            renderKaraoke(context: context, words: words, activeIndex: activeWordIndex,
                         fontSize: scaledFontSize, width: CGFloat(width), textY: textY)

        case .bold:
            renderBold(context: context, text: text, fontSize: scaledFontSize * 1.3,
                      width: CGFloat(width), height: CGFloat(height))

        case .outline:
            renderOutline(context: context, text: text, fontSize: scaledFontSize,
                         width: CGFloat(width), textY: textY)

        case .gradient:
            renderStandard(context: context, text: text, fontSize: scaledFontSize,
                          width: CGFloat(width), textY: textY)
        }

        return context.makeImage()
    }

    // MARK: - Style Renderers

    private static func renderStandard(context: CGContext, text: String, fontSize: CGFloat, width: CGFloat, textY: CGFloat) {
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, fontSize, nil)
        let attrs: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorFromContextAttributeName: true]
        let attrStr = CFAttributedStringCreate(nil, text as CFString, attrs as CFDictionary)!
        let line = CTLineCreateWithAttributedString(attrStr)
        let bounds = CTLineGetBoundsWithOptions(line, [])

        let textX = (width - bounds.width) / 2
        let padding: CGFloat = 16

        // Background pill
        let pillRect = CGRect(x: textX - padding, y: textY - padding / 2,
                             width: bounds.width + padding * 2, height: bounds.height + padding)
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.75))
        context.addPath(CGPath(roundedRect: pillRect, cornerWidth: 12, cornerHeight: 12, transform: nil))
        context.fillPath()

        // Text
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.textPosition = CGPoint(x: textX, y: textY)
        CTLineDraw(line, context)
    }

    private static func renderKaraoke(context: CGContext, words: [String], activeIndex: Int?, fontSize: CGFloat, width: CGFloat, textY: CGFloat) {
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, fontSize, nil)

        // Calculate total width to center
        let fullText = words.joined(separator: " ")
        let fullAttrs: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorFromContextAttributeName: true]
        let fullAttrStr = CFAttributedStringCreate(nil, fullText as CFString, fullAttrs as CFDictionary)!
        let fullLine = CTLineCreateWithAttributedString(fullAttrStr)
        let fullBounds = CTLineGetBoundsWithOptions(fullLine, [])
        var cursorX = (width - fullBounds.width) / 2

        // Background
        let padding: CGFloat = 16
        let pillRect = CGRect(x: cursorX - padding, y: textY - padding / 2,
                             width: fullBounds.width + padding * 2, height: fullBounds.height + padding)
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.75))
        context.addPath(CGPath(roundedRect: pillRect, cornerWidth: 12, cornerHeight: 12, transform: nil))
        context.fillPath()

        // Draw each word with highlight on active
        for (i, word) in words.enumerated() {
            let isActive = (i == activeIndex)
            let displayWord = i < words.count - 1 ? word + " " : word

            let attrs: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorFromContextAttributeName: true]
            let wordAttrStr = CFAttributedStringCreate(nil, displayWord as CFString, attrs as CFDictionary)!
            let wordLine = CTLineCreateWithAttributedString(wordAttrStr)
            let wordBounds = CTLineGetBoundsWithOptions(wordLine, [])

            // Set color: accent for active, white for others
            if isActive {
                context.setFillColor(CGColor(red: 0.76, green: 0.76, blue: 1.0, alpha: 1)) // Primary accent
            } else {
                context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.8))
            }

            context.textPosition = CGPoint(x: cursorX, y: textY)
            CTLineDraw(wordLine, context)
            cursorX += wordBounds.width
        }
    }

    private static func renderBold(context: CGContext, text: String, fontSize: CGFloat, width: CGFloat, height: CGFloat) {
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, fontSize, nil)
        let attrs: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorFromContextAttributeName: true]
        let attrStr = CFAttributedStringCreate(nil, text as CFString, attrs as CFDictionary)!
        let line = CTLineCreateWithAttributedString(attrStr)
        let bounds = CTLineGetBoundsWithOptions(line, [])

        let textX = (width - bounds.width) / 2
        let textY = height * 0.35 // Center-ish vertically

        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.textPosition = CGPoint(x: textX, y: textY)
        CTLineDraw(line, context)
    }

    private static func renderOutline(context: CGContext, text: String, fontSize: CGFloat, width: CGFloat, textY: CGFloat) {
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, fontSize, nil)
        let attrs: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorFromContextAttributeName: true]
        let attrStr = CFAttributedStringCreate(nil, text as CFString, attrs as CFDictionary)!
        let line = CTLineCreateWithAttributedString(attrStr)
        let bounds = CTLineGetBoundsWithOptions(line, [])
        let textX = (width - bounds.width) / 2

        // Draw outline (stroke)
        context.setTextDrawingMode(.stroke)
        context.setLineWidth(4)
        context.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.textPosition = CGPoint(x: textX, y: textY)
        CTLineDraw(line, context)

        // Draw fill
        context.setTextDrawingMode(.fill)
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.textPosition = CGPoint(x: textX, y: textY)
        CTLineDraw(line, context)
    }
}
