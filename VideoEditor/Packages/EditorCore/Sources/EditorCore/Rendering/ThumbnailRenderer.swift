// ThumbnailRenderer.swift
import Foundation
import CoreGraphics
import CoreImage
import CoreText
import ImageIO

public enum ThumbnailRenderError: Error {
    case contextCreationFailed
    case imageExportFailed
}

public struct ThumbnailRenderer: Sendable {

    public static let canvasWidth = 1536
    public static let canvasHeight = 1024

    public init() {}

    public func render(config: ThumbnailConfig) async throws -> Data {
        let w = Self.canvasWidth
        let h = Self.canvasHeight

        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ThumbnailRenderError.contextCreationFailed
        }

        let size = CGSize(width: CGFloat(w), height: CGFloat(h))

        // 1. Background: use provided image or draw gradient
        if let bgData = config.backgroundImage,
           let bgCIImage = CIImage(data: bgData),
           let bgCGImage = CIContext().createCGImage(bgCIImage, from: bgCIImage.extent) {
            // Draw background image scaled to fill canvas
            let bgRect = CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h))
            ctx.draw(bgCGImage, in: bgRect)
        } else {
            // Fall back to gradient background
            drawBackground(ctx: ctx, layout: config.layout, brand: config.brand, size: size)
        }

        // 2. Gold accent corner lines
        drawAccents(ctx: ctx, layout: config.layout, brand: config.brand, size: size)

        // 3. Host photo cutouts
        let cutouts = try generateCutouts(photos: config.hostPhotos)
        drawHosts(ctx: ctx, layout: config.layout, brand: config.brand, cutouts: cutouts, size: size)

        // 4. Logo
        drawLogo(ctx: ctx, brand: config.brand, size: size)

        // 5. Title and subtitle text
        drawText(ctx: ctx, config: config, size: size)

        // 6. Export as PNG
        guard let cgImage = ctx.makeImage() else {
            throw ThumbnailRenderError.imageExportFailed
        }
        return try exportPNG(image: cgImage)
    }
}

// MARK: - Background Gradients

extension ThumbnailRenderer {

    private func drawBackground(ctx: CGContext, layout: ThumbnailLayout, brand: ThumbnailBrand, size: CGSize) {
        let primary = brand.primaryBackground
        let black = CGColor(red: 0, green: 0, blue: 0, alpha: 1)

        switch layout {
        case .splitPanel:
            // Left panel: primary → black diagonal
            let leftRect = CGRect(x: 0, y: 0, width: size.width / 2, height: size.height)
            if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: [primary, black] as CFArray, locations: [0, 1]) {
                ctx.saveGState()
                ctx.clip(to: leftRect)
                ctx.drawLinearGradient(grad,
                                       start: CGPoint(x: 0, y: size.height),
                                       end: CGPoint(x: size.width / 2, y: 0),
                                       options: [])
                ctx.restoreGState()
            }
            // Right panel: primary → black reverse diagonal
            let rightRect = CGRect(x: size.width / 2, y: 0, width: size.width / 2, height: size.height)
            if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: [primary, black] as CFArray, locations: [0, 1]) {
                ctx.saveGState()
                ctx.clip(to: rightRect)
                ctx.drawLinearGradient(grad,
                                       start: CGPoint(x: size.width, y: 0),
                                       end: CGPoint(x: size.width / 2, y: size.height),
                                       options: [])
                ctx.restoreGState()
            }

        case .centered:
            // Radial gradient: primary center → black edges
            if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: [primary, black] as CFArray, locations: [0, 1]) {
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = hypot(size.width, size.height) / 2
                ctx.drawRadialGradient(grad,
                                       startCenter: center, startRadius: 0,
                                       endCenter: center, endRadius: radius,
                                       options: [])
            }

        case .textHeavy:
            // Diagonal gradient: primary → black
            if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: [primary, black] as CFArray, locations: [0, 1]) {
                ctx.drawLinearGradient(grad,
                                       start: CGPoint(x: 0, y: size.height),
                                       end: CGPoint(x: size.width, y: 0),
                                       options: [])
            }
        }
    }
}

