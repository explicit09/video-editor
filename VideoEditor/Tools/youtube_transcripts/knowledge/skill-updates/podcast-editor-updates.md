# Podcast Editor Skill Update

## Executive Summary

The podcast-editor skill provides a solid foundation for podcast and interview cleanup, but knowledge from the audio, pacing, and cuts categories reveals significant gaps in audio processing chain knowledge, multi-speaker handling strategies, and personality preservation techniques. This update integrates industry-standard audio processing workflows, interview-specific pacing guidance, and intentional cutting principles that preserve speaker authenticity while tightening content.

---

## Knowledge Gap Analysis

### 1. Audio Processing Chain (FROM: audio.md)
**Current State in podcast-editor.md:** Absent
**Relevance:** CRITICAL
**Why:** The skill mentions normalization and volume adjustments but lacks the industry-standard signal flow that defines professional podcast production. Multi-speaker recordings especially benefit from gating, compression, and de-essing applied in the correct sequence.

**Specific Audio Rules Applicable:**
- Rule: Apply Professional Audio Chain in Correct Order (Gate → Compressor → De-esser → Noise Reduction → EQ → Limiter)
- Rule: Use Gate for Multi-Person Recordings (prevents microphone bleed)
- Rule: De-Ess All Spoken Content (manages sibilance in dialogue)
- Rule: Shape Voice Presence with EQ (high-pass filter at 80Hz + 3kHz boosts)
- Rule: Protect Against Peak Distortion with Master Limiter

**Impact on Skill:** Editors currently skip audio processing and move straight to editing. Adding context about professional chains will prevent over-reliance on volume normalization alone and ensure tighter, more professional results.

---

### 2. Multi-Speaker Isolation (FROM: audio.md)
**Current State in podcast-editor.md:** Not covered
**Relevance:** CRITICAL
**Why:** The skill handles multi-speaker recordings but lacks explicit guidance on using gates to prevent microphone bleed—a key quality differentiator in interview content.

**Specific Audio Rules Applicable:**
- Rule: Use Gate for Multi-Person Recordings
- Rule: Sync Audio via Clap or Spoken Spike (for multi-mic setups)
- Rule: Link Audio and Video Tracks After Syncing

**Impact on Skill:** Adding gate-based bleed prevention will improve clean dialogue isolation before any cuts or filler removal, resulting in noticeably crisper multi-speaker content.

---

### 3. Personality Preservation Through Pacing (FROM: pacing.md)
**Current State in podcast-editor.md:** Partially covered (natural pauses preserved, WPM-based speed adjustments)
**Relevance:** HIGH
**Why:** The skill mentions preserving pauses and natural breathing, but pacing knowledge reveals that interview-specific pacing principles differ fundamentally from short-form content. The "Interview Natural Breathing" rule directly supports authenticity.

**Specific Pacing Rules Applicable:**
- Rule: Interview Natural Breathing (maintain breathing room between speaker exchanges)
- Rule: Silence Must Be Intentional (every silence should serve a clear purpose)
- Rule: Never Eliminate All Space (avoid overly compressed, exhausting feel)
- Rule: Variable Pacing Creates Rhythm (slow key moments, speed through weaker sections)

**Impact on Skill:** Editors currently use fixed silence thresholds (0.5s between speakers, 0.3s within). Adding interview-specific pacing guidance will help editors understand when to preserve longer pauses for authenticity vs. tighten for energy.

---

### 4. Intentional Cutting Principles (FROM: cuts.md)
**Current State in podcast-editor.md:** Partially covered (remove dead zones, filler words, tighten silence)
**Relevance:** HIGH
**Why:** The skill removes content procedurally but lacks the creative decision-making framework that makes cuts feel invisible. Several cuts.md rules directly enhance the podcast editing methodology.

