# Viral Clip Extractor: Knowledge Integration Updates

## Executive Summary

This document outlines how knowledge from hooks, pacing, storytelling, and platform categories should enhance the viral-clip-extractor skill. The current skill correctly prioritizes audio energy and transcript analysis, but lacks explicit guidance on narrative completeness, hook technique sophistication, platform-specific energy curves, and vertical format optimization.

---

## 1. Knowledge Relevance to Viral Clip Extraction

### Hooks Category (HIGH RELEVANCE)
The hooks category directly supports the clip extraction process. Key alignments:
- **First-Second Grab** and **Three-Second Mandate**: The skill mentions hook windows (first 2-5 seconds depending on platform) but needs stronger emphasis on why these windows matter and how to identify "grabbable" moments within high-energy zones.
- **Cold Open Technique**: The skill describes the mechanical implementation but lacks the strategic reasoning from hooks knowledge about why visible transitions and hook-first positioning work psychologically.
- **Memory Context and Visual/Verbal Punch**: Currently missing. Clips sometimes need context metadata about what's being referenced or what makes a moment "punchy" beyond just audio metrics.

### Pacing Category (HIGH RELEVANCE)
Pacing directly impacts how extracted clips feel and perform:
- **Silence Kills Short-Form**: The skill correctly removes silence >0.8s but doesn't explicitly address platform-specific silence thresholds (1.5s for shorts, 1.2s for talking heads).
- **Variable Pacing and Emotional Energy Curves**: The skill lacks guidance on creating internal pacing variety within a clip (fast sections, breath moments, rhythmic beats).
- **Intentional vs. Dead Air**: Current skill removes all silence; pacing knowledge suggests some silence can be strategic emphasis.

### Storytelling Category (MEDIUM-HIGH RELEVANCE)
Storytelling provides framework for "narrative completeness" scoring:
- **Three-Act Structure**: Clips need setup-conflict-payoff micro-arcs within 30-60 seconds. Current skill mentions "setup + payoff" but not the three-act framework.
- **Story Drives All Choices**: Helps determine what makes a moment "standalone" (can it be understood without the full video?).
- **Tension and Payoff**: Explains why certain high-energy zones are more viral (they build to payoff moments).

### Platform Category (HIGH RELEVANCE)
Platform knowledge reveals critical gaps in current platform-specific rules:
- **Aspect Ratio Affects Pacing**: Current skill assumes all platforms handle 30-60s the same way; vertical formats need tighter pacing.
- **Captions Are Essential for Vertical**: Current skill mentions loudness but not caption timing or design integration.
- **Muted Viewing Expectation (80%+)**: Affects hook strategy—text overlays and visual cues become as important as audio hooks.
- **Sound Design Importance Scales**: Clarifies loudness standards (-14 LUFS for social vs. -16 LUFS for podcasts).

---

## 2. Specific Additions and Changes to Recommend

### Addition A: Enhance Narrative Completeness Scoring
**Current:** "Narrative completeness (15 points): setup + payoff within 30-60 seconds, makes sense standalone"

**Limitation:** Vague on what makes a clip "standalone." Users need clearer criteria.

**Recommendation:** Replace with a three-act micro-structure framework:

---

### Addition B: Upgrade Hook Technique Section
**Current:** Step 5 describes cold-open mechanics but not when/why to use them or the psychological impact.

**Limitation:** Users may not apply the technique strategically—they implement it mechanically or skip it when it would help.

**Recommendation:** Add decision matrix and principle-based reasoning.

---

### Addition C: Add Platform-Specific Energy Curves
**Current:** Platform table specifies duration and loudness but not how energy *curves* should change across formats.

**Limitation:** A fast TikTok hook (2 seconds) performs differently than a YouTube Shorts hook (3 seconds). Pacing aggressiveness differs.

**Recommendation:** Define expected energy arc for each platform.

---

### Addition D: Integrate Vertical Format Optimization
**Current:** Platform table exists but step-by-step workflow doesn't address vertical-specific editing.

**Limitation:** Vertical content (Shorts/Reels/TikTok) needs tighter pacing and different silence thresholds than horizontal formats.

**Recommendation:** Add vertical-specific pass in Step 6 (tighten edit).

---

