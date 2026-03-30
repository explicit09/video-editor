import Foundation
import CoreImage
import CoreText
import CoreGraphics

/// Renders broadcast-style overlays onto video frames.
/// Stateless: all animation is computed from `time`. Same pattern as SubtitleRenderer.
///
/// Components (bottom to top):
/// - SmartTicker: scrolling sponsors ↔ topics
/// - HostNameBar: persistent host names
/// - HostIntroStrip: gold strip with photos (38-92s)
/// - EpisodeTitleCard: centered title (0-30s)
/// - ChapterCard: pop-in chapter labels
public struct BroadcastOverlayRenderer {

    /// Render the full overlay stack for a given frame time.
    /// Returns a CIImage with alpha that composites over the video frame.
    public static func render(
        config: BroadcastOverlayConfig,
        at time: TimeInterval,
        renderSize: CGSize
    ) -> CIImage? {
        let scale = renderSize.width / 3840.0 // All dimensions are 4K reference
        let w = Int(renderSize.width)
        let h = Int(renderSize.height)
        guard w > 0, h > 0 else { return nil }

        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))

        let s = config.style

        // Draw layers (bottom to top in the visual stack, but CGContext y=0 is bottom)
        drawSmartTicker(ctx: ctx, config: config, time: time, scale: scale, size: renderSize)
        drawHostNameBar(ctx: ctx, config: config, time: time, scale: scale, size: renderSize)
        drawHostIntroStrip(ctx: ctx, config: config, time: time, scale: scale, size: renderSize)
        drawEpisodeTitleCard(ctx: ctx, config: config, time: time, scale: scale, size: renderSize)
        drawChapterCard(ctx: ctx, config: config, time: time, scale: scale, size: renderSize)

        guard let cgImage = ctx.makeImage() else { return nil }
        return CIImage(cgImage: cgImage)
    }
}

// MARK: - Episode Title Card

extension BroadcastOverlayRenderer {

    /// Centered title card that fades in/out over the first 30 seconds.
    static func drawEpisodeTitleCard(
        ctx: CGContext, config: BroadcastOverlayConfig,
        time: TimeInterval, scale: CGFloat, size: CGSize
    ) {
        let s = config.style
        guard time < s.titleVisibleEnd else { return }
        guard !config.episodeTitle.isEmpty else { return }

        // Compute opacity
        let opacity: CGFloat
        if time < s.titleFadeInEnd {
            opacity = CGFloat(time / s.titleFadeInEnd)
        } else if time > s.titleFadeOutStart {
            opacity = CGFloat(1.0 - (time - s.titleFadeOutStart) / (s.titleVisibleEnd - s.titleFadeOutStart))
        } else {
            opacity = 1.0
        }
        guard opacity > 0.01 else { return }

        let gold = OverlayStyle.parseHex(s.goldHex)
        let navy = OverlayStyle.parseHex(s.darkNavyHex)
        let cyan = OverlayStyle.parseHex(s.cyanHex)

        // Card dimensions
        let cardW = size.width * 0.6
        let cardH = 300 * scale
        let cardX = (size.width - cardW) / 2
        let cardY = (size.height - cardH) / 2 + (1.0 - opacity) * 40 * scale // Slide up effect

        ctx.saveGState()
        ctx.setAlpha(opacity)

        // Background
        let cardRect = CGRect(x: cardX, y: cardY, width: cardW, height: cardH)
        ctx.setFillColor(CGColor(red: navy.r, green: navy.g, blue: navy.b, alpha: 0.88))
        ctx.fill(cardRect)

        // Gold top border
        ctx.setFillColor(CGColor(red: gold.r, green: gold.g, blue: gold.b, alpha: 1))
        ctx.fill(CGRect(x: cardX, y: cardY + cardH - 4 * scale, width: cardW, height: 4 * scale))

        // Cyan bottom border
        ctx.setFillColor(CGColor(red: cyan.r, green: cyan.g, blue: cyan.b, alpha: 0.5))
        ctx.fill(CGRect(x: cardX, y: cardY, width: cardW, height: 2 * scale))

        // "EPISODE" label
        let labelFont = condensedFont(size: 36 * scale)
        drawText(ctx: ctx, text: "EPISODE", x: cardX + 60 * scale, y: cardY + cardH - 70 * scale,
                 font: labelFont, color: CGColor(red: gold.r, green: gold.g, blue: gold.b, alpha: 1))

        // Title
        let titleFont = condensedFont(size: 90 * scale)
        drawText(ctx: ctx, text: config.episodeTitle.uppercased(), x: cardX + 60 * scale, y: cardY + cardH - 170 * scale,
                 font: titleFont, color: .white)

        // Subtitle
        if !config.episodeSubtitle.isEmpty {
            let subFont = bodyFont(size: 40 * scale)
            let gray = CGColor(red: 0.58, green: 0.64, blue: 0.72, alpha: 1) // #94A3B8
            drawText(ctx: ctx, text: config.episodeSubtitle, x: cardX + 60 * scale, y: cardY + cardH - 240 * scale,
                     font: subFont, color: gray)
        }

        ctx.restoreGState()
    }
}