// MARK: - Gold Accent Corner Lines

extension ThumbnailRenderer {

    private func drawAccents(ctx: CGContext, layout: ThumbnailLayout, brand: ThumbnailBrand, size: CGSize) {
        let gold = brand.accentGold
        let lineWidth: CGFloat = 3
        let lineLen: CGFloat = 80

        ctx.setStrokeColor(gold)
        ctx.setLineWidth(lineWidth)

        switch layout {
        case .splitPanel:
            // Top-left corner
            drawCornerLines(ctx: ctx, x: 20, y: size.height - 20, dx: 1, dy: -1, length: lineLen)
            // Bottom-right corner
            drawCornerLines(ctx: ctx, x: size.width - 20, y: 20, dx: -1, dy: 1, length: lineLen)

        case .centered:
            // All four corners
            drawCornerLines(ctx: ctx, x: 20, y: size.height - 20, dx: 1, dy: -1, length: lineLen)
            drawCornerLines(ctx: ctx, x: size.width - 20, y: size.height - 20, dx: -1, dy: -1, length: lineLen)
            drawCornerLines(ctx: ctx, x: 20, y: 20, dx: 1, dy: 1, length: lineLen)
            drawCornerLines(ctx: ctx, x: size.width - 20, y: 20, dx: -1, dy: 1, length: lineLen)

        case .textHeavy:
            // Top-left and bottom-right
            drawCornerLines(ctx: ctx, x: 20, y: size.height - 20, dx: 1, dy: -1, length: lineLen)
            drawCornerLines(ctx: ctx, x: size.width - 20, y: 20, dx: -1, dy: 1, length: lineLen)
        }
    }

    private func drawCornerLines(ctx: CGContext, x: CGFloat, y: CGFloat, dx: CGFloat, dy: CGFloat, length: CGFloat) {
        // Horizontal line from corner
        ctx.move(to: CGPoint(x: x, y: y))
        ctx.addLine(to: CGPoint(x: x + dx * length, y: y))
        ctx.strokePath()
        // Vertical line from corner
        ctx.move(to: CGPoint(x: x, y: y))
        ctx.addLine(to: CGPoint(x: x, y: y + dy * length))
        ctx.strokePath()
    }
}

// MARK: - Host Photo Cutouts

extension ThumbnailRenderer {

