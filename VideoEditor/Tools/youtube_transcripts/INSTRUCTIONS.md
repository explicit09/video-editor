# YouTube Knowledge Extraction — Instructions for Claude

You are extracting professional video editing knowledge from YouTube tutorial transcripts to improve a video editor's AI skills. Read this entire file before starting.

## Goal

Turn raw tutorial transcripts into a structured knowledge base that teaches Claude Code how to make better editing decisions. This is NOT about tuning code parameters — it's about giving the AI pro-level reasoning and judgment.

## What's In This Folder

```
youtube_transcripts/
├── INSTRUCTIONS.md          ← You are here
├── transcripts/             ← 65 raw transcript .txt files
├── knowledge/
│   ├── categories/          ← OUTPUT: one .md file per category (you create these)
│   └── skill-updates/       ← OUTPUT: one .md file per skill with suggested additions
└── current-skills/          ← REFERENCE: copies of the current SKILL.md files (read-only)
```

## Process

### Stage 1: Summarize (per transcript)

For each transcript in `transcripts/`, mentally extract ONLY the editing principles, reasoning, and advice. Ignore:
- Software-specific UI instructions ("click the color tab", "drag the node here")
- Banter, intros, outros, sponsor reads
- Product-specific features that only exist in DaVinci Resolve / Premiere Pro / After Effects

Keep:
- WHY decisions are made ("I cut here because the energy drops")
- Universal editing principles ("always cut on action")
- Rules of thumb ("silence longer than 1.5s kills pacing in short-form")
- Context-dependent advice ("for interviews, keep breathing room; for montages, cut tight")
- Creative reasoning ("warm highlights + cool shadows creates depth")

### Stage 2: Categorize

Write one markdown file per category into `knowledge/categories/`. Use these categories:

| File | What goes here |
|------|---------------|
| `cuts.md` | When/where/how to cut. Cut on action, J/L cuts, match cuts, jump cuts. Timing. |
| `pacing.md` | Rhythm, speed, silence handling, energy curves. Content-type-specific pacing rules. |
| `audio.md` | Levels, ducking, cleanup, music mixing, filler removal, breath handling. |
| `color.md` | Grading philosophy, correction vs grading, looks, skin tones, scopes, contrast. |
| `hooks.md` | Opening moments, cold opens, retention strategies, first-3-seconds rules. |
| `transitions.md` | When to use cuts vs dissolves vs wipes. Motivated transitions. Speed ramps. |
| `storytelling.md` | Narrative structure, arcs, episode structure, segment ordering, emotional flow. |
| `platform.md` | Platform-specific rules (YouTube, Shorts, TikTok, Reels). Format, length, captions. |
| `organization.md` | Project setup, bin structure, naming, workflow efficiency, proxy workflows. |
| `broll.md` | When to cut to b-roll, how long, matching energy, types of b-roll. |
| `composition.md` | Framing, reframing for vertical, rule of thirds, headroom, eye-line. |

If a transcript has nothing useful for a category, skip it. If you find knowledge that doesn't fit any category, create a new one.

### Category File Format

Each category file should follow this structure:

```markdown
# Category Name

## Rules

Context-dependent rules. Each rule should say WHEN it applies.

### Rule: [short name]
- **Applies to:** [content type — podcast / interview / montage / shorts / all]
- **Rule:** [the actual principle]
- **Reasoning:** [why this works]

### Rule: [short name]
...

## Tips

Less definitive guidance — useful but situational.

- [tip]
- [tip]
```

### Stage 3: Skill Updates

For each skill in `current-skills/`, read the current SKILL.md and the relevant category files. Write a file into `knowledge/skill-updates/` named `{skill-name}-updates.md` that contains:

1. What knowledge from the categories is relevant to this skill
2. Specific additions or changes to suggest for the SKILL.md
3. The actual text blocks to insert, clearly marked with where they should go

#### Skills to update:

| Skill | Relevant categories |
|-------|-------------------|
| `auto-cutter` | cuts, pacing, audio |
| `beat-sync-editor` | cuts, pacing, transitions |
| `meeting-highlights` | cuts, pacing, storytelling |
| `pacing-optimizer` | pacing, cuts, audio |
| `podcast-editor` | audio, pacing, cuts |
| `podcast-episode-producer` | storytelling, audio, pacing, hooks |
| `rough-cut-assembler` | cuts, organization, storytelling |
| `shorts-formatter` | hooks, platform, pacing, composition |
| `viral-clip-extractor` | hooks, pacing, storytelling, platform |

## Guidelines

- **No attribution needed.** Just clean rules.
- **Context-dependent rules.** When pros disagree, keep both opinions tagged with when each applies (e.g., "for podcasts: X; for montages: Y").
- **Be specific.** "Good pacing matters" is useless. "For talking-head content, silence gaps over 1.2s lose viewer attention" is useful.
- **Reasoning matters.** Always include WHY, not just WHAT. The AI needs to understand the principle to apply it in novel situations.
- **Deduplicate.** If 5 people say the same thing, write it once. If they say slightly different versions, pick the most complete one.
- **Quality over quantity.** 30 great rules per category beats 100 mediocre ones.
