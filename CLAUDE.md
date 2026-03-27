# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A native macOS video editor built with Swift, designed to be AI-ready from day one. The full architecture is in ARCHITECTURE.md — read it before making structural decisions.

**Stack:** Swift + SwiftUI/AppKit + AVFoundation + Metal + VideoToolbox + Core ML

## Build & Test Commands

All xcodebuild commands run from the `VideoEditor/` directory (where `project.yml` lives).

```bash
# Regenerate Xcode project (after pulling or changing project.yml)
cd VideoEditor && xcodegen generate

# Build
cd VideoEditor && xcodebuild -scheme VideoEditor -destination 'platform=macOS' build

# Run all tests (EditorCore + AIServices)
cd VideoEditor && xcodebuild -scheme VideoEditor -destination 'platform=macOS' test

# Run a specific test suite
cd VideoEditor && xcodebuild -scheme VideoEditor -destination 'platform=macOS' -only-testing:EditorCoreTests/ModelTests test

# Build/test packages independently
cd VideoEditor/Packages/EditorCore && swift build && swift test
cd VideoEditor/Packages/AIServices && swift build && swift test
```

**Project generation:** The `.xcodeproj` is generated from `VideoEditor/project.yml` via XcodeGen and is gitignored. Run `xcodegen generate` after cloning or modifying `project.yml`.

## Architecture (read ARCHITECTURE.md for full detail)

**Four layers:** UI (SwiftUI) → Playback/Render (AVFoundation+Metal) → Media Pipeline (VideoToolbox) → AI Services (Core ML + cloud)

**Two Swift packages:**
- `EditorCore` — all editor logic, no UI. Models, commands, intents, timeline, playback, rendering, media, export, storage, cache, actions, action log.
- `AIServices` — AI layer. Protocols, context building, three buckets (ingestion/assistive/generative), provider implementations.

**Critical patterns:**
- Timeline holds references + instructions, never video data. Clips point to immutable source assets via UUID.
- All state mutations flow: **EditorIntent → Command → Execute**. Intents are the shared vocabulary for human actions, AI, keyboard shortcuts, and automation.
- Commands receive an `EditingContext` (DI container) — no singletons, no global state.
- Every domain with mutable state is a Swift **actor** (ProjectStore, PlaybackEngine, RenderCache, ProxyService, etc.).
- Two rendering pipelines share one composition graph: interactive preview (proxy media, Metal, frame-budget-capped) and offline export (full-res, VideoToolbox hardware encode).
- AI operates on representations (transcript, metadata, embeddings), not raw pixels. AI failures never block human editing.

**Project persistence:** Bundle directory (`.veditor/`) with manifest.json, timeline.json, media/, proxies/, cache/, analysis/, and metadata.sqlite for action log + indexes.
