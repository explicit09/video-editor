# Coverage Expansion Report

Date: 2026-04-01

## Coverage

- Workflow specs declaring MCP coverage: `18`
- MCP tools in inventory: `83`
- Declared coverage from workflow specs: `83/83`
- Observed live coverage across baseline + expansion runs: `83/83`

Observed coverage was verified by aggregating:

- `/Volumes/Explicit's Hard Drive/videoeditor_eval_system/index.sqlite`
- `/tmp/videoeditor-expansion-pass1/index.sqlite`
- `/tmp/videoeditor-expansion-pass2/index.sqlite`
- `/tmp/videoeditor-expansion-pass3/index.sqlite`
- `/tmp/videoeditor-expansion-pass4/index.sqlite`
- `/tmp/videoeditor-expansion-sanity/index.sqlite`
- `/tmp/videoeditor-expansion-sanity-2/index.sqlite`
- `/tmp/videoeditor-expansion-sanity-3/index.sqlite`

## New Workflow Families

- `audio_cleanup_suite`
- `video_processing_suite`
- `content_analysis_suite`
- `broll_hook_suite`
- `shorts_deep_suite`
- `asset_management_suite`

## Harness Changes

- Added strict tool-output validation so MCP responses like `Error: ...` fail the step instead of being recorded as a successful call.
- Added a lightweight `sleep` workflow op for async asset-refresh cases such as delete/reimport.
- Added config-path templating so workflows can reference repo-local support assets.
- Added task inference updates so corpus items receive the new workflow families automatically.

## Live Sanity Results

Passed live:

- `clip_editing_suite`
- `track_management_suite`
- `snapshot_platform_export_suite`
- `caption_overlay_suite`
- `audio_cleanup_suite`
- `video_processing_suite`
- `content_analysis_suite`
- `broll_hook_suite`
- `shorts_deep_suite`
- `asset_management_suite`
- `clip_styling_suite`
- `transcript_editing_suite`

Earlier baseline workflows already existed and remained in place:

- `import_and_verify`
- `export_verify`
- `transcribe`
- `episode_cut`
- `short_extract`
- `speaker_alignment_eval`

## Workflow Fixes Made During Expansion

- `content_analysis_suite`
  - switched `auto_cut` to `gentle` dry-run mode so transcript-light synthetic assets do not fail for the wrong reason.
- `broll_hook_suite`
  - changed `search_broll` to search-only mode and imported a fixed local support B-roll clip so the suite no longer depends on the top Pexels result exposing an HD MP4 download target.
- `clip_styling_suite`
  - reduced opacity impact and strengthened color-correction settings to avoid a false negative where opacity cancelled the visual brightness check.
- `transcript_editing_suite`
  - moved the delete range away from the first second so `verify_playback` no longer samples directly across the edit seam.

## Current State

Coverage expansion is complete at both levels:

- workflow declaration coverage: complete
- observed live tool coverage: complete

The next phase is no longer coverage work. It is quality work:

- rerun broader slices for the fully expanded workflow set
- investigate remaining suite-level or validator-level failures when they appear at scale
- produce the consolidated PR/report from the stabilized expanded suite
