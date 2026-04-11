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
            ctx.draw(bgCGImage, in: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
        } else {
            drawBackground(ctx: ctx, layout: config.layout, brand: config.brand, size: size)
        }

        // 2. Dark gradient overlay at bottom for text readability
        drawBottomGradient(ctx: ctx, size: size)

        // 3. Host photo cutouts — positioned to not cover center of background
        let cutouts = try generateCutouts(photos: config.hostPhotos)
        drawHosts(ctx: ctx, layout: config.layout, brand: config.brand, cutouts: cutouts, size: size)

        // 4. Brand badge bar at bottom
        drawBrandBar(ctx: ctx, brand: config.brand, size: size)

        // 5. Title text — BIG, bold, TBPN style
        drawTitle(ctx: ctx, config: config, size: size)

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
        let primary = brand.secondaryBackground  // dark green
        let black = brand.primaryBackground       // black

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let grad = CGGradient(colorsSpace: colorSpace,
                                     colors: [primary, black] as CFArray, locations: [0, 1]) else { return }

        switch layout {
        case .splitPanel:
            ctx.drawLinearGradient(grad,
                                   start: CGPoint(x: 0, y: size.height),
                                   end: CGPoint(x: size.width, y: 0),
                                   options: [.drawsAfterEndLocation])
        case .centered:
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = hypot(size.width, size.height) / 2
            ctx.drawRadialGradient(grad,
                                    startCenter: center, startRadius: 0,
                                    endCenter: center, endRadius: radius,
                                    options: [])
        case .textHeavy:
            ctx.drawLinearGradient(grad,
                                   start: CGPoint(x: 0, y: size.height),
                                   end: CGPoint(x: size.width, y: 0),
                                   options: [.drawsAfterEndLocation])
        }
    }

    /// Dark gradient at the bottom 40% of the frame so text is always readable
    private func drawBottomGradient(ctx: CGContext, size: CGSize) {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let clear = CGColor(red: 0, green: 0, blue: 0, alpha: 0)
        let dark = CGColor(red: 0, green: 0, blue: 0, alpha: 0.85)

        guard let grad = CGGradient(colorsSpace: colorSpace,
                                     colors: [dark, clear] as CFArray, locations: [0, 1]) else { return }

        // Bottom 40% of frame
        ctx.saveGState()
        ctx.clip(to: CGRect(x: 0, y: 0, width: size.width, height: size.height * 0.45))
        ctx.drawLinearGradient(grad,
                               start: CGPoint(x: 0, y: 0),
                               end: CGPoint(x: 0, y: size.height * 0.45),
                               options: [])
        ctx.restoreGState()
    }
}

// MARK: - Brand Bar

extension ThumbnailRenderer {

    /// Green/gold brand bar at the very bottom — like TBPN's green bar
    private func drawBrandBar(ctx: CGContext, brand: ThumbnailBrand, size: CGSize) {
        let barHeight: CGFloat = 6
        // Gold accent line
        ctx.setFillColor(brand.accentGold)
        ctx.fill(CGRect(x: 0, y: 0, width: size.width, height: barHeight))

        // Logo in bottom-right corner, above the bar
        if let logo = brand.logoImage {
            let logoMaxH: CGFloat = 45
            let logoW = CGFloat(logo.width)
            let logoH = CGFloat(logo.height)
            let scale = logoMaxH / logoH
            let drawW = logoW * scale
            let drawH = logoMaxH
            let padding: CGFloat = 20
            let x = size.width - drawW - padding
            let y = barHeight + 10
            ctx.draw(logo, in: CGRect(x: x, y: y, width: drawW, height: drawH))
        }
    }
}

// MARK: - Host Photo Cutouts

extension ThumbnailRenderer {

    private func generateCutouts(photos: [Data]) throws -> [CGImage] {
        let ciContext = CIContext()
        var results: [CGImage] = []
        for photo in photos {
            let ciImage = try PhotoCutout.cutout(photo: photo, featherRadius: 8)
            guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { continue }
            results.append(cgImage)
        }
        return results
    }