**Specific Cuts Rules Applicable:**
- Rule: Cut on Energy Shifts (natural energy transitions as cut points)
- Rule: Never Cut Mid-Sentence (maintain complete thoughts)
- Rule: Every Shot Must Serve Purpose (eliminate shots that don't advance narrative)
- Rule: Cutting Decisions Are Creative Choices (removal shapes meaning as much as inclusion)
- Rule: Maintain Contextual Pacing for interviews (breathing room > tight cutting)
- Rule: Cut Approximately 20% of Recorded Time (plan for ~80% retention in final edit)

**Impact on Skill:** The skill currently uses transcript search to identify filler and dead zones, but doesn't frame cutting as a creative decision-making process. Adding cuts.md context will help editors understand *why* they're removing content and *what* they're preserving about speaker voice.

---

### 5. Audio Quality and Source Optimization (FROM: audio.md)
**Current State in podcast-editor.md:** Not covered
**Relevance:** MEDIUM
**Why:** The skill focuses on post-production cleanup, but tips about source quality and spectral analysis reveal that some problems should be prevented upstream rather than fixed in editing.

**Specific Audio Tips Applicable:**
- Invest in source quality (professional audio starts with good microphones)
- Use spectral analysis to identify and remove noise (iZotope RX for surgical removal)
- Create audio snapshots before destructive edits (backup unedited tracks)
- Create marker-based edit points (colored markers for precision)

**Impact on Skill:** Adding references to source quality and backup procedures will help editors set realistic expectations and avoid irreversible decisions.

---

## Recommended Additions to podcast-editor.md

### ADDITION 1: Insert After Step 1 (Transcribe and Analyze)

**Location:** After "## Step 2: Remove dead zones" header, before the current content

**Heading:** "## Step 1.5: Audio Processing Chain (Multi-Speaker Setup)"

**Content:**

```markdown
## Step 1.5: Audio Processing Chain (Multi-Speaker Setup)

Before removing any filler or tightening silence, establish a clean audio foundation:

### Gate: Isolate Each Speaker
- Apply a gate to each microphone channel to prevent bleed
- Threshold: Set to just below ambient noise level, allowing only full-volume speech through
- This cuts off-camera chatter and room noise leaking into individual tracks
- Result: Cleaner, more isolated dialogue for each speaker

### Compressor: Manage Dynamics (1176 Style)
- Ratio: 4:1
- Attack: 5ms
- Release: 30-50ms
- Target: Tame peaks without losing natural breath and emphasis
- Applies AFTER gate, so it works on already-isolated audio

### De-Esser: Reduce Sibilance
- Target frequency: 5-7kHz
- Amount: -2 to -4dB depending on speaker
- Apply to all spoken content to reduce harsh "S" sounds
- More aggressive with closer-miked speakers (podcasters, hosts)

### Noise Reduction
- Apply surgical noise removal to eliminate room hum, AC buzz, or fan noise
- Use spectral analysis (iZotope RX or similar) to identify specific frequencies
- Remove only the noise, not the dialogue

### EQ: Shape Presence
- High-pass filter: 80Hz (removes low rumble and mic handling noise)
- Presence boost: +2-3dB around 3kHz (adds clarity and presence to speech)
- Gentle Q, avoid aggressive shelving

### Limiter: Protect Against Peaks
- L2 Maximizer style, threshold: -4 to -6dB
- Attack: 1ms (protect against fast transients)
- Release: 50-100ms
- Acts as final safety net for unexpected peaks

### Important: Link Tracks and Create Backups
- After syncing audio and video tracks, link them so they move as a single unit
- Create an unedited backup of original audio before any destructive cuts
- Mark each filler word or silence with colored markers for visual reference
```

---

### ADDITION 2: Insert Into Step 3 (Remove Filler Words)

**Location:** Replace the "**Process:**" section with expanded guidance

**Old Content:**
```
**Process:**
1. `search_transcript` for each filler pattern
2. `split_clip` at word boundaries to isolate
3. `delete_clips` to remove
4. Never cut mid-word — always at word boundaries
```

**New Content:**

```markdown
**Process:**
1. `search_transcript` for each filler pattern
2. `split_clip` at word boundaries to isolate — aim to include ~50ms before and after the filler word for smooth removal
3. Review each instance in context before deleting:
   - "like" in "like, you know, it was" → remove (filler)
   - "like" in "do you like this idea?" → keep (comparative, intentional)
   - "basically" in "basically, what happened..." → remove (hedging)
   - "you know" as rhetoric → remove; as genuine question → keep
4. `delete_clips` to remove only confirmed fillers
5. Never cut mid-word — always at word boundaries
6. Remember: Removing ALL filler creates robotic dialogue. Preserve speaker personality by keeping filler that reflects natural rhythm.
```

---

### ADDITION 3: Insert After Step 4 (Tighten Silence)

**Location:** After the silence timing guidelines, add new subsection

**Heading:** "### Silence as a Creative Tool"

**Content:**

```markdown
### Silence as a Creative Tool

Not all silence is dead air. Use intentional silence to:

**Dramatic Pauses (up to 0.8s)**
- Before punchlines or big reveals
- After surprising statements to let impact land
- When a speaker takes a breath before an important point
- These pauses emphasize meaning and give listeners time to absorb

**Processing Pauses (3-5s with optional background music)**
- Between major topic shifts in longer interviews
- Allows listeners to mentally transition between subjects
- Optional: underlay with soft background music to signal a "breathing room" moment

**Turn-Taking Silence (0.2-0.5s)**
- Between speaker exchanges in dialogue
- Shorter gaps (0.2-0.3s) feel natural and conversational
- Longer gaps (0.3-0.5s) suggest contemplation or weight
- Gaps over 0.5s begin to feel awkward or like a technical error

**Energy Shift Points**
- When speaker changes volume, pacing, or emotional intensity, a natural pause often occurs
- These are ideal cut points—the silence itself signals a transition
- Never remove silence at energy shift points; it's doing creative work
```

---

### ADDITION 4: Insert Into Step 7 (Mandatory Verification)

**Location:** After the `get_state` verification step, before "Never tell the user editing is done..."

**Heading:** "### Quality Markers: Speech vs. Filler"

**Content:**

```markdown
### Quality Markers: Speech vs. Filler

Beyond technical verification, audit for personality preservation:

1. **Speaker Voice Check:**
   - Listen for sections where you cut heavily (lots of filler removed)
   - Do they still sound natural, or do edits feel abrupt?
   - If dialogue sounds robotic, you've removed too much personality

2. **Pacing Consistency:**
   - Compare fast-paced sections to slower sections
   - Do speed adjustments feel motivated by content, not artificial?
   - Verify no speaker sounds unnaturally accelerated (max 1.2x)

3. **Silence Distribution:**
   - Visually scan timeline for dramatic pauses (they should cluster at key moments)
   - Check that silence reductions don't feel "squeezed"—breathing room should exist between exchanges

4. **Multi-Speaker Integrity:**
   - If multiple speakers: verify no one person was edited much more heavily than others
   - Unbalanced editing can make one person sound more articulate than another (changing narrative)
   - Aim for similar edit intensity across all speakers
```

---

### ADDITION 5: Expand the "What NOT to do" Section

**Location:** Replace and expand current "What NOT to do" section

**Current Content:**
```markdown
## What NOT to do

- Never remove ALL pauses — speech becomes robotic
- Never speed up already-fast speakers
- Never cut mid-laugh or mid-reaction
- Never skip the audio energy scan — transcript lies about engagement
- Never report success without verify_playback
- Never assume speed applied to audio — check get_state shows it on both tracks
```

**New Content:**

```markdown
## What NOT to do

**Cutting & Authenticity:**
- Never remove ALL pauses — speech becomes robotic
- Never cut mid-laugh, mid-reaction, or mid-emotional beat (these are character, not filler)
- Never edit one speaker significantly more than others—this changes power dynamics
- Never use the same filler removal pattern across all speakers; allow for individual speaking styles

**Speed & Personality:**
- Never speed up already-fast speakers (>150 WPM should stay at 1.0x)
- Never speed up emotional or dramatic content—slowing it down is often better
- Never apply speed uniformly across entire interview; adjust per speaker and context

**Audio Processing:**
- Never skip the audio energy scan—transcript alone doesn't reveal engagement patterns
- Never normalize all voices to identical levels; preserve natural personality differences in mic presence
- Never over-compress interview content; dynamic range is part of authentic speech

**Silence & Pacing:**
- Never remove intentional dramatic pauses (especially before punchlines)
- Never reduce all silences uniformly; longer pauses often mark important thinking moments
- For interviews: preserve some breathing room even if you're tightening overall—silence is part of dialogue rhythm

**Verification & Reversibility:**
- Never report success without verify_playback
- Never assume speed applied to audio—check get_state shows it on both tracks
- Never perform destructive edits on original tracks; always work on a backup copy
- Never delete a clip you're unsure about; mark it for review instead

**Creative Decision-Making:**
- Never view editing as purely technical removal; every cut is a creative choice
- Never cut based on transcript alone; audio energy analysis reveals what transcripts miss
- Never assume the user wants maximum tightness; some podcasts thrive on conversational breathing room
```

---

## Summary of Integration Points

| Knowledge Area | Integration Point | Impact |
|---|---|---|
| **Audio Processing Chain** | Step 1.5 (new) | Establishes professional audio foundation before cutting; improves multi-speaker clarity |
| **Multi-Speaker Handling** | Step 1.5 (new) | Gate-based bleed prevention; backup procedures; linked tracks |
| **Filler Removal Context** | Step 3 (expanded) | Contextual decision-making vs. blanket removal; personality preservation |
| **Intentional Silence** | Step 4 (expanded) | Moves from purely technical timing to creative silence use; dramatic pauses; processing breaks |
| **Personality Preservation** | Step 7 (expanded) + What NOT to do | Verification includes voice authenticity check; expands prohibitions to cover style-based editing |
| **Interview-Specific Pacing** | What NOT to do (expanded) | Breathing room for interviews vs. short-form; speaker-by-speaker balance |
| **Creative Cutting Principles** | What NOT to do (expanded) | Frames cutting as creative choice, not just technical removal |

---

## Implementation Notes

1. **Step 1.5 should be conditional:** The audio processing chain guidance applies primarily to multi-speaker interviews. Single-speaker podcasts may skip this if source audio is already clean, but the skill should present it as best practice.

2. **Silence thresholds remain unchanged:** The 0.5s / 0.3s / 0.8s rules are sound. The expansion contextualizes them within interview pacing rather than replacing them.

3. **Personality preservation is now explicit:** The skill previously assumed personality preservation implicitly; these additions make it an explicit verification step, increasing accountability for maintaining speaker voice.

4. **Backup procedures added:** The audio.md tip about creating "audio snapshots before destructive edits" aligns with professional workflow. This should be mentioned early in Step 1.5.

5. **Editing speed caps refined:** Current guidance (1.2x max) is preserved. The expansion clarifies that extremely fast speakers (150+ WPM) should not be sped up at all.

---

## Testing Recommendations

Once these updates are integrated:

1. **Test on multi-speaker interviews** (2+ hosts/guests): Verify gating steps improve isolation
2. **Test on single speaker with heavy filler**: Confirm personality preservation check catches over-editing
3. **Test on conversational vs. scripted**: Ensure pacing guidance adapts appropriately
4. **Test on high-energy vs. reflective content**: Verify that silence expansion doesn't suggest removing dramatic pauses