### Addition E: Add Caption and Visual Hook Guidance
**Current:** No mention of text overlays, captions, or on-screen hooks beyond audio.

**Limitation:** 80%+ viewers watch muted on social platforms; text overlays are critical for hook delivery.

**Recommendation:** Add caption timing and visual emphasis guidelines.

---

## 3. Detailed Text Blocks for Insertion

### TEXT BLOCK 1: Enhanced Narrative Completeness Framework
**Location:** Insert in Step 3 (Score and select), replacing the current "Narrative completeness" bullet

**Current text to replace:**
```
- Narrative completeness (15 points): setup + payoff within 30-60 seconds, makes sense standalone
```

**New text block:**

```
- Narrative completeness (15 points): Clip must follow a micro three-act structure:

  **Act 1 (Setup, first 5-15 seconds):** Establishes the situation, question, or problem.
  - Examples: "Most people don't realize..." / "Here's the mistake I made..." / Shows a contradiction
  - NOT just context dumping; the setup must create curiosity

  **Act 2 (Conflict/Content, middle section):** Delivers the meat—explanation, story progression, or surprising detail.
  - Continues momentum from Act 1
  - Includes the "why" or evidence

  **Act 3 (Payoff/Resolution, last 5-10 seconds):** Delivers the promise made in Act 1.
  - A conclusion, a lesson learned, a punchline, or a cliffhanger that feels intentional
  - Ends on a completed thought (never mid-sentence)

  **Standalone test:** Show the clip to someone unfamiliar with the source. If they understand what happened and why it matters without needing the full video, it passes. If they're confused about context or the payoff feels incomplete, downgrade the score by 5 points.
```

---

### TEXT BLOCK 2: Cold-Open Strategy Framework
**Location:** Insert in Step 5 (Create the cold-open hook), after the current description of mechanics, as a new subsection

**New text block:**

```
### When and Why to Use the Cold-Open Technique

**Use cold-open if:**
- The first 5-10 seconds are setup/context (not the compelling part)
- The most interesting claim or moment happens mid-clip
- The clip would lose a viewer's attention before reaching the payoff
- The hook sentence is shorter than 5 seconds and easily extractable

**Don't use cold-open if:**
- The clip already starts with a bold statement, question, or surprise
- The setup is essential to understanding the payoff (removing it creates confusion)
- The hook and context are too intertwined to separate naturally

**Psychological principle:** Cold-open works because it creates a cognitive loop—viewers hear the punchline, reset attention with the wipe transition, then re-engage with context, and the punchline hits a second time with reinforced impact. This doubles emotional landing.

**Hook extraction checklist:**
1. Identify the single most provocative sentence (the "punchline")—it should be a claim, surprise, or question
2. Verify it's complete as a standalone statement (not dependent on preceding context to make sense)
3. Confirm it's under 5 seconds of audio (extract only the essential words)
4. Test the wipe timing: fast (0.1-0.15s) feels snappy; slower (0.2s+) feels deliberate
5. Never hook-extract if removal of that sentence creates a logical gap in the remaining clip
```

---

### TEXT BLOCK 3: Platform-Specific Energy Curves
**Location:** Insert after the platform-specific rules table (after Step 5), as a new subsection

**New text block:**

```
## Platform-Specific Energy Curves

Each platform has an expected emotional/energy arc that affects how you edit and position hooks. Clips that fight these curves feel out-of-place.

| Platform | Expected Energy Arc | Hook Intensity | Mid-Clip Variation | Ending |
|----------|-------------------|-----------------|-------------------|---------|
| **YouTube Shorts** | Slow build → peak → sustain | Medium (establish authority first) | Slight dips okay between ideas | Bang—memorable closing line or visual |
| **TikTok** | FAST start → micro-variation → peak end | Aggressive (hook HARD in first 2s) | Constant micro-variations to prevent fatigue | Cliffhanger, question, or visual shock |
| **Instagram Reels** | Balanced opening → moderate build → satisfying close | Medium (visually engaging from frame 1) | Visual-audio synchronization drives variation | Clean, share-worthy ending or lesson |
| **Twitter/X** | Immediate grab → quick payoff → social bait | Aggressive (hook in first 2 seconds) | Fast-paced throughout (no breathing room) | Hook continuation or call-to-engage |
| **LinkedIn** | Professional tone → credibility → value statement | Low-key (authority through substance) | Steady, professional pacing | Clear takeaway or professional insight |

**How to use this:**
- **YouTube Shorts** clips should start with a credibility phrase ("Here's something most people miss...") before the hook. TikTok clips should *start* with the hook.
- **Reels** benefit from visual hooks (text overlay, striking image) paired with audio hooks. Timing the visual cut to audio emphasis matters more.
- **TikTok** needs aggressive opening AND constant micro-cuts/transitions to signal novelty (prevent algorithm drop-off).
- **LinkedIn** clips should avoid fast-cut energy and focus on clear, substantive narration.
```

