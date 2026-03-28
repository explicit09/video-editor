import Foundation
import CoreImage
import CoreText
import CoreGraphics

/// Renders subtitle text onto a CIImage frame.
/// Used by EffectCompositor to burn captions into the video.
public struct SubtitleRenderer {

    public struct SubtitleEntry: Sendable {
        public let text: String
        public let startTime: TimeInterval
        public let endTime: TimeInterval

        public init(text: String, startTime: TimeInterval, endTime: TimeInterval) {
            self.text = text
            self.startTime = startTime
            self.endTime = endTime
        }
    }

    /// Render subtitle text onto a frame at the given time.
    public static func render(
        subtitles: [SubtitleEntry],
        at time: TimeInterval,
        onto image: CIImage,
        renderSize: CGSize
    ) -> CIImage {
        // Find the active subtitle at this time
        guard let active = subtitles.first(where: { time >= $0.startTime && time < $0.endTime }) else {
            return image
        }

        // Create text image using Core Graphics
        let textImage = renderText(
            active.text,
            size: renderSize,
            fontSize: max(renderSize.height * 0.04, 18), // 4% of frame height
            bottomMargin: renderSize.height * 0.08 // 8% from bottom
        )

        guard let textCIImage = textImage else { return image }

        // Composite text over video
        return textCIImage.composited(over: image)
    }

    /// Create a CIImage of text with a semi-transparent background pill.
    private static func renderText(
        _ text: String,
        size: CGSize,
        fontSize: CGFloat,
        bottomMargin: CGFloat
    ) -> CIImage? {
        let scale: CGFloat = 2 // retina
        let width = Int(size.width * scale)
        let height = Int(size.height * scale)

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Clear (transparent)
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))

        // Set up text attributes
        let scaledFontSize = fontSize * scale
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, scaledFontSize, nil)
        let attributes: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorFromContextAttributeName: true,
        ]

        let attrString = CFAttributedStringCreate(nil, text as CFString, attributes as CFDictionary)!
        let line = CTLineCreateWithAttributedString(attrString as CFAttributedString)
        let textBounds = CTLineGetBoundsWithOptions(line, [])

        // Position text centered, near bottom
        let textX = (CGFloat(width) - textBounds.width) / 2
        let textY = bottomMargin * scale

        // Draw background pill
        let padding: CGFloat = 12 * scale
        let pillRect = CGRect(
            x: textX - padding,
            y: textY - padding / 2,
            width: textBounds.width + padding * 2,
            height: textBounds.height + padding
        )
        let pillPath = CGPath(roundedRect: pillRect, cornerWidth: 8 * scale, cornerHeight: 8 * scale, transform: nil)
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.7))
        context.addPath(pillPath)
        context.fillPath()

        // Draw text
        context.textPosition = CGPoint(x: textX, y: textY)
        CTLineDraw(line, context)

        guard let cgImage = context.makeImage() else { return nil }
        return CIImage(cgImage: cgImage)
    }

    /// Group transcript words into subtitle lines (~8 words each).
    public static func groupWordsIntoSubtitles(_ words: [TranscriptWord], wordsPerLine: Int = 8) -> [SubtitleEntry] {
        var entries: [SubtitleEntry] = []

        for start in stride(from: 0, to: words.count, by: wordsPerLine) {
            let end = min(start + wordsPerLine, words.count)
            let chunk = Array(words[start..<end])
            let text = chunk.map(\.word).joined(separator: " ")
            let startTime = chunk.first?.start ?? 0
            let endTime = chunk.last?.end ?? 0
            entries.append(SubtitleEntry(text: text, startTime: startTime, endTime: endTime))
        }

        return entries
    }
}
