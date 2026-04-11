# Thumbnail Renderer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Programmatic thumbnail generation using Core Graphics — real host photos with background removal, perfect text, brand-consistent output with zero AI API calls.

**Architecture:** `ThumbnailRenderer` in EditorCore draws thumbnails via CGContext. Host photo backgrounds removed via existing `PersonMasker` (Vision framework) with feathered mask edges. Three layouts (split panel, centered, text heavy) defined as geometry structs. MCPServer dispatches to renderer when `provider: "local"` (new default).

**Tech Stack:** Swift, Core Graphics, Core Image, Vision, CoreText

---

### Task 1: ThumbnailConfig and ThumbnailBrand data models

**Files:**
- Create: `VideoEditor/Packages/EditorCore/Sources/EditorCore/Rendering/ThumbnailConfig.swift`

- [ ] **Step 1: Create the Rendering directory and data models file**

```swift
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

    public init(
        title: String,
        subtitle: String? = nil,
        layout: ThumbnailLayout = .splitPanel,
        hostPhotos: [Data] = [],
        brand: ThumbnailBrand
    ) {
        self.title = title
        self.subtitle = subtitle
        self.layout = layout
        self.hostPhotos = hostPhotos
        self.brand = brand
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cd VideoEditor/Packages/EditorCore && swift build 2>&1 | tail -5`
Expected: Build Succeeded

- [ ] **Step 3: Commit**

```bash
git add VideoEditor/Packages/EditorCore/Sources/EditorCore/Rendering/ThumbnailConfig.swift
git commit -m "feat(thumbnail): add ThumbnailConfig, ThumbnailBrand, ThumbnailLayout data models"
```

---

### Task 2: PhotoCutout — background removal with feathered edges

**Files:**
- Create: `VideoEditor/Packages/EditorCore/Sources/EditorCore/Rendering/PhotoCutout.swift`

**Context:** The existing `PersonMasker.generateMask(for:)` at `EditorCore/Analysis/PersonMasker.swift` takes a `CGImage` and returns a `CIImage?` mask (white=person, black=background). We wrap it with feathering.

- [ ] **Step 1: Create PhotoCutout.swift**

```swift
// PhotoCutout.swift
import Foundation
import CoreImage
import CoreGraphics

public struct PhotoCutout: Sendable {

    /// Remove background from a photo and feather the edges.
    /// Returns a CIImage of the person with transparent background and soft edges.
    public static func cutout(photo: Data, featherRadius: CGFloat = 8) throws -> CIImage {
        guard let ciPhoto = CIImage(data: photo) else {
            throw PhotoCutoutError.invalidImageData
        }
        guard let cgPhoto = CIContext().createCGImage(ciPhoto, from: ciPhoto.extent) else {
            throw PhotoCutoutError.invalidImageData
        }

        // Generate person mask using Vision framework
        guard let mask = PersonMasker.generateMask(for: cgPhoto) else {
            throw PhotoCutoutError.maskGenerationFailed
        }

        // Feather the mask edges with gaussian blur
        let featheredMask: CIImage
        if featherRadius > 0, let blurred = mask.applyingGaussianBlur(sigma: Double(featherRadius)) {
            // Crop back to original extent (blur expands the image)
            featheredMask = blurred.cropped(to: mask.extent)
        } else {
            featheredMask = mask
        }

        // Scale mask to match photo dimensions if needed
        let photoExtent = ciPhoto.extent
        let maskExtent = featheredMask.extent
        let scaleX = photoExtent.width / maskExtent.width
        let scaleY = photoExtent.height / maskExtent.height
        let scaledMask = featheredMask
            .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
            .transformed(by: CGAffineTransform(translationX: photoExtent.origin.x, y: photoExtent.origin.y))

        // Apply mask to photo: multiply photo by mask alpha
        guard let blendFilter = CIFilter(name: "CIBlendWithAlphaMask") else {
            throw PhotoCutoutError.filterNotAvailable
        }
        blendFilter.setValue(ciPhoto, forKey: kCIInputImageKey)
        blendFilter.setValue(CIImage(color: .clear).cropped(to: photoExtent), forKey: kCIInputBackgroundImageKey)
        blendFilter.setValue(scaledMask, forKey: kCIInputMaskImageKey)

        guard let result = blendFilter.outputImage else {
            throw PhotoCutoutError.compositionFailed
        }

        return result.cropped(to: photoExtent)
    }
}

public enum PhotoCutoutError: Error {
    case invalidImageData
    case maskGenerationFailed
    case filterNotAvailable
    case compositionFailed
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cd VideoEditor/Packages/EditorCore && swift build 2>&1 | tail -5`
Expected: Build Succeeded

