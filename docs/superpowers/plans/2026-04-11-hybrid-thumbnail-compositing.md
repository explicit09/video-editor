# Hybrid Thumbnail Compositing Pipeline

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a thumbnail pipeline that composites real host cutout photos on top of a topic background image, with programmatic text and brand badge — TBPN style.

**Architecture:** The `ThumbnailRenderer` gains a new `hybrid` mode. AI generates only the topic background scene (no hosts, no text). Then Core Graphics composites the real host cutouts (from studio photos with Vision background removal), renders text via CoreText, and places the brand logo. This gives AI creativity for backgrounds while preserving exact host faces and perfect text.

**Tech Stack:** Swift, Core Graphics, Core Image, Vision, CoreText, Gemini API

---

## File Structure

- **Modify:** `EditorCore/Rendering/ThumbnailRenderer.swift` — add `renderHybrid()` that takes a background image + host cutouts and composites them
- **Modify:** `EditorCore/Rendering/ThumbnailConfig.swift` — add `backgroundImage: Data?` field to ThumbnailConfig
- **Modify:** `MCPServer.swift` — add `provider: "hybrid"` path that generates background via AI, then composites with local renderer
- **Modify:** `MCPServer.swift` — update prompt system for background-only generation (no hosts, no text)

---

### Task 1: Add backgroundImage to ThumbnailConfig

**Files:**
- Modify: `VideoEditor/Packages/EditorCore/Sources/EditorCore/Rendering/ThumbnailConfig.swift`

- [ ] **Step 1: Add backgroundImage field to ThumbnailConfig**

In `ThumbnailConfig`, add a `backgroundImage` property. When present, the renderer uses this as the background instead of drawing gradients.

```swift
public struct ThumbnailConfig: Sendable {
    public let title: String
    public let subtitle: String?
    public let layout: ThumbnailLayout
    public let hostPhotos: [Data]
    public let brand: ThumbnailBrand
    public let backgroundImage: Data?  // ADD THIS

    public init(
        title: String,
        subtitle: String? = nil,
        layout: ThumbnailLayout = .splitPanel,
        hostPhotos: [Data] = [],
        brand: ThumbnailBrand,
        backgroundImage: Data? = nil  // ADD THIS
    ) {
        self.title = title
        self.subtitle = subtitle
        self.layout = layout
        self.hostPhotos = hostPhotos
        self.brand = brand
        self.backgroundImage = backgroundImage  // ADD THIS
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cd VideoEditor/Packages/EditorCore && swift build 2>&1 | tail -5`
Expected: Build Succeeded

- [ ] **Step 3: Commit**

```bash
git add VideoEditor/Packages/EditorCore/Sources/EditorCore/Rendering/ThumbnailConfig.swift
git commit -m "feat(thumbnail): add backgroundImage field to ThumbnailConfig"
```

---

### Task 2: Update ThumbnailRenderer to support background images

**Files:**
- Modify: `VideoEditor/Packages/EditorCore/Sources/EditorCore/Rendering/ThumbnailRenderer.swift`

**Context:** The current `render()` method calls `drawBackground()` which draws gradients. We need to check if `config.backgroundImage` is set — if so, draw that image scaled to fill the canvas instead of the gradient. Everything else (host cutouts, text, logo, accents) stays the same and draws ON TOP of the background image.

- [ ] **Step 1: Read the current ThumbnailRenderer.swift to understand the render() flow**

Read the full file at `VideoEditor/Packages/EditorCore/Sources/EditorCore/Rendering/ThumbnailRenderer.swift`.

- [ ] **Step 2: Modify the render() method to check for background image**

In the `render()` method, right after creating the CGContext and before calling `drawBackground()`, add a check:

```swift
// 1. Background: use provided image or draw gradient
if let bgData = config.backgroundImage,
   let bgCIImage = CIImage(data: bgData),
   let bgCGImage = CIContext().createCGImage(bgCIImage, from: bgCIImage.extent) {
    // Draw background image scaled to fill canvas
    let bgRect = CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h))
    ctx.draw(bgCGImage, in: bgRect)
} else {
    drawBackground(ctx: ctx, layout: config.layout, brand: config.brand, size: size)
}
```