---

### TEXT BLOCK 4: Vertical Format Tightening Pass
**Location:** Insert in Step 6 (Tighten the edit), after the general guidelines, as a conditional subsection

**New text block:**

```
### Vertical Format Optimization (for Shorts/Reels/TikTok)

Vertical formats require an additional tightening pass beyond horizontal content:

**Silence threshold adjustment:**
- Horizontal (YouTube): Remove silence > 0.8 seconds
- Vertical (Shorts/Reels/TikTok): Remove silence > 0.5 seconds
- *Reasoning:* Smaller screen real estate means silence reads as "dead time" faster in vertical

**Speech rate check:**
- If speaker is slower than 130 words per minute (WPM), apply 1.1-1.15x speed
- Do NOT exceed 1.15x for speech—intelligibility drops and it sounds unnatural
- Verify after speed adjustment using `measure_loudness` to ensure loudness doesn't increase unexpectedly

**Visual breathing room:**
- Even in vertical, do NOT remove all pauses (keep 0.2-0.3 seconds of intentional breath)
- Strategic pauses after punchlines allow impact to land (0.3-0.5 seconds before next idea)
- Vary pacing: fast sections followed by slightly slower reveals prevent monotonous exhaustion

**Vertical-specific edits:**
- Move text overlays 0.5 inches from edges (mobile safe zone)
- Hook text should appear within first 1-2 seconds (before cognitive decision to scroll)
- Use word-by-word caption timing if auto-generating captions—word-level sync increases comprehension by ~15%

**Platform-specific vertical tweaks:**
- **YouTube Shorts:** Can sustain slightly longer pauses (0.8s still acceptable between major ideas)
- **TikTok:** Tightest pacing—remove all non-essential pauses, constant micro-cuts signal algorithmic relevance
- **Instagram Reels:** Moderate tightness + high visual priority (images, text, graphics drive pacing as much as audio)
```

---

### TEXT BLOCK 5: Caption and Visual Hook Integration
**Location:** Insert in Step 5 (Create the cold-open hook), as a new subsection after the mechanical description

**New text block:**

```
### Pairing Audio Hooks with Visual and Caption Hooks

**Critical insight:** 80%+ of your audience watches without sound on social platforms. An audio hook alone is insufficient; you must pair it with visual or caption emphasis.

**For each clip, ask:**
1. **Does the hook work with sound off?** If no, add a text overlay or visual cue.
2. **Is there a word or phrase that could be highlighted with on-screen text?** Highlight it for 1-2 seconds (during or immediately after the hook sentence).
3. **Is there visual movement, gesture, or expression that reinforces the hook?** If yes, zoom slightly or cut to a tighter frame to emphasize it.

**Hook text overlay guidelines:**
- **Timing:** Introduce text overlay 0.2 seconds BEFORE the hook audio begins (primes visual attention)
- **Size:** Large enough to read on phone (minimum 48pt, preferably 60+pt for social)
- **Color:** High contrast to background (avoid pastels on white; use bold colors)
- **Animation:** Fade in (0.1s) or pop (0s) — no spin/bounce effects (they distract from content)
- **Duration:** Keep text on-screen for entire hook sentence + 0.5 seconds after (let it hang slightly for emphasis)
- **Placement:** Center or upper-left (mobile safe zone, where eyes naturally move)

**Visual hook examples:**
- **Zoom:** Slowly zoom into speaker's face during the hook sentence (draws attention, creates intimacy)
- **Cut:** Jump-cut to a close-up of the speaker's expression during the punchline (emphasizes emotion/conviction)
- **B-roll:** If using supporting footage, cut to a relevant visual (e.g., if hook mentions a product, show the product) during hook audio
- **Graphic:** Introduce a stat, number, or key phrase as animated text (not just overlaid text—let it build or slide in)

**Muted viewing best practices:**
- Use captions word-by-word if auto-generating (word-level sync is critical for comprehension)
- If manually captioning, time captions to appear just before the spoken word (gives visual context)
- Place critical captions in the "safe zone" (center and upper 60% of frame for mobile)
- Use color-coded captions if multiple speakers (helps with speaker identification in muted context)

**Testing:** Mute your clip and watch it. If the hook still lands (from text + visual cues alone), you've done it right. If the audience needs sound to understand, add more visual emphasis.
```

