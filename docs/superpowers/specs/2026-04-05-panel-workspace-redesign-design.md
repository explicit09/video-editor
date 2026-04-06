# Panel Workspace Redesign

Date: 2026-04-05
Status: Approved in conversation, pending written-spec review

## Summary

Redesign the application from a custom fixed-shell editor into a professional panel-based nonlinear editor. The new baseline should be closer to Premiere and Resolve in structure and behavior: a top workspace/page bar, dual monitors in `Edit`, drag-and-drop docking, denser utility-first controls, workspace-specific persisted layouts, and a full replacement of the current cinematic component language.

This is a product-level UI architecture change. It covers `Edit`, `Media`, `Transcript`, `AI`, and `Deliver`, but implementation should proceed incrementally with verification after each slice.

## Problem Statement

The current UI has drifted into an awkward middle ground:

- it is not dense enough to feel like a serious editor
- it is not responsive enough to survive resizing gracefully
- its navigation consumes too much space relative to editing content
- selection behavior does not match editor expectations
- supporting panels behave like decorative cards instead of tools
- workspace composition is hardcoded instead of being driven by a reusable layout model

The screenshots highlighted fundamental UX failures, not just visual roughness:

- a normal clip click can resolve into batch selection because linked-clip behavior is being applied too aggressively
- narrow rails compress controls into unreadable, low-quality arrangements
- the workspace switcher wastes space that should belong to editing tools
- multi-selection, inspector posture, and zoom behavior do not match professional editor norms

The app therefore needs a broader redesign than the current timeline-shell work alone.

## Goals

- Replace the fixed-shell editor layout with a true dockable panel system
- Replace the current cinematic UI language with a denser utilitarian design system
- Move workspace switching to a top page bar
- Introduce dual monitors in `Edit` with separate source and program panels
- Support drag-and-drop panel docking, tabbing, splitting, resizing, collapse, and restore
- Persist layouts per workspace, with workspace-specific defaults and reset actions
- Rebuild all major workspaces on top of the same layout engine
- Correct editor behavior problems, especially selection semantics and inspector posture
- Make resizing preserve usability through minimum panel sizes and reflow rules
- Implement step by step with verification after each milestone

## Non-Goals

- Matching Premiere or Resolve pixel-for-pixel
- Rewriting the editing engine or command pipeline
- Bundling unrelated feature expansion into the redesign
- Building an unrestricted floating-window system in the first milestone
- Preserving the cinematic design language as a compatibility goal

## Product Decisions

The redesign is anchored to the following approved product decisions:

- top workspace/page bar instead of the current left workspace rail
- dual-monitor editing in `Edit`
- drag-and-drop docking, not fixed dock regions only
- AI closed by default until explicitly opened
- full replacement of the current cinematic visual system
- workspace-specific persisted layouts
- all workspaces covered by the architecture, rebuilt incrementally with verification

## Design Principles

- Tool-first, not chrome-first: editing tools own the screen, not branded surfaces
- Density without confusion: more information and controls, but grouped clearly
- Explicit state: focused panel, selected clip, active track, and target destination must all be obvious
- Resilience under resize: panels must stay usable as the window changes size
- Workspace purpose: each workspace should optimize for a job, not be a weak variation of one global shell
- Shared architecture: the same panel engine and design system should power every workspace
- Behavioral correctness over visual polish: selection, docking, focus, and reveal behavior matter more than styling

## Target Architecture

The current workspace composition in [ContentView.swift](/Users/explicit/Projects/video-editor/.worktrees/timeline-shell-redesign/VideoEditor/VideoEditor/UI/Layout/ContentView.swift) should be replaced by a dedicated panel-layout subsystem.

### Core layout model

- `PanelDefinition`
  - stable identity, title, icon, default sizing hints, allowed dock behaviors
- `PanelInstance`
  - concrete instance state for a panel in a workspace
- `DockLayoutNode`
  - recursive tree representing split containers and tab stacks
- `DockWorkspaceLayout`
  - persisted layout payload for a given workspace
- `WorkspaceLayoutStore`
  - loading, saving, validating, resetting, and migrating layouts
- `DockingCoordinator`
  - drag state, hover targets, drop previews, active tab, focus, and docking commands
- `PanelHost`
  - renders the dock tree and resolves panel definitions into views

### Required behaviors

- drag a panel tab to redock into another stack
- drag a panel to split left/right/top/bottom relative to another panel
- tab multiple panels into a shared dock region
- resize split regions
- collapse or hide panels
- reopen hidden panels from a panel/menu registry
- persist layout per workspace
- restore workspace defaults if saved layouts become invalid

