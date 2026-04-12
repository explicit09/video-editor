# Auto-Cutter Skill Updates
## Knowledge Integration & Enhancement Recommendations

**Date:** April 8, 2026
**Source Documents:** cuts.md, pacing.md, audio.md
**Skill Focus:** Mechanical cleanup, silence handling, filler removal, pacing awareness

---

## 1. RELEVANT KNOWLEDGE FROM CATEGORIES

### From cuts.md (Episode Extraction & Mechanical Decisions)

**Directly Applicable:**
- **Trim Dead Space at Clip Beginnings** — The review pass already checks if the start is clean; this knowledge validates why the review pass exists and should be emphasized
- **Cut on Energy Shifts** — Relevant to detecting natural pause points where silence exists; helps distinguish intentional pauses from dead air
- **Every Shot Must Serve Purpose** — Applies to filler word and retake removal; removes material that doesn't serve the narrative
- **Cut Approximately 20% of Recorded Time** — Establishes the baseline expectation for podcast content reduction; helps set auto_cut intensity targets

**Supporting Context:**
- The skill performs mechanical cutting, which means it removes content that doesn't serve narrative purpose (filler, false starts, excessive silence)

### From pacing.md (Silence & Rhythm Management)

**Critical for auto_cut Preset Tuning:**
- **Silence Kills Short-Form Pacing** — 1.5s max for short-form (explains why aggressive preset is appropriate for social clips)
- **Talking Head Attention Threshold** — 1.2s max for talking-head content (suggests threshold for standard preset on single-speaker content)
- **Podcast Breathing Room** — 3-5 second pauses signal topic transitions; tells auto_cut to preserve intentional pauses, not remove all silence
- **Silence Must Be Intentional** — Core principle: auto_cut should remove dead air but preserve contextual pauses
- **Never Eliminate All Space** — Confirms that gentle, standard, and aggressive presets should all preserve some breathing room
- **Variable Pacing Creates Rhythm** — Explains why overly aggressive silence removal creates robotic feel

**Silence Duration Guidance:**
- Current standard preset removes >0.8s silence
- Pacing knowledge suggests refined thresholds:
  - Gentle: preserve all silence >0.5s (conversational breathing room)
  - Standard: 0.5-0.8s borderline, remove >0.8s (podcast rhythm)
  - Aggressive: remove >0.4s silence (social clip momentum)

### From audio.md (Filler & Quality Rules)