- [ ] **Step 3: Commit**

```bash
git add VideoEditor/Packages/EditorCore/Sources/EditorCore/Rendering/PhotoCutout.swift
git commit -m "feat(thumbnail): add PhotoCutout — background removal with feathered edges"
```

---

### Task 3: ThumbnailRenderer — core rendering engine

**Files:**
- Create: `VideoEditor/Packages/EditorCore/Sources/EditorCore/Rendering/ThumbnailRenderer.swift`

**Context:** Uses CGContext (same pattern as `BroadcastOverlayRenderer.swift` at `EditorCore/Playback/BroadcastOverlayRenderer.swift`): create context with `CGContext(data:nil, width:w, height:h, bitsPerComponent:8, bytesPerRow:w*4, space:CGColorSpaceCreateDeviceRGB(), bitmapInfo:premultipliedLast)`, draw into it, then `ctx.makeImage()` to get CGImage.

- [ ] **Step 1: Create ThumbnailRenderer.swift with background + accent drawing**

```swift
// ThumbnailRenderer.swift
import Foundation
import CoreGraphics
import CoreImage
import CoreText

public struct ThumbnailRenderer: Sendable {

    public static let thumbnailWidth = 1536
    public static let thumbnailHeight = 1024

    public init() {}

    /// Render a complete thumbnail as PNG Data.
    public func render(config: ThumbnailConfig) async throws -> Data {
        let w = Self.thumbnailWidth
        let h = Self.thumbnailHeight

        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ThumbnailRenderError.contextCreationFailed
        }

        // CGContext has origin at bottom-left; we work in that coordinate system
        let brand = config.brand

        // 1. Draw background gradient
        drawBackground(ctx: ctx, width: w, height: h, layout: config.layout, brand: brand)

        // 2. Draw gold accent corner lines
        drawAccents(ctx: ctx, width: w, height: h, layout: config.layout, brand: brand)

        // 3. Composite host photo cutouts
        let cutouts = try await generateCutouts(photos: config.hostPhotos)
        drawHosts(ctx: ctx, width: w, height: h, layout: config.layout, cutouts: cutouts)

        // 4. Draw logo
        drawLogo(ctx: ctx, width: w, height: h, brand: brand)

        // 5. Render title text
        drawTitle(ctx: ctx, width: w, height: h, layout: config.layout, title: config.title, subtitle: config.subtitle, brand: brand)

        // 6. Export as PNG
        guard let cgImage = ctx.makeImage() else {
            throw ThumbnailRenderError.imageExportFailed
        }
        return try exportPNG(cgImage: cgImage)
    }

    // MARK: - Background

    private func drawBackground(ctx: CGContext, width w: Int, height h: Int, layout: ThumbnailLayout, brand: ThumbnailBrand) {
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        switch layout {
        case .splitPanel:
            // Left panel: 135° green→black
            ctx.saveGState()
            ctx.clip(to: CGRect(x: 0, y: 0, width: w / 2, height: h))
            if let gradient = CGGradient(colorsSpace: colorSpace, colors: [brand.secondaryBackground, brand.primaryBackground] as CFArray, locations: [0, 1]) {
                ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: CGFloat(h)), end: CGPoint(x: CGFloat(w / 2), y: 0), options: [])
            }
            ctx.restoreGState()

            // Right panel: 225° green→black
            ctx.saveGState()
            ctx.clip(to: CGRect(x: w / 2, y: 0, width: w / 2, height: h))
            if let gradient = CGGradient(colorsSpace: colorSpace, colors: [brand.secondaryBackground, brand.primaryBackground] as CFArray, locations: [0, 1]) {
                ctx.drawLinearGradient(gradient, start: CGPoint(x: CGFloat(w), y: CGFloat(h)), end: CGPoint(x: CGFloat(w / 2), y: 0), options: [])
            }
            ctx.restoreGState()

        case .centered:
            // Radial gradient: green center → black edges
            if let gradient = CGGradient(colorsSpace: colorSpace, colors: [brand.secondaryBackground, brand.primaryBackground] as CFArray, locations: [0, 1]) {
                ctx.drawRadialGradient(gradient, startCenter: CGPoint(x: CGFloat(w) / 2, y: CGFloat(h) / 2), startRadius: 0, endCenter: CGPoint(x: CGFloat(w) / 2, y: CGFloat(h) / 2), endRadius: CGFloat(max(w, h)) / 1.5, options: .drawsAfterEndLocation)
            }

        case .textHeavy:
            // Diagonal gradient: 160° green→black
            if let gradient = CGGradient(colorsSpace: colorSpace, colors: [brand.secondaryBackground, brand.primaryBackground] as CFArray, locations: [0, 1]) {
                ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: CGFloat(h) * 0.8), end: CGPoint(x: CGFloat(w), y: CGFloat(h) * 0.2), options: [.drawsAfterEndLocation])
            }
        }
    }

    // MARK: - Accent Lines

    private func drawAccents(ctx: CGContext, width w: Int, height h: Int, layout: ThumbnailLayout, brand: ThumbnailBrand) {
        ctx.setStrokeColor(brand.accentGold)
        ctx.setLineWidth(3)
        let cornerSize: CGFloat = 80

        let drawCorner = { (x: CGFloat, y: CGFloat, dx: CGFloat, dy: CGFloat) in
            ctx.move(to: CGPoint(x: x, y: y + dy * cornerSize))
            ctx.addLine(to: CGPoint(x: x, y: y))
            ctx.addLine(to: CGPoint(x: x + dx * cornerSize, y: y))
            ctx.strokePath()
        }

        switch layout {
        case .splitPanel:
            drawCorner(2, CGFloat(h) - 2, 1, -1)    // top-left
            drawCorner(CGFloat(w) - 2, 2, -1, 1)     // bottom-right

        case .centered:
            drawCorner(2, CGFloat(h) - 2, 1, -1)              // top-left
            drawCorner(CGFloat(w) - 2, CGFloat(h) - 2, -1, -1) // top-right
            drawCorner(2, 2, 1, 1)                              // bottom-left
            drawCorner(CGFloat(w) - 2, 2, -1, 1)               // bottom-right

        case .textHeavy:
            drawCorner(2, CGFloat(h) - 2, 1, -1)    // top-left
            drawCorner(CGFloat(w) - 2, 2, -1, 1)     // bottom-right
        }
    }

    // MARK: - Host Photos

    private func generateCutouts(photos: [Data]) async throws -> [CIImage] {
        var cutouts: [CIImage] = []
        for photo in photos {
            let cutout = try PhotoCutout.cutout(photo: photo, featherRadius: 12)
            cutouts.append(cutout)
        }
        return cutouts
    }

    private func drawHosts(ctx: CGContext, width w: Int, height h: Int, layout: ThumbnailLayout, cutouts: [CIImage]) {
        let ciContext = CIContext()

        switch layout {
        case .splitPanel:
            // Host A: left 5-47%, top 8-68% (in CGContext coords: bottom-left origin)
            if cutouts.count > 0 {
                let rect = CGRect(x: CGFloat(w) * 0.05, y: CGFloat(h) * 0.24, width: CGFloat(w) * 0.42, height: CGFloat(h) * 0.68)
                drawCutout(ctx: ctx, ciContext: ciContext, cutout: cutouts[0], rect: rect)
            }
            // Host B: right 53-95%
            if cutouts.count > 1 {
                let rect = CGRect(x: CGFloat(w) * 0.53, y: CGFloat(h) * 0.24, width: CGFloat(w) * 0.42, height: CGFloat(h) * 0.68)
                drawCutout(ctx: ctx, ciContext: ciContext, cutout: cutouts[1], rect: rect)
            }

        case .centered:
            // Host A: bottom-left, tilted 2°
            if cutouts.count > 0 {
                let rect = CGRect(x: CGFloat(w) * 0.05, y: CGFloat(h) * 0.02, width: CGFloat(w) * 0.42, height: CGFloat(h) * 0.62)
                ctx.saveGState()
                ctx.translateBy(x: rect.midX, y: rect.midY)
                ctx.rotate(by: 2 * .pi / 180)
                ctx.translateBy(x: -rect.midX, y: -rect.midY)
                drawCutout(ctx: ctx, ciContext: ciContext, cutout: cutouts[0], rect: rect)
                ctx.restoreGState()
            }
            // Host B: bottom-right, tilted -2°
            if cutouts.count > 1 {
                let rect = CGRect(x: CGFloat(w) * 0.53, y: CGFloat(h) * 0.02, width: CGFloat(w) * 0.42, height: CGFloat(h) * 0.62)
                ctx.saveGState()
                ctx.translateBy(x: rect.midX, y: rect.midY)
                ctx.rotate(by: -2 * .pi / 180)
                ctx.translateBy(x: -rect.midX, y: -rect.midY)
                drawCutout(ctx: ctx, ciContext: ciContext, cutout: cutouts[1], rect: rect)
                ctx.restoreGState()
            }

        case .textHeavy:
            // Small circular photos top-left, 80px each
            let circleSize: CGFloat = 100
            let padding: CGFloat = 20
            for (i, cutout) in cutouts.prefix(2).enumerated() {
                let x = padding + CGFloat(i) * (circleSize + 10)
                let y = CGFloat(h) - padding - circleSize  // top-left in flipped coords
                let circleRect = CGRect(x: x, y: y, width: circleSize, height: circleSize)

                // Clip to circle
                ctx.saveGState()
                ctx.addEllipse(in: circleRect)
                ctx.clip()
                drawCutout(ctx: ctx, ciContext: ciContext, cutout: cutout, rect: circleRect)
                ctx.restoreGState()

                // Gold circle border
                ctx.setStrokeColor(config_accentGold_placeholder)
                // We don't have brand here — draw accent in caller. Skip border for now.
            }
        }
    }

    private func drawCutout(ctx: CGContext, ciContext: CIContext, cutout: CIImage, rect: CGRect) {
        // Scale cutout to fit rect while preserving aspect ratio
        let extent = cutout.extent
        let scale = max(rect.width / extent.width, rect.height / extent.height)
        let scaledWidth = extent.width * scale
        let scaledHeight = extent.height * scale
        let offsetX = rect.origin.x + (rect.width - scaledWidth) / 2
        let offsetY = rect.origin.y + (rect.height - scaledHeight) / 2
        let drawRect = CGRect(x: offsetX, y: offsetY, width: scaledWidth, height: scaledHeight)

        if let cgImage = ciContext.createCGImage(cutout, from: cutout.extent) {
            ctx.draw(cgImage, in: drawRect)
        }
    }

    // MARK: - Logo

    private func drawLogo(ctx: CGContext, width w: Int, height h: Int, brand: ThumbnailBrand) {
        guard let logo = brand.logoImage else { return }
        let logoHeight: CGFloat = 50
        let logoWidth = CGFloat(logo.width) / CGFloat(logo.height) * logoHeight
        let padding: CGFloat = 20
        let logoRect = CGRect(
            x: CGFloat(w) - logoWidth - padding,
            y: CGFloat(h) - logoHeight - padding,  // top-right in CG coords
            width: logoWidth,
            height: logoHeight
        )
        ctx.draw(logo, in: logoRect)
    }

    // MARK: - Title Text

    private func drawTitle(ctx: CGContext, width w: Int, height h: Int, layout: ThumbnailLayout, title: String, subtitle: String?, brand: ThumbnailBrand) {
        let titleFontSize: CGFloat
        let subtitleFontSize: CGFloat
        let titleRect: CGRect
        let subtitleRect: CGRect
        let alignment: CTTextAlignment

        switch layout {
        case .splitPanel:
            titleFontSize = 72
            subtitleFontSize = 52
            titleRect = CGRect(x: CGFloat(w) * 0.05, y: CGFloat(h) * 0.04, width: CGFloat(w) * 0.9, height: CGFloat(h) * 0.12)
            subtitleRect = CGRect(x: CGFloat(w) * 0.05, y: CGFloat(h) * 0.14, width: CGFloat(w) * 0.9, height: CGFloat(h) * 0.08)
            alignment = .center

        case .centered:
            titleFontSize = 68
            subtitleFontSize = 48
            titleRect = CGRect(x: CGFloat(w) * 0.05, y: CGFloat(h) * 0.78, width: CGFloat(w) * 0.9, height: CGFloat(h) * 0.12)
            subtitleRect = CGRect(x: CGFloat(w) * 0.05, y: CGFloat(h) * 0.88, width: CGFloat(w) * 0.9, height: CGFloat(h) * 0.08)
            alignment = .center

        case .textHeavy:
            titleFontSize = 96
            subtitleFontSize = 56
            titleRect = CGRect(x: CGFloat(w) * 0.05, y: CGFloat(h) * 0.25, width: CGFloat(w) * 0.9, height: CGFloat(h) * 0.30)
            subtitleRect = CGRect(x: CGFloat(w) * 0.05, y: CGFloat(h) * 0.50, width: CGFloat(w) * 0.9, height: CGFloat(h) * 0.10)
            alignment = .left
        }

        // Title
        drawText(ctx: ctx, text: title.uppercased(), rect: titleRect, fontSize: titleFontSize, color: brand.textPrimary, alignment: alignment, shadow: true)

        // Subtitle
        if let subtitle = subtitle {
            drawText(ctx: ctx, text: subtitle.uppercased(), rect: subtitleRect, fontSize: subtitleFontSize, color: brand.textAccent, alignment: alignment, shadow: true)
        }
    }

    private func drawText(ctx: CGContext, text: String, rect: CGRect, fontSize: CGFloat, color: CGColor, alignment: CTTextAlignment, shadow: Bool) {
        if shadow {
            ctx.setShadow(offset: CGSize(width: 3, height: -3), blur: 10, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.8))
        }

        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, fontSize, nil)
        var alignmentValue = alignment
        let alignmentSetting = CTParagraphStyleSetting(
            spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size, value: &alignmentValue
        )
        let paragraphStyle = CTParagraphStyleCreate([alignmentSetting], 1)

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle,
        ]
        let attrString = NSAttributedString(string: text, attributes: attributes)
        let framesetter = CTFramesetterCreate(attrString)
        let path = CGPath(rect: rect, transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: attrString.length), path, nil)
        CTFrameDraw(frame, ctx)

        if shadow {
            ctx.setShadow(offset: .zero, blur: 0)
        }
    }

    // MARK: - Export

    private func exportPNG(cgImage: CGImage) throws -> Data {
        let mutableData = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(mutableData as CFMutableData, "public.png" as CFString, 1, nil) else {
            throw ThumbnailRenderError.imageExportFailed
        }
        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw ThumbnailRenderError.imageExportFailed
        }
        return mutableData as Data
    }
}

public enum ThumbnailRenderError: Error {
    case contextCreationFailed
    case imageExportFailed
}
```