---

### TEXT BLOCK 6: Verification Expansion for Vertical Clips
**Location:** Insert in Step 7 (Verify), after the existing verification checklist, as an additional subsection

**New text block:**

```
### Vertical Format Verification Checklist

For Shorts/Reels/TikTok clips, add these vertical-specific verification steps:

**Muted playback test:**
1. Mute the clip entirely
2. Watch from start to finish
3. Verify the hook is clear from visual + text alone (captions must be readable)
4. Check that no critical information is lost without audio

**Pacing verification for vertical:**
1. Count silent pauses longer than 0.5 seconds (should be rare and intentional)
2. Identify any moment where the screen feels "static" for more than 2-3 seconds (add cut or animation if needed)
3. Confirm hook text appears within first 2 seconds (for TikTok) or 3 seconds (for Shorts/Reels)

**Text overlay technical check:**
1. All text is readable on 5-inch phone screen (zoom into text to verify)
2. Text doesn't overlap with important facial features or key visuals
3. Text transitions are smooth (no jittery animations or delays)
4. Caption timing aligns with speech (if auto-generated, manually sync critical words)

**If any verification fails:**
- Muted test fails → Add text overlay or visual emphasis to hook
- Pacing feels sluggish → Remove silence, add micro-cuts, increase speech rate by 1.05x
- Text overlay blocks important content → Reposition or resize overlay, or shorten the text
- Caption sync is off → Manually adjust word timing (most platforms allow word-level caption editing)
```

---

## 4. Summary of Integration Points

| Knowledge Category | Current Skill Gap | Recommended Addition | Impact |
|-------------------|------------------|----------------------|---------|
| **Hooks** | Mechanical description, lacks strategic reasoning | Add cold-open decision matrix + psychological principle (TEXT BLOCK 2) | Users apply technique more strategically, not just mechanically |
| **Pacing** | Treats all silence equally, no platform variance | Add silence threshold table + vertical tightening pass (TEXT BLOCKS 3, 4) | Clips feel snappier on TikTok, more authoritative on LinkedIn |
| **Storytelling** | "Narrative completeness" is too vague | Add three-act micro-structure framework + standalone test (TEXT BLOCK 1) | Clips have clearer emotional arcs, higher replay/share value |
| **Platform** | Table exists but lacks energy curve guidance | Add platform-specific energy arc table + muted-first editing (TEXT BLOCKS 3, 5) | Clips feel native to each platform; higher algorithmic resonance |
| **Platform (Captions)** | Completely absent from workflow | Add caption timing + visual hook integration (TEXT BLOCK 5) | Hooks land for 80% of viewers who watch muted |

---

## 5. Priority Implementation Order

1. **High Priority (implement first):**
   - TEXT BLOCK 2 (Cold-open strategy) — changes approach to hook application
   - TEXT BLOCK 5 (Visual hook integration) — addresses silent viewers (80% of audience)

2. **High Priority (implement next):**
   - TEXT BLOCK 1 (Narrative completeness framework) — clarifies scoring
   - TEXT BLOCK 3 (Platform energy curves) — improves platform-specific quality

3. **Medium Priority (implement after core updates):**
   - TEXT BLOCK 4 (Vertical format pass) — refinement for specific platforms
   - TEXT BLOCK 6 (Vertical verification) — verification-specific update

---

## 6. Validation Notes

These additions maintain the skill's core principle: **audio energy first, transcript second**. They enhance decision-making around what to do *with* extracted high-energy moments once identified. The recommendations are grounded in platform behavior, viewer psychology (attention curves, silent viewing), and narrative structure principles from the knowledge base.