// MARK: - Host Name Bar

extension BroadcastOverlayRenderer {

    /// Persistent bottom bar with host names. Hides during intro strip.
    static func drawHostNameBar(
        ctx: CGContext, config: BroadcastOverlayConfig,
        time: TimeInterval, scale: CGFloat, size: CGSize
    ) {
        let s = config.style
        guard !config.hostA.name.isEmpty || !config.hostB.name.isEmpty else { return }

        // Hide during host intro strip (with smooth transition)
        let hideMargin: TimeInterval = 0.5
        if time > s.hostIntroStart - hideMargin && time < s.hostIntroEnd + hideMargin {
            return // Hidden during intro strip
        }

        let navy = OverlayStyle.parseHex(s.darkNavyHex)
        let gold = OverlayStyle.parseHex(s.goldHex)
        let barH = s.nameBarHeight * scale
        let tickerH = s.tickerHeight * scale
        let barY = tickerH // Sits above ticker

        // Background
        ctx.setFillColor(CGColor(red: navy.r, green: navy.g, blue: navy.b, alpha: 0.85))
        ctx.fill(CGRect(x: 0, y: barY, width: size.width, height: barH))

        // Gold top border
        ctx.setFillColor(CGColor(red: gold.r, green: gold.g, blue: gold.b, alpha: 0.3))
        ctx.fill(CGRect(x: 0, y: barY + barH - 2 * scale, width: size.width, height: 2 * scale))

        let nameFont = condensedFont(size: 54 * scale)
        let titleFont = condensedFont(size: 38 * scale)
        let midX = size.width / 2
        let textY = barY + barH / 2 - 10 * scale

        // Host A (left)
        drawText(ctx: ctx, text: config.hostA.name.uppercased(), x: 60 * scale, y: textY,
                 font: nameFont, color: .white)
        drawText(ctx: ctx, text: config.hostA.title.uppercased(), x: 60 * scale, y: textY - 40 * scale,
                 font: titleFont, color: CGColor(red: gold.r, green: gold.g, blue: gold.b, alpha: 1))

        // Divider
        ctx.setFillColor(CGColor(red: gold.r, green: gold.g, blue: gold.b, alpha: 0.33))
        ctx.fill(CGRect(x: midX - 1 * scale, y: barY + 20 * scale, width: 2 * scale, height: barH - 40 * scale))

        // Host B (right-aligned)
        let hostBNameWidth = measureText(config.hostB.name.uppercased(), font: nameFont)
        let hostBTitleWidth = measureText(config.hostB.title.uppercased(), font: titleFont)
        drawText(ctx: ctx, text: config.hostB.name.uppercased(), x: size.width - 60 * scale - hostBNameWidth, y: textY,
                 font: nameFont, color: .white)
        drawText(ctx: ctx, text: config.hostB.title.uppercased(), x: size.width - 60 * scale - hostBTitleWidth, y: textY - 40 * scale,
                 font: titleFont, color: CGColor(red: gold.r, green: gold.g, blue: gold.b, alpha: 1))
    }
}