**Note:** The `textHeavy` layout's gold circle borders for host photos need the brand color. We'll fix the `drawHosts` method to accept brand as a parameter.

- [ ] **Step 2: Fix drawHosts to accept brand parameter for text heavy circle borders**

Update the `drawHosts` signature and call site:

```swift
// Change signature:
private func drawHosts(ctx: CGContext, width w: Int, height h: Int, layout: ThumbnailLayout, cutouts: [CIImage], brand: ThumbnailBrand)

// In the textHeavy case, after restoreGState(), add:
ctx.setStrokeColor(brand.accentGold)
ctx.setLineWidth(3)
ctx.addEllipse(in: circleRect)
ctx.strokePath()

// Update the call in render():
drawHosts(ctx: ctx, width: w, height: h, layout: config.layout, cutouts: cutouts, brand: brand)
```

- [ ] **Step 3: Verify it compiles**

Run: `cd VideoEditor/Packages/EditorCore && swift build 2>&1 | tail -5`
Expected: Build Succeeded

- [ ] **Step 4: Commit**

```bash
git add VideoEditor/Packages/EditorCore/Sources/EditorCore/Rendering/ThumbnailRenderer.swift
git commit -m "feat(thumbnail): add ThumbnailRenderer — Core Graphics compositing engine"
```

