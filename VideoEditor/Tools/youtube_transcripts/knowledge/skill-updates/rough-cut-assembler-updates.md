# Rough Cut Assembler — Knowledge Integration & Skill Updates

## Executive Summary

The rough-cut-assembler skill provides a solid technical foundation for assembly workflow using audio energy analysis and take selection. Integration of relevant knowledge from cuts, organization, and storytelling categories reveals opportunities to strengthen narrative prioritization, workflow structure, and quality assurance frameworks. Recommended updates emphasize decision-making context, organization discipline, and narrative coherence alongside technical execution.

---

## 1. Relevant Knowledge Integration

### From Cuts Category

**Highly Relevant:**
- **Rule: Cut on Action** — Applies to take selection when evaluating which take has the cleanest natural movement or gesture completion
- **Rule: Cut on Energy Shifts** — Directly supports the take selection step by identifying natural transitions between takes based on energy changes
- **Rule: Never Cut Mid-Sentence** — Critical for take boundary identification and selection; current skill mentions "complete thoughts" but cuts knowledge formalizes this
- **Rule: Trim Dead Space at Clip Beginnings** — Already implemented in Step 3 (trim 0.3s before speech) but knowledge provides explicit reasoning
- **Rule: Every Shot Must Serve Purpose** — Applies to take selection: each take should be chosen because it advances narrative, not by default
- **Rule: Cutting Decisions Are Creative Choices** — Reframes take selection from mechanical scoring to conscious editorial decision-making
- **Rule: Maintain Contextual Pacing** — Helps determine assembly order: interview content needs breathing room vs. dynamic montage content

**Moderately Relevant:**
- **Rule: Cut Approximately 20% of Recorded Time** — Useful baseline for assessing completeness of raw footage; if raw footage is 90+ minutes and script is ~20 minutes, expect substantial cutting
- **Rule: Problem-Solve Rather Than Over-Decorate** — Reminds that assembly is about clarity and working with what exists, not showcasing technique

### From Organization Category

**Highly Relevant:**
- **Rule: Process is Everything** — The skill IS a process; should emphasize that consistency of this workflow produces better results than ad-hoc decisions
- **Rule: Keep Drafts of Everything** — Skill doesn't mention version control; should advise keeping before/after versions of assembly
- **Rule: Color and Label Everything in Timeline** — Step 1 uses rename/markers; should expand to include color labels for take quality ratings
- **Rule: Name Clips Clearly and Descriptively** — Step 1 uses "Take N: [first words]"; knowledge suggests more specificity (date, content type)
- **Rule: Simpler Tasks Drive Faster Workflow** — The skill's step-by-step structure embodies this; can be made more explicit

**Moderately Relevant:**
- **Rule: Radio Edit for Spoken Content** — Applies when rough cut is interview/voiceover content; create clean audio baseline first
- **Rule: Isolate Technical From Creative Problems** — Helps during verification step: audio energy issues vs. narrative issues are different problems

### From Storytelling Category

**Highly Relevant:**
- **Rule: Story Drives All Choices** — Take selection should be guided by narrative contribution, not just audio metrics
- **Rule: Three-Act Structure** — Assembly order in Step 4 ("order by script/topic/chronology") should reference narrative structure
- **Rule: Ruthless Focus on Value** — Informs take selection: does this take add value, or does a better take exist?
- **Rule: Natural Moments in Narrative** — May conflict with audio energy scoring; some "lower energy" takes preserve authenticity
- **Rule: Pacing Signals Emotional Shifts** — Ordering affects pacing; assembly should consider emotional beats, not just chronology

**Moderately Relevant:**
- **Rule: Story Before Polish** — Emphasizes that rough cut priority is narrative clarity, not technical perfection
- **Rule: Know Your Audience** — Take selection may differ for different audiences (casual vs. professional, etc.)

---

## 2. Specific Additions & Changes to Recommend

### A. Enhanced Step 1: Identify Takes — Add Narrative Context

**What's Missing:** Current step focuses on technical identification (audio energy, transcript markers). Should add narrative framing to make take identification conscious rather than mechanical.

**Add Before Step 1:**
- Brief section explaining that take identification is both technical AND narrative; audio energy finds the takes, but understanding story structure helps prioritize which takes to score heavily

**Enhance Step 1 Itself:**
- Add consideration of content type (interview, voiceover, scripted, etc.) which affects how energy patterns map to actual takes
- Include note that director cues ("action", "cut") are shortcuts but audio energy is more reliable when verbal cues are inconsistent

### B. Enhanced Step 2: Select Best Take Per Scene — Add Strategic Context

