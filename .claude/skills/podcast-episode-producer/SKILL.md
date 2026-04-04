---
name: podcast-episode-producer
description: Produce edited podcast episodes from raw recordings. Handles transcription, episode detection, extraction, overlay setup, cuts, and export. Use when the user asks to produce a podcast episode, extract an episode, set up overlays or lower thirds, export a podcast, or work on Technologia Talks.
allowed-tools: import_media add_to_timeline transcribe_asset analyze_transcript extract_segment get_transcript_with_timing search_transcript set_overlay_config remove_section split_clip ripple_delete export_video save_snapshot restore_snapshot get_state set_caption_style set_zoom take_screenshot
---

# Podcast Episode Producer

You produce edited podcast episodes from raw multi-hour recordings. Your job is to find the real episodes (not rehearsals or pre-show), extract them cleanly, apply broadcast overlays, make precise cuts, and export.

## Step 0: Import and transcribe

1. `import_media` — bring the raw recording in
2. `add_to_timeline` — put it on the timeline
3. `transcribe_asset` — get the full transcript (async for files >5min, poll `get_transcript` until ready)
4. `save_snapshot` label="raw_import" — ALWAYS save before any edits

## Step 1: Analyze with Claude — NEVER SKIP THIS

1. `analyze_transcript` — sends full transcript to Claude for comprehension
2. Claude identifies:
   - Real episodes (not rehearsals, pre-show chatter, or intro takes)
   - Exact start/end timestamps for each episode
   - Topics discussed in each episode
   - Pre-show sections, post-show wrap-up, off-camera moments
3. **DO NOT use `detect_episodes`** — it's regex pattern matching ("welcome to"), not comprehension. It WILL find rehearsal intros and pre-show takes as false positives.
4. Read Claude's analysis carefully — it distinguishes pre-show from real content.

## Step 2: Extract the episode

1. Use the timestamps from `analyze_transcript` — Claude's timestamps, not keyword matching
2. `extract_segment` with `source_start` and `source_end`
3. **VERIFY** the first words match the expected episode start:
   - `get_transcript_with_timing` for the first 30 seconds
   - Watch for multiple takes — hosts often do 2-3 intro takes ("Welcome to..."). Use the LAST clean take.
   - The first take is usually incomplete or has mistakes
4. `save_snapshot` label="episode_extracted"

## Step 3: Set up overlay from template

1. `set_overlay_config` with `template="technologia_talks"` (loads hosts, photos, sponsors)
   - Only need to add: `episode_title`, `episode_subtitle`, `topics`, `chapters`
   - If no template system yet, set the full config with correct host info:
     - Host A (left): Tadiwa Mbuwayesango, Co-Host · Founder, LEARN-X
     - Host B (right): Elvis Kimara, Co-Host · Founder, Throwly
2. Topics and chapters: use `search_transcript` to find REAL timestamps for each topic
   - **NEVER guess timestamps** — always verify from the transcript
   - Convert source timestamps to timeline-relative (subtract episode start time)
3. `set_caption_style` style="none" — unless captions are explicitly requested

## Step 4: Make cuts

Use `split_clip` + `ripple_delete` — the proven manual approach:

1. Get the clip ID from `get_state`
2. `split_clip` at the start boundary of the section to remove
3. `split_clip` at the end boundary (on the NEW clip that starts at the split point)
4. `ripple_delete` the middle clip (between the two splits)
5. After EVERY cut: overlay timestamps after the cut point shift automatically (if auto-shift is enabled). If not, manually update the overlay config.
6. `save_snapshot` after cuts

**DO NOT use `remove_section`** — it has known issues with deleting entire clips instead of just the slice.

**DO NOT use `auto_cut`** on episodes longer than 5 minutes — it creates 100+ clips which can crash export. Use it only on short clips (<2 min) or in `dry_run` mode to preview what would be cut.

## Step 5: Verify and export

1. `get_state` — verify timeline duration is correct (original minus sum of all cuts)
2. `set_zoom` level="fit" then `take_screenshot` — verify overlay rendering looks correct
3. `export_video` preset="high" filename="EpisodeN_Title"
4. Verify export file exists and has reasonable size

## Step 6: Generate YouTube metadata

After export, ALWAYS generate:
1. **Title** — compelling, includes show name
2. **Description** — 2-3 sentence hook, then chapter timestamps
3. **Chapters** — use the overlay topic timestamps formatted as `M:SS - Topic Name`. YouTube requires `0:00` as the first chapter.
4. **Tags/hashtags** — relevant keywords

Example format:
```
TITLE:
How To Get REAL Feedback On Your Startup Idea | Technologia Talks

DESCRIPTION:
[2-3 sentence hook about the episode content]

⏱️ CHAPTERS:
0:00 - Intro
0:46 - Topic One
3:48 - Topic Two
...

🎙️ HOSTS:
Tadiwa Mbuwayesango — Co-Host · Founder, LEARN-X
Elvis Kimara — Co-Host · Founder, Throwly

#startups #technologiatalks #podcast
```

**Present this to the user after export. Do not skip this step.**

## What NOT to do

- **Never** use `detect_episodes` for finding real episodes — use `analyze_transcript`
- **Never** guess topic/chapter timestamps — search the transcript
- **Never** use `auto_cut` on long episodes (100+ clips crashes export)
- **Never** forget to `save_snapshot` before destructive operations
- **Never** set captions unless explicitly asked
- **Never** assume the first "Welcome to..." is the real intro — check for multiple takes
- **Never** use `remove_section` — use split_clip + ripple_delete instead
- **Never** export without verifying timeline duration matches expected

## Overlay Reference (Technologia Talks)

Timing at 30fps:
- Title card: 0-30s (fade in, hold, fade out)
- Host intro strip: 38s-1:32 (gold bar with photos, slides up from bottom)
- Name bars: always visible (bottom, above ticker)
- Smart ticker: bottom bar with sponsors cycling with current topic
- Chapter cards: pop in at chapter timestamps (centered, 6s display)

Host photos are at:
- `/Users/explicit/Library/Containers/com.videoeditor.app/Data/Documents/tadiwa.jpg`
- `/Users/explicit/Library/Containers/com.videoeditor.app/Data/Documents/elvis.jpg`
