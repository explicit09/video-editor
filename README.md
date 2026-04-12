# VideoEditor

A native macOS video editor built with Swift, designed to be AI-ready from day one.

Built for podcast and long-form content creators who want AI-powered editing without leaving a native app.

## What It Does

Import a 3-hour podcast recording, and the editor will:
- **Transcribe** the full audio (Deepgram cloud or WhisperKit local)
- **Find the real episodes** — Claude reads the transcript and identifies actual content vs pre-show chatter, rehearsals, and multiple intro takes
- **Extract cleanly** — pull the episode with the right start point
- **Apply broadcast overlays** — title cards, host name bars, chapter cards, scrolling ticker, host intro strip with photos
- **Make precise cuts** — split + ripple delete with automatic chapter timestamp adjustment
- **Export** — platform-aware presets for YouTube, TikTok, Instagram, and 8 more

## Stack

- **Swift + SwiftUI/AppKit** — native macOS UI
- **AVFoundation + Metal** — hardware-accelerated playback and rendering
- **VideoToolbox** — hardware encode for export
- **Core ML + WhisperKit** — on-device transcription (zero cost, works offline)
- **Deepgram** — cloud transcription with speaker diarization
- **Claude API** — content analysis, episode detection, hook optimization, title generation
- **Pexels API** — stock footage search and B-roll insertion

## 116 MCP Tools

The editor exposes 116 tools via MCP at `localhost:8420`, enabling any AI agent to edit video programmatically:

| Category | Tools | Examples |
|----------|-------|---------|
| Timeline editing | 14 | split, trim, move, slip, ripple trim, roll trim, speed |
| Audio processing | 9 | normalize, voice cleanup, denoise, auto-duck, loudness |
| Transcription | 6 | transcribe (cloud + local), search, timing |
| AI analysis | 7 | episode detection, content scoring, topic segmentation |
| Captions | 1 | 9 animated styles + disable |
| Short-form | 7 | face tracking, 9:16 recomposition, person mask, object tracking |
| Export | 3 | 11 platform presets |
| Broadcast overlay | 2 | template system, auto-shift timestamps |
| B-roll | 4 | Pexels search, local search, suggest, auto-insert |
| Text editing | 3 | transcript range delete, filler removal |
| Image generation | 2 | AI thumbnails, carousel graphics |
| Project management | 7 | create, open, save, close, delete, rename, list |
| Track management | 8 | add, remove, mute, solo, lock, rename, reorder, volume |
| Clip properties | 5 | volume, opacity, blend mode, crop, keyframes |
| Visual effects | 11 | LUT, chroma key, denoise video, stabilize, transitions |
| Playback control | 3 | play/pause, seek, loop |
| Utility | 24 | snapshots, verify, screenshots, undo/redo, action log |

## 9 AI Skills

Pre-built workflows following the [Agent Skills spec](https://agentskills.io):

- **podcast-episode-producer** — end-to-end episode production
- **podcast-editor** — audio cleanup and polish
- **viral-clip-extractor** — find shareable moments, format for social
- **shorts-formatter** — vertical 9:16 with face tracking
- **auto-cutter** — transcript-first editing
- **rough-cut-assembler** — assemble raw footage
- **beat-sync-editor** — cut to music
- **meeting-highlights** — executive summaries
- **pacing-optimizer** — remove dead zones

## Eval System

Automated testing against a 305-video corpus:
- 18 workflow suites covering all 116 tools
- Deterministic validators (playback, audio, export, duration, black frames)
- Gemini model judge for subjective quality grading
- 5 Swift tests + 45 Python tests

## Quick Start

```bash
# Prerequisites
brew install xcodegen

# Clone and generate Xcode project
git clone https://github.com/explicit09/video-editor.git
cd video-editor/VideoEditor
xcodegen generate

# Build and run
xcodebuild -scheme VideoEditor -destination 'platform=macOS' build
open /path/to/DerivedData/VideoEditor-xxx/Build/Products/Debug/VideoEditor.app

# Set up API keys (create VideoEditor/.env)
echo "DEEPGRAM_API_KEY=your_key" >> .env
echo "ANTHROPIC_API_KEY=your_key" >> .env
```

## Architecture

```
UI (SwiftUI)
  → Playback/Render (AVFoundation + Metal)
    → Media Pipeline (VideoToolbox)
      → AI Services (Core ML + Cloud)
```

Two Swift packages:
- **EditorCore** — all editor logic, no UI. Models, commands, intents, timeline, playback, rendering, media, export.
- **AIServices** — AI layer. Transcription (Deepgram + WhisperKit), analysis, providers.

All state mutations flow through: **EditorIntent → Command → Execute**

See [ARCHITECTURE.md](ARCHITECTURE.md) for full detail.

## License

Proprietary. All rights reserved.