### Explicit non-requirements for phase one

- floating detached windows
- cross-window docking
- arbitrary monitor placement outside the main app window

Those can be added later, but the first redesign should stay inside one main application window.

## Workspace Model

Each workspace should have its own default panel layout, but every layout should be built from the same panel inventory and docking rules.

### Edit

The default `Edit` workspace should use the industry-standard editing posture:

- top center: source monitor and program monitor
- lower center: dominant timeline
- left side: project/media bin and effects/tools
- right side: inspector
- transcript/search available as dockable secondary panels
- AI hidden by default, openable as a docked utility panel

This workspace should optimize for clip inspection, rough cutting, trimming, track work, and playback.

### Media

The `Media` workspace should shift emphasis toward browsing and ingest:

- large project bin/browser
- metadata and source inspection nearby
- source-focused viewing
- import and organization tools prominent
- timeline accessible, but subordinate

### Transcript

The `Transcript` workspace should make transcript work primary without disconnecting it from editorial context:

- transcript/search panel dominant
- source or program viewer available
- timeline still visible
- inspector and result actions nearby

### AI

The `AI` workspace should not be a separate app mode in spirit. It should be a dock layout where AI is primary:

- large AI/chat panel
- current media, timeline, and inspector still accessible as supporting panels
- search results, transcript results, and generated actions can dock adjacent to the AI surface

### Deliver

The `Deliver` workspace should prioritize output management:

- export queue / export dialog surface
- render settings / preset management
- final program viewer
- project summary and readiness diagnostics

## Workspace Persistence Strategy

Industry behavior is best approximated by workspace-specific layout persistence:

- each workspace has its own default layout
- each workspace remembers user-customized docking and visibility
- users can reset a workspace to defaults
- panel changes across releases should be validated on load
- invalid or stale layouts should degrade safely by restoring defaults or reinserting missing panels

This is better than one global layout because the jobs are materially different across workspaces.

## Panel Inventory

The panel system should start with a clear set of first-class panels:

- `ProjectBinPanel`
- `SourceMonitorPanel`
- `ProgramMonitorPanel`
- `TimelinePanel`
- `InspectorPanel`
- `TranscriptPanel`
- `SearchResultsPanel`
- `AIPanel`
- `EffectsPanel`
- `DeliverPanel`
- `ProjectBrowserPanel`
- `SettingsPanel`

Not every panel needs to be visible in every workspace, but all should be registrable and recoverable through the same system.

## Selection And Editing UX Rules

The redesign must correct selection behavior as a first-class product rule.

### Clip selection

- single click selects one clip only
- shift-click or modifier-click performs multi-select
- linked clips should be indicated as related, not force-selected on ordinary click
- explicit commands can select linked groups when needed
- primary selection should be stable and inspectable

The current behavior in [AppState.swift](/Users/explicit/Projects/video-editor/.worktrees/timeline-shell-redesign/VideoEditor/VideoEditor/App/AppState.swift), where a normal click can replace selection with the whole linked group, should be redesigned so linked relationships augment selection instead of hijacking it.

### Inspector behavior

- one selected clip: clip inspector
- one selected track: track inspector
- multiple selected clips: concise batch inspector with primary item emphasis
- no selection: project or workspace inspector

Multi-selection should not overwhelm the right side with oversized generic cards. The inspector should stay useful at a glance.

### Focus rules

- exactly one panel is keyboard-focused at a time
- focused panel should be visually clear
- shortcuts should route based on focus and editing context
- docking and tab switching should preserve focus intentionally

## Docking Interaction Model

Docking should behave like editor software, not like a generic settings dashboard.

### Required interaction states

- visible drop zones during drag
- preview of split direction before drop
- preview of tab insertion when docking into a tab stack
- cancel path when drag leaves valid zones
- panel tab drag affordance with clear grab target
- minimum readable panel sizes
- overflow handling for tab strips with too many panels

### Resize rules

- split panes should enforce minimum sizes
- controls should reflow before they become unreadable
- labels may collapse to icons where appropriate
- panels with hard usability minimums should stop shrinking further

This is especially important for the issues shown in the screenshots, where library controls and navigation surfaces compress into poor-quality layouts instead of preserving readable structure.

## Visual System Replacement

The current cinematic visual system should be replaced, not merely toned down.

### New visual posture

- flatter surfaces
- tighter spacing
- reduced gradient/glow treatment
- smaller controls
- more neutral, utilitarian backgrounds
- higher functional contrast where state matters
- panel chrome that reads like a tool, not a card

### Component requirements

