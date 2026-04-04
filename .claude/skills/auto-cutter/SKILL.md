---
name: auto-cutter
description: Extract and clean podcast episodes from long recordings. Transcript-first analysis, then mechanical cleanup. Handles multi-episode recordings, rehearsals, false starts. Use when the user asks about auto cut, clean up, remove fillers, tighten, one click edit, auto edit, clean edit, polish, remove ums, remove silence, clean audio, tighten pacing, extract episode, podcast editing, or make episode.
allowed-tools: analyze_transcript get_full_transcript auto_cut get_state get_transcript transcribe_asset search_transcript score_content verify_playback trim_clip add_to_timeline clear_project
---

# Auto-Cutter: Episode Extraction & Cleanup

## CRITICAL: The Correct Order

**NEVER run auto_cut on a raw recording.** Always extract the episode first.

```
1. analyze_transcript → understand what's in the recording
2. Trim to episode boundaries → extract just the episode
3. auto_cut → mechanical cleanup (silence, fillers)
4. Review the result → verify it starts clean
```

## Step 1: Understand the Content (analyze_transcript)

Call `analyze_transcript` with the asset_id. This sends the FULL transcript to Claude, which reads everything and identifies:
- How many real episodes exist
- Exact start/end timestamps for each
- What's pre-show conversation vs actual content
- Where rehearsals and false starts are

**A real episode** develops a topic for an audience over 10+ minutes. An intro tagline ("Welcome to X") does NOT make something an episode — the content after it must actually deliver value. If they say "Welcome to Technologer" and then talk about their own YouTube views, that's pre-show chat, not an episode.

## Step 2: Extract the Episode (trim_clip)

Use Claude's timestamps to trim to the FINAL good take of the intro, not the first attempt. If Claude says there are rehearsals at 112:43 and 112:50, and the clean take is at 114:32 — start at 114:32.

```
1. clear_project
2. add_to_timeline with the asset
3. trim_clip to the episode boundaries from Step 1
```

Do NOT include rehearsals and hope auto_cut catches them. It can't.

## Step 3: Clean Up (auto_cut)

Now run `auto_cut` on the extracted episode. It handles:
- Silence removal (>0.8s for standard preset)
- Filler word removal (um, uh, er, ah, hmm)
- Basic retake detection (consecutive similar sentences)

Three presets:
| Preset | Best for |
|--------|----------|
| gentle | Interviews, tutorials — only removes >2s silence |
| standard | Podcasts, vlogs — removes silence + fillers + retakes |
| aggressive | Social clips — tightens everything + speeds up weak sections |

auto_cut includes a Claude review pass that reads the result transcript and checks if the start is clean. If it finds remaining issues, it trims automatically.

## Step 4: Verify

After auto_cut completes:
1. Check `get_state` to confirm clip count and duration
2. Use `get_full_transcript` to read the beginning — does it start with the real intro?
3. Take a screenshot to verify video renders

## What NOT to Do

- **Don't run auto_cut on a full 2-hour recording.** Extract the episode first.
- **Don't use energy analysis to find episodes.** Read the transcript. Energy analysis is for AFTER you know the boundaries.
- **Don't trust keyword matching for episode detection.** "Welcome to X" in casual conversation doesn't mean an episode started. Claude understands the difference.
- **Don't include rehearsals in the episode.** Multiple "Welcome to" attempts = rehearsal. Use the LAST one.
- **Don't skip the review pass.** auto_cut is mechanical. Claude catches what it misses.

## Example: Multi-Episode Podcast Recording

A 164-minute recording contains:
- 0:00-56:00 — Pre-show conversation
- 56:23 — "Welcome to Technologer" (FALSE — just a tagline in pre-show)
- 112:43-114:32 — Rehearsal of "Technology Talks" intro (3 attempts)
- 114:32-140:42 — Episode 1: "Feedback & Customer Discovery" (REAL)
- 148:59-159:31 — Episode 2: "Is AI Making People Dumber?" (REAL)

Only `analyze_transcript` (Claude reading the full transcript) correctly identified 2 real episodes. Energy analysis found nothing. Keyword matching found 12 false episodes. Local heuristics scored pre-show chat as "episode content" because it contained tech vocabulary.
