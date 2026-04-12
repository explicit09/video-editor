# Beat Sync Editor Knowledge Integration

## Executive Summary

The beat-sync-editor skill has strong foundational beat detection and energy mapping logic, but lacks integration of critical editing principles from the knowledge base. This document identifies relevant knowledge from cuts, pacing, and transitions categories and proposes specific additions to enhance cut timing, energy matching, transition choices, and pacing rhythm.

---

## 1. Relevant Knowledge Mapping

### From CUTS Category

**Highly Relevant:**
- **Cut on Action** — Critical for beat-sync editing. Cuts should occur during visible movement to mask the transition point and make timing feel seamless. This directly improves how beat-aligned cuts land visually.
- **Cut on Energy Shifts** — Music has natural energy peaks (drops, buildups, breakdowns). Aligning cuts to these energy shifts makes beat synchronization feel motivated and organic, not arbitrary.
- **Trim Dead Space at Clip Beginnings** — Beat-sync editing creates tight timings; removing silence and dead space from clip starts maintains the tight rhythm the beat structure demands.
- **Every Shot Must Serve Purpose** — In montage-based beat sync work, every clip placement should reinforce the music's energy arc, not just fill beats.
- **Maintain Contextual Pacing** — Montages and action sequences benefit from tight, dynamic cutting. Beat-sync work is inherently montage-style, so this principle directly applies.

**Secondary Relevance:**
- Cut on Energy Shifts supports choosing which shots work best at which beat markers.

### From PACING Category

**Highly Relevant:**
- **Edit Speed Matches Emotional Moment** — Beat sync editing uses cut frequency to match emotional intensity. Fast cuts (every 1-2 beats) for high energy; slower cuts (every 4-8 beats) for breakdowns. The SKILL.md describes this but doesn't frame it as emotional pacing.
- **Variable Pacing Creates Rhythm** — The song structure (intro, verse, chorus, drop) naturally demands variable pacing. This is already in SKILL.md but could emphasize WHY it matters beyond just synchronization.
- **Emotional Energy Curves** — Build tension through the edit by progressively tightening cuts toward drops and expanding during breakdowns. This creates a satisfying arc aligned to the music.
- **Audio-Visual Pacing Sync** — Critical principle: visual cut frequency should match audio rhythm. The skill does this through beat detection, but the principle deserves emphasis.

**Secondary Relevance:**
- Silence Must Be Intentional — Even in beat-sync work, intentional pauses (fadeToBlack on breakdowns) should be purposeful.

### From TRANSITIONS Category

**Highly Relevant:**
- **Motivated Transitions** — The SKILL.md lists available transitions but doesn't explain WHEN to use them beyond brief music match hints. Knowledge base emphasizes transitions must serve a purpose, not just look cool.
- **Cuts as Default** — The skill correctly uses hard cuts on strong beats. This principle reinforces that cuts are the right choice for beat synchronization.
- **Music Stings Signal Change** — Transitions paired with music (fadeFromBlack on drops, fadeToBlack on breakdowns) work because they prepare the audience for energy shifts. This is hinted at but not explicit.
- **Visible Transitions for Hooks** — If editing to a song with a hook structure (pre-chorus → chorus), visible transitions (wipeLeft/wipeRight) can signal the shift from setup to payoff.

**Secondary Relevance:**
- Dissolves Signal Transitions — Brief dissolves (0.5-1s) can smooth topic/mood shifts during extended verses.
- No Visual Novelty Without Narrative — Warns against using flashy effects just for visual interest; beat-sync editors can over-rely on effects thinking they "match" music.

---

## 2. Specific Additions and Changes

### Section 2A: Add "Cut Selection Principles" after Step 1

**Purpose:** Integrate CUTS knowledge to make beat-aligned cuts feel motivated by content, not just arbitrary beat timing.

**Location:** After "Classify song structure by energy" in Step 1

**Text to insert:**

---

### Cut Selection Principles (NEW)

When selecting which clips to place at each beat marker, apply these rules:

**Cut on Action (Primary):**
- Prioritize clips where movement occurs at or near the beat marker. Movement naturally masks the cut and makes timing feel seamless rather than imposed. A punch, spin, gesture, or camera movement at the beat creates invisible editing.
- Example: Place a dancing cut on the beat if the dancer's body peaks at that moment. Avoid placing a static pose on the beat—it will feel rigid.

