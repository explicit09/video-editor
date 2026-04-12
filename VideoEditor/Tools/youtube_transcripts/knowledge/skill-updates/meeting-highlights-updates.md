# Meeting Highlights Skill — Knowledge Integration Updates

## Overview

The meeting-highlights skill creates executive summaries from meeting recordings by using audio energy analysis to identify active discussion zones. Integration with knowledge from cuts, pacing, and storytelling categories strengthens three core areas: maintaining narrative coherence during compression, applying intentional pacing principles to compressed content, and structuring summaries with clear editorial intent.

---

## 1. Relevant Knowledge from Categories

### From Cuts Category

**Most Relevant Rules:**
- **Cut on Action & Energy Shifts** — Meeting summaries benefit from cutting at natural transitions where speaker energy or topic shifts occur. The skill already scans for energy; this reinforces cutting at those energy boundaries rather than arbitrary points.
- **Never Cut Mid-Sentence** — Critical for maintaining speaker credibility and message clarity in compressed formats. When extracting decision and action item segments, preserve complete thoughts.
- **Every Shot Must Serve Purpose** — In audio form, every segment kept in the summary must serve a communicative function. This aligns with the current budget allocation (decisions 40%, actions 30%, discussions 20%, context 10%).
- **Maintain Contextual Pacing for Conversations** — Meetings are conversational content. This rule emphasizes preserving natural turn-taking and response pacing, not just removing silence.

**Application:**
The skill currently focuses on removing dead zones and identifying key segments. These cutting principles reinforce that each segment kept must earn its place—not just by content classification, but by how it connects to the narrative arc of decisions and actions.

### From Pacing Category

**Most Relevant Rules:**
- **Silence Must Be Intentional** — The skill removes silence > 1.5s within kept segments. This rule deepens that practice: every silence removed should have intention (compression, not dead air).
- **Podcast Breathing Room (3-5 second pauses)** — While meetings aren't podcasts, the principle applies: deliberate pauses between summary sections (decision clusters, action items, key discussion shifts) help listeners process information and signal transitions.
- **Variable Pacing Creates Rhythm** — Meeting summaries risk monotony if every segment moves at the same speed. The skill should vary speaker speed slightly (already uses 1.05-1.1x speed adjustment) to emphasize high-priority segments and slow key decisions.
- **Emotional Energy Curves** — Even in executive summaries, tension-and-payoff structure matters. Lead with context setup, build through decisions, deliver action items as the payoff.
- **Audio-Visual Pacing Sync** — While audio-only, the transcript markers and transitions should sync with pacing. When cutting between different speakers or topics, transitions signal these shifts.
- **Every Second Earns Its Place** — Reinforces the 5-minute target for 1-hour meetings. Every 12 seconds compressed into 1 second of output must carry weight.

**Application:**
Current pacing guidance is implicit in the budget and compression ratio. These rules make it explicit: use speed variation strategically, intentionally insert pauses between summary sections, and structure the summary with emotional rhythm (not flat compression).

### From Storytelling Category

**Most Relevant Rules:**
- **Story Drives All Choices** — In meeting summaries, the story is: "What did we decide, what do we do next, and what context mattered?" All kept segments should support this narrative arc.
- **Three-Act Structure** — Meeting summaries map naturally: Act 1 (context/decisions), Act 2 (action items and ownership), Act 3 (resolution/next steps or timeline). This provides narrative scaffolding.
- **Intercutting for Clarity** — Alternate between decision statements and the discussions that led to them. Don't jump straight to decisions without the reasoning that earned them.
- **Ruthless Focus on Value** — The skill explicitly targets decisions and actions. This rule reinforces: cut anything that doesn't advance those two narrative pillars, even if it's interesting discussion.
- **Remove Distracting Scenes** — In meeting context: remove tangents, jokes, or extended problem exploration that doesn't lead to a decision or action. Protect the summary's through-line.
- **Tension and Payoff** — Structure: build tension through problem statements and discussions, deliver payoff with decisions and clear action assignments.
- **Know Your Audience** — Meeting summaries for executives differ in pace and depth from summaries for individual contributors. Audience context shapes what counts as "key discussion."

**Application:**
The skill should explicitly adopt three-act structure for summaries, intercut discussions with decisions (not isolate them), and recognize that audience context changes what counts as essential content.

---

## 2. Specific Additions & Changes to SKILL.md

### Addition 1: Narrative Structure Section (Insert after Step 1: Transcribe and classify)

**Location:** Between Step 1 and Step 2, or as a new Step 1.5

**Rationale:** The current skill maps segments to content type but doesn't address how to maintain narrative coherence while compressing. This addition bridges that gap.

**Text block:**

