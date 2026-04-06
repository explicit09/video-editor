# Agent/MCP Tool Parity — Design Spec

## Problem

The video editor exposes capabilities across four surfaces: UI, In-App Agent, MCP Server, and Codebase (EditorIntent + Commands). Agent and MCP share the same 98 tools, but 9 EditorIntent cases and 6 AppState capabilities have no tool — making them unreachable by AI. (A 10th intent, `replacePrimaryClipEffect`, is already covered by `set_clip_effect`.)

Since this is an AI-first editor, Agent/MCP must have complete coverage of all editing capabilities.

## Scope

Add 20 tools to close every gap between Agent/MCP and the codebase. No UI changes. No new EditorIntent cases — all 37 already exist.

Note: `replacePrimaryClipEffect` is already covered by the existing `set_clip_effect` tool (which resolves to `.replacePrimaryClipEffect` internally). No new tool needed for that intent.

### Out of scope

- AudioRecorder (physical user action)
- CrashRecovery (internal/automatic)
- ProxyService (internal optimization)
- WaveformExtractor (UI visualization only)
- Source monitor mark in/out/insert/overwrite (covered by existing insert_clip + add_to_timeline)

---

## The 21 New Tools

### Group A: Intent-Backed (10 tools)

These resolve to existing EditorIntent cases via AIToolResolver.

#### 1. `set_clip_crop`

Set the crop region of a clip. Values are normalized 0-1 relative to source frame.

| Param | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| clip_id | string | yes | — | UUID of the clip |
| x | double | yes | — | Left edge (0-1) |
| y | double | yes | — | Top edge (0-1) |
| width | double | yes | — | Width (0-1) |
| height | double | yes | — | Height (0-1) |

Resolves to: `.setClipCrop(clipID:, cropRect: CropRect(x:, y:, width:, height:))`

Values 0/0/1/1 clear the crop (full frame).

#### 2. `set_clip_blend_mode`

Set how a clip composites over clips below it.

| Param | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| clip_id | string | yes | — | UUID of the clip |
| blend_mode | string | yes | — | One of: normal, multiply, screen, overlay, darken, lighten, colorDodge, colorBurn, softLight, hardLight, difference, exclusion, hue, saturation, color, luminosity, add |

Resolves to: `.setClipBlendMode(clipID:, blendMode:)`

#### 3. `set_clip_overlay_presentation`

Configure how a clip is presented as an overlay (PiP mode, border, shadow, mask).

| Param | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| clip_id | string | yes | — | UUID of the clip |
| mode | string | no | "inline" | "inline" or "pip" |
| pip_x | double | no | 0.65 | Normalized X when mode=pip |
| pip_y | double | no | 0.05 | Normalized Y when mode=pip |
| pip_width | double | no | 0.3 | Normalized width when mode=pip |
| pip_height | double | no | 0.3 | Normalized height when mode=pip |
| border_visible | bool | no | false | Show border |
| border_width | double | no | 2.0 | Border width in points |
| shadow | string | no | "none" | none/light/medium/heavy |
| corner_radius | double | no | 0 | Corner radius (0-50) |
| mask_shape | string | no | "rectangle" | rectangle/roundedRect/circle |

Resolves to: `.setClipOverlayPresentation(clipID:, presentation: OverlayPresentation(...))`

#### 4. `apply_pip_preset`

Quick PiP positioning. Sets overlay mode and snaps to a corner.

| Param | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| clip_id | string | yes | — | UUID of the clip |
| preset | string | yes | — | topLeft, topRight, bottomLeft, bottomRight |

Resolves to: `.applyClipPiPPreset(clipID:, preset:)`

#### 5. `solo_track`

Solo a track (mute all others). Toggle off to restore.

| Param | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| track_id | string | yes | — | UUID of the track |
| soloed | bool | no | true | true to solo, false to unsolo |

Resolves to: `.soloTrack(trackID:, soloed:)`

#### 6. `rename_track`

Rename a track.

| Param | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| track_id | string | yes | — | UUID of the track |
| name | string | yes | — | New track name |

Resolves to: `.renameTrack(trackID:, name:)`

#### 7. `reorder_track`

Move a track to a new position in the stack. Index 0 = bottom.

| Param | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| track_id | string | yes | — | UUID of the track |
| new_index | int | yes | — | Target position (0-based) |

Resolves to: `.reorderTrack(trackID:, newIndex:)`

#### 8. `link_clips`

Link or unlink clips so edits propagate together (e.g. video+audio pair).

| Param | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| clip_ids | string[] | yes | — | UUIDs of clips to link/unlink |
| link | bool | yes | — | true to link, false to unlink |

Resolves to: `.linkClips(clipIDs:, linkGroupID: link ? UUID() : nil)`

When unlinking, sets linkGroupID to nil. When linking, generates a fresh UUID for the group.

#### 9. `remove_clip_effect`

Remove a specific effect from a clip by effect ID.

| Param | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| clip_id | string | yes | — | UUID of the clip |
| effect_id | string | yes | — | UUID of the effect to remove |

Resolves to: `.removeClipEffect(clipID:, effectID:)`

#### 10. `batch`

Execute multiple tool calls as a single undoable operation.

| Param | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| operations | string | yes | — | JSON array of `{"tool": "tool_name", "args": {...}}` objects |

The resolver:
1. Parses the JSON array
2. For each entry, calls `resolve(toolName:arguments:)` recursively
3. Collects all returned intents into a flat array
4. Returns `[.batch(allIntents)]`

Only intent-backed tools are allowed inside batch. AppState tools (undo, redo, playback) are rejected with a clear error.

---

### Group B: AppState-Backed (6 tools)

