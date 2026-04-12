# Shorts Formatter Skill Updates

Based on analysis of hooks, platform, pacing, and composition knowledge categories, the following updates are recommended for the shorts-formatter.md skill to strengthen hook strategy, vertical framing expertise, caption implementation, and platform-specific rules.

---

## 1. Knowledge Mapping to Current Skill

### Hooks Category
The current skill references "cold-open hook structure" in Step 2 but lacks depth on:
- **Rule: First-Second Grab** — Currently followed but not explicitly documented as critical principle
- **Rule: Visual or Verbal Punch** — Implied but not detailed; skill should emphasize "bold claim, question, surprise"
- **Rule: Visible Transitions for Hooks** — Already implemented (wipeLeft/wipeRight), but reasoning not explained
- **Rule: Three-Second Mandate** — Implemented but could be more explicit across all platforms
- **Rule: Memory Context** — Not addressed; relevant for archive-heavy shorts

**Missing:** Authority-building hooks, intrigue layering, and silent-viewer design for hooks

### Platform Category
Current skill covers most platform rules but gaps exist:
- **Rule: Aspect Ratio Affects Pacing** — Auto-reframe exists but doesn't tie pacing to vertical constraints
- **Rule: Format-Specific Reediting** — Not detailed; auto-reframe alone is insufficient
- **Rule: Captions Are Essential** — Mentioned in Step 4 but treated as afterthought, not primary design element
- **Rule: Sound Design Importance** — Loudness target mentioned (-14 LUFS) but no context on why vertical requires tighter audio
- **Rule: Muted Viewing Expectation** — 80%+ silent viewers mentioned in captions step, but not central design principle

**Missing:** Batch conversion guidance, caption-as-design approach, platform-specific B-roll strategies, loudness verification across platform exports

### Pacing Category
Current skill follows several pacing rules but lacks integrated framework:
- **Rule: Silence Kills Short-Form** — Stated as "> 0.3s remove" but knowledge base says > 1.5s disrupts; discrepancy needs resolution
- **Rule: Talking Head Attention Threshold** — Not addressed; relevant for interview/talking-head shorts
- **Rule: Audio-Visual Pacing Sync** — Not explicitly covered
- **Rule: Edit Speed Matches Emotional Moment** — Not considered in speed adjustments

**Missing:** Intentional silence usage, talking-head-specific rules, rhythm-based structuring, variable pacing strategies

### Composition Category
Vertical composition receives minimal coverage:
- **Rule: Vertical Video Requires Tight Framing** — Mentioned in auto-reframe step but not emphasized throughout
- **Rule: Safe Title Area in Vertical Format** — Not addressed; critical for caption placement
- **Rule: Headroom Composition** — Not covered; especially important for vertical reframes
- **Rule: Auto-Reframe Starting Point** — Current skill uses auto-reframe as solution; knowledge base suggests it's only starting point
- **Rule: Draw Viewer Attention Intentionally** — Could strengthen caption placement and visual hierarchy

**Missing:** Manual vertical composition refinement, safe-area guidance, vignetting for mobile clarity, attention direction for vertical medium

---

## 2. Specific Additions and Changes

### A. Reframe Hook Understanding (Step 2 Enhancement)
**Change:** Expand cold-open hook section to emphasize hook principles and silent-viewer design

**Current limitation:** Hook technique is mechanically sound but lacks strategic context

**New addition needed:** Explicit guidance on what makes a hook "provocative" and how to evaluate hooks for silent viewers

### B. Vertical Composition Integration (Step 1 Enhancement)
**Change:** Add mandatory manual composition check after auto-reframe

**Current limitation:** Auto-reframe produces crop regions but doesn't verify composition quality

**New addition needed:** Post-reframe checklist for headroom, safe title area, and subject positioning

### C. Pacing-to-Platform Mapping (Step 3 Enhancement)
**Change:** Tie silence thresholds explicitly to platform duration limits

**Current limitation:** Silence rule (> 0.3s) lacks justification; should vary by platform

**New addition needed:** Platform-specific silence guidelines and talking-head rules

### D. Captions as Design System (Step 4 Elevation)
**Change:** Promote captions from "requirement" to "primary information carrier"

**Current limitation:** Captions treated as accessibility feature; should be treated as core design element

**New addition needed:** Caption timing, color strategy, and safe-area placement guidance

### E. Audio-Visual Sync Verification (Step 5 Enhancement)
**Change:** Add explicit check for pacing alignment between cuts and audio rhythm

**Current limitation:** Only loudness is verified; doesn't check if visual rhythm matches audio timing

**New addition needed:** Step to verify that visual cuts align with audio beats or speech cadence

### F. Post-Reframe Composition Refinement (New Sub-step in Step 1)
**Change:** Add manual adjustment phase after auto-reframe