Replace the existing `drawBackground` call with this conditional block. The rest of the pipeline (accents, hosts, logo, text) remains unchanged and draws on top.

- [ ] **Step 3: Verify it compiles**

Run: `cd VideoEditor/Packages/EditorCore && swift build 2>&1 | tail -5`
Expected: Build Succeeded

- [ ] **Step 4: Commit**

```bash
git add VideoEditor/Packages/EditorCore/Sources/EditorCore/Rendering/ThumbnailRenderer.swift
git commit -m "feat(thumbnail): support background image in renderer — draws real image instead of gradient"
```

---

### Task 3: Add hybrid provider path to MCPServer

**Files:**
- Modify: `VideoEditor/VideoEditor/App/MCPServer.swift`

**Context:** When `provider: "hybrid"` is used:
1. Generate a background-only image via Gemini (no hosts, no text — just topic scene)
2. Pass that background image to ThumbnailRenderer along with real host photos
3. Renderer composites host cutouts + text + logo on top of the AI background

- [ ] **Step 1: Add "hybrid" to the tool schema provider description**

Find the `generate_thumbnail` tool definition (search for `"name": "generate_thumbnail"`) and update the provider description:

```swift
"provider": ["type": "string", "description": "Provider: 'local' (default — programmatic), 'hybrid' (AI background + real host compositing), 'flux', 'gemini', 'both' (flux + gemini)"],
```

- [ ] **Step 2: Add the hybrid provider path in handleGenerateThumbnail**

After the `if providerFilter == "local"` block and its closing brace, add the hybrid path:

```swift
// Hybrid: AI generates background, then composite real hosts + text on top
if providerFilter == "hybrid" {
    let brand = loadThumbnailBrand(templateName: args["template"] as? String)

    // Generate background-only prompt
    let bgPrompt: String
    if let override = promptOverride {
        bgPrompt = override
    } else {
        let topicDesc = description ?? title
        bgPrompt = "A 1536x1024 cinematic background scene for a YouTube thumbnail about: \(topicDesc). "
            + "Show the topic visually — relevant imagery, logos, symbols, or scenes that represent the subject. "
            + "The topic visual should be bold and fill most of the frame. "
            + "Leave space in the lower-left and lower-right areas for people to be composited on top later. "
            + "DO NOT include any people, faces, or human figures. "
            + "DO NOT include any text, titles, or words. "
            + "Use dark moody lighting. Color palette: dark greens, blacks, and gold accents."
    }

    // Use Gemini to generate background
    var backgroundData: Data? = nil
    if let key = ProcessInfo.processInfo.environment["GEMINI_API_KEY"]
        ?? ProcessInfo.processInfo.environment["GOOGLE_AI_API_KEY"]
        ?? loadEnvKey("GEMINI_API_KEY")
        ?? loadEnvKey("GOOGLE_AI_API_KEY") {
        let gemini = GeminiImageProvider(apiKey: key)
        do {
            backgroundData = try await gemini.generateImage(
                prompt: bgPrompt,
                referenceImages: [],  // No reference images for background
                size: .thumbnail
            )
        } catch {
            return "Error generating background: \(error)"
        }
    } else {
        return "Error: GEMINI_API_KEY not set (needed for hybrid background generation)"
    }

    // Composite: background + real host cutouts + text + logo
    let config = ThumbnailConfig(
        title: title,
        subtitle: subtitle,
        layout: ThumbnailLayout(rawValue: layout) ?? .splitPanel,
        hostPhotos: hostPhotos,
        brand: brand,
        backgroundImage: backgroundData
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
    let filename = "thumbnail_\(sanitizedTitle)_hybrid.png"
    let filePath = thumbnailDir.appendingPathComponent(filename)
    try? pngData.write(to: filePath)

    return "Generated hybrid thumbnail: \(filePath.path)\nBackground: AI-generated (Gemini)\nHosts: Real photos with background removal\nText: Programmatic\nSize: \(ThumbnailRenderer.canvasWidth)x\(ThumbnailRenderer.canvasHeight)"
}
```

- [ ] **Step 3: Verify it compiles**

