# Timeline Shell Redesign

Date: 2026-04-05
Status: Approved for planning

## Summary

Redesign the editor around a Resolve-style, timeline-first shell. The center editing surface becomes the dominant workspace, with separate collapsible left and right rails for library/media and inspector/AI. The timeline stops behaving like a single scroll view and becomes a coordinated shell with fixed chrome, synchronized scrolling, denser track headers, stronger readability, and predictable track interactions.

This redesign is architectural and visual. It is not a feature-expansion milestone.

## Problem Statement

The current editor behaves more like a multi-panel dashboard than a professional nonlinear editor:

- the timeline does not dominate the workspace
- sidebars consume too much attention and width
- the timeline shell is structurally weak, especially around ruler/header stability and scrolling
- track headers are oversized and under-informative
- track interactions are not explicit enough for editing at speed
- timeline readability is too soft and low-density

This creates a gap between the engine capabilities and the UI surface that exposes them.

## Goals

- Make the timeline the dominant editing surface
- Keep library/media and inspector/AI in separate, collapsible rails
- Rebuild the timeline as a coordinated shell with fixed toolbar, ruler, and track headers
- Support proper two-axis scrolling with synchronized regions
- Improve scroll-to-playhead and scroll-to-selection behavior
- Redesign track headers for density and clarity
- Improve track interactions: collapse, resize, reorder, add/remove lane, drop targeting
- Increase timeline readability through stronger visual hierarchy
- Keep the redesign modular enough to implement without growing any single file into another monolith

## Non-Goals

- Building a general-purpose docking framework
- Redesigning the app around source/program dual monitors in this milestone
- Expanding editing features unrelated to shell and timeline architecture
- Reworking unrelated media-management or AI workflows beyond their placement in the shell

## Design Principles

- Timeline-first: the center edit surface has priority over all supporting panels
- Fixed chrome, scrolling content: structural UI remains stable while edit content moves
- Density over decoration: controls should be compact, legible, and functional
- Explicit state: targeted tracks, selected clips, and drop destinations must be visually obvious
- Modular composition: shell, ruler, headers, canvas, and coordination state should have clear boundaries

## Target Layout

The editing workspace becomes a fixed three-column shell:

- Left rail: library and media management
- Center column: preview, transport, timeline toolbar, timeline shell
- Right rail: inspector, context, AI tools

The side rails remain separate, as requested, but are subordinate to the center column:

- both rails are collapsible
- collapsing either rail expands the center column immediately
- rails should feel quieter than the center edit surface

The center column should resemble a professional NLE rather than a dashboard:

- preview remains prominent, but more compact than it is today
- the timeline receives materially more height and width
- the timeline visually reads as the main work area
- in the default editing posture, the timeline should own the majority of the center-column height, with the preview occupying the smaller upper share

## Timeline Shell Architecture

The timeline should be restructured into coordinated regions rather than one large scroll container.

### Regions

1. Timeline toolbar row
2. Ruler row
3. Track header column
4. Clip canvas

### Scroll model

- The toolbar remains fixed.
- The ruler remains fixed at the top of the scrolling timeline body.
- Track headers remain fixed at the left side of the scrolling timeline body.
- The clip canvas scrolls horizontally and vertically.
- Horizontal scrolling moves the ruler and clip canvas together.
- Vertical scrolling moves the track headers and clip canvas together.
- The top-left corner block where ruler and headers meet remains stable and intentional.

### Navigation behavior

- Selecting a clip should scroll it into view when it is materially outside the viewport.
- Moving the playhead should keep it visible only when auto-follow is enabled; auto-follow should be explicit rather than always-on.
- Zooming should preserve context around the playhead when no clip is selected, and around the selection when one exists.
- Adding tracks or lanes expands the vertical canvas without breaking alignment.

## Proposed UI Component Boundaries

To keep the redesign modular, the timeline should be decomposed into focused units instead of growing `TimelinePanel.swift` further.

### Shell-level components

- `EditorWorkspaceShell`
  - owns left rail, center editor column, right rail, and rail collapse state
- `TimelineShellView`
  - owns toolbar, ruler/header corner, track headers, clip canvas, and synchronized scroll wiring

### Timeline chrome components

- `TimelineToolbarView`
  - timeline actions, view controls, snap/ripple/link states, zoom entry points
- `TimelineRulerView`
  - time scale, markers, playhead scrub interaction, visible-range rendering
- `TimelineCornerView`
  - stable top-left block for track/global controls

### Track-region components

- `TrackHeaderColumnView`
  - renders visible track headers aligned to track rows