    private func generateCutouts(photos: [Data]) throws -> [CGImage] {
        let ciContext = CIContext()
        var results: [CGImage] = []
        for photo in photos {
            let ciImage = try PhotoCutout.cutout(photo: photo, featherRadius: 8)
            guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
                continue
            }
            results.append(cgImage)
        }
        return results
    }

    private func drawHosts(ctx: CGContext, layout: ThumbnailLayout, brand: ThumbnailBrand, cutouts: [CGImage], size: CGSize) {
        switch layout {
        case .splitPanel:
            // Host A: left panel (5-47% width), upper portion
            if cutouts.count > 0 {
                let hostRect = CGRect(
                    x: size.width * 0.05,
                    y: size.height * 0.15,
                    width: size.width * 0.42,
                    height: size.height * 0.75
                )
                drawHostImage(ctx: ctx, image: cutouts[0], in: hostRect)
            }
            // Host B: right panel (53-95% width), upper portion
            if cutouts.count > 1 {
                let hostRect = CGRect(
                    x: size.width * 0.53,
                    y: size.height * 0.15,
                    width: size.width * 0.42,
                    height: size.height * 0.75
                )
                drawHostImage(ctx: ctx, image: cutouts[1], in: hostRect)
            }

        case .centered:
            // Host A: bottom-left, slight 2 degree clockwise tilt
            if cutouts.count > 0 {
                let hostRect = CGRect(
                    x: size.width * 0.05,
                    y: size.height * 0.02,
                    width: size.width * 0.42,
                    height: size.height * 0.60
                )
                ctx.saveGState()
                let centerA = CGPoint(x: hostRect.midX, y: hostRect.midY)
                ctx.translateBy(x: centerA.x, y: centerA.y)
                ctx.rotate(by: -2 * .pi / 180) // 2 deg clockwise (CG is counter-clockwise positive)
                ctx.translateBy(x: -centerA.x, y: -centerA.y)
                drawHostImage(ctx: ctx, image: cutouts[0], in: hostRect)
                ctx.restoreGState()
            }
            // Host B: bottom-right, slight -2 degree counter-clockwise tilt
            if cutouts.count > 1 {
                let hostRect = CGRect(
                    x: size.width * 0.53,
                    y: size.height * 0.02,
                    width: size.width * 0.42,
                    height: size.height * 0.60
                )
                ctx.saveGState()
                let centerB = CGPoint(x: hostRect.midX, y: hostRect.midY)
                ctx.translateBy(x: centerB.x, y: centerB.y)
                ctx.rotate(by: 2 * .pi / 180) // -2 deg counter-clockwise
                ctx.translateBy(x: -centerB.x, y: -centerB.y)
                drawHostImage(ctx: ctx, image: cutouts[1], in: hostRect)
                ctx.restoreGState()
            }

        case .textHeavy:
            // Small circular cutouts (~100px) with gold border, top-left
            let circleSize: CGFloat = 100
            let startX: CGFloat = 40
            let startY: CGFloat = size.height - 140 // Near top in screen coords (CG origin bottom-left)
            for (i, cutout) in cutouts.prefix(2).enumerated() {
                let cx = startX + CGFloat(i) * (circleSize + 16)
                let cy = startY
                let circleRect = CGRect(x: cx, y: cy, width: circleSize, height: circleSize)

                // Clip to circle and draw
                ctx.saveGState()
                ctx.addEllipse(in: circleRect)
                ctx.clip()
                drawHostImage(ctx: ctx, image: cutout, in: circleRect)
                ctx.restoreGState()

                // Gold circle border
                ctx.setStrokeColor(brand.accentGold)
                ctx.setLineWidth(3)
                ctx.strokeEllipse(in: circleRect.insetBy(dx: 1.5, dy: 1.5))
            }
        }
    }

    private func drawHostImage(ctx: CGContext, image: CGImage, in rect: CGRect) {
        // Aspect-fill the image into the rect
        let imgW = CGFloat(image.width)
        let imgH = CGFloat(image.height)
        let scale = max(rect.width / imgW, rect.height / imgH)
        let drawW = imgW * scale
        let drawH = imgH * scale
        let drawX = rect.origin.x + (rect.width - drawW) / 2
        let drawY = rect.origin.y + (rect.height - drawH) / 2
        ctx.draw(image, in: CGRect(x: drawX, y: drawY, width: drawW, height: drawH))
    }
}

// MARK: - Logo

extension ThumbnailRenderer {

    private func drawLogo(ctx: CGContext, brand: ThumbnailBrand, size: CGSize) {
        guard let logo = brand.logoImage else { return }
        let logoMaxH: CGFloat = 60
        let logoW = CGFloat(logo.width)
        let logoH = CGFloat(logo.height)
        let scale = logoMaxH / logoH
        let drawW = logoW * scale
        let drawH = logoMaxH
        // Centered horizontally, near the very top
        let x = (size.width - drawW) / 2
        let y = size.height - drawH - 30
        ctx.draw(logo, in: CGRect(x: x, y: y, width: drawW, height: drawH))
    }
}

// MARK: - Text Rendering

extension ThumbnailRenderer {