// MARK: - Smart Ticker

extension BroadcastOverlayRenderer {

    /// Scrolling bottom ticker: sponsors ↔ topics on a 41-second cycle.
    static func drawSmartTicker(
        ctx: CGContext, config: BroadcastOverlayConfig,
        time: TimeInterval, scale: CGFloat, size: CGSize
    ) {
        let s = config.style
        let tickerH = s.tickerHeight * scale
        let navy = OverlayStyle.parseHex(s.darkNavyHex)
        let gold = OverlayStyle.parseHex(s.goldHex)
        let goldLight = OverlayStyle.parseHex(s.goldLightHex)
        let cyan = OverlayStyle.parseHex(s.cyanHex)

        // Background
        ctx.setFillColor(CGColor(red: navy.r, green: navy.g, blue: navy.b, alpha: 0.9))
        ctx.fill(CGRect(x: 0, y: 0, width: size.width, height: tickerH))

        // Left label: "TECHNOLOGIA TALKS" on gold gradient
        let labelW = 520 * scale
        ctx.setFillColor(CGColor(red: gold.r, green: gold.g, blue: gold.b, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: labelW, height: tickerH))

        let labelFont = condensedFont(size: 44 * scale)
        drawText(ctx: ctx, text: "TECHNOLOGIA TALKS", x: 24 * scale, y: tickerH / 2 - 12 * scale,
                 font: labelFont, color: CGColor(red: navy.r, green: navy.g, blue: navy.b, alpha: 1))

        // Right section: sponsors or topic based on cycle
        let cycleDuration = s.tickerCycleDuration
        let cyclePos = time.truncatingRemainder(dividingBy: cycleDuration)
        let sponsorEnd = s.tickerSponsorDuration
        let fade1End = sponsorEnd + s.tickerFadeDuration
        let topicEnd = fade1End + s.tickerTopicDuration

        let contentX = labelW + 24 * scale
        let contentW = size.width - contentX - 24 * scale
        let contentY = tickerH / 2

        if cyclePos < sponsorEnd {
            // Sponsors scrolling
            let scrollText = config.sponsors.joined(separator: "   ◆   ") + "   ◆   "
            let scrollFont = condensedFont(size: 46 * scale)
            let charWidth: CGFloat = 28 * scale
            let segmentWidth = CGFloat(scrollText.count) * charWidth
            let scrollOffset = CGFloat(time * 1.6 * Double(scale) * 30).truncatingRemainder(dividingBy: max(segmentWidth, 1))

            ctx.saveGState()
            ctx.clip(to: CGRect(x: contentX, y: 0, width: contentW, height: tickerH))
            let gray = CGColor(red: 0.80, green: 0.84, blue: 0.88, alpha: 1) // #CBD5E1
            drawText(ctx: ctx, text: scrollText + scrollText, x: contentX - scrollOffset, y: contentY - 14 * scale,
                     font: scrollFont, color: gray)
            ctx.restoreGState()

        } else if cyclePos >= fade1End && cyclePos < topicEnd {
            // Topic display: "NOW DISCUSSING" + active topic
            let activeTopic = config.topics.last(where: { $0.timeSeconds <= time })

            // "NOW DISCUSSING" badge
            let badgeFont = condensedFont(size: 32 * scale)
            let badgeW = 280 * scale
            let badgeH = 44 * scale
            ctx.setFillColor(CGColor(red: cyan.r, green: cyan.g, blue: cyan.b, alpha: 1))
            let badgeRect = CGRect(x: contentX, y: contentY - badgeH / 2, width: badgeW, height: badgeH)
            let badgePath = CGPath(roundedRect: badgeRect, cornerWidth: 6 * scale, cornerHeight: 6 * scale, transform: nil)
            ctx.addPath(badgePath)
            ctx.fillPath()

            drawText(ctx: ctx, text: "NOW DISCUSSING", x: contentX + 16 * scale, y: contentY - 10 * scale,
                     font: badgeFont, color: CGColor(red: navy.r, green: navy.g, blue: navy.b, alpha: 1))

            // Topic text
            if let topic = activeTopic {
                let topicFont = bodyFont(size: 48 * scale)
                drawText(ctx: ctx, text: topic.text, x: contentX + badgeW + 24 * scale, y: contentY - 14 * scale,
                         font: topicFont, color: .white)
            }
        }
        // During fade transitions, draw nothing (creates a clean cross-fade effect)
    }
}

