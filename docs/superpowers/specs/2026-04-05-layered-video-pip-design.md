# Layered Video And PiP Redesign

Date: 2026-04-05
Branch: `codex/timeline-shell-redesign`

## Summary

The editor should support layered video properly, with picture-in-picture as the first polished presentation of that system rather than as a separate special-case feature. A clip placed on a higher video track should render above clips on lower video tracks, remain an ordinary timeline clip, and become directly manipulable in the program monitor. The first milestone should deliver a real overlay workflow with on-canvas controls, inspector controls, snapping, safe margins, crop and mask support, opacity and blend modes, PiP styling, and simple preset entrance and exit animations.

## Goals

- Make higher video tracks composite above lower video tracks predictably.
- Treat PiP as a polished mode of ordinary overlay clips, not a separate object type.
- Let users manipulate overlay clips directly in the program monitor.
- Expose precise overlay controls and PiP presets in the inspector.
- Preserve ordinary timeline editing behavior while making layered clips feel intentional.

## Non-Goals

- Full arbitrary keyframe animation UI in this milestone.
- A separate motion graphics or compositing workspace.
- Deep effects authoring beyond the subset needed for polished layered video and PiP.
- A new timeline object model that splits overlays away from normal video clips.

## Product Scope

The first milestone should feel like a proper editor-grade overlay workflow:

- Clips on higher video tracks render above clips on lower video tracks.
- Overlay clips can be moved and scaled directly in the program monitor.
- The inspector provides numeric controls and polished PiP presets.
- Overlay clips can use crop and mask controls, opacity, and blend modes.
- Overlay clips can use presentation styling such as border, shadow, and corner radius.
- Snapping and safe-margin guides make placement deliberate instead of approximate.
- Simple preset entrance and exit animations are available for PiP-style overlays.

## Architecture

### Layering Model

Layered video should remain based on ordinary video clips on ordinary video tracks:

- Track order defines compositing order.
- Lower video tracks render first.
- Higher video tracks render above them.
- Audio routing remains separate from the visual overlay model.

PiP should not be represented as a different clip type. Instead, an overlay clip remains a standard video clip with additional presentation properties.

### Clip Visual Model

The clip model already carries raw visual controls such as transform, crop, opacity, and blend mode. That foundation should remain. To support polished PiP, add a focused overlay presentation model to the clip that owns styled presentation concerns, separate from the raw transform.

Recommended presentation fields:

- presentation mode
- border visibility and width
- border color
- shadow style
- corner radius
- mask shape
- safe-margin snap preference
- entrance animation preset
- exit animation preset

The separation should be:

- geometric transform controls where the clip sits and how large it is
- presentation controls how that transformed clip is styled and revealed

### Playback And Compositing

Playback should move from implicit multi-track support to explicit layered compositing:

- composite all visible lower tracks first
- apply clip crop or mask before styled decoration
- apply transform and opacity consistently per clip
- composite higher tracks over lower tracks in stable order
- apply PiP decoration after clip image transforms so borders and shadows follow the visible result

The compositor should continue supporting ordinary playback and not require PiP-specific code paths just to render a clip on a higher track.

## Interaction Model

### Timeline

Timeline behavior should remain simple and unsurprising:

- dropping or moving a clip onto a higher video track makes it overlay automatically
- moving a clip between video tracks changes visual layer order
- selecting a layered clip in the timeline selects that same clip for monitor manipulation
- layered clips remain standard timeline clips with standard trim and move behavior

### Program Monitor

The program monitor should become the primary manipulation surface for overlays:

- selected overlay clips show a transform box
- dragging inside the box moves the clip
- corner handles resize proportionally
- snapping works to frame center, edge anchors, and safe margins
- guides appear during manipulation and disappear when interaction ends

The first milestone does not require full arbitrary transform editing. It should support the direct controls needed for polished PiP placement.

### Inspector

The inspector should become the precision and preset surface:

- quick PiP presets:
  - top left
  - top right
  - bottom left
  - bottom right
  - centered inset
  - split-side layout
- numeric position controls
- numeric scale controls
- crop and mask controls
- opacity
- blend mode
- border
- shadow
- corner radius
- entrance animation preset
- exit animation preset

The inspector should update the same clip state used by the program monitor, rather than maintaining a separate PiP configuration object.

## PiP UX Standard

To feel properly done, PiP should have a clear default visual language:

- sensible default inset size
- clean corner placement presets
- visible but restrained shadow options
- rounded corners that work across common video sizes
- border options that are subtle by default
- snapping that avoids awkward almost-aligned placement

Applying a PiP preset should be reversible and should not lock the clip into a special editing mode. Users must still be able to drag, resize, and fine-tune the result afterward.

## Animations

This milestone should support simple preset entrance and exit animations only.

Recommended presets:

- fade in or out
- scale in
- slide in from edge
- slide out to edge

These should be implemented as presentation presets on top of the overlay clip model, not as general-purpose keyframe authoring. Full keyframe animation belongs to a later milestone.

## Delivery Slices

Implementation should proceed in the following slices:

1. Verify and correct true multi-track compositing order.
2. Expose overlay clip selection and direct manipulation in the program monitor.
3. Add inspector presentation controls and PiP presets.
4. Add snapping, safe margins, and simple animation presets.
5. Polish timeline behavior for layered clips and overlay selection.

## Testing

Testing should cover:

- compositing order across multiple video tracks
- correct selection and manipulation of overlay clips
- inspector and monitor editing staying in sync
- PiP preset application producing expected transform and presentation state
- snapping and safe-margin behavior
- overlay clips continuing to play correctly after save and reload

Verification should include both automated tests and manual visual validation in the running app because monitor interaction and compositing behavior are strongly visual.

## Risks

- Compositing order may appear correct in the timeline model but still render incorrectly in the playback compositor.
- Direct monitor manipulation can conflict with existing monitor interactions if hit-testing is not carefully scoped.
- Styling and animation can become tightly coupled to transform logic if presentation state is not separated cleanly.
- Overlay editing can become brittle if inspector edits and monitor edits are not routed through the same clip-owned state.

## Recommendation

Build a general layered-video foundation and ship PiP as the first polished overlay mode on top of it. That gives the editor a real compositing direction instead of a one-off PiP feature, while still keeping the first milestone contained enough to execute and verify properly.