```
## Step 1.5: Map the narrative arc

Meetings have an implicit story: problem → discussion → decision → action.
Preserve this arc even in compression:

1. **Context opener:** Why are we here? (3-5 sentence context from opening)
2. **Decision cluster:** What did we agree on? (Group decisions by topic)
3. **Action cluster:** What happens next? (Who does what by when)
4. **Tension and payoff:** Lead with the decision or action that carries most weight

**Critical:** Do not jump from problem statement directly to action item—include the discussion that led to the decision. This provides reasoning and credibility. Compress the discussion, but don't erase it.

Example narrative flow:
- "We discussed three vendor options for Q2 (problem/discussion, 20 seconds)"
- "Decided to move forward with vendor B due to timeline and cost (decision, 15 seconds)"
- "Sarah owns implementation; first checkpoint Friday (action, 10 seconds)"

Intercut discussion with decision, not after. This maintains the reasoning chain.
```

### Addition 2: Strategic Speed and Pacing Section (Insert after Step 2: Build the summary)

**Location:** As Step 2.5 or integrated into Step 3 editing guidance

**Rationale:** The skill applies speed adjustment (1.05-1.1x) uniformly. This addition uses variable pacing intentionally to emphasize content and structure.

**Text block:**

```
## Step 2.5: Strategic pacing for compressed narrative

Compression without rhythm feels rushed. Use variable pacing to guide attention:

**Speed variation strategy:**
- **Decisions:** 1.0x (normal speed, maximum clarity)
- **Action items:** 1.0x (ownership and deadlines must be clear)
- **Background discussion:** 1.05-1.1x (faster to compress while maintaining coherence)
- **Context opener:** 0.95-1.0x (slightly slower to establish setup)

**Intentional silence (0.5-1.2 seconds):**
- Insert after each decision cluster (signals topic shift)
- Insert before action items (prepares listener for specifics)
- Never remove all silence within a segment—preserve natural speaker breathing

**Transition cues:**
- Use `crossDissolve` (0.3s) between different speakers or topics within a cluster
- Use `none` (hard cut) only within a single decision or action statement
- Position transitions at energy shifts (speaker changes, topic changes)

This creates rhythm that guides the listener through the narrative without feeling rushed.
```

### Addition 3: Verification Checklist Expansion (Expand Step 4)

**Location:** Within Step 4, after `verify_playback` and `analyze_audio_energy` checks

**Rationale:** Current verification focuses on technical metrics. This addition verifies narrative integrity and pacing intention.

**Text block:**

```
3. **Narrative structure verification:**
   - Does the summary follow a clear arc: context → decision(s) → action(s)?
   - Is each decision preceded by at least 5-10 seconds of supporting discussion or reasoning?
   - Are action items isolated with clear ownership (name + task + deadline)?
   - Do pacing changes align with topic shifts? (Context is calm, decisions clear, actions crisp)

4. **Compression integrity check:**
   - Play back at normal speed. Does it feel coherent, not rushed?
   - Are there 0.5-1.2 second pauses between clusters? (Check with `get_state` markers)
   - Does the audience understand *why* each decision was made, not just *what* was decided?
   - Can a first-time listener identify 3-4 key action items and owners?

If narrative arc is unclear or decisions lack supporting context, add back 10-15 seconds of discussion
rather than cutting further.
```

### Addition 4: Audience Context Guidance (Insert as new section before Step 0)

**Location:** Prepend as introductory guidance before Step 0

**Rationale:** Storytelling principles emphasize knowing your audience. This addition acknowledges that executive summaries vary by recipient.

**Text block:**

```
## Understanding Your Audience: Context Before Editing

Meeting summaries compress differently depending on who receives them.

**Executive summary (C-suite, 5 minutes):**
- Decisions: 50% (tight, action-focused)
- Key risk/blocker: 20%
- Action items: 30%
- Context: minimal (assume domain knowledge)

**Team summary (direct reports, 7-8 minutes):**
- Context: 15% (why was this discussed?)
- Decisions: 40%
- Action items & ownership: 35%
- Discussions that led to decisions: 10% (credibility)

**Async summary (cross-functional teams, 10 minutes):**
- Context: 20% (new context is valuable)
- Decisions with reasoning: 40%
- Action items with impact: 30%
- Open questions/risks: 10%

Before starting analysis, confirm your audience. This determines whether you cut aggressively for brevity or preserve more discussion for context and buy-in.
```

---

## 3. Text Blocks Ready to Insert

### Block 1: Pre-Step 0 — Audience Context

**Insert at the very beginning of the guide, before "## Step 0: Audio energy scan"**

```markdown
## Understanding Your Audience: Context Before Editing

Meeting summaries compress differently depending on who receives them.

**Executive summary (C-suite, 5 minutes):**
- Decisions: 50% (tight, action-focused)
- Key risk/blocker: 20%
- Action items: 30%
- Context: minimal (assume domain knowledge)

**Team summary (direct reports, 7-8 minutes):**
- Context: 15% (why was this discussed?)
- Decisions: 40%
- Action items & ownership: 35%
- Discussions that led to decisions: 10% (credibility)

**Async summary (cross-functional teams, 10 minutes):**
- Context: 20% (new context is valuable)
- Decisions with reasoning: 40%
- Action items with impact: 30%
- Open questions/risks: 10%

Before starting analysis, confirm your audience. This determines whether you cut aggressively for brevity or preserve more discussion for context and buy-in.
```

