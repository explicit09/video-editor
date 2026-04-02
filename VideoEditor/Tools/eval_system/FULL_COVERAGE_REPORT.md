# VideoEditor Eval System — Full Coverage Broad Rerun Report

**Generated:** 2026-04-01
**Eval DB:** `/Volumes/Explicit's Hard Drive/videoeditor_eval_system/index.sqlite`
**Corpus Manifest:** `/Volumes/Explicit's Hard Drive/eval_corpus/manifest.json`

## Executive Summary

This report covers the first broad rerun after workflow-family expansion reached full MCP surface coverage.

Important update:

- The touched-suite follow-up work in `TARGETED_RERUN_REPORT.md` supersedes the broad-run verdict for:
  - `clip_styling_suite`
  - `caption_overlay_suite`
  - focused `import_and_verify`
- In particular, `caption_overlay_suite` should no longer be treated as product-red based on this broad report alone; later targeted reruns show it is product-passing and infrastructure-limited on long AVA items.

- MCP tool inventory: `83`
- Declared workflow coverage: `83 / 83`
- Observed live coverage: `83 / 83`
- Total run records: `1233`
- Completed runs used for this report: `1208`
- Queued runs: `0`
- Stale `running` rows: `25`

The rerun is effectively complete. No `run-queued` worker was still alive when this report was generated, so the remaining `running` rows are stale crash leftovers and are excluded from the result totals below.

Final completed-run outcomes:

- `188` pass
- `873` fail
- `147` quarantine

Overall pass rate on completed runs: `15.6%`

This is not yet a clean product-quality scorecard. The run surfaced real workflow and validation problems, but it also contains known contamination from:

- provider rate limiting in TwelveLabs
- long-running timeout failures
- stale pre-fix results for caption and verifier work that were debugged mid-run

## Corpus Slices Actually Exercised

Completed runs by split:

- `576` calibration
- `448` development
- `184` holdout

Completed runs by source family:

- `488` AVA
- `211` TVSum
- `235` Pexels
- `250` Synthetic
- `24` Failure pack

The broad rerun did not apply every workflow to every corpus item. The workflow families were targeted to the source families they were designed for.

## Workflow Results

| Workflow | Completed | Pass | Fail | Quarantine | Pass Rate |
|---|---:|---:|---:|---:|---:|
| `asset_management_suite` | 11 | 8 | 3 | 0 | 72.7% |
| `audio_cleanup_suite` | 41 | 5 | 36 | 0 | 12.2% |
| `broll_hook_suite` | 42 | 1 | 40 | 1 | 2.4% |
| `caption_overlay_suite` | 63 | 7 | 49 | 7 | 11.1% |
| `clip_editing_suite` | 16 | 12 | 4 | 0 | 75.0% |
| `clip_styling_suite` | 62 | 19 | 43 | 0 | 30.6% |
| `content_analysis_suite` | 41 | 9 | 32 | 0 | 22.0% |
| `episode_cut` | 1 | 1 | 0 | 0 | 100.0% |
| `export_verify` | 300 | 4 | 239 | 57 | 1.3% |
| `import_and_verify` | 302 | 0 | 231 | 71 | 0.0% |
| `short_extract` | 1 | 0 | 0 | 1 | 0.0% |
| `shorts_deep_suite` | 32 | 1 | 26 | 5 | 3.1% |
| `snapshot_platform_export_suite` | 11 | 3 | 3 | 5 | 27.3% |
| `speaker_alignment_eval` | 1 | 0 | 1 | 0 | 0.0% |
| `track_management_suite` | 11 | 7 | 4 | 0 | 63.6% |
| `transcribe` | 200 | 82 | 118 | 0 | 41.0% |
| `transcript_editing_suite` | 42 | 24 | 18 | 0 | 57.1% |
| `video_processing_suite` | 31 | 5 | 26 | 0 | 16.1% |

## Workflow Coverage Notes

Workflows that held up reasonably well:

- `clip_editing_suite`
- `track_management_suite`
- `asset_management_suite`
- `transcript_editing_suite`

Workflows that are red and need direct follow-up:

- `caption_overlay_suite`
- `audio_cleanup_suite`
- `broll_hook_suite`
- `shorts_deep_suite`
- `video_processing_suite`
- `export_verify`
- `import_and_verify`

Important caveat:

- `caption_overlay_suite` and `clip_styling_suite` were actively debugged mid-run. Their broad-rerun numbers should be treated as pre-fix-heavy and require a targeted clean rerun.

## Validator Summary

| Validator | Pass | Fail | Quarantine | Total | Pass Rate |
|---|---:|---:|---:|---:|---:|
| `audio_present` | 140 | 65 | 19 | 224 | 62.5% |
| `duration_sanity` | 205 | 0 | 19 | 224 | 91.5% |
| `export_exists` | 205 | 19 | 0 | 224 | 91.5% |
| `no_black_frames` | 178 | 27 | 19 | 224 | 79.5% |
| `transcript_present` | 122 | 0 | 0 | 122 | 100.0% |
| `verify_playback_clean` | 212 | 219 | 0 | 431 | 49.2% |

Largest validator failure buckets:

- `verify_playback_clean`: `219`
- `audio_present`: `65`
- `no_black_frames`: `27`
- `export_exists`: `19`

What these numbers mean right now:

- `transcript_present` is strong once a transcription run succeeds.
- `verify_playback_clean` remains the biggest deterministic problem area.
- `audio_present` is still materially distorted by corpus/media expectations and verifier behavior.
- `export_exists` and `duration_sanity` are comparatively healthy.

## Judge Summary

The judge lane produced useful signal, but it is not clean enough to be the final gate yet.

Largest judge result buckets:

- `timeline_visual_sanity`: `106` pass, `73` fail, `307` quarantine, `4` unavailable
- `export_visual_quality`: `65` pass, `27` fail, `224` quarantine, `34` skipped
- `caption_overlay_export_quality`: `7` pass, `13` fail, `7` quarantine, `31` skipped

Provider-related contamination in this run:

- TwelveLabs rate limiting produced `80` run reasons with `HTTP 429`
- TwelveLabs also produced `44` short-video errors on `0.0s` or too-short evidence clips
- Gemini had a small number of write-timeout failures

So the judge data is directionally useful, but broad-run quarantine counts are inflated by provider behavior and evidence-window issues.

## Top Failure Reasons

Most common recorded fail/quarantine reasons:

1. `257` — `Run raised exception: timed out`
2. `219` — `verify_playback reported failures`
3. `80` — `TwelveLabs evaluation failed: HTTP 429`
4. `65` — `Audio stream was expected but missing`
5. `44` — `TwelveLabs evaluation failed: video_duration_too_short`
6. `27` — `Black frames detected in export`
7. `19` — `Export path was not detected`
8. `18` — `transcribe_asset failed validation: Error: No audio track found in media`
9. `18` — `No matching track found for step audio_track`
10. `12` — `hook_optimize failed validation: Error: No transcript words in clip source range`

Interpretation:

- Timeouts are the single biggest operational problem in the current broad rerun.
- The verifier still contributes a large amount of fail noise.
- Judge-rate-limit failures are high enough that they must be treated as infrastructure noise, not product verdicts.

## Notable Findings

### 1. Caption and styling remain the clearest product red flags

`caption_overlay_suite` and `clip_styling_suite` are the most obvious areas of product trouble in the newly expanded workflow set.

- `caption_overlay_suite`: `7 / 63` pass
- `clip_styling_suite`: `19 / 62` pass

These suites were debugged during the run, including caption-layout work, so the broad-rerun counts are not a clean post-fix measurement. They still require targeted reruns.

### 2. Clip and track editing are in better shape than the headline fail totals suggest

- `clip_editing_suite`: `12 / 16` pass
- `track_management_suite`: `7 / 11` pass

These are among the healthier new suites, and a meaningful share of their failures come from edge or failure-oriented corpus items rather than obvious product collapse.

### 3. The judge layer is useful but not gate-ready

The current run proves the judge adapters work at scale, but the outcome mix is still distorted by:

- provider quotas
- evidence clips that are too short
- skip policies

So the judge layer should remain advisory until the quota and evidence-window problems are cleaned up.

### 4. The verifier is still too sensitive for broad truth-claiming

`verify_playback_clean` is still failing on nearly half its checks. The rerun confirms this is still a top investigation area, but this report does not claim all of those are tool bugs. Some are:

- source-content edge cases
- no-audio media expectations
- boundary sensitivity
- likely real workflow/product issues

This needs a focused post-run cleanup pass, not hand-waving.

## Tool Coverage

Coverage status from the main eval DB:

- MCP inventory: `83`
- Declared by workflows: `83`
- Observed in live runs: `83`
- Missing observed tools: `none`

This rerun achieved the intended workflow/tool coverage milestone. The remaining problem is result quality, not missing tool coverage.

## Stale Rows

There are `25` rows still marked `running`, but they are stale. They include old records started on `2026-03-31`, and no `run-queued` worker process was alive when this report was generated.

Those rows should be treated as incomplete crash leftovers, not active work.

## What To Do Next

Priority order:

1. Run targeted clean reruns for:
   - `caption_overlay_suite`
   - `clip_styling_suite`
   - `audio_cleanup_suite`
   - focused `import_and_verify` verifier samples
2. Clean up stale `running` rows in reporting so they stop making the run look active.
3. Fix or soften the main verifier noise sources:
   - no-audio handling
   - overly early boundary checks
   - source-edge sensitivity
4. Fix judge infrastructure noise:
   - TwelveLabs rate-limit handling
   - too-short evidence windows
5. Only after those targeted reruns, write the PR-quality product verdict.

## Bottom Line

The expansion succeeded technically:

- the eval platform is running
- the corpus is being exercised at scale
- all `83` MCP tools are covered

But the first broad full-coverage rerun is not a “ship it” result. It is a high-signal discovery run. The strongest conclusions from it are:

- coverage is complete
- the broad rerun infrastructure works
- caption/styling, audio cleanup, B-roll/hook, and verifier behavior need focused cleanup
- judge-rate-limit noise is too high for clean gating yet

This is the right report to base the next targeted fix/rerun cycle on.