---

### Task 4: Wire up MCPServer — local provider path

**Files:**
- Modify: `VideoEditor/VideoEditor/App/MCPServer.swift`

**Context:** The `handleGenerateThumbnail` function at line 5111 reads `providerFilter` from args (default `"both"`). We change the default to `"local"` and add a new code path that uses `ThumbnailRenderer` before the existing AI provider initialization block.

- [ ] **Step 1: Update tool schema description and default**

Find the `generate_thumbnail` tool definition (around line 558-570) and update:

```swift
// Change the description line:
"description": "Generate YouTube thumbnails. Default: programmatic renderer with real host photos (provider='local'). Also supports AI generation via FLUX/Gemini.",

// Change the provider description:
"provider": ["type": "string", "description": "Provider: 'local' (default — programmatic), 'flux', 'gemini', 'both' (flux + gemini)"],

// Add subtitle parameter after title:
"subtitle": ["type": "string", "description": "Subtitle text (rendered in gold). If omitted with local provider, extracted from title."],
```

- [ ] **Step 2: Add local provider path in handler**

In `handleGenerateThumbnail` (line 5111), change the default provider and add the local rendering path. After the parameter reading block (around line 5119), change:

```swift
// Change default from "both" to "local"
let providerFilter = args["provider"] as? String ?? "local"
let subtitle = args["subtitle"] as? String
```

