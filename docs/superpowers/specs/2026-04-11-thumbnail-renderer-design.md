# Programmatic Thumbnail Renderer

## Problem

AI image generators (FLUX, Gemini, OpenAI) alter host photos and misspell text. Thumbnails need exact host faces and perfect typography for brand consistency.

## Solution

A `ThumbnailRenderer` in EditorCore that composites thumbnails programmatically using Core Graphics. Real host photos with backgrounds removed via Vision framework, text rendered via CoreText, brand assets loaded from overlay template JSON. No AI API calls — instant output.

## Pipeline

1. **Load host photos** — fixed files from app Documents dir (`tadiwa.jpg`, `elvis.jpg`)
2. **Remove backgrounds** — Vision `VNGeneratePersonSegmentationRequest` (existing `PersonMasker`)
3. **Feather edges** — Gaussian blur on segmentation mask for soft blend into gradient
4. **Draw background** — Dark green (#0A3D2A) to black (#000000) gradient via CGContext
5. **Composite hosts** — Place cutout CIImages onto background at layout-defined positions
6. **Render text** — CoreText for title (white, bold) and subtitle (gold #C8A84E, bold)
7. **Render logo** — Load `technolgia_logo_horizontal.png` from Documents, composite top-right
8. **Draw accents** — Gold (#C8A84E) corner lines via CGContext stroke paths
9. **Export PNG** — 1536×1024, save to Thumbnails/ directory

## Components

### ThumbnailRenderer (EditorCore)

Main entry point. Takes `ThumbnailConfig`, returns PNG `Data`.

```swift
public struct ThumbnailRenderer {
    func render(config: ThumbnailConfig) async throws -> Data
}
```

### ThumbnailConfig

```swift
public struct ThumbnailConfig {
    let title: String
    let subtitle: String?
    let layout: ThumbnailLayout
    let hostPhotos: [Data]        // JPEG/PNG data
    let brand: ThumbnailBrand
}
```

### ThumbnailLayout (enum)

```swift
public enum ThumbnailLayout: String {
    case splitPanel     // Two hosts side by side, title at bottom
    case centered       // Hosts angled inward, title above (debate energy)
    case textHeavy      // Small circular host photos, massive title dominates
}
```

Each case defines positioning geometry for hosts, text, logo, and accents.

### ThumbnailBrand

```swift
public struct ThumbnailBrand {
    let primaryBackground: CGColor    // #000000
    let secondaryBackground: CGColor  // #0A3D2A
    let accentGold: CGColor           // #C8A84E
    let textPrimary: CGColor          // #FFFFFF
    let textAccent: CGColor           // #C8A84E
    let logoImage: CGImage?
}
```

Loaded from overlay template JSON `brand` section.

### PhotoCutout (utility)

Uses existing `PersonMasker` + CIFilter gaussian blur on mask edges.

```swift
struct PhotoCutout {
    static func cutout(photo: Data, featherRadius: CGFloat = 8) async throws -> CIImage
}
```

## Layouts

### Split Panel (default)
- Background: two-panel gradient (left: 135° green→black, right: 225° green→black)
- Host A: left 5-47% width, top 8-68% height, feathered cutout
- Host B: right 53-95% width, top 8-68% height, feathered cutout
- Title: centered, bottom 8-20%, white uppercase bold
- Subtitle: centered, below title, gold uppercase bold
- Logo: top-right corner
- Accents: gold corner lines (top-left, bottom-right)

### Centered Face-Off
- Background: radial gradient (green center → black edges)
- Title: centered, top 6-18%, white + gold
- Host A: bottom-left, slight clockwise tilt (2°), feathered cutout
- Host B: bottom-right, slight counter-clockwise tilt (-2°), feathered cutout
- Logo: top-right corner
- Accents: gold corner lines (all four corners)

### Text Heavy
- Background: diagonal gradient (160° green→black)
- Host photos: small circular cutouts (gold border), top-left, 80×80px
- Title: large, left-aligned, 30-70% vertical, white
- Subtitle: below title, gold
- Logo: top-right corner
- Accents: gold corner lines (top-left, bottom-right)

## MCP Tool Interface

Extends existing `generate_thumbnail` tool:

- `provider: "local"` — programmatic renderer (new default)
- `provider: "flux"` / `"gemini"` / `"both"` — AI generation (existing, unchanged)
- New parameter: `layout` — `"split_panel"` (default), `"centered"`, `"text_heavy"`
- Title auto-generation: if title not provided, pull from most recent `analyze_transcript` result

When `provider` is omitted, default to `"local"`.

## Title Auto-Generation

When title/subtitle are not provided:
1. Check if `analyze_transcript` has been run for the current timeline's asset
2. Extract the episode title from the analysis
3. Split into title (main hook) + subtitle (supporting line)
4. Fall back to requiring manual title if no analysis exists

## Brand Loading

Brand info loaded from overlay template JSON (`technologia_talks.json`):

```json
{
  "brand": {
    "colors": {
      "primary_background": "#000000",
      "secondary_background": "#0A3D2A",
      "accent_gold": "#C8A84E",
      "text_primary": "#FFFFFF",
      "text_accent": "#C8A84E"
    },
    "logos": {
      "horizontal": "technolgia_logo_horizontal.png"
    }
  }
}
```

Structured for future templates — different shows can define different brands.

## File Location

- New files in `EditorCore/Rendering/`:
  - `ThumbnailRenderer.swift`
  - `ThumbnailConfig.swift`
  - `ThumbnailLayout.swift`
  - `PhotoCutout.swift`
- Modified: `MCPServer.swift` (add `provider: "local"` path, new default)

## Output

- Format: PNG, 1536×1024 (YouTube thumbnail)
- Location: `Documents/Thumbnails/thumbnail_{title}_{layout}.png`
- Generation time: <1 second (no network calls)

## What Stays the Same

- AI providers (FLUX, Gemini) remain available via `provider` parameter
- Existing `generate_thumbnail` MCP tool signature stays compatible
- Template JSON structure extended (brand section), not replaced