### Block 2: After Step 1 — Narrative Arc Mapping

**Insert between Step 1 ("Transcribe and classify") and Step 2 ("Build the summary")**

```markdown
## Step 1.5: Map the narrative arc

Meetings have an implicit story: problem → discussion → decision → action.
Preserve this arc even in compression:

1. **Context opener:** Why are we here? (3-5 sentence context from opening)
2. **Decision cluster:** What did we agree on? (Group decisions by topic)
3. **Action cluster:** What happens next? (Who does what by when)
4. **Tension and payoff:** Lead with the decision or action that carries most weight

**Critical:** Do not jump from problem statement directly to action item—include the discussion that led to the decision. This provides reasoning and credibility. Compress the discussion, but don't erase it.

Example narrative flow:
- "We discussed three vendor options for Q2 (problem/discussion, 20 seconds)"
- "Decided to move forward with vendor B due to timeline and cost (decision, 15 seconds)"
- "Sarah owns implementation; first checkpoint Friday (action, 10 seconds)"

Intercut discussion with decision, not after. This maintains the reasoning chain.
```

### Block 3: After Step 2 — Strategic Pacing

**Insert between Step 2 ("Build the summary") and Step 3 ("Edit")**

```markdown
## Step 2.5: Strategic pacing for compressed narrative

Compression without rhythm feels rushed. Use variable pacing to guide attention:

**Speed variation strategy:**
- **Decisions:** 1.0x (normal speed, maximum clarity)
- **Action items:** 1.0x (ownership and deadlines must be clear)
- **Background discussion:** 1.05-1.1x (faster to compress while maintaining coherence)
- **Context opener:** 0.95-1.0x (slightly slower to establish setup)

**Intentional silence (0.5-1.2 seconds):**
- Insert after each decision cluster (signals topic shift)
- Insert before action items (prepares listener for specifics)
- Never remove all silence within a segment—preserve natural speaker breathing

**Transition cues:**
- Use `crossDissolve` (0.3s) between different speakers or topics within a cluster
- Use `none` (hard cut) only within a single decision or action statement
- Position transitions at energy shifts (speaker changes, topic changes)

This creates rhythm that guides the listener through the narrative without feeling rushed.
```

### Block 4: Expanded Step 4 — Enhanced Verification

**Replace the current Step 4 verification section with this expanded version**

```markdown
## Step 4: Mandatory verification

1. `verify_playback` mode "quick":
   - Audio at all checkpoints
   - Duration within 10% of target (4:30-5:30 for 5-min target)

2. `analyze_audio_energy` on the output:
   - Speech ratio should be > 80% (tight content, no dead air)
   - Engagement score should be > 60

3. **Narrative structure verification:**
   - Does the summary follow a clear arc: context → decision(s) → action(s)?
   - Is each decision preceded by at least 5-10 seconds of supporting discussion or reasoning?
   - Are action items isolated with clear ownership (name + task + deadline)?
   - Do pacing changes align with topic shifts? (Context is calm, decisions clear, actions crisp)

4. **Compression integrity check:**
   - Play back at normal speed. Does it feel coherent, not rushed?
   - Are there 0.5-1.2 second pauses between clusters? (Check with `get_state` markers)
   - Does the audience understand *why* each decision was made, not just *what* was decided?
   - Can a first-time listener identify 3-4 key action items and owners?

5. `get_state`:
   - Every decision/action item has a marker
   - Clips are named with classifications
   - Speed shows on both V+A tracks with strategic variation (decisions/actions at 1.0x)
   - Intentional pauses between clusters (0.5-1.2s)
   - No gaps between segments within clusters

If narrative arc is unclear or decisions lack supporting context, add back 10-15 seconds of discussion
rather than cutting further.

**Never tell the user the summary is ready without verification.**
```

---

## 4. Summary of Changes

| Section | Change Type | Rationale |
|---------|------------|-----------|
| **Pre-Step 0** | Addition: Audience Context | Storytelling principle: Know your audience determines compression ratio and what counts as essential |
| **Step 1.5** | Addition: Narrative Arc | Cuts principle: Maintain complete narrative chains; storytelling principle: intercut discussion with decision |
| **Step 2.5** | Addition: Strategic Pacing | Pacing principle: Variable pacing creates rhythm; intentional silence aids clarity |
| **Step 4** | Expansion: Verification | Adds narrative and compression integrity checks beyond technical metrics |

### Key Principles Applied

1. **From Cuts:** Preserve complete narrative chains; every segment kept must serve a communicative purpose
2. **From Pacing:** Use variable speed strategically (decisions and actions at normal speed, background discussion slightly faster); insert intentional pauses between clusters; match pacing to emotional/narrative intent
3. **From Storytelling:** Structure summaries with three-act arc; intercut reasoning with decisions; know your audience; remove distracting tangents that break the through-line

These additions deepen the skill from pure compression (remove dead air + identify key segments) to **narrative compression** (remove dead air while maintaining why decisions matter and how action items connect to those decisions).