**Cut on Energy Shifts (Secondary):**
- Music contains natural energy peaks (buildups to drops, breakdown moments). Align cuts to these peaks when possible. A drop landing on a tight action cut feels earned; a drop on a static shot feels missed.
- Use `analyze_audio_energy` not just for structure (intro/verse/chorus), but to identify micro-peaks within sections for cut placement refinement.

**Purpose in Sequence:**
- Every clip at every beat marker should serve the narrative or visual progression. Avoid placeholder footage just because the beat timing works. If a clip doesn't add energy or context, replace it.

---

### Section 2B: Revise "Step 2: Calculate clip durations" with pacing context

**Purpose:** Frame clip duration decisions as pacing choices tied to emotional intensity, not just mathematical calculation.

**Current text (lines 26-35):**
```
## Step 2: Calculate clip durations

clip_duration = (beats_per_cut × 60) / BPM

At 120 BPM:
- Every 2 beats = 1.0s per clip
- Every 4 beats = 2.0s per clip
- Every 8 beats = 4.0s per clip
```

**Replace with:**

---

## Step 2: Calculate clip durations and match to emotional intensity

**Duration Formula:**
```
clip_duration = (beats_per_cut × 60) / BPM

At 120 BPM:
- Every 2 beats = 1.0s per clip (very high energy)
- Every 4 beats = 2.0s per clip (high energy)
- Every 8 beats = 4.0s per clip (medium energy)
```

**Pacing Strategy — Match to Emotional Curve:**

Variable pacing creates rhythm and sustains engagement. Plan your edit to follow the song's emotional arc:

- **Building sections (pre-chorus, buildups):** Accelerate cuts progressively. Start at 4-beat intervals, move to 2-beat, then 1-beat as tension rises. This visual tightening mirrors musical tension.
- **Peak sections (chorus, drop):** Hold tight pacing (1-2 beat cuts) to maintain maximum energy and impact.
- **Release sections (bridge, breakdown):** Expand to 4-8 beat cuts to allow visual breathing and emotional reset.
- **Transitions between sections:** Use pacing shifts as mental cues. A sudden shift from 8-beat slow cuts to 1-beat fast cuts signals the drop arrival to the viewer before the audio even lands.

Do not maintain the same cut frequency throughout—monotonous pacing becomes exhausting and fails to emphasize the song's structure.

---

### Section 2C: Enhance "Step 4: Transitions matched to music" with decision framework

**Purpose:** Replace vague "use on" guidance with principle-based decision-making tied to transition knowledge.

**Current text (lines 44-52):**
```
## Step 4: Transitions matched to music

**Available transitions (only these exist):**
- `none` — hard cut: use on strong beats (the beat IS the punctuation)
- `wipeLeft` / `wipeRight` at 0.1-0.15s: use on dramatic accents
- `fadeToBlack` at 1.0s: use on breakdowns (go dark)
- `fadeFromBlack` at 0.1s: use on drops (flash-to-content)
- `crossDissolve` at 0.5-1.0s: use on sustained notes

**Do NOT use transitions that don't exist** (no spin, zoom, flash, etc.)
```

**Replace with:**

---

## Step 4: Transitions matched to music and motivated by energy

**Transition Decision Framework:**

Every transition choice must be motivated—it should serve a musical or narrative purpose, not exist for visual novelty alone.

**Available transitions and when to use them:**

| Transition | Duration | Purpose | Musical Moment |
|---|---|---|---|
| `none` (hard cut) | instant | Default choice; cuts are invisible and feel natural. Uses the beat itself as punctuation. | Strong beats, action moments, high-energy continuous sections |
| `wipeLeft` / `wipeRight` | 0.1-0.15s | Visible transition that signals intentionality; draws attention to a moment. Reserve for earned, important beats. | Dramatic accents, pre-chorus → chorus transitions, hook signaling |
| `fadeToBlack` | 1.0s | Creates a pause and reset; tells the audience "something is about to change." Provides visual breathing room. | Breakdowns, mood shifts, intentional pause moments within the song |
| `fadeFromBlack` | 0.1s | Announces the return of energy with visual impact; works with drops and dynamic re-entries. | Drops after breakdowns, sudden energy increases, surprise impact moments |
| `crossDissolve` | 0.5-1.0s | Signals time passage or topic shift; creates a bridge between contrasting sections. Keep brief to avoid breaking pacing. | Verse → verse transitions, sustained sustained notes, emotional moment shifts |

**Transition Rules:**

