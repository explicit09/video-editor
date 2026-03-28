# Design System Document: The Cinematic Canvas

## 1. Overview & Creative North Star
**Creative North Star: "The Silent Orchestrator"**

This design system is built to bridge the gap between high-end professional film editing and the fluid, predictive nature of Artificial Intelligence. Unlike traditional editors that clutter the screen with legacy chrome, this system treats the UI as a "Stage" where the content is the protagonist.

We break the "template" look by avoiding rigid, boxed-in grids. Instead, we use **Intentional Asymmetry** and **Tonal Depth**. Navigation and AI tools do not sit *beside* the work; they float *over* or *within* it, using depth and blur to maintain focus. The aesthetic is "Apple Pro" meets "Futuristic Lab"—utilizing high-contrast typography scales and layered surfaces to create a sense of infinite workspace.

---

## 2. Colors & Surface Philosophy

The palette is anchored in deep charcoals and "Electric Indigo," designed to recede into the background of a dimly lit studio while highlighting AI-driven insights.

### Core Palette
- **Background:** `#131313` (The base canvas)
- **Primary (AI Accent):** `primary: #c2c1ff` / `primary_container: #5e5ce6`
- **Functional (Timeline):** `tertiary: #aac7ff` (Blue), `error: #ffb4ab` (Red/Alert), and muted custom greens/purples for clip categorization.

### The "No-Line" Rule
To achieve a premium, editorial feel, **1px solid borders for sectioning are strictly prohibited.**
Structure is defined through **Background Color Shifts**.
- A Timeline (`surface_container_low`) sits on the main Workspace (`surface`).
- An Inspector panel (`surface_container_high`) emerges from the background through color alone.