Then, right after the host photo loading block (around line 5142) and before the prompt generation block, add:

```swift
// Local programmatic renderer — no AI needed
if providerFilter == "local" {
    let brand = loadThumbnailBrand(templateName: args["template"] as? String)

    let config = ThumbnailConfig(
        title: title,
        subtitle: subtitle,
        layout: ThumbnailLayout(rawValue: layout) ?? .splitPanel,
        hostPhotos: hostPhotos,
        brand: brand
    )

    let renderer = ThumbnailRenderer()
    let pngData: Data
    do {
        pngData = try await renderer.render(config: config)
    } catch {
        return "Error rendering thumbnail: \(error)"
    }

    // Save to Thumbnails directory
    let thumbnailDir: URL
    if let exportFolder = ExportFolderManager.defaultFolder {
        thumbnailDir = exportFolder.appendingPathComponent("Thumbnails")
    } else {
        thumbnailDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Thumbnails")
    }
    try? FileManager.default.createDirectory(at: thumbnailDir, withIntermediateDirectories: true)

    let sanitizedTitle = title.replacingOccurrences(of: "[^a-zA-Z0-9_-]", with: "_", options: .regularExpression).prefix(50)
    let filename = "thumbnail_\(sanitizedTitle)_\(layout).png"
    let filePath = thumbnailDir.appendingPathComponent(filename)
    try? pngData.write(to: filePath)

    return "Generated thumbnail: \(filePath.path)\nLayout: \(layout)\nSize: \(ThumbnailRenderer.thumbnailWidth)x\(ThumbnailRenderer.thumbnailHeight)"
}
```

