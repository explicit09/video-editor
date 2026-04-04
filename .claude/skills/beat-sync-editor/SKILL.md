---
name: beat-sync-editor
description: Edit video to music by detecting beats and syncing cuts to the rhythm. Matches visual energy to musical energy, handles speed ramps on drops. Verifies beat alignment. Use when the user asks about beat sync, music editing, rhythm, montage, beat drop, music video, cut to beat, tempo, BPM, dance, or energy matching.
allowed-tools: detect_beats analyze_audio_energy split_clip trim_clip move_clip delete_clips set_clip_speed set_clip_effect set_clip_transition set_marker measure_loudness rename_clip verify_playback get_state
---

# Beat Sync Editor

You create visually rhythmic edits where every cut aligns precisely with the music.

## Step 1: Analyze the music

1. `detect_beats` — returns BPM, beat timestamps, strong beats
2. `analyze_audio_energy` with `segments: 10` — energy profile for song structure
3. `measure_loudness` — baseline levels
4. `set_marker` at every strong beat for visual reference

**Classify song structure by energy:**
- Intro (low energy): wide/establishing shots, cut every 4-8 beats
- Verse (medium): mix of angles, cut every 2-4 beats
- Pre-chorus (rising): accelerate cuts, every 2 beats → every beat
- Chorus (high): dynamic footage, cut every 4 beats with bold transitions
- Bridge (dip): emotional/slow footage, every 4-8 beats
- Drop: most dramatic cut on the exact beat

## Step 2: Calculate clip durations

```
clip_duration = (beats_per_cut × 60) / BPM

At 120 BPM:
- Every 2 beats = 1.0s per clip
- Every 4 beats = 2.0s per clip
- Every 8 beats = 4.0s per clip
```

## Step 3: Align cuts to beats

1. Plan cut points based on section structure
2. `split_clip` at each beat-aligned timestamp
3. Cuts must land within ±50ms of the beat (±1.5 frames at 30fps)
4. `trim_clip` to snap precisely

## Step 4: Transitions matched to music

**Available transitions (only these exist):**
- `none` — hard cut: use on strong beats (the beat IS the punctuation)
- `wipeLeft` / `wipeRight` at 0.1-0.15s: use on dramatic accents
- `fadeToBlack` at 1.0s: use on breakdowns (go dark)
- `fadeFromBlack` at 0.1s: use on drops (flash-to-content)
- `crossDissolve` at 0.5-1.0s: use on sustained notes

**Do NOT use transitions that don't exist** (no spin, zoom, flash, etc.)

## Step 5: Speed effects

- Breakdown: `set_clip_speed` 0.5x (slow motion)
- Drop ramp: 0.5x → 1.0x → 2.0x across 4 beats
- Freeze frame: very low speed for 1 beat on a dramatic accent

Speed propagates to linked audio automatically.

## Step 6: Energy-matched color

- Chorus: `set_clip_effect` colorCorrection: saturation 1.2, contrast 1.15
- Bridge: saturation 0.8 (desaturated for emotion)

## Step 7: Mandatory verification

1. `verify_playback` mode "quick":
   - Audio present throughout
   - Video frames valid
   - Total duration matches music

2. `get_state`:
   - Markers at every strong beat
   - Clips named by section
   - Speed/effects visible in properties
   - No gaps

## What NOT to do

- Never cut between beats — off-beat cuts feel amateur
- Never use the same clip twice until all footage is used
- Never have more than 3 flash effects per second (epilepsy concern)
- Never use crossDissolve on a strong beat — hard cuts are better
- Never mismatch energy — no slow footage on drops
- Never skip verification
- Never use transitions that don't exist in the editor
