# AI Thumbnail & Carousel Generation

## Problem

The video editor lacks image generation for YouTube thumbnails and Instagram carousels. Currently, after editing a video, the user must switch to a separate tool (Canva, Photoshop, etc.) to create thumbnails. This breaks the workflow.

## Solution

Add a `generate_thumbnail` MCP tool that composites host photos with styled text/backgrounds using AI image generation. Uses a two-stage pipeline: Claude writes the image prompt, then two image gen providers execute it in parallel, producing 4 options to choose from.

## Decisions

- **Providers:** GPT Image 1.5 (primary) + Nano Banana 2 (secondary), both called in parallel
- **Prompt strategy:** Claude auto-generates the image prompt from episode metadata; optional manual override
- **Host photos:** Reuse existing overlay template system (`technologia_talks.json` already has host names, titles, photo paths)
- **Default layout:** Split panel (host on each side, title centered) — other layouts available via `layout` param
- **Output:** 4 images (2 per provider) saved to `{project}/Thumbnails/`
- **Carousel:** Interface stubbed, implementation deferred

---

## Architecture

### Provider Abstraction

```
ImageGenProvider (protocol)
  func generateImage(prompt: String, referenceImages: [Data], size: ImageSize) async throws -> Data

OpenAIImageProvider  — GPT Image 1.5, POST /v1/images/edits
GeminiImageProvider  — Nano Banana 2, Gemini 3.1 Flash Image generateContent
```

Both providers:
- Accept text prompt + reference images (host photos as PNG Data)
- Return PNG image data
- Load API key from environment (`OPENAI_API_KEY` / `GEMINI_API_KEY`)
- Located in `Packages/AIServices/Sources/AIServices/ImageGen/`

### Pipeline

```
generate_thumbnail tool call
  │
  ├─ 1. Load host config from overlay template (or host_photos override)
  ├─ 2. Read host photo files from disk
  ├─ 3. If no prompt override → Claude writes image gen prompt
  │     Input: title, description, host names, style, layout
  │     Output: detailed image generation prompt
  ├─ 4. Fire requests in parallel:
  │     ├─ OpenAIImageProvider.generateImage() x2
  │     └─ GeminiImageProvider.generateImage() x2
  ├─ 5. Save to {project}/Thumbnails/thumbnail_{title}_{provider}_{n}.png
  └─ 6. Return array of { path, provider, index }
```

---

## Tool Schema

### generate_thumbnail

```
name: generate_thumbnail
description: Generate YouTube thumbnails using AI. Composites host photos with styled
  text and backgrounds. Produces multiple options from different AI models. Requires
  OPENAI_API_KEY and/or GOOGLE_AI_API_KEY.

parameters:
  title:        (string, required)  Episode title text
  description:  (string)            Episode description for AI context
  template:     (string)            Overlay template name (e.g. "technologia_talks")
  host_photos:  (array of string)   Override: paths to host photo files
  style:        (string)            "bold" (default), "minimal", "dramatic", "vibrant"
  layout:       (string)            "split_panel" (default), "hosts_left", "centered", "text_heavy"
  prompt:       (string)            Override: skip Claude prompt gen, use directly
  count:        (integer)           Images per provider (default: 2)
  provider:     (string)            "both" (default), "openai", "gemini"
```

**Returns:** JSON array of generated thumbnail paths with provider info.

### generate_carousel (stub)

```
name: generate_carousel
description: Generate Instagram carousel slides using AI. Not yet implemented.

parameters:
  title:           (string, required)
  slides:          (array of { text, image_description })
  template:        (string)
  style:           (string)
  count_per_slide: (integer)
```

**Returns:** "Not yet implemented — coming soon."

---

## Prompt Engineering

When no `prompt` override is provided, Claude generates the image prompt.

**System prompt for Claude (thumbnail prompt writer):**