- compact workspace/page bar across the top
- professional tab strips for docked panels
- denser panel headers with practical controls
- smaller action buttons and pills
- inspector sections that read as utility groups, not floating feature cards
- track headers and timeline controls aligned to professional editor density

The redesign should not preserve the old look as a fallback target. Existing cinematic components may be reused internally if practical, but the public visual result should move to a different utility-first system.

## Responsive Layout Rules

Responsiveness should be defined around preserving editor usability, not shrinking everything proportionally.

### Required rules

- panel minimum widths and heights by type
- header/control reflow behavior for constrained panels
- icon-only fallback states where appropriate
- tab truncation rules for narrow stacks
- hide/show behavior for low-priority panels before destroying core editing space
- consistent reveal/restore for hidden panels

The top workspace bar should remain compact and stable as width changes. The old oversized left workspace rail should be removed from the main shell.

## Dual-Monitor Editing Layout

The `Edit` workspace should adopt separate source and program monitors.

### Source monitor responsibilities

- browse selected media or source context
- mark in/out
- prepare source-side edits
- inspect source clip data independently of timeline state

### Program monitor responsibilities

- preview current timeline/program output
- reflect playhead and sequence state
- host overlays relevant to the active edit

This split is necessary because a professional panel-based editor is not just a prettier single-viewer app. It supports source preparation and timeline evaluation as distinct tasks.

## Migration Strategy

The redesign should be implemented in verified slices while keeping one architecture in scope.

### Phase 1: Docking foundation

- panel definitions
- dock layout tree
- panel host
- docking coordinator
- workspace layout persistence
- top workspace/page bar
- new utility-first chrome primitives

Verification:

- layout persistence tests
- dock tree serialization tests
- drag/drop target resolution tests
- minimum-size enforcement tests

### Phase 2: Edit workspace rebuild

- dual monitors
- timeline panel integration
- project bin and inspector docking
- corrected selection semantics
- AI hidden by default, openable as docked panel

Verification:

- selection behavior tests
- resize behavior checks
- dock/restore tests
- manual screenshot comparison against design targets

### Phase 3: Media workspace rebuild

- media-focused default dock layout
- import and metadata UX cleanup
- source-monitor integration

Verification:

- import flow checks
- thumbnail loading checks
- constrained-width panel behavior checks

### Phase 4: Transcript and AI workspace rebuild

- transcript-first layout
- AI-first layout
- docked result panels and inspector integration

Verification:

- transcript selection and reveal checks
- AI panel open/close/focus checks

### Phase 5: Deliver workspace rebuild

- export/deliver dock layout
- output settings and queue integration

Verification:

- export dialog flow
- readiness and completion state checks

## Testing Strategy

### Unit and state tests

- dock tree creation and mutation
- split/tab operations
- layout persistence and migration
- panel visibility restoration
- selection semantics for single, multi, and linked clips

### UI behavior verification

- panel drag and dock previews
- tab strip overflow behavior
- minimum readable sizes under resize
- workspace switching and layout restoration
- monitor, timeline, and inspector composition in `Edit`

### Regression checks

- media thumbnail loading
- preview quality selection between source and proxy media
- transcript/search visibility and workspace behavior
- export and deliver flow
- command shortcuts relative to focused panels

### Visual verification

- screenshot checkpoints for each rebuilt workspace
- side-by-side comparison against layout targets
- manual checks for compressed controls, unreadable labels, and broken spacing

## Risks And Mitigations

### Risk: architecture sprawl

A docking system can easily become a monolith.

Mitigation:

- isolate panel model, persistence, drag logic, and rendering responsibilities
- avoid putting docking logic directly into feature panels
- keep panel views focused on content, not layout orchestration

### Risk: regressions while replacing the shell

Layout rewrites can unintentionally break working editor flows.

Mitigation:

- stepwise implementation with explicit verification gates
- preserve focused tests for media management, preview quality, and selection behavior
- avoid mixing unrelated feature work into the redesign

### Risk: resizing edge cases

Professional panel systems fail visibly when minimum sizes are not respected.

Mitigation:

- define panel-specific constraints up front
- test narrow widths deliberately
- prioritize reflow and collapse rules early

## Open Questions Resolved In Design

- Visual language: replace current cinematic system
- Workspace switching: top page bar
- Editor monitors: dual source/program
- AI default posture: closed until opened
- Layout persistence: workspace-specific
- Scope: all workspaces architecturally, rebuilt incrementally with verification

## Implementation Boundary

This spec defines the target architecture and UX model. It does not require rebuilding every workspace in one code change. The implementation should follow the phased plan above, but each phase must move the application toward the same final panel-based system rather than producing temporary one-off shells.