**What's Missing:** Current scoring system is weighted but lacks decision framework for when metrics conflict or when lower-energy takes may be narratively superior.

**Changes:**
- Add section on "Reading Beyond Metrics" — recognizing when a take with lower energy but higher authenticity serves story better
- Clarify when to prioritize: Completeness > Audio Energy for interview content; Audio Energy > Completeness for voiceover/narration
- Add explicit instruction to consider three-act structure: opening takes may prioritize energy and hook; middle takes may prioritize authenticity; closing takes may prioritize resolution energy

### C. Enhanced Step 3: Remove Dead Air — Add Workflow Integration

**What's Missing:** Current step is technically sound but doesn't reference the organization principle of maintaining clean workflow and version control.

**Add:**
- Note about keeping a "before trim" version of each clip for potential restoration
- Clarification that trim decisions should flag ambiguous cases rather than assume; mark with setmarker for review

### D. Enhanced Step 4: Assemble — Add Narrative Architecture

**What's Missing:** Current step says "order by script/topic/chronology" but doesn't provide hierarchy or decision framework.

**Add:**
- Explicit guidance: Story structure (three-act setup/conflict/resolution) overrides chronology
- Consider pacing: alternate between interview/static vs. B-roll, or between high-energy and contemplative moments
- Check for narrative continuity: does flow from one take to next feel motivated by story or arbitrary?

### E. New: Pre-Step 0 — Preparation & Context Gathering

**What's Missing:** Skill jumps directly to audio analysis without establishing narrative context.

**Add New Section:**
- Brief assessment of what the content is trying to communicate
- Identification of content type (interview, voiceover-driven, B-roll with narration, multi-camera, etc.)
- Quick note on target audience/context (this affects assembly priorities)
- Establish whether script exists, and if so, review it before analyzing audio

### F. Enhanced Step 5: Verification — Add Narrative Check

**What's Missing:** Current verification is audio-focused (energy ratios, loudness). Should include narrative verification.