- `TrackHeaderRowView`
  - compact track strip with track identity and controls
- `TimelineCanvasView`
  - renders clips, gaps, overlays, waveforms, selection state, drop previews

### Coordination state

- `TimelineScrollCoordinator`
  - authoritative horizontal and vertical offsets
  - keeps ruler/header/canvas synchronized
- `TimelineViewportState`
  - visible time range, visible track range, zoom scale, auto-follow behavior
- `TrackLayoutState`
  - track heights, collapsed state, lane presentation, reorder/drop preview state

These names are design-level targets, not a requirement to match exact type names. The important part is separation of concerns.

## Track Header Redesign

Track headers should change from padded cards into compact functional strips.

### Required information and controls

- track type and name
- mute
- solo
- lock
- target/armed state
- collapse/expand
- height mode
- lane count or lane-management entry point
- reorder affordance

### Behavior

- Collapsing a track reduces it to a compact strip while retaining key controls.
- Resizing a track changes presentation density but does not destabilize row alignment.
- Reordering uses a clear drag handle and insertion indicator.
- Add/remove lane actions are surfaced from the track header instead of scattered controls.
- Drop targeting shows destination track and lane before release.

Targeting should be a first-class visual state. A track that is the active edit destination must look armed, not merely selected.

## Layout And Proportion Rules

The redesign should deliberately rebalance the screen:

- give the timeline significantly more vertical space than the current layout
- keep the preview visible and useful, but not oversized
- reduce the visual weight and padding of both side rails
- avoid large card surfaces competing with timeline content

The center column should remain stable as rails collapse or expand. Rail visibility should not force the timeline shell to recompose unpredictably.

## Readability And Visual Hierarchy

The timeline visual language should move toward higher density and stronger contrast.

### Required improvements

- stronger ruler tick hierarchy and more legible time labels
- higher-contrast playhead line and clearer playhead cap
- more obvious selected-clip treatment
- clearer clip boundaries and trim handles
- stronger waveform visibility and consistency
- clearer markers and edit boundaries
- subtle but effective track separators

### Visual posture

- the timeline should look operational, not ornamental
- controls should be smaller, clearer, and more purposeful
- neutral background surfaces should support scanning rather than calling attention to themselves

## Interaction Model

The shell redesign must support the following interaction outcomes:

- reliable two-axis scrolling
- fixed ruler and fixed track headers
- scroll-to-selection
- optional scroll-to-playhead
- clear drag-and-drop insertion feedback
- predictable collapse/expand behavior
- predictable lane growth when tracks become more complex

The design assumes professional-editor interaction norms: fast scanning, low ambiguity, and immediate feedback.

## State And Data Flow Constraints

The redesign must respect existing editor architecture:

- editor mutations still flow through `EditorIntent -> Command -> Execute`
- visual layout state should remain separate from editing-domain state
- shell state, viewport state, and track layout state should not be mixed into clip-edit commands

This milestone is primarily a UI architecture change. It should expose engine capabilities better, but not entangle layout logic with editing logic.

## Testing Strategy

### Unit and logic tests

- scroll coordination behavior
- viewport calculations for visible time and visible tracks
- track layout calculations for collapsed and expanded states
- selection and playhead visibility heuristics

### UI and interaction verification

- ruler remains stable while horizontal scrolling
- track headers remain aligned while vertical scrolling
- clip canvas alignment survives rail collapse/expand
- reorder and drop targeting remain visually accurate
- timeline remains usable with many tracks and lanes

### Regression focus

- no direct state mutation bypassing command architecture
- no broken selection, playhead scrubbing, or zoom behavior
- no timeline/header misalignment when resizing or changing track density

## Delivery Boundary

This redesign is complete when:

- the editor presents a clear timeline-first shell
- left and right rails remain separate but supporting
- the timeline has fixed chrome with synchronized scrolling
- track headers are compact, clear, and operationally useful
- scrolling, selection, targeting, and readability feel like a real editor rather than a prototype

This redesign is not complete merely because the visuals change. The shell must be structurally correct.

## Recommended Implementation Decomposition

This work should be planned as a bounded architecture refactor, not a single-file rewrite.

1. Introduce the new workspace shell layout and center-column proportions.
2. Split the timeline into shell regions with shared scroll coordination.
3. Rebuild track headers and track layout behavior.
4. Apply the readability and visual language pass on the new structure.
5. Verify alignment, scrolling, and navigation behavior under realistic track counts.

This order preserves momentum while keeping the redesign grounded in structural correctness.