1. **Cuts are default.** Use hard cuts on strong beats and action moments. They feel natural and don't slow pacing.
2. **Transitions must be motivated.** If a transition doesn't serve the music's energy shift, it's decorative. Remove it.
3. **No arbitrary surprises.** A wipe on a random beat will feel jarring. Reserve visible transitions for moments the audience anticipates (a known drop, a obvious structural shift).
4. **Never use transitions that don't exist** (no spin, zoom, flash, etc.)

**Anti-Pattern:** Do not use `crossDissolve` on a strong beat or drop moment—hard cuts land better on peaks. Save dissolves for sustained notes or moment shifts where pacing can expand.

---

### Section 2D: Add new "Step 4.5: Verify energy motivation" before verification

**Purpose:** Insert a checkpoint to ensure transitions and cuts are motivated, catching cases where beat-sync logic overrides editorial sense.

**Location:** New section between Step 4 and Step 5

**Text to insert:**

---

## Step 4.5: Verify energy motivation (NEW)

Before applying effects and speed ramps, review your transition and cut decisions:

1. **For each hard cut on a strong beat:** Does the clip have movement or action at that beat? If static, consider moving to an action-based moment nearby (within ±1 beat) or replacing the clip entirely. Static shots on strong beats feel rigid.

2. **For each visible transition (wipe, fade, dissolve):** Does it correspond to a clear energy shift in the music? If not, change it to a hard cut. Motivated transitions feel earned; unmotivated ones distract.

3. **For pacing consistency within sections:** Are cut frequencies matching the song's emotional moment? Review your cut intervals against the energy curve. A slow section should not have 1-beat cuts; a drop should not have 8-beat cuts.

4. **Orphaned clips:** Does every clip serve the visual or emotional narrative? Placeholder footage inserted just to fill beat markers will feel out of place. Replace with more appropriate content if available.

This review prevents the trap of "it fits the beat" while missing "it fits the story."

---

### Section 2E: Enhance "Step 7: Mandatory verification" with pacing and transition checks

**Purpose:** Add verification steps to ensure cuts and transitions work not just technically but narratively/emotionally.

**Current text (lines 68-79):**
```
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
```

**Revise Step 7 to add:**

---

## Step 7: Mandatory verification

1. **Technical verification** — `verify_playback` mode "quick":
   - Audio present throughout
   - Video frames valid
   - Total duration matches music

2. **Structural verification** — `get_state`:
   - Markers at every strong beat
   - Clips named by section
   - Speed/effects visible in properties
   - No gaps

3. **Editorial verification** (NEW) — Watch playback and ask:
   - Does every cut land on action or movement (not static moments)?
   - Does every visible transition (wipe, fade) correspond to a clear energy shift?
   - Do pacing speeds match emotional intensity (tight cuts on high energy, slow cuts on low)?
   - Do all clips serve the narrative or visual arc, or are any placeholder shots?

4. **Final playback** — Watch the entire edit at intended viewing size/platform. Does the rhythm feel intentional and motivated, or does it feel like beats were hit arbitrarily?

---

---

## 3. Summary of Changes

| Area | Change | Rationale |
|---|---|---|
| **Cut Selection** | Add "Cut on Action" and "Cut on Energy Shifts" principles | Ensures beat-aligned cuts feel motivated by content, not arbitrary timing |
| **Clip Duration** | Reframe as pacing strategy tied to emotional intensity | Connects mathematical beat timing to editing philosophy; builds awareness of emotional arcs |
| **Transitions** | Expand from terse hints to decision framework with rules | Clarifies WHEN and WHY to use each transition; prevents overuse of decorative effects |
| **Energy Motivation** | Add Step 4.5 checkpoint | Catches cases where beat-sync logic overrides editorial judgment |
| **Verification** | Add editorial checks beyond technical verification | Ensures final edit is narratively sound, not just beat-synchronized |

---

## 4. Integration Notes

These additions do not change the skill's core workflow or available tools. They enhance the decision-making framework to incorporate editorial principles from the knowledge base. The beat detection, timing calculations, and effect applications remain unchanged; the enhancement focuses on HOW and WHY those tools are deployed.

The skill should continue to prioritize beat synchronization, but with explicit awareness of:
- Action-based cutting (not just beat-based)
- Emotional pacing curves (not uniform cut frequencies)
- Motivated transition choices (not decorative effects)
- Purposeful shot selection (not placeholder coverage)

These principles align beat-sync editing with professional editorial standards while maintaining the skill's unique focus on music-driven rhythm.