**Add:**
- Does the assembly tell a coherent story? (Can someone unfamiliar understand what they're hearing?)
- Does assembly match intended emotional arc? (pacing appropriate for story beats?)
- Are there any orphan takes (isolated visually/narratively from context)?
- Check for unintended repetition: does the same content appear in multiple takes accidentally?

### G. What NOT to Do — Add Strategic Guidance

**Enhance existing section with:**
- Never select takes based solely on audio energy; always verify that take serves narrative
- Never assemble in strict chronological order if story structure suggests different arrangement
- Never trim aggressively until you understand context; mark ambiguous boundaries for review rather than auto-removing

---

## 3. Actual Text Blocks for Insertion

### INSERTION 1: New Section Before "Step 0"

**Location:** Before "Step 0: Audio energy map" — Insert as new "Step -1" or rename all steps

**Text Block:**

```markdown
## Step -1: Prepare — Understand Context & Story

Before analyzing audio, establish the narrative context for editorial decisions:

1. **Identify content type:**
   - Interview-driven (prioritizes completeness and authenticity)
   - Voiceover-driven (prioritizes clean delivery and energy)
   - B-roll with narration (prioritizes synchronization and pacing)
   - Multi-camera (prioritize coverage and angle variety)

   This affects which takes score highest and how assembly will be ordered.

2. **Review any existing script or outline:**
   - Does one exist? If yes, reference it during take selection and assembly
   - What is the intended narrative structure? (three-act flow, topical organization, chronological journey?)
   - This determines assembly order in Step 4

3. **Note the intended audience and context:**
   - What should the audience feel or understand after this assembly?
   - This guides take selection: does a take contribute to that intention?

4. **Quick assessment of raw footage:**
   - How many hours of footage? (Expect ~80% to be removed)
   - Are there obvious re-takes of the same content?
   - Any technical issues (audio inconsistency, camera drift)?

This context shapes editorial decisions downstream. Spending 2 minutes here prevents guessing later.
```

### INSERTION 2: Add to Step 1 — After "split_clip at each take boundary"

**Location:** In Step 1, after the bullet point listing director cues

**Text Block:**

```markdown

**Audio energy pattern guide for different content types:**
- Interviews: Look for speech spikes above 50% speech ratio separated by dead zones (hesitations, thinking pauses)
- Voiceover: Consistent high speech ratio with clear on/off boundaries; takes are separated by complete silence or room tone reset
- Multi-camera: Each take boundary shows full silence, not just speech ending (camera roll-down or reset period)
- B-roll narration: Speech occurs in chunks; takes are separated when voiceover stops and restarts

Use content type to interpret energy data, not just numerical thresholds.
```

### INSERTION 3: Enhanced Step 2 — Replace entire section

**Location:** Replace existing "Step 2: Select best take per scene" section

**Text Block:**

```markdown
## Step 2: Select Best Take Per Scene

When the same content appears multiple times (re-takes), choose which version advances the story best.

**Understand the hierarchy for different content types:**

*For Interview/Conversational Content:*
1. Completeness (40%) — Full thought without restarts or verbal stumbles
2. Authenticity (30%) — Natural delivery, even if audio energy is lower
3. Recency (20%) — Later takes tend to be more polished
4. Audio quality (10%) — Consistent volume, minimal background noise

*For Voiceover/Narration:*
1. Audio energy (40%) — Higher engagement and delivery energy = stronger presence
2. Completeness (30%) — No stumbles, restarts, or verbal tics
3. Audio quality (20%) — Consistent with other takes in the piece
4. Recency (10%) — Earlier takes acceptable if performance is superior

**Score each take:**
- Use `analyze_audio_energy` on each take individually for precise comparison
- For interviews, manually listen to assess authenticity beyond metrics
- Flag takes where metrics conflict (high energy but incomplete speech; low energy but natural delivery)

**Make the creative choice:**
- Metrics guide but don't determine. A take with 15% lower energy but 40% better authenticity may be the right choice
- Consider what the take contributes to the narrative: Does it set up story? Provide evidence? Deliver payoff? Choose based on narrative role, not just performance metrics
- Recency matters less if an earlier take is demonstrably stronger for the story

**Three-act guidance:**
- Opening/Setup takes: Prioritize energy and hook; audience needs to engage immediately
- Middle/Conflict takes: Balance energy with authenticity; audience is invested, natural moments matter more
- Closing/Resolution takes: Prioritize completeness and emotional clarity; audience needs resolution to feel earned

**Mark rejected takes with color labels** (e.g., red for "rejected", yellow for "backup candidate") rather than deleting. You may need them if a selected take has issues during assembly.
```

### INSERTION 4: Enhanced Step 4 — Expand "Assemble" section

**Location:** Replace existing "Step 4: Assemble" section

**Text Block:**

```markdown
## Step 4: Assemble — Build Narrative Structure

Order clips to create coherent story, not just technical sequence.

**Establish assembly hierarchy:**

1. **Story structure first** — If content has three-act structure (setup → conflict → resolution), arrange takes to support that shape
2. **Topic/thematic grouping second** — If content is topical (multiple interview subjects on different topics), group by topic
3. **Chronology last** — Only use chronological order if story itself is a timeline and narrative progression requires it

**Assembly pacing strategy:**

- Alternate between energy states: if a take has high energy, follow with slightly lower energy to create rhythm
- For interview content: balance speaking vs. listening moments; don't stack multiple uninterrupted speaker takes
- For voiceover-driven: ensure B-roll pacing complements audio pacing; rapid cuts match energetic narration; static shots match contemplative sections
- Watch for momentum: each take should bridge to the next naturally, not feel isolated

**Check narrative continuity:**

1. `move_clip` each take sequentially with no gaps (butt cuts)
2. After each placement, ask: Does this take naturally follow the previous one? If the answer is "technically yes but narratively no", reconsider order
3. Look for unintended repetition: Are you showing the same content twice with different takes? If both survive, you have a problem

**Measure loudness per clip:**

- `measure_loudness` for all clips
- Flag inconsistencies > 6 LUFS with `set_marker`
- Note: These may be legitimate (interview subject speaks quietly vs. loudly) but should be visible during verification
```

### INSERTION 5: New Step 5A — Narrative Verification (before technical verification)

**Location:** Before current "Step 5: Mandatory verification" — Insert as "Step 5: Narrative Verification"

**Text Block:**

```markdown
## Step 5: Narrative Verification — Does the Story Work?

Before checking technical metrics, verify the assembly tells the intended story.

1. **Play through the entire assembly without stopping:**
   - Can someone unfamiliar with the project understand what they're hearing?
   - If clarity is lost, where does it break down?
   - Mark those sections for assembly re-ordering

2. **Emotional arc check:**
   - Does the pacing support emotional beats? (Fast when energy rises, slow when contemplative)
   - Do take selections align with emotional intention at each moment?
   - Is there appropriate tension and release, or does it feel monotone?

3. **Redundancy check:**
   - Does any content appear twice unintentionally?
   - Are all included takes necessary, or is something surviving by default rather than intent?
   - Ask about each take: "If I remove this, does the story suffer?" If not, mark it for deletion

4. **Continuity check:**
   - Does flow from one take to the next feel motivated by story or arbitrary?
   - Are there places where the assembly jumps thematically without a bridge?
   - Are there orphan takes that feel isolated from surrounding context?

Mark all issues with `set_marker` for review. You may need to re-order assembly sections, re-select takes, or trim internal content.
```

### INSERTION 6: Enhanced Step 5 (Technical) — Rename and Clarify

**Location:** Rename current "Step 5: Mandatory verification" to "Step 6: Technical Verification"

**Text Block:**

```markdown
## Step 6: Technical Verification — Audio & Workflow Integrity

After narrative verification, confirm technical execution.

1. `verify_playback` mode "quick":
   - Audio present at all checkpoints
   - No dead air > 1s at boundaries (assembly should feel continuous)
   - All clips play in order without gaps

2. `analyze_audio_energy` on the assembly:
   - Speech ratio should be > 70% (dead air removed)
   - Overall score should be higher than raw footage average
   - If not, mark sections for additional trimming or dead air removal

3. `get_state` — Confirm workflow completeness:
   - All clips named with take numbers (format: "Take N: [content]")
   - All rejected takes marked with color labels
   - Markers set at each section start or problematic boundary
   - No gaps between clips (butt cuts throughout)
   - Loudness inconsistencies marked (> 6 LUFS variance)

4. **Final checklist:**
   - Do you have a saved backup of this assembly before any further refinement?
   - Have you documented which takes were selected and why (if needed for handoff)?

Report done only after both narrative and technical verification are complete.
```

### INSERTION 7: Enhanced "What NOT to Do" Section

**Location:** Replace or expand existing "What NOT to do" section

**Text Block:**

```markdown
## What NOT to Do

**Technical mistakes:**
- Never delete a take without confirming a better version exists (archive it with color label instead)
- Never trim into spoken content — trim silence around speech, not speech itself
- Never skip audio energy analysis — it's the fastest way to find takes in raw footage
- Never assemble without checking for duplicate content

**Editorial mistakes:**
- Never select takes based solely on audio energy metrics; verify that each take serves the narrative
- Never assemble in strict chronological order if the story suggests a different arrangement
- Never trim aggressively until you understand context; mark ambiguous boundaries with markers for review
- Never report done without narrative verification; technical quality matters less than story clarity

**Workflow mistakes:**
- Never skip the preparation step; understanding content type and story intent saves time downstream
- Never forget version control; keep "pre-trim" and "before final assembly" backups
- Never assume metrics tell the whole story; listen to rejected takes if narrative questions arise during assembly

**Remember:** The rough cut's job is story clarity and structural coherence, not technical perfection. A rough cut with clear narrative beats and authentic takes is complete. Audio balance, color, and polish come later.
```

---

## 4. Summary of Integration Benefits

### Narrative Coherence
- Adding preparation context ensures editorial decisions are guided by story, not just metrics
- Step 2 enhancement provides decision-making framework for when metrics conflict
- New narrative verification step ensures the assembly tells a coherent story

### Workflow Discipline
- Organization knowledge reinforces version control and color labeling (reduces mistakes during refinement)
- Emphasis on "process is everything" validates the skill's step-by-step structure
- Clarifies that consistency produces better results than ad-hoc decisions

### Editorial Judgment
- Cuts knowledge helps contextualize take selection beyond audio metrics
- Storytelling knowledge reframes assembly from technical ordering to narrative architecture
- Recognizes that natural moments and lower-energy takes sometimes serve story better than high-energy takes

### Quality Verification
- Distinguishes between narrative verification (does story work?) and technical verification (do mechanics work?)
- Both are mandatory; narrative verification happens first because story clarity outweighs technical perfection in a rough cut
- Provides actionable checklist for each verification type

### Scalability
- Content type guidance (interview vs. voiceover vs. multi-camera) lets the skill adapt to different footage types
- Three-act structure reference helps with longer-form content assembly
- Audience consideration allows for variations in assembly priorities

---

## 5. Implementation Notes

- **Non-breaking changes:** All additions can be integrated without removing existing content; they enhance context and decision-making without contradicting current steps
- **Step numbering:** If implementing new "Step -1" and renamed steps, update all cross-references (e.g., "verify_playback is used in Step X" references)
- **Color labeling:** Current skill doesn't mandate color labels; organization knowledge strongly supports adopting this as standard
- **Verification order:** The current single "Step 5" should be split into "Step 5: Narrative" and "Step 6: Technical" to emphasize narrative-first verification
- **Tone shift:** Updates subtly shift tone from "mechanical assembly" to "conscious editorial decision-making" while preserving technical rigor