// MARK: - Chapter Card

extension BroadcastOverlayRenderer {

    /// Pop-in card showing chapter title at specific timestamps.
    static func drawChapterCard(
        ctx: CGContext, config: BroadcastOverlayConfig,
        time: TimeInterval, scale: CGFloat, size: CGSize
    ) {
        let s = config.style
        guard time > s.titleVisibleEnd else { return } // Don't show during title card
        guard !config.chapters.isEmpty else { return }

        // Find the active chapter (last one that has started)
        var chapterIdx = -1
        var chapter: TimedEntry?
        for (i, ch) in config.chapters.enumerated() {
            if ch.timeSeconds <= time {
                chapterIdx = i
                chapter = ch
            }
        }
        guard let chapter, chapterIdx >= 0 else { return }

        let elapsed = time - chapter.timeSeconds
        guard elapsed < s.chapterDisplayDuration else { return }

        let gold = OverlayStyle.parseHex(s.goldHex)

        // Animation: slide in for first 0.5s, hold, slide out for last 0.5s
        let progress: CGFloat
        if elapsed < 0.5 {
            progress = easeOut(CGFloat(elapsed / 0.5))
        } else if elapsed > s.chapterDisplayDuration - 0.5 {
            progress = easeOut(CGFloat((s.chapterDisplayDuration - elapsed) / 0.5))
        } else {
            progress = 1.0
        }

        let cardY = size.height * 0.62 // 38% from top = 62% from bottom in CG coords
        let goldBlockW = 120 * scale
        let goldBlockH = 80 * scale
        let textPadding = 24 * scale
        let chapterFont = condensedFont(size: 56 * scale)
        let numberFont = condensedFont(size: 56 * scale)
        let chapterText = chapter.text.uppercased()
        let textWidth = measureText(chapterText, font: chapterFont)
        let totalW = goldBlockW + textPadding * 2 + textWidth + 40 * scale

        // Slide from right
        let startX = size.width
        let endX = size.width - totalW - 60 * scale
        let cardX = startX + (endX - startX) * progress

        // Gold number block
        ctx.setFillColor(CGColor(red: gold.r, green: gold.g, blue: gold.b, alpha: 1))
        ctx.fill(CGRect(x: cardX, y: cardY, width: goldBlockW, height: goldBlockH))

        let navy = OverlayStyle.parseHex(s.darkNavyHex)
        let numText = "\(chapterIdx + 1)"
        let numWidth = measureText(numText, font: numberFont)
        drawText(ctx: ctx, text: numText, x: cardX + (goldBlockW - numWidth) / 2, y: cardY + goldBlockH / 2 - 16 * scale,
                 font: numberFont, color: CGColor(red: navy.r, green: navy.g, blue: navy.b, alpha: 1))

        // Text block with dark background
        let textBlockX = cardX + goldBlockW
        let textBlockW = totalW - goldBlockW
        ctx.setFillColor(CGColor(red: navy.r, green: navy.g, blue: navy.b, alpha: 0.88))
        ctx.fill(CGRect(x: textBlockX, y: cardY, width: textBlockW, height: goldBlockH))

        drawText(ctx: ctx, text: chapterText, x: textBlockX + textPadding, y: cardY + goldBlockH / 2 - 16 * scale,
                 font: chapterFont, color: .white)

        // Gold accent line on top
        ctx.setFillColor(CGColor(red: gold.r, green: gold.g, blue: gold.b, alpha: 1))
        ctx.fill(CGRect(x: cardX, y: cardY + goldBlockH, width: totalW * progress, height: 3 * scale))
    }
}