    private func drawHosts(ctx: CGContext, layout: ThumbnailLayout, brand: ThumbnailBrand, cutouts: [CGImage], size: CGSize) {
        switch layout {
        case .splitPanel:
            // Host A: bottom-left, occupying lower 55% of frame
            if cutouts.count > 0 {
                let hostRect = CGRect(
                    x: size.width * -0.02,
                    y: size.height * 0.08,
                    width: size.width * 0.38,
                    height: size.height * 0.60
                )
                drawHostImage(ctx: ctx, image: cutouts[0], in: hostRect)
            }
            // Host B: bottom-right, occupying lower 55% of frame
            if cutouts.count > 1 {
                let hostRect = CGRect(
                    x: size.width * 0.64,
                    y: size.height * 0.08,
                    width: size.width * 0.38,
                    height: size.height * 0.60
                )
                drawHostImage(ctx: ctx, image: cutouts[1], in: hostRect)
            }

        case .centered:
            // Host A: bottom-left with tilt
            if cutouts.count > 0 {
                let hostRect = CGRect(
                    x: size.width * 0.02,
                    y: size.height * 0.02,
                    width: size.width * 0.42,
                    height: size.height * 0.65
                )
                ctx.saveGState()
                let center = CGPoint(x: hostRect.midX, y: hostRect.midY)
                ctx.translateBy(x: center.x, y: center.y)
                ctx.rotate(by: -2 * .pi / 180)
                ctx.translateBy(x: -center.x, y: -center.y)
                drawHostImage(ctx: ctx, image: cutouts[0], in: hostRect)
                ctx.restoreGState()
            }
            // Host B: bottom-right with opposite tilt
            if cutouts.count > 1 {
                let hostRect = CGRect(
                    x: size.width * 0.56,
                    y: size.height * 0.02,
                    width: size.width * 0.42,
                    height: size.height * 0.65
                )
                ctx.saveGState()
                let center = CGPoint(x: hostRect.midX, y: hostRect.midY)
                ctx.translateBy(x: center.x, y: center.y)
                ctx.rotate(by: 2 * .pi / 180)
                ctx.translateBy(x: -center.x, y: -center.y)
                drawHostImage(ctx: ctx, image: cutouts[1], in: hostRect)
                ctx.restoreGState()
            }

        case .textHeavy:
            // Small circular cutouts, top-left
            let circleSize: CGFloat = 100
            let startX: CGFloat = 40
            let startY: CGFloat = size.height - 140
            for (i, cutout) in cutouts.prefix(2).enumerated() {
                let cx = startX + CGFloat(i) * (circleSize + 16)
                let circleRect = CGRect(x: cx, y: startY, width: circleSize, height: circleSize)
                ctx.saveGState()
                ctx.addEllipse(in: circleRect)
                ctx.clip()
                drawHostImage(ctx: ctx, image: cutout, in: circleRect)
                ctx.restoreGState()
                ctx.setStrokeColor(brand.accentGold)
                ctx.setLineWidth(3)
                ctx.strokeEllipse(in: circleRect.insetBy(dx: 1.5, dy: 1.5))
            }
        }
    }

    private func drawHostImage(ctx: CGContext, image: CGImage, in rect: CGRect) {
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

// MARK: - Title Text (TBPN Style — BIG and bold)

extension ThumbnailRenderer {

    private func drawTitle(ctx: CGContext, config: ThumbnailConfig, size: CGSize) {
        let brand = config.brand

        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 4, height: -4),
            blur: 12,
            color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.9)
        )

        let titleText = config.title.uppercased()
        let subtitleText = config.subtitle?.uppercased()

        switch config.layout {
        case .splitPanel, .centered:
            // MASSIVE title centered, near bottom (above brand bar)
            let titleFont = CTFontCreateWithName("Helvetica-Bold" as CFString, 110, nil)
            let subtitleFont = CTFontCreateWithName("Helvetica-Bold" as CFString, 52, nil)

            // Title — auto-size to fit width
            let maxWidth = size.width * 0.85
            let titleW = measureText(titleText, font: titleFont)
            let actualTitleFont: CTFont
            if titleW > maxWidth {
                // Scale down to fit
                let scaleFactor = maxWidth / titleW
                actualTitleFont = CTFontCreateWithName("Helvetica-Bold" as CFString, 96 * scaleFactor, nil)
            } else {
                actualTitleFont = titleFont
            }

            let finalW = measureText(titleText, font: actualTitleFont)
            let titleX = (size.width - finalW) / 2
            let titleY: CGFloat = 75

            drawCTText(ctx: ctx, text: titleText, x: titleX, y: titleY, font: actualTitleFont, color: brand.textPrimary)

            // Subtitle below
            if let sub = subtitleText {
                let subW = measureText(sub, font: subtitleFont)
                let subX = (size.width - subW) / 2
                let subY: CGFloat = 20
                drawCTText(ctx: ctx, text: sub, x: subX, y: subY, font: subtitleFont, color: brand.textAccent)
            }

        case .textHeavy:
            let largeTitleFont = CTFontCreateWithName("Helvetica-Bold" as CFString, 110, nil)
            let subtitleFont = CTFontCreateWithName("Helvetica-Bold" as CFString, 56, nil)
            let titleX: CGFloat = 40
            let maxWidth = size.width * 0.85

            drawWrappedText(ctx: ctx, text: titleText, x: titleX, y: size.height * 0.50, maxWidth: maxWidth,
                           font: largeTitleFont, color: brand.textPrimary)

            if let sub = subtitleText {
                drawCTText(ctx: ctx, text: sub, x: titleX, y: size.height * 0.30, font: subtitleFont, color: brand.textAccent)
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