### Surface Hierarchy & Nesting
Treat the UI as physical layers.
1. **Level 0 (Base):** `surface` (#131313) - The primary application shell.
2. **Level 1 (Sub-Panels):** `surface_container_low` (#1c1b1b) - Media pools and secondary tools.
3. **Level 2 (Active Focus):** `surface_container_high` (#2a2a2a) - Timeline tracks and inspector fields.
4. **Level 3 (Floating AI):** `surface_container_highest` (#353534) - Contextual menus and the Command Bar.

### The "Glass & Gradient" Rule
Main CTAs and AI-generated elements must use the **Signature Glow**. Transitions from `primary` to `primary_container` should be applied to hero buttons to provide a "vibrating" energy. Use backdrop blurs (20px-40px) on any overlay to ensure the video content beneath feels part of the same environment.

---

## 3. Typography: The Editorial Edge

We utilize **Inter** (as a high-performance alternative to SF Pro for cross-platform precision) to maintain a compact, high-density professional look.

| Role | Token | Size | Weight | Usage |
| :--- | :--- | :--- | :--- | :--- |
| **Display** | `display-lg` | 3.5rem | Bold | Hero AI stats or mode transitions. |
| **Headline** | `headline-sm` | 1.5rem | SemiBold | Major panel headers (e.g., "Project Bin"). |
| **Title** | `title-sm` | 1rem | Medium | Clip names, effect titles. |
| **Body** | `body-md` | 0.875rem | Regular | Secondary metadata and AI chat text. |
| **Label** | `label-sm` | 0.6875rem | Bold | Timeline timestamps, keyboard shortcuts. |

**The Hierarchy Rule:** Headlines should be high-contrast (`on_surface`) while body text uses `on_surface_variant` (#c7c4d7) to reduce visual noise during long editing sessions.

---

## 4. Elevation & Depth

### The Layering Principle
Depth is achieved by "stacking" tones. Place a `surface_container_lowest` (#0e0e0e) card on a `surface_container_low` section to create a "recessed" look for input fields.

### Ambient Shadows
For floating AI Command Bars, use **Ambient Shadows**:
- **Blur:** 32px
- **Color:** `primary` at 8% opacity.
- **Result:** A soft, indigo-tinted "aura" that signifies the AI is active and listening.

### The "Ghost Border" Fallback
If visual separation is impossible through tone alone (e.g., overlapping clips), use a **Ghost Border**: `outline_variant` (#464554) at **15% opacity**. Never use 100% opaque lines.

---

## 5. Components

### The AI Command Bar (Signature Component)
The centerpiece of the UI. It is a floating `full` rounded bar using `surface_container_highest` with a 30px backdrop blur.
- **Stroke:** `outline_variant` at 20%.
- **Interaction:** On hover, the border glows with a `primary` gradient.

### Buttons
- **Primary (AI Actions):** Background `primary_container` (#5e5ce6), text `on_primary_container`. 0.375rem (`md`) corner radius.
- **Secondary (Tools):** Background `surface_container_high`, `on_surface` text. No border.

### Timeline Clips
Forbid dividers. Use **Spacing Scale 0.5** (0.1rem) as a "gap" between clips to reveal the `surface_container_lowest` background underneath.
- **Clip Colors:** Use `tertiary_fixed_dim` and `secondary_fixed_dim` for a muted, pro-colorist aesthetic.

### Input Fields
Inputs must be "recessed." Use `surface_container_lowest` with a `sm` (0.125rem) rounded corner. The label sits in `label-sm` style directly above the field, never inside.

---

## 6. Do's and Don'ts

### Do:
- **Do** use `2.5` (0.5rem) as your "standard" padding for tight professional density.
- **Do** use `surface_bright` (#393939) sparingly for subtle hover states on icons.
- **Do** allow video previews to "bleed" into the glass-morphic Command Bar.
- **Do** use asymmetric layouts (e.g., a left-aligned chat with a right-aligned playback monitor) to break the "grid" feel.

### Don't:
- **Don't** use 100% white (#FFFFFF). All text must be at most `on_surface` (#e5e2e1) to prevent eye strain.
- **Don't** use traditional "Drop Shadows" (Black/0,0,0). Always tint shadows with the `primary` token.
- **Don't** use divider lines to separate list items. Use vertical space `1.5` (0.3rem) and subtle background shifts.
- **Don't** use standard OS scrollbars. Use a custom `primary_fixed_dim` (2px width) scroll indicator.

---

## 7. Color Tokens Reference

| Token | Hex | Usage |
|-------|-----|-------|
| `surface` | #131313 | Base canvas |
| `surface_container_low` | #1c1b1b | Sub-panels |
| `surface_container` | #201f1f | Primary panels |
| `surface_container_high` | #2a2a2a | Active focus areas |
| `surface_container_highest` | #353534 | Floating elements |
| `surface_container_lowest` | #0e0e0e | Recessed elements |
| `surface_bright` | #393939 | Hover states |
| `primary` | #c2c1ff | AI accent (light) |
| `primary_container` | #5e5ce6 | AI accent (dark) |
| `secondary` | #c8c6c8 | Neutral content |
| `tertiary` | #aac7ff | Timeline/functional blue |
| `error` | #ffb4ab | Alerts |
| `on_surface` | #e5e2e1 | Primary text |
| `on_surface_variant` | #c7c4d7 | Secondary text |
| `outline` | #918fa0 | Visible outlines |
| `outline_variant` | #464554 | Ghost borders |

---

## 8. Screens

| # | Screen | Description |
|---|--------|-------------|
| 1 | Main Editor | Full workspace — project bin, preview with floating AI bar, multi-track timeline |
| 2 | Empty State | AI-first onboarding — "Ask AI to start a project..." with example prompts |
| 3 | AI Working | AI Orchestrator overlay on preview, AI Insights panel with recommendations |
| 4 | Complex Project | Multi-track (Subtitles, B-Roll, SFX), AI annotations, 4K ProRes badges |
| 5 | Transcript View | Synced transcript with inline AI insights and suggested cut points |
| 6 | Export Flow | AI-recommended presets (YouTube 4K, TikTok/Reels, ProRes), smart analysis |
| 7 | Media Import | Smart Bins (auto-categorized), inspector with codec details, AI tags |
| 8 | AI Search | "Find where I mention..." with thumbnail matches, context, and AI suggestions |