// MARK: - Host Intro Strip

extension BroadcastOverlayRenderer {

    /// Gold strip with host photos and names. Slides in at 38s, out at 92s.
    static func drawHostIntroStrip(
        ctx: CGContext, config: BroadcastOverlayConfig,
        time: TimeInterval, scale: CGFloat, size: CGSize
    ) {
        let s = config.style
        guard time >= s.hostIntroStart - 1.0 && time <= s.hostIntroEnd + 1.0 else { return }
        guard !config.hostA.name.isEmpty || !config.hostB.name.isEmpty else { return }

        // Slide animation
        let slideProgress: CGFloat
        if time < s.hostIntroStart {
            slideProgress = 0
        } else if time < s.hostIntroStart + 1.0 {
            slideProgress = easeOut(CGFloat((time - s.hostIntroStart) / 1.0))
        } else if time > s.hostIntroEnd - 1.0 && time <= s.hostIntroEnd {
            slideProgress = easeOut(CGFloat((s.hostIntroEnd - time) / 1.0))
        } else if time > s.hostIntroEnd {
            slideProgress = 0
        } else {
            slideProgress = 1.0
        }
        guard slideProgress > 0.01 else { return }

        let gold = OverlayStyle.parseHex(s.goldHex)
        let goldLight = OverlayStyle.parseHex(s.goldLightHex)
        let navy = OverlayStyle.parseHex(s.darkNavyHex)

        let stripH = s.hostStripHeight * scale
        let tickerH = s.tickerHeight * scale
        let nameBarH = s.nameBarHeight * scale
        let baseY = tickerH + nameBarH
        let slideOffset = stripH * (1.0 - slideProgress)
        let stripY = baseY - slideOffset

        // Gold gradient background
        ctx.setFillColor(CGColor(red: gold.r, green: gold.g, blue: gold.b, alpha: 1))
        ctx.fill(CGRect(x: 0, y: stripY, width: size.width, height: stripH))

        // Lighter gold highlight on top half
        ctx.setFillColor(CGColor(red: goldLight.r, green: goldLight.g, blue: goldLight.b, alpha: 0.3))
        ctx.fill(CGRect(x: 0, y: stripY + stripH / 2, width: size.width, height: stripH / 2))

        let midX = size.width / 2
        let photoSize = 200 * scale
        let nameFont = condensedFont(size: 80 * scale)
        let titleFont = condensedFont(size: 40 * scale)

        // Host A (left side)
        let photoY = stripY + (stripH - photoSize) / 2

        // Photo placeholder (circle with initial)
        drawHostPhoto(ctx: ctx, initial: String(config.hostA.name.prefix(1)), x: 80 * scale, y: photoY,
                      size: photoSize, navy: navy, scale: scale)

        let textX = 80 * scale + photoSize + 30 * scale
        let nameY = stripY + stripH / 2 + 10 * scale
        drawText(ctx: ctx, text: config.hostA.name.uppercased(), x: textX, y: nameY,
                 font: nameFont, color: CGColor(red: navy.r, green: navy.g, blue: navy.b, alpha: 1))
        drawText(ctx: ctx, text: config.hostA.title.uppercased(), x: textX, y: nameY - 50 * scale,
                 font: titleFont, color: CGColor(red: navy.r, green: navy.g, blue: navy.b, alpha: 0.62))

        // Center divider
        ctx.setFillColor(CGColor(red: navy.r, green: navy.g, blue: navy.b, alpha: 0.2))
        ctx.fill(CGRect(x: midX - 1.5 * scale, y: stripY + 40 * scale, width: 3 * scale, height: stripH - 80 * scale))

        // Host B (right side, right-aligned)
        let photoBX = size.width - 80 * scale - photoSize
        drawHostPhoto(ctx: ctx, initial: String(config.hostB.name.prefix(1)), x: photoBX, y: photoY,
                      size: photoSize, navy: navy, scale: scale)

        let hostBNameW = measureText(config.hostB.name.uppercased(), font: nameFont)
        let hostBTitleW = measureText(config.hostB.title.uppercased(), font: titleFont)
        let textBX = photoBX - 30 * scale
        drawText(ctx: ctx, text: config.hostB.name.uppercased(), x: textBX - hostBNameW, y: nameY,
                 font: nameFont, color: CGColor(red: navy.r, green: navy.g, blue: navy.b, alpha: 1))
        drawText(ctx: ctx, text: config.hostB.title.uppercased(), x: textBX - hostBTitleW, y: nameY - 50 * scale,
                 font: titleFont, color: CGColor(red: navy.r, green: navy.g, blue: navy.b, alpha: 0.62))
    }