**Filler Word Strategy:**
- **Remove Filler Words Strategically** — Always remove um, uh, er, ah, hmm (current auto_cut handles these)
- **Conditionally remove "like", "you know", "basically"** — Based on context and speaker style (auto_cut currently doesn't distinguish; improvement opportunity)
- **Control Silence Between Speakers** — Max 0.5s between speakers, 0.3s within speaker; dramatic pauses up to 0.8s (refines silence handling)
- **Preserve Natural Pauses** — Never remove all pauses; dialogue without pauses sounds robotic (validates the review pass approach)

**Speech Clarity & Pacing:**
- **Adjust Speech Speed Based on Delivery Rate** — WPM thresholds for acceleration (complements silence removal: slower speakers need more breathing room)
- **Normalize Audio Levels First** — Not directly in auto_cut scope, but context for why mechanical cleanup happens before audio processing

**Retake Detection Context:**
- Related to "Remove Non-Essential Filler Sounds" — breaths, clicks, background noise (current retake detection is good; could expand to breath detection)

---

## 2. SPECIFIC ADDITIONS & CHANGES TO RECOMMEND

### A. Enhance the Presets with Pacing-Aware Silence Thresholds

**Current Problem:** Standard preset uses a single 0.8s threshold; pacing rules show different content types benefit from different thresholds.

**Recommendation:** Add pacing context and update silence thresholds in the presets table.

### B. Expand Filler Word Strategy

**Current Status:** auto_cut removes um, uh, er, ah, hmm (hard rules)

**Recommendation:** Add a note about conditional filler word removal (like, you know, basically) with context about speaker style, which the review pass should evaluate.

### C. Add Silence Preservation Principle

**Current Status:** Rules focus on what to remove; no explicit guidance on preserving intentional pauses.

**Recommendation:** Add a section explaining why intentional silence matters and how to recognize it in the review pass.

### D. Detail the Review Pass: What Claude Looks For

**Current Status:** Mentioned briefly; not detailed.

**Recommendation:** Explain the review pass criteria: remaining dead air, jarring silence removals, lost natural breathing rhythm, false starts missed, overaggressive filler removal that sounds robotic.

### E. Add Context on Content Type Differences

**Current Status:** Presets exist but limited guidance on when to use each.

**Recommendation:** Add guidance on content type + preset matching (interviews lean toward gentle, social clips toward aggressive).

---

## 3. TEXT BLOCKS TO INSERT

---

### TEXT BLOCK 1: Enhanced Presets Table
**Location:** Replace the current presets table (lines 50-54)

**Context:** The pacing rules show that different content types need different silence handling. This expands the presets with pacing-aware guidance.

```markdown
Three presets:
| Preset | Best for | Silence Threshold | Breathing Room Strategy |
|--------|----------|-------------------|------------------------|
| gentle | Interviews, tutorials, conversations | >1.0s | Preserves 0.5-1.0s pauses for contemplation; respects natural speaker rhythm |
| standard | Podcasts, vlogs, general content | >0.8s | Removes dead air while maintaining natural conversational pauses; balances tightness with authenticity |
| aggressive | Social clips, shorts, high-energy content | >0.4s | Tight pacing for momentum; removes nearly all silence except dramatic pauses (0.8s max) |

**Key principle:** Silence below the threshold is evaluated in context—if it feels intentional (after a statement, before a punchline), it may be preserved regardless of duration.
```

---

### TEXT BLOCK 2: New Section on the Review Pass
**Location:** Insert after "## Step 3: Clean Up (auto_cut)" and before "## Step 4: Verify"

**Context:** The pacing and audio rules make clear that the review pass is doing critical work. This details what it's checking for.

```markdown
### What the Review Pass Checks

After mechanical cleanup, Claude reviews the result transcript and checks for:

1. **Jarring silence removals** — Were natural pauses between statements preserved? Or does speech run together without breathing room?
2. **Dead air at the start** — Does the intro begin with actual content, or is there remaining silence/false start/intro fumbling?
3. **Overaggressive filler removal** — Do remaining fillers (um, uh) feel natural, or was dialogue stripped to the point of sounding robotic?
4. **Missed false starts** — Are there still obvious retakes or multiple intro attempts that should have been caught?
5. **Conditional fillers in context** — Words like "like", "you know", "basically" may remain if they're tied to the speaker's natural style; the review pass confirms they enhance rather than detract.
6. **Pacing rhythm** — Does the overall flow feel intentional and energetic (not overly compressed) or natural and conversational (not dragging)?

If issues are found, auto_cut trims automatically to fix them.
```

---

### TEXT BLOCK 3: New Section on Content Type & Preset Matching
**Location:** Insert after the presets table, before "auto_cut includes a Claude review pass..."

**Context:** The cuts.md and pacing.md rules show that cutting strategy varies by content type. This guides users on preset selection.

```markdown
### Choosing Your Preset: Content Type Guide

- **Gentle:** Use for interviews, tutorials, conversations, and any content where natural breathing room matters. Speakers need space to think and respond. Preserves pauses that show contemplation.

- **Standard:** Default for podcasts, vlogs, and mixed-speech content. Removes obvious dead time and harsh silence while maintaining the authentic feel of conversation. Plan for ~15-20% duration reduction.

- **Aggressive:** Use for social media clips, shorts, reels, and high-energy content. Momentum is the priority. Removes nearly all silence and tightens pacing for viewer retention. Plan for ~20-30% duration reduction.

**Rule of thumb:** If you'd watch the content on Instagram or TikTok, use aggressive. If it's long-form and audience should feel heard, use gentle or standard.
```

---

### TEXT BLOCK 4: Expanded Filler Removal Strategy
**Location:** Insert after "## Step 3: Clean Up (auto_cut)" section, as a subsection

**Context:** Audio.md rule on strategic filler removal shows that um/uh/er/ah/hmm are always removed, but "like", "you know", "basically" depend on context. This clarifies auto_cut's approach.

```markdown
### Filler Word Removal Strategy

**Always removed:** um, uh, er, ah, hmm
These contribute nothing to meaning or authenticity; removal is always better.

**Conditionally removed:** like, you know, basically
These words are tied to speaker style and natural cadence. The review pass checks whether removing them creates robotic dialogue or whether they genuinely interrupt flow. Some speakers naturally say "like" every few words; removing all instances makes them sound artificial.

**Recommendation:** Let the review pass evaluate conditional fillers in context. If the transcript reads naturally without them, they're removed. If removal makes dialogue sound choppy or unnatural, they're preserved.
```

---

### TEXT BLOCK 5: Silence Preservation Principle
**Location:** Insert in "## What NOT to Do" section, after the current list

**Context:** The pacing rules emphasize that silence must be intentional; this guards against over-aggressive silence removal.

```markdown
- **Don't remove all silence in the name of pacing.** The goal is to remove *dead air*, not all pauses. Natural pauses between statements, after questions, and before key points create rhythm and let listeners absorb information. The review pass preserves these. Overly compressed content feels robotic and exhausting.
```

---

### TEXT BLOCK 6: Updated Example with Pacing Context
**Location:** Replace or enhance the current "## Example: Multi-Episode Podcast Recording" section

**Context:** The example should reference pacing and silence handling to show how presets relate to real-world content.

```markdown
## Example: Multi-Episode Podcast Recording

A 164-minute recording contains:
- 0:00-56:00 — Pre-show conversation
- 56:23 — "Welcome to Technologer" (FALSE — just a tagline in pre-show)
- 112:43-114:32 — Rehearsal of "Technology Talks" intro (3 attempts)
- 114:32-140:42 — Episode 1: "Feedback & Customer Discovery" (REAL)
- 148:59-159:31 — Episode 2: "Is AI Making People Dumber?" (REAL)

Only `analyze_transcript` (Claude reading the full transcript) correctly identified 2 real episodes. Energy analysis found nothing. Keyword matching found 12 false episodes. Local heuristics scored pre-show chat as "episode content" because it contained tech vocabulary.

**After extraction to 114:32-140:42 (Episode 1):**
- Running time: 26m 10s
- Expected after standard preset auto_cut: ~21-23 minutes (15-20% reduction for dead time, fillers, breathing room adjustment)
- Contains natural pauses between major points (preserved); removes 2-3 second silence gaps (dead air) and filler words
- Result: Tight but authentic podcast rhythm, ready for audio processing

**If using aggressive preset instead:**
- Expected result: ~19-20 minutes
- Silence threshold drops to 0.4s; removes more breathing room
- Better for YouTube shorts/clips extracted from the episode, worse for full podcast release
```

---

## 4. SUMMARY OF ENHANCEMENTS

| Area | Current State | Enhancement |
|------|---------------|-------------|
| Silence Thresholds | Single 0.8s threshold | Pacing-aware thresholds: gentle 1.0s, standard 0.8s, aggressive 0.4s |
| Filler Removal | Only um/uh/er/ah/hmm | Add context for conditional fillers (like, you know, basically) |
| Review Pass | Mentioned, not detailed | Explain what Claude checks for; establish review criteria |
| Content Type Guidance | Presets exist, minimal context | Add clear matching rules: interview=gentle, podcast=standard, social=aggressive |
| Silence Preservation | Not explicitly addressed | Add principle: remove dead air, preserve intentional pauses |
| Example | Covers episode detection only | Add post-extraction outcome showing expected duration reduction |

---

## 5. IMPLEMENTATION PRIORITY

**High Priority (Apply First):**
1. TEXT BLOCK 1 — Updated presets table (most immediately useful)
2. TEXT BLOCK 3 — Content type & preset matching (guides user decisions)
3. TEXT BLOCK 4 — Filler removal strategy (clarifies scope)

**Medium Priority (Strengthens Understanding):**
4. TEXT BLOCK 2 — Review pass explanation (helps users trust the automation)
5. TEXT BLOCK 5 — Silence preservation principle (prevents over-aggressive use)

**Lower Priority (Context & Examples):**
6. TEXT BLOCK 6 — Enhanced example (illustrative; not strictly necessary)

---

## 6. KNOWLEDGE GAPS NOT ADDRESSED

The knowledge base contains information that doesn't directly apply to auto_cut's mechanical cleanup focus:

- **Audio processing chain** (gate, compressor, de-esser, EQ, limiter) — Applies after auto_cut, in audio engineering phase
- **Multi-camera switching and camera audio replacement** — Applies to source recording, before auto_cut
- **Music stings and emotional pacing** — Applies to final mixing, after auto_cut
- **Energy analysis** — Explicitly mentioned in auto-cutter.md as "don't use this"; knowledge validates that rule

These can be documented in separate skill updates if editing/mixing workflow expansion is planned.