    private func drawText(ctx: CGContext, config: ThumbnailConfig, size: CGSize) {
        let brand = config.brand
        let titleFont = CTFontCreateWithName("Helvetica-Bold" as CFString, 72, nil)
        let subtitleFont = CTFontCreateWithName("Helvetica-Bold" as CFString, 36, nil)

        // Drop shadow for all text
        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 3, height: -3),
            blur: 10,
            color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.8)
        )

        let titleText = config.title.uppercased()
        let subtitleText = config.subtitle?.uppercased()

        switch config.layout {
        case .splitPanel:
            // Title: centered at bottom, white
            let titleW = measureText(titleText, font: titleFont)
            let titleX = (size.width - titleW) / 2
            let titleY: CGFloat = 80
            drawCTText(ctx: ctx, text: titleText, x: titleX, y: titleY, font: titleFont, color: brand.textPrimary)

            // Subtitle: centered below title (below in screen = lower y in CG)
            if let sub = subtitleText {
                let subW = measureText(sub, font: subtitleFont)
                let subX = (size.width - subW) / 2
                let subY: CGFloat = 35
                drawCTText(ctx: ctx, text: sub, x: subX, y: subY, font: subtitleFont, color: brand.textAccent)
            }

        case .centered:
            // Title: centered at top, white
            let titleW = measureText(titleText, font: titleFont)
            let titleX = (size.width - titleW) / 2
            let titleY = size.height - 120
            drawCTText(ctx: ctx, text: titleText, x: titleX, y: titleY, font: titleFont, color: brand.textPrimary)

            // Subtitle: centered below title
            if let sub = subtitleText {
                let subW = measureText(sub, font: subtitleFont)
                let subX = (size.width - subW) / 2
                let subY = size.height - 170
                drawCTText(ctx: ctx, text: sub, x: subX, y: subY, font: subtitleFont, color: brand.textAccent)
            }

        case .textHeavy:
            // Title: large, left-aligned, middle of canvas
            let largeTitleFont = CTFontCreateWithName("Helvetica-Bold" as CFString, 96, nil)
            let titleY = size.height * 0.45
            let titleX: CGFloat = 40

            // Use CTFramesetter for multi-line wrapping
            let maxWidth = size.width * 0.85
            drawWrappedText(ctx: ctx, text: titleText, x: titleX, y: titleY, maxWidth: maxWidth,
                           font: largeTitleFont, color: brand.textPrimary)

            // Subtitle: below title, gold
            if let sub = subtitleText {
                let subY = titleY - 120
                drawCTText(ctx: ctx, text: sub, x: titleX, y: subY, font: subtitleFont, color: brand.textAccent)
            }
        }

        ctx.restoreGState()
    }

    private func drawCTText(ctx: CGContext, text: String, x: CGFloat, y: CGFloat, font: CTFont, color: CGColor) {
        let attrs: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: color
        ]
        let attrString = CFAttributedStringCreate(nil, text as CFString, attrs as CFDictionary)!
        let line = CTLineCreateWithAttributedString(attrString)
        ctx.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(line, ctx)
    }

    private func drawWrappedText(ctx: CGContext, text: String, x: CGFloat, y: CGFloat, maxWidth: CGFloat,
                                  font: CTFont, color: CGColor) {
        let attrs: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: color
        ]
        let attrString = CFAttributedStringCreate(nil, text as CFString, attrs as CFDictionary)!
        let framesetter = CTFramesetterCreateWithAttributedString(attrString)

        let framePath = CGPath(rect: CGRect(x: x, y: y - 300, width: maxWidth, height: 300), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), framePath, nil)
        CTFrameDraw(frame, ctx)
    }

    private func measureText(_ text: String, font: CTFont) -> CGFloat {
        let attrs: [CFString: Any] = [kCTFontAttributeName: font]
        let attrString = CFAttributedStringCreate(nil, text as CFString, attrs as CFDictionary)!
        let line = CTLineCreateWithAttributedString(attrString)
        return CTLineGetBoundsWithOptions(line, []).width
    }
}

// MARK: - PNG Export

extension ThumbnailRenderer {

    private func exportPNG(image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, "public.png" as CFString, 1, nil) else {
            throw ThumbnailRenderError.imageExportFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ThumbnailRenderError.imageExportFailed
        }
        return data as Data
    }
}