- [ ] **Step 3: Add loadThumbnailBrand helper method**

Add this method to `MCPServer` (after the existing `loadOverlayTemplatePhotos` method):

```swift
private func loadThumbnailBrand(templateName: String?) -> ThumbnailBrand {
    // Default Technolgia brand
    var primaryBg = ThumbnailBrand.parseHex("#000000")
    var secondaryBg = ThumbnailBrand.parseHex("#0A3D2A")
    var accentGold = ThumbnailBrand.parseHex("#C8A84E")
    var textPrimary = ThumbnailBrand.parseHex("#FFFFFF")
    var textAccent = ThumbnailBrand.parseHex("#C8A84E")
    var logoImage: CGImage? = nil

    // Try loading from template JSON brand section
    if let name = templateName, let templateData = loadOverlayTemplateJSON(name) {
        if let brand = templateData["brand"] as? [String: Any],
           let colors = brand["colors"] as? [String: String] {
            if let v = colors["primary_background"] { primaryBg = ThumbnailBrand.parseHex(v) }
            if let v = colors["secondary_background"] { secondaryBg = ThumbnailBrand.parseHex(v) }
            if let v = colors["accent_gold"] { accentGold = ThumbnailBrand.parseHex(v) }
            if let v = colors["text_primary"] { textPrimary = ThumbnailBrand.parseHex(v) }
            if let v = colors["text_accent"] { textAccent = ThumbnailBrand.parseHex(v) }
        }
        if let brand = templateData["brand"] as? [String: Any],
           let logos = brand["logos"] as? [String: String],
           let logoFilename = logos["horizontal"] {
            let logoPath = resolveDocumentsPath(logoFilename)
            if let data = FileManager.default.contents(atPath: logoPath),
               let provider = CGDataProvider(data: data as CFData),
               let image = CGImage(pngDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) {
                logoImage = image
            }
        }
    }

    return ThumbnailBrand(
        primaryBackground: primaryBg,
        secondaryBackground: secondaryBg,
        accentGold: accentGold,
        textPrimary: textPrimary,
        textAccent: textAccent,
        logoImage: logoImage
    )
}
```

