---
name: meeting-highlights
description: Create executive summaries from meeting recordings. Uses audio energy to skip dead zones, identifies decisions and action items from transcript, removes small talk and technical issues. Verifies output quality. Use when the user asks about meeting highlights, summary, executive summary, action items, decisions, minutes, key moments, recap, meeting notes, or important parts.
allowed-tools: analyze_audio_energy get_transcript transcribe_asset search_transcript split_clip trim_clip move_clip delete_clips set_marker rename_clip measure_loudness set_clip_speed set_clip_transition verify_playback get_state
---

# Meeting Highlights Editor

You create concise, actionable summaries from meeting recordings. Every second in the output earns its place.

## Step 0: Audio energy scan — find where real discussion happens

Meetings are mostly dead air, setup, and filler. Find the real content first:

1. `analyze_audio_energy` with `segments: 20-30`
2. Dead zones (score < 30): likely "can you hear me?", waiting for people, screen share fumbles
3. Hot zones (score > 55): active discussion, debates, decisions being made
4. This map tells you where to focus. Don't waste time cleaning dead zones — cut them entirely.

## Step 1: Transcribe and classify

1. `transcribe_asset` if needed
2. `get_transcript`
3. Search for key patterns using `search_transcript`:

**Decisions (KEEP — HIGH):**
"decided", "agreed", "going with", "approved", "consensus", "final answer", "let's go with"

**Action items (KEEP — HIGH):**
"I will", "action item", "next step", "by Friday", "deadline", "follow up", "responsible"

**Risks/blockers (KEEP — MEDIUM):**
"concern", "risk", "blocker", "worried", "issue", "problem", "delayed"

**Cut entirely:**
"can you hear me", "you're on mute", "let me share", "one second", "how's everyone", "good morning"

## Step 2: Build the summary

Target: 5-minute summary from a 1-hour meeting (12:1 compression).

Budget:
- Decisions: 40% (120s)
- Action items: 30% (90s)
- Key discussions: 20% (60s)
- Opening context: 10% (30s)

Cross-reference: only keep segments that are BOTH high-energy (audio score > 45) AND contain decisions/actions (transcript search).

## Step 3: Edit

1. `split_clip` at each segment boundary
2. `rename_clip` with classification: "DECISION: pricing", "ACTION: John deploys Friday"
3. `delete_clips` all cut-classified segments
4. `trim_clip` each kept segment to sentence boundaries (0.3s padding)
5. Remove internal silence > 1.5s within kept segments
6. `set_marker` at each decision and action item
7. `set_clip_transition` with `crossDissolve` (0.3s) between segments from different meeting sections
8. Slight speed up if speakers are slow: `set_clip_speed` 1.05-1.1x

## Step 4: Mandatory verification

1. `verify_playback` mode "quick":
   - Audio at all checkpoints
   - Duration within 10% of target (4:30-5:30 for 5-min target)

2. `analyze_audio_energy` on the output:
   - Speech ratio should be > 80% (tight content, no dead air)
   - Engagement score should be > 60

3. `get_state`:
   - Every decision/action item has a marker
   - Clips are named with classifications
   - Speed shows on both V+A tracks
   - No gaps between segments

**Never tell the user the summary is ready without verification.**

## Available transitions (only these exist)

- `none` — hard cut (between consecutive segments)
- `crossDissolve` — soft blend (between segments from different meeting sections)
- `fadeToBlack` / `fadeFromBlack` — opening/closing
- `wipeLeft` / `wipeRight` — visible transition

## What NOT to do

- Never include "can you hear me?" segments
- Never cut a decision without enough context
- Never leave action items without identifying who owns them
- Never create a summary longer than 20% of the original
- Never skip audio energy scan — meetings have massive dead zones that waste editing time
- Never report done without verify_playback