These call AppState methods directly. They do not go through EditorIntent.

#### 11. `undo`

Undo the last editing action.

No parameters.

Calls `appState.undo()`. Returns description of what was undone.

#### 12. `redo`

Redo the last undone action.

No parameters.

Calls `appState.redo()`. Returns description of what was redone.

#### 13. `play_pause`

Control playback.

| Param | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| action | string | no | "toggle" | "play", "pause", or "toggle" |

Calls `appState.playbackEngine.togglePlayPause()` for toggle, or sets state directly for play/pause. Returns current playback state.

#### 14. `seek`

Move the playhead to a specific time.

| Param | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| time | any | yes | — | Seconds (double), or "start"/"end" as string alias |

- `"start"` resolves to 0
- `"end"` resolves to `timeline.duration`
- Number resolves directly

Calls `appState.playbackEngine.seek(to:)`. Returns new playhead position.

#### 15. `toggle_loop`

Enable or disable playback looping.

| Param | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| enabled | bool | yes | — | true to enable, false to disable |

Sets `appState.playbackEngine.loopEnabled`. Returns current loop state.

#### 16. `get_action_log`

Get recent editing actions for debugging or review.

| Param | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| limit | int | no | 20 | Max entries to return |

Queries `appState.actionLog` for recent entries. Returns compact list: timestamp, action name, source (ai/user), affected IDs.

---

## File Changes

### 1. `AIToolRegistry.swift`

**What:** Add 16 `AIToolDefinition` statics (10 intent-backed + 6 AppState-backed). Append all 16 to `allTools` array.

**Where:** After the existing tool definitions (after line ~688, before `AIToolResolver`).

**Pattern:** Same as existing definitions — static let with name, description, parameters schema.

### 2. `AIToolResolver.resolve()` (inside AIToolRegistry.swift)

**What:** Add 10 new cases to the switch statement for Group A tools. Add 6 `return []` cases for Group B tools (handled upstream).

**Where:** Before the `default:` case at line 1018.

**Pattern:** Same as existing cases — parse args, validate, return `[EditorIntent]`.

New cases:
- `set_clip_crop` → parse x/y/width/height → `.setClipCrop`
- `set_clip_blend_mode` → parse blend_mode string → `.setClipBlendMode`
- `set_clip_overlay_presentation` → build OverlayPresentation → `.setClipOverlayPresentation`
- `apply_pip_preset` → parse preset string → `.applyClipPiPPreset`
- `solo_track` → parse track_id, soloed → `.soloTrack`
- `rename_track` → parse track_id, name → `.renameTrack`
- `reorder_track` → parse track_id, new_index → `.reorderTrack`
- `link_clips` → parse clip_ids, link bool → `.linkClips`
- `remove_clip_effect` → parse clip_id, effect_id → `.removeClipEffect`
- `batch` → recursive resolve → `.batch(allIntents)`
- `undo`, `redo`, `play_pause`, `seek`, `toggle_loop`, `get_action_log` → `return []`

### 3. `AIChatController.swift`

**What:** Add `handlePlaybackTool()` method for the 6 AppState tools. Call it before the MCPServer fallback at line 382.

**Where:** New private method, called from `executeTool()`.

**Handler logic:**
```
undo → try appState.undo(); return "Undone: {description}"
redo → try appState.redo(); return "Redone: {description}"
play_pause → toggle/play/pause on playbackEngine; return state
seek → parse time/aliases; seek; return "Playhead at {time}s"
toggle_loop → set loopEnabled; return state
get_action_log → query actionLog; return formatted entries
```

Also add cases to `describeTool()` for richer agent feedback.

### 4. `MCPServer.swift`

**No changes needed for tool registration.** MCPServer already merges `AIToolRegistry.allTools` at line 114.

**Execution:** For the 6 AppState tools, add handling in the `executeToolForAgent` path — before the `AIToolResolver` fallback at line 833. Same pattern as the existing MCP-only tool handlers.

### 5. `IntentRouter.swift`

**What:** Update keyword sets and tool subsets.

**Tool subset updates:**
- `propertyTools` += `"set_clip_crop"`, `"set_clip_blend_mode"`, `"solo_track"`, `"rename_track"`
- `structuralTools` += `"reorder_track"`, `"link_clips"`, `"remove_clip_effect"`
- New `playbackTools` = `["play_pause", "seek", "toggle_loop", "undo", "redo"]`

**Keyword updates:**
- `propertyKeywords` += `"crop"`, `"blend"`, `"composite"`, `"solo"`, `"unsolo"`
- `structuralKeywords` += `"reorder"`, `"link"`, `"unlink"`, `"group"`, `"ungroup"`
- New `playbackKeywords` = `["undo", "redo", "play", "pause", "stop", "seek", "go to", "jump to", "loop", "rewind"]`

**New routing block** (before property keywords check):
```swift
if matchesAny(lower, keywords: playbackKeywords) {
    return RoutingDecision(tier: .fast, toolSubset: playbackTools)
}
```

Playback tools route to Haiku (fast tier) — these are simple mechanical operations.

---

## What Does NOT Change

- **EditorIntent enum** — all 37 cases already exist
- **Commands** — all command implementations already exist
- **EditorCore package** — no changes
- **UI** — no changes
- **MCPServer tool registration** — automatic via AIToolRegistry merge

---

## Verification

After implementation:
1. Run `swift test` in EditorCore — existing tests must pass
2. Run `xcodebuild test` — full test suite
3. Manual verification: call each of the 21 tools via MCP (`tools/call`) and confirm execution
4. Verify IntentRouter routes new keywords to correct subsets
5. Verify `batch` correctly wraps multiple intents and undoes as one unit