- [ ] **Step 4: Add loadOverlayTemplateJSON helper if it doesn't exist**

Check if there's already a method that loads the template JSON as a dictionary. If not, add:

```swift
private func loadOverlayTemplateJSON(_ name: String) -> [String: Any]? {
    let candidates = [
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("overlay_templates/\(name).json"),
        Bundle.main.bundleURL
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Tools/overlay_templates/\(name).json"),
    ].compactMap { $0 }

    for url in candidates {
        if let data = try? Data(contentsOf: url),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return json
        }
    }
    return nil
}
```

- [ ] **Step 5: Add import for EditorCore at top of MCPServer if needed**

The MCPServer already imports EditorCore. Verify `ThumbnailRenderer` and `ThumbnailConfig` are accessible.

- [ ] **Step 6: Build the full app**

Run: `cd VideoEditor && xcodebuild -scheme VideoEditor -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD" | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7: Commit**

```bash
git add VideoEditor/VideoEditor/App/MCPServer.swift
git commit -m "feat(thumbnail): wire local programmatic renderer as default provider"
```

---

### Task 5: Manual test — generate a thumbnail via MCP

**Files:** None (test only)

- [ ] **Step 1: Restart the app**

```bash
pkill -9 -f "VideoEditor.app" 2>/dev/null
lsof -ti :8420 | xargs kill -9 2>/dev/null
sleep 1
open /path/to/DerivedData/VideoEditor.app
```

Wait for MCP to respond on port 8420.

- [ ] **Step 2: Generate a split panel thumbnail**

```bash
curl -s http://localhost:8420/mcp -X POST \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"generate_thumbnail","arguments":{"title":"One Person Built OpenClaw","subtitle":"Why Solo Founders Win","template":"technologia_talks","layout":"split_panel"}}}'
```

Expected: Response with file path, no errors.

- [ ] **Step 3: Verify the output image exists and looks correct**

Open the generated PNG. Verify:
- Dark green/black gradient background
- Two host cutouts with feathered edges (no boxy photo frames)
- White title text, gold subtitle
- Technolgia logo top-right
- Gold corner accent lines

- [ ] **Step 4: Test centered layout**

```bash
curl -s http://localhost:8420/mcp -X POST \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"generate_thumbnail","arguments":{"title":"OpenAI vs Anthropic","subtitle":"The AI Competition Heats Up","template":"technologia_talks","layout":"centered"}}}'
```

- [ ] **Step 5: Test text heavy layout**

```bash
curl -s http://localhost:8420/mcp -X POST \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"generate_thumbnail","arguments":{"title":"AI IPOs Are a Bad Idea","subtitle":"Here Is Why","template":"technologia_talks","layout":"text_heavy"}}}'
```

- [ ] **Step 6: Test AI provider still works**

```bash
curl -s http://localhost:8420/mcp -X POST \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"generate_thumbnail","arguments":{"title":"Test AI","template":"technologia_talks","provider":"gemini","count":1}}}'
```

Expected: Gemini generates as before (existing path unchanged).

- [ ] **Step 7: Commit any fixes from testing**

```bash
git add -A
git commit -m "fix(thumbnail): adjustments from manual testing"
```

---

### Task 6: Update podcast-episode-producer skill

**Files:**
- Modify: `.claude/skills/podcast-episode-producer/SKILL.md`

- [ ] **Step 1: Update Step 7 thumbnail section to use local provider by default**

Replace the `generate_thumbnail` call template in the skill's Step 7 section:

```markdown
### How to Generate

```
generate_thumbnail(
  title="<episode title>",
  subtitle="<subtitle line>",
  template="technologia_talks",
  layout="split_panel"
)
```

The default provider is `"local"` — programmatic rendering with real host photos, background removal, and brand colors from the template. No AI API calls needed.

For AI-generated thumbnails (experimental), pass `provider="flux"` or `provider="gemini"`.
```

- [ ] **Step 2: Commit**

```bash
git add .claude/skills/podcast-episode-producer/SKILL.md
git commit -m "docs: update podcast producer skill to use local thumbnail renderer"
```
