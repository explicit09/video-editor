# Visual Scene Understanding for AI Editing Intelligence

**Date:** 2026-04-07
**Status:** Approved

## Summary

Add visual understanding to the AI editing assistant by analyzing video content at the scene level. Uses Apple's on-device VLM (macOS 26+) to generate natural language descriptions of each scene, giving the AI content comprehension it currently lacks — it works only from transcript and audio energy today.

## Motivation

The AI assistant makes editing decisions about video it cannot see. It relies entirely on transcript text and audio energy analysis. This means it can't understand what's visually happening — whether a speaker is gesturing, whether a shot is a wide or close-up, whether B-roll matches the visual mood. Adding scene-level visual descriptions lets the AI reason about visual content the same way it reasons about spoken content.

## Approach

**Scene-segmented visual context** — combine shot boundary detection with VLM descriptions. Detect scene changes first (cheap pixel histogram diff), then describe each scene with the on-device VLM. Store descriptions as time-ranged segments on MediaAsset, following the same pattern as `speakerSegments` and `silenceRanges`.

**Background progressive scan** — analysis runs automatically after import as a background task. The UI shows a progress indicator ("Analyzing visuals...") on the asset. By the time the user asks the AI to make editing decisions, visual context is typically ready.

### Why not fixed-interval frame sampling?

Fixed intervals (e.g., every 5s) miss important moments between samples and waste descriptions on static shots. Scene-based sampling aligns descriptions with actual visual content changes — where editorial decisions happen.

### Why not Claude Vision API?

API calls add cost and latency per frame. Apple's on-device VLM is free, private, and fast enough for batch processing. No cloud fallback — if the VLM isn't available, visual analysis is simply unavailable.

### Why not Vision framework + CLIP?

Apple's on-device VLM replaces both. It can detect faces, describe scenes, and understand semantic queries through natural language — one model instead of two pipelines stitched together.

## Data Model

```swift
struct VisualScene: Codable, Identifiable {
    let id: UUID
    let timeRange: ClosedRange<Double>  // seconds
    let description: String             // VLM-generated natural language
    let thumbnailPath: String?          // representative frame, cached to disk
    let confidence: Float               // shot detection confidence
}
```

Stored on `MediaAsset` as `visualScenes: [VisualScene]?`:
- `nil` — not yet analyzed
- `[]` — analyzed, no scenes detected (e.g., static image)

## Analysis Pipeline

A new `VisualAnalysisTask` running on `AnalysisQueue` (existing actor for background analysis).

### Three stages, sequential per asset:

1. **Shot boundary detection** — Read frames via `AVAssetReader`, compare consecutive frames using pixel histogram difference. Scene boundary when difference exceeds threshold. No ML needed.

2. **Frame extraction** — For each scene, extract a representative frame (middle of scene). Save as JPEG thumbnail to asset cache directory under `visual_scenes/`.

3. **VLM description** — Pass each representative frame to Apple's on-device VLM with an editorial-focused prompt: "Describe what's happening in this video frame, focusing on people, actions, setting, and mood." Store description on the `VisualScene`.

### Triggering

Kicks off automatically after media import, same as proxy generation. Runs at lower priority than transcription (transcript is more immediately useful).

### Progress

Publishes progress via existing `AnalysisQueue` observation pattern. UI shows "Analyzing visuals..." indicator on the asset in the media browser, matching the transcription spinner pattern.

### Failure handling

If VLM fails on a frame (e.g., macOS version doesn't support it), the scene still gets created with `description: ""` and the thumbnail. Degrades gracefully — the AI just has less context.

## AI Integration

### Context exposure

`AIContextBuilder` includes visual scenes at the `.full` level for assets on the timeline:

```json
{
  "assets": [{
    "id": "...",
    "name": "interview.mov",
    "visualScenes": [
      { "timeRange": [0.0, 12.4], "description": "Speaker at desk, leaning forward, animated gesturing" },
      { "timeRange": [12.4, 28.1], "description": "Wide shot of studio, crew visible in background" }
    ]
  }]
}
```

Token management: only include scenes for assets currently on the timeline. If an asset has 100+ scenes, truncate to scenes within the visible timeline region plus a summary count.

### New MCP tool

`get_visual_scenes` — returns visual scenes for an asset, with optional time range filter. Mirrors `get_transcript` pattern: AI pulls visual context on demand rather than always in the system prompt.

### System prompt

A short `<visual_context>` section telling the AI:
- Visual scene descriptions are available and how to request them
- Prefer cutting at scene boundaries
- Match B-roll to visual mood, not just transcript topic
- Use scene descriptions to understand on-screen action

### Skills

No changes to existing skills. Skills describe *what* to do; visual context makes the AI better at *where* and *when*.

## Storage & Caching

### Persistence

Visual scenes serialize to the same SQLite metadata store that transcripts use, keyed by asset name + file size:
- Survive re-imports
- Survive project close/reopen
- No duplicate analysis for same file imported twice

### Thumbnails

Representative frame JPEGs in asset cache directory under `visual_scenes/`. Follows existing cache policy — evictable, regenerable. If thumbnails are evicted, descriptions remain in SQLite; thumbnails re-extract on next access.

### Cache budget

~50-100KB per thumbnail JPEG. A 1-hour video with ~200 scenes uses ~10-20MB. Well within existing cache budget.

### Invalidation

If source asset changes (different file size), scenes are invalidated and re-analyzed — same trigger as transcript invalidation.

## Non-Goals

- **No semantic search over scenes** — AI reads descriptions and reasons; no "find all reaction shots" query system
- **No frame-level analysis** — scene-level only; thumbnail selection and blink detection are separate features
- **No real-time analysis during playback** — pre-computed on import, not live
- **No custom VLM prompts per skill** — all scenes get the same editorial-focused prompt
- **No training or fine-tuning** — Apple's VLM used as-is
- **No fallback to Claude Vision API** — if on-device VLM unavailable, visual analysis is unavailable