    /// Draw a circular photo placeholder with initial.
    private static func drawHostPhoto(
        ctx: CGContext, initial: String, x: CGFloat, y: CGFloat,
        size: CGFloat, navy: (r: CGFloat, g: CGFloat, b: CGFloat), scale: CGFloat
    ) {
        let circle = CGRect(x: x, y: y, width: size, height: size)
        ctx.saveGState()
        ctx.addEllipse(in: circle)
        ctx.clip()
        ctx.setFillColor(CGColor(red: navy.r, green: navy.g, blue: navy.b, alpha: 0.3))
        ctx.fill(circle)
        ctx.restoreGState()

        // Draw border
        ctx.setStrokeColor(CGColor(red: navy.r, green: navy.g, blue: navy.b, alpha: 0.5))
        ctx.setLineWidth(4 * scale)
        ctx.strokeEllipse(in: circle.insetBy(dx: 2 * scale, dy: 2 * scale))

        // Initial letter
        let initialFont = condensedFont(size: 80 * scale)
        let initialW = measureText(initial, font: initialFont)
        drawText(ctx: ctx, text: initial, x: x + (size - initialW) / 2, y: y + size / 2 - 24 * scale,
                 font: initialFont, color: CGColor(red: navy.r, green: navy.g, blue: navy.b, alpha: 0.6))
    }
}

// MARK: - Text Helpers

extension BroadcastOverlayRenderer {

    /// Draw text at position using Core Text.
    private static func drawText(
        ctx: CGContext, text: String, x: CGFloat, y: CGFloat,
        font: CTFont, color: CGColor
    ) {
        let attributes: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: color,
        ]
        let attrString = CFAttributedStringCreate(nil, text as CFString, attributes as CFDictionary)!
        let line = CTLineCreateWithAttributedString(attrString)
        ctx.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(line, ctx)
    }

    /// Measure text width.
    private static func measureText(_ text: String, font: CTFont) -> CGFloat {
        let attributes: [CFString: Any] = [kCTFontAttributeName: font]
        let attrString = CFAttributedStringCreate(nil, text as CFString, attributes as CFDictionary)!
        let line = CTLineCreateWithAttributedString(attrString)
        return CTLineGetBoundsWithOptions(line, []).width
    }

    /// Condensed bold font (BarlowCondensed fallback to system condensed).
    private static func condensedFont(size: CGFloat) -> CTFont {
        let font = CTFontCreateWithName("BarlowCondensed-Black" as CFString, size, nil)
        if CTFontCopyFamilyName(font) as String == "Barlow Condensed" {
            return font
        }
        // Fallback: system condensed bold
        return CTFontCreateWithName("HelveticaNeue-CondensedBold" as CFString, size, nil)
    }

    /// Body font (Inter fallback to system).
    private static func bodyFont(size: CGFloat) -> CTFont {
        let font = CTFontCreateWithName("Inter" as CFString, size, nil)
        if CTFontCopyFamilyName(font) as String == "Inter" {
            return font
        }
        return CTFontCreateWithName("HelveticaNeue" as CFString, size, nil)
    }

    /// Ease-out cubic.
    private static func easeOut(_ t: CGFloat) -> CGFloat {
        let t = min(max(t, 0), 1)
        return 1.0 - pow(1.0 - t, 3)
    }
}