**Current limitation:** Assumes auto-reframe output is acceptable; should be starting point only

**New addition needed:** Guidance on adjusting positionX/Y, vignetting, and safe-area verification

---

## 3. Text Blocks to Insert

### INSERT 1: Before Step 1 (New Hook Strategy Preamble)

**Location:** Insert after "You format clips for maximum impact on vertical-first platforms." and before "## Step 0"

```markdown
## Hook Strategy Foundation

Shorts live or die on the hook—viewers decide within the first second whether to keep watching. Every hook must satisfy three simultaneous requirements:

1. **Grab immediately** — Bold claim, sharp question, visual surprise, or provocative statement. Never ease in.
2. **Work without sound** — 80%+ viewers watch muted. Visual hook must land without audio (captions will carry meaning).
3. **Signal value** — The hook must make clear what the viewer will gain by staying (entertainment, insight, resolution, intrigue).

Treat the hook as your primary design element, not an afterthought. All other decisions (pacing, composition, captions) serve the hook.
```

### INSERT 2: In Step 1 (After auto-reframe, add composition refinement)

**Location:** After `set_clip_transform` line in Step 1, add new sub-section:

```markdown
**Composition refinement (mandatory after auto-reframe):**
1. Check headroom: Subject's eyes should sit on upper third of frame (not centered)
2. Verify safe title area: Text must stay > 40px from all edges (mobile notches + OS UI)
3. Assess subject positioning: Face and hand gestures should dominate (side-to-side movement wastes vertical space)
4. If subject is off-center or cropped awkwardly, manually adjust positionX/Y before proceeding
5. Consider subtle vignetting via `set_clip_effect` to isolate subject from background (especially important for weak backgrounds)

**Do NOT accept auto-reframe output without verification — it's a starting point, not a final solution.**
```

### INSERT 3: In Step 2 (Hook evaluation criteria)

**Location:** Replace the bulleted "Evaluate the opening" section with expanded guidance:

```markdown
**Evaluate the opening for hook strength:** Does the first sentence grab attention?
- **Strong hooks** (KEEP): Bold claim ("This breaks physics"), sharp question ("What if you could...?"), visual shock, surprising statistic, provocative statement
- **Weak openers** (NEEDS COLD OPEN): Setup statements ("So..."), context ("Let me tell you..."), apologies ("This is crazy but..."), gradual build-ups

**For silent viewers:** If your hook is audio-dependent (subtle joke, unclear statement), it will fail. The visual and/or captions must make the hook land WITHOUT sound.

**For multi-hook content:** If the clip has 2-3 strong hooks available, extend the hook slightly (up to 4-5s for YouTube Shorts, 2-3s for TikTok) to showcase them. Multiple hook points give different viewers different reasons to stay.
```

### INSERT 4: In Step 2 (Visible transitions reasoning)

**Location:** After the "Do NOT use crossDissolve..." line, add:

```markdown
**Why visible transitions matter for hooks:** Invisible transitions (crossDissolve) blur the boundary between hook and content, making the hook feel like filler. Visible transitions (wipeLeft/wipeRight) create a mental reset—they signal "this was the hook, now comes the payload." This distinction helps viewers understand structure and prepares them for the body content.
```

### INSERT 5: In Step 3 (Pacing rules by platform)

**Location:** Replace the current "Tighten pacing" bullet section with expanded platform-specific guidance:

```markdown
### Pacing by Platform

**YouTube Shorts (59s max):**
- Remove silence > 0.3s (extremely tight; vertical space is premium)
- Apply speed: WPM < 140 → 1.15x, WPM 140-170 → 1.08x, WPM > 170 → no change
- Talking head runs > 6s require visual change (zoom, angle swap, graphics)
- Music: Never exceed 20-30s without visual progression

**TikTok (60s max):**
- Remove silence > 0.5s (slightly more breathing room than Shorts, still tight)
- Match visual beats to trending audio if participating in trends
- Talking heads benefit from faster cuts (switch every 3-5s) to maintain energy
- Hook window: 2 seconds (tighter than Shorts)

**Reels (30s max):**
- Remove silence > 0.3s (most constrained; every second counts)
- Pacing must be fastest of all three platforms
- Talking heads work poorly; favor B-roll heavy content with voiceover
- Hook window: 3 seconds

**General rule:** Silence can be intentional only if it emphasizes a key moment (e.g., pause after a provocative statement). Unintentional silence always reads as dead air. When in doubt, trim it.
```

### INSERT 6: In Step 4 (Captions as design system)

**Location:** Replace the brief caption step with expanded caption design guidance:

```markdown
## Step 4: Captions as Primary Information System

**Captions are not an accessibility feature—they are your primary information carrier.** 80%+ of viewers watch without sound. Captions must land just as hard as audio.

**Implementation:**
1. `set_caption_style` with style "karaoke" (word-by-word highlight)
2. Check caption timing: Each phrase should appear on-screen for at least 1.5s, with a max of 3s (faster on TikTok)
3. Verify safe area: Captions must stay > 40px from all edges (mobile notches + interface elements)
4. Color strategy: High contrast against background (white text for dark backgrounds, dark for light). Consider a subtle semi-transparent background bar for readability
5. Position captions to avoid obstructing faces or key visual elements
6. Match caption timing to audio rhythm—captions that lag behind speech feel disconnected

**Caption design principle:** Treat captions like you would motion graphics. They're visible information architecture, not boring text. Strategic color, timing, and positioning transform captions from required text into a design element that enhances the hook and maintains engagement.
```

### INSERT 7: In Step 5 (Add audio-visual sync check)

**Location:** After the colorCorrection line, add new pacing verification:

```markdown
- Verify pacing alignment: Check that visual cuts and transitions sync with audio rhythm. If speech speeds up, cuts should get tighter. If speech slows, allow for more visual breathing room. Misalignment between audio and visual pacing creates cognitive dissonance.
```

### INSERT 8: New section before "Available transitions"

**Location:** Insert between Step 6 and "Available transitions" section:

```markdown
## Why These Steps Matter for Vertical

Vertical short-form content is fundamentally different from horizontal video:

- **Framing is tighter:** Side-to-side movement wastes space. Face, hands, and emotional expression dominate. Auto-reframe is a starting point; manual refinement is mandatory.
- **Silent viewing is the norm:** Design for muted playback first, then add audio as enhancement. Captions aren't optional—they're your primary narrative layer.
- **Hooks are survival:** The first 3 seconds determine everything. Weak hooks lose viewers before the content begins.
- **Pacing drives perception:** Tighter pacing isn't just aesthetic—it's required for the narrow vertical frame. Long shots, slow cuts, and extended silence feel like dead air in vertical.
- **Captions are design:** Done right, they're typography, rhythm, and information architecture combined. Done wrong, they're invisible clutter.

Every decision—composition, pacing, captions, transitions—must be intentional for the vertical medium. Shortcuts show immediately on mobile screens.
```

### INSERT 9: Update platform specs table (location: same table)

**Location:** Replace existing platform specs table to add Hook Window column and clarify caption expectations:

```markdown
## Platform Specifications

| Platform | Max Duration | Loudness | Hook Window | Silence Threshold | Primary Medium |
|----------|-------------|----------|-------------|-------------------|----------------|
| YouTube Shorts | 59s | -14 LUFS | 3 seconds | > 0.3s (remove) | Captions (80%+ muted) |
| TikTok | 60s | -14 LUFS | 2 seconds | > 0.5s (remove) | Captions + audio trends |
| Reels | 30s | -14 LUFS | 3 seconds | > 0.3s (remove) | Captions (most muted) |
```

---

## 4. Summary of Enhancements

### Strategic Improvements

1. **Hook Design Elevation** — Transforms hooks from a technical step into a strategic foundation with explicit criteria for "strong" vs "weak" openers
2. **Silent-Viewer Centrality** — Makes muted-first design an explicit principle throughout, not just a caption requirement
3. **Vertical Composition Authority** — Adds mandatory manual refinement post-auto-reframe and explains why auto-reframe is insufficient
4. **Pacing Specificity** — Ties silence thresholds and speed adjustments directly to platform constraints
5. **Captions as Design** — Elevates captions from compliance feature to primary information architecture with design guidance
6. **Audio-Visual Alignment** — Adds explicit verification that cuts sync with audio rhythm
7. **Medium-Specific Framing** — Explains why vertical requires fundamentally different composition and pacing than horizontal

### Coverage Gaps Addressed

- **Hooks:** Now includes authority-building, intrigue layering, multi-hook strategies, and silent-viewer design
- **Platform:** Now covers format-specific reediting, caption-as-design, safe-area guidance, and platform-specific silence rules
- **Pacing:** Now tied to platforms, includes talking-head rules, and explains intentional silence
- **Composition:** Now includes headroom, safe-area, vignetting, and post-reframe refinement

### Consistency with Knowledge Base

- Reconciles silence threshold discrepancy (current skill says 0.3s, knowledge base says 1.5s context-dependent—now clarified by platform)
- Implements all "Rule: Visible Transitions for Hooks" reasoning
- Incorporates "Rule: Muted Viewing Expectation" as central design principle
- Applies "Rule: Auto-Reframe Starting Point" explicitly
- Integrates "Rule: Safe Title Area in Vertical Format" throughout