```
You are a YouTube thumbnail designer. Given an episode title, description,
host names, and style preferences, write a detailed image generation prompt.

Rules:
- Layout: {layout} — follow the specified layout structure
- Always specify: "Preserve the exact faces from the reference photos"
- Include: bold readable text, high contrast, YouTube-optimized composition
- Size: 1536x1024 landscape
- Style the background, lighting, and colors to match the episode mood
- Keep text to title + optional subtitle only — no clutter
- The prompt should work for both GPT Image and Gemini image generation
```

**Input to Claude:**

```json
{
  "title": "Why AI Will Change Everything",
  "description": "We discuss the latest breakthroughs...",
  "host_a": "Tadiwa Mbuwayesango",
  "host_b": "Elvis Kimara",
  "style": "bold",
  "layout": "split_panel"
}
```

**Output:** A single detailed prompt string sent to both image gen providers.

---

## Layout Presets

| Layout | Description |
|--------|-------------|
| `split_panel` (default) | Host on each side with own color zone, title centered |
| `hosts_left` | Both hosts on left, title text on right |
| `centered` | Title top-center, hosts below in face-off style |
| `text_heavy` | Small host photos corner, massive title dominates |

---

## File Changes

### New Files

| Path | Purpose |
|------|---------|
| `Packages/AIServices/Sources/AIServices/ImageGen/ImageGenProvider.swift` | Protocol, `ThumbnailRequest`, `GeneratedImage`, `ImageSize` types |
| `Packages/AIServices/Sources/AIServices/ImageGen/OpenAIImageProvider.swift` | GPT Image 1.5 provider (actor, `/v1/images/edits` endpoint) |
| `Packages/AIServices/Sources/AIServices/ImageGen/GeminiImageProvider.swift` | Nano Banana 2 provider (actor, Gemini `generateContent` endpoint) |

### Modified Files

| Path | Change |
|------|--------|
| `Packages/AIServices/Sources/AIServices/Tools/AIToolRegistry.swift` | Add `generateThumbnail` + `generateCarousel` definitions to `allTools` |
| `VideoEditor/App/MCPServer.swift` | Add both tools to `tools/list`, add handler in `executeToolCall` |

---

## Environment Variables

| Key | Provider | Required |
|-----|----------|----------|
| `OPENAI_API_KEY` | GPT Image 1.5 | Yes (if provider=openai or both) |
| `GEMINI_API_KEY` | Nano Banana 2 | Yes (if provider=gemini or both) |
| `ANTHROPIC_API_KEY` | Claude (prompt gen) | Yes (already used by app) |

---

## Reused Code

| What | Where |
|------|-------|
| Overlay template loading | `MCPServer.swift` — already loads `technologia_talks.json` |
| `HostInfo` struct | `Packages/EditorCore/.../Models/BroadcastOverlay.swift` |
| Claude API calls | `ClaudeProvider.swift` — for prompt generation step |
| `loadEnvKey()` pattern | `MCPServer.swift` — for loading API keys from .env |
| Export folder resolution | `MCPServer.swift` — for resolving project output path |

---

## Verification

1. `cd VideoEditor && xcodegen generate && xcodebuild -scheme VideoEditor -destination 'platform=macOS' build`
2. Set `OPENAI_API_KEY` and `GOOGLE_AI_API_KEY` in environment
3. MCP test: `tools/call generate_thumbnail { "title": "Test Episode", "template": "technologia_talks" }`
4. Verify 4 PNG files created in project's `Thumbnails/` directory
5. Verify images contain host faces, title text, and styled background
6. Test prompt override: pass `prompt` param, verify Claude step is skipped
7. Test single provider: `provider: "openai"`, verify only 2 images
8. Test in-app AI chat: "generate a thumbnail for episode: Why AI Will Change Everything"

---

## Out of Scope

- Carousel implementation (stubbed only)
- Thumbnail UI panel in the editor
- Thumbnail selection/rating workflow
- Video frame extraction for thumbnail context
