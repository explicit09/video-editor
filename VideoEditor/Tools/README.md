# MCP Visual Harness

This is the local QA harness for replacing manual editor checks with repeatable scenario runs.

What it does:
- drives the app through MCP tools
- asserts deterministic expectations from tool output and `editor://timeline`
- captures screenshots
- compares screenshots against approved baseline images
- writes JSON reports and visual diff artifacts

It is intentionally not production infrastructure. It is a developer-side oracle for running lots of repeatable visual checks without having to sit in front of the app.

It now has two layers:
- legacy screenshot scenario runs
- the local-first automated eval system under `eval_system/`

## Layout

- `mcp_visual_harness.py`: harness runner
- `eval_system/`: corpus, workflow, run, grading, coverage, and dashboard code
- `prepare_eval_corpus.py`: manifest ingest, validate, rescan, and repair utility
- `scenarios/*.json`: scenario definitions
- `baselines/`: approved screenshots
- `artifacts/`: generated reports, captured screenshots, and diffs for legacy scenarios

## Scenario Model

Each scenario is JSON and can:
- map asset aliases to library asset names
- call MCP tools with resolved asset IDs or generated UUIDs
- assert output text
- assert timeline counts
- capture a screenshot and compare it to a baseline

Supported argument references:
- `{"$asset": "demo"}`: resolve by scenario asset alias
- `{"$asset_name": "Demo_Raw_2"}`: resolve directly by asset name
- `{"$uuid": "overlay_track"}`: generate/store a UUID once
- `{"$var": "overlay_track"}`: reuse a stored variable

## First Run

Use `--accept-new` once to create the initial approved baseline:

```bash
python3 /Users/explicit/Projects/video-editor/VideoEditor/Tools/mcp_visual_harness.py \
  /Users/explicit/Projects/video-editor/VideoEditor/Tools/scenarios/demo_visual_smoke.json \
  --accept-new
```

That creates:
- `baselines/demo_visual_smoke/timeline_after_insert.png`
- an artifact report under `artifacts/<timestamp>-demo-visual-smoke/`

## Normal Run

```bash
python3 /Users/explicit/Projects/video-editor/VideoEditor/Tools/mcp_visual_harness.py \
  /Users/explicit/Projects/video-editor/VideoEditor/Tools/scenarios
```

If a screenshot no longer matches:
- the run fails with a non-zero exit code
- the captured screenshot is stored in `artifacts/...`
- a diff image is written so you can inspect the regression

## Automated Eval Commands

The eval system defaults to:
- corpus root: `/Volumes/Explicit's Hard Drive/eval_corpus`
- eval root: `/Volumes/Explicit's Hard Drive/videoeditor_eval_system`

Sync and validate the corpus:

```bash
python3 /Users/explicit/Projects/video-editor/VideoEditor/Tools/mcp_visual_harness.py sync-corpus --repair
```

Discover MCP tools and print coverage gaps:

```bash
python3 /Users/explicit/Projects/video-editor/VideoEditor/Tools/mcp_visual_harness.py inventory-tools
python3 /Users/explicit/Projects/video-editor/VideoEditor/Tools/mcp_visual_harness.py coverage-report
```

Queue and run workflow-based eval jobs:

```bash
python3 /Users/explicit/Projects/video-editor/VideoEditor/Tools/mcp_visual_harness.py enqueue import_and_verify --limit 5
python3 /Users/explicit/Projects/video-editor/VideoEditor/Tools/mcp_visual_harness.py run-queued --limit 5
```

Start the local dashboard:

```bash
python3 /Users/explicit/Projects/video-editor/VideoEditor/Tools/mcp_visual_harness.py serve
```

Repair or summarize a corpus manifest directly:

```bash
python3 /Users/explicit/Projects/video-editor/VideoEditor/Tools/prepare_eval_corpus.py repair-manifest --output-dir "/Volumes/Explicit's Hard Drive/eval_corpus"
python3 /Users/explicit/Projects/video-editor/VideoEditor/Tools/prepare_eval_corpus.py summarize --manifest "/Volumes/Explicit's Hard Drive/eval_corpus/manifest.json"
```

## What This Replaces

This is the right harness for:
- “does the timeline look the way we expect?”
- “did the waveform/clip/track layout visually regress?”
- “did this MCP edit sequence end in a valid composition?”

It should be paired with:
- package tests for pure logic
- `verify_playback` for content integrity
- scenario expansion as you add more UI states and workflows

## Recommended Next Step

Add one scenario per editor behavior you currently inspect manually:
- waveform visible after import
- linked audio/video insertion
- transform/effect playback
- split/trim/ripple timeline states
- short-form layout states

Once those baselines exist, you can run hundreds of scenario variations without manually opening the app each time.