Run: `cd VideoEditor && xcodebuild -scheme VideoEditor -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD" | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add VideoEditor/VideoEditor/App/MCPServer.swift
git commit -m "feat(thumbnail): add hybrid provider — AI background + real host compositing"
```

---

### Task 4: Test and visually verify

**Files:** None (test only)

- [ ] **Step 1: Restart the app**

```bash
pkill -9 -f "VideoEditor.app" 2>/dev/null
lsof -ti :8420 | xargs kill -9 2>/dev/null
sleep 1
open /Users/tadies/Library/Developer/Xcode/DerivedData/VideoEditor-fbjkrqemkbafmgazbphxgomwuvnh/Build/Products/Debug/VideoEditor.app
```

Wait for MCP on port 8420.

- [ ] **Step 2: Generate a hybrid thumbnail for "Solo Founders"**

```bash
curl -s http://localhost:8420/mcp -X POST \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"generate_thumbnail","arguments":{"title":"One Person Built OpenClaw","subtitle":"Why Solo Founders Win","template":"technologia_talks","description":"Solo entrepreneurs building with AI. OpenClaw built by one person. a16z funding solo founders. One-person startups.","provider":"hybrid"}}}'
```

Expected: Response with file path. Open the PNG and verify:
- AI-generated background shows topic-relevant imagery (laptop, code, AI symbols)
- Real Tadiwa and Elvis cutouts composited on top with clean edges
- Text is perfect (not AI-generated) — white title, gold subtitle
- Brand logo visible
- No fake/garbled logos

- [ ] **Step 3: Generate a hybrid thumbnail for "OpenAI vs Anthropic"**

```bash
curl -s http://localhost:8420/mcp -X POST \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"generate_thumbnail","arguments":{"title":"OpenAI vs Anthropic","subtitle":"Who Wins?","template":"technologia_talks","description":"The fierce battle between OpenAI and Anthropic. Claude Code vs Codex. Who is winning the AI race.","provider":"hybrid"}}}'
```

- [ ] **Step 4: Generate a hybrid thumbnail for "AI IPOs"**

```bash
curl -s http://localhost:8420/mcp -X POST \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"generate_thumbnail","arguments":{"title":"AI IPOs Are Risky","subtitle":"Here Is Why","template":"technologia_talks","description":"Should OpenAI and Anthropic go public? Risks of IPO during AI arms race. Tesla analogy. Figma cautionary tale.","provider":"hybrid"}}}'
```

- [ ] **Step 5: Visually compare all three outputs**

Open all generated PNGs. For each, verify:
- Background is topic-relevant and visually interesting (not generic)
- Host cutouts have clean feathered edges (no halos, no artifacts)
- Hosts are positioned well on the background (not covering key visuals)
- Text is sharp, correctly rendered, readable at small sizes
- No AI-generated text or logos in the background (should be scene-only)
- Overall composition feels professional — close to TBPN quality

- [ ] **Step 6: Commit any fixes from testing**

```bash
git add -A
git commit -m "fix(thumbnail): adjustments from hybrid compositing testing"
```

---

### Task 5: Update skill documentation

**Files:**
- Modify: `.claude/skills/podcast-episode-producer/SKILL.md`

- [ ] **Step 1: Update Step 7 to document hybrid provider**

In the "How to Generate" section under Step 7, update to show the hybrid provider as the recommended approach:

```markdown
### How to Generate

Default (programmatic, instant):
```
generate_thumbnail(
  title="<episode title>",
  subtitle="<subtitle line>",
  template="technologia_talks",
  layout="split_panel"
)
```

Recommended (AI background + real photos):
```
generate_thumbnail(
  title="<episode title>",
  subtitle="<subtitle line>",
  template="technologia_talks",
  description="<topic description for visual background>",
  provider="hybrid"
)
```

The `hybrid` provider generates a topic-relevant background with AI (Gemini), then composites real host cutout photos on top with programmatic text and brand badge. This gives the best results — AI creativity for the scene, exact host faces, perfect text.

The `description` field drives the visual content of the background. Be specific about the topic — mention companies, technologies, people, or concepts that should appear visually.
```

- [ ] **Step 2: Commit**

```bash
git add .claude/skills/podcast-episode-producer/SKILL.md
git commit -m "docs: update skill to recommend hybrid thumbnail provider"
```
