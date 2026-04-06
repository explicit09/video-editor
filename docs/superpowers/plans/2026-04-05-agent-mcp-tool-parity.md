# Agent/MCP Tool Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add 16 missing tools to AIToolRegistry so Agent and MCP have complete coverage of all editing capabilities.

**Architecture:** All 10 intent-backed tools get definitions in AIToolRegistry + resolver cases in AIToolResolver. All 6 AppState-backed tools get definitions in AIToolRegistry + handler methods in AIChatController and MCPServer. IntentRouter gets updated subsets and keywords. MCP picks up new tools automatically via the existing merge at MCPServer line 114.

**Tech Stack:** Swift, AIServices package, EditorCore types

**Spec:** `docs/superpowers/specs/2026-04-05-agent-mcp-tool-parity-design.md`

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `VideoEditor/Packages/AIServices/Sources/AIServices/Tools/AIToolRegistry.swift` | Modify | 16 new tool definitions + 16 new resolver cases |
| `VideoEditor/Packages/AIServices/Sources/AIServices/Routing/IntentRouter.swift` | Modify | New keyword sets + tool subsets |
| `VideoEditor/VideoEditor/App/AIChatController.swift` | Modify | AppState tool handlers + describeTool cases |
| `VideoEditor/VideoEditor/App/MCPServer.swift` | Modify | AppState tool handlers in executeToolForAgent |
| `VideoEditor/Packages/AIServices/Tests/AIServicesTests/AIServicesTests.swift` | Modify | Tests for all 16 new resolver cases |

---

### Task 1: Tool Definitions — Clip Properties (3 tools)

**Files:**
- Modify: `VideoEditor/Packages/AIServices/Sources/AIServices/Tools/AIToolRegistry.swift:8-69` (allTools array)
- Modify: `VideoEditor/Packages/AIServices/Sources/AIServices/Tools/AIToolRegistry.swift:~688` (before AIToolResolver)
- Test: `VideoEditor/Packages/AIServices/Tests/AIServicesTests/AIServicesTests.swift`

- [ ] **Step 1: Write failing tests for set_clip_crop, set_clip_blend_mode, remove_clip_effect**

Add to `AIServicesTests.swift` after the existing `visualEffectToolResolution` test:

```swift
@MainActor
@Test("Clip property tools resolve to correct intents")
func clipPropertyToolResolution() throws {
    let resolver = AIToolResolver()
    let clipID = UUID()

    // set_clip_crop
    let cropIntents = try resolver.resolve(toolName: "set_clip_crop", arguments: [
        "clip_id": clipID.uuidString,
        "x": 0.1,
        "y": 0.2,
        "width": 0.5,
        "height": 0.6,
    ])
    #expect(cropIntents.count == 1)
    if case .setClipCrop(let id, let crop) = cropIntents[0] {
        #expect(id == clipID)
        #expect(crop.x == 0.1)
        #expect(crop.y == 0.2)
        #expect(crop.width == 0.5)
        #expect(crop.height == 0.6)
    } else {
        Issue.record("set_clip_crop should resolve to setClipCrop")
    }

    // set_clip_blend_mode
    let blendIntents = try resolver.resolve(toolName: "set_clip_blend_mode", arguments: [
        "clip_id": clipID.uuidString,
        "blend_mode": "multiply",
    ])
    #expect(blendIntents.count == 1)
    if case .setClipBlendMode(let id, let mode) = blendIntents[0] {
        #expect(id == clipID)
        #expect(mode == .multiply)
    } else {
        Issue.record("set_clip_blend_mode should resolve to setClipBlendMode")
    }

    // remove_clip_effect
    let effectID = UUID()
    let removeIntents = try resolver.resolve(toolName: "remove_clip_effect", arguments: [
        "clip_id": clipID.uuidString,
        "effect_id": effectID.uuidString,
    ])
    #expect(removeIntents.count == 1)
    if case .removeClipEffect(let cid, let eid) = removeIntents[0] {
        #expect(cid == clipID)
        #expect(eid == effectID)
    } else {
        Issue.record("remove_clip_effect should resolve to removeClipEffect")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd VideoEditor/Packages/EditorCore && swift test 2>&1 | tail -5`
Then: `cd VideoEditor && xcodebuild -scheme VideoEditor -destination 'platform=macOS' test 2>&1 | grep -E "Test.*passed|Test.*failed|error:"`

Expected: FAIL — "Unknown tool: set_clip_crop"

- [ ] **Step 3: Add tool definitions to AIToolRegistry**

In `AIToolRegistry.swift`, add these three statics before the `// MARK: - AIToolResolver` comment (around line 688). Also add them to the `allTools` array (lines 8-69).

```swift
// MARK: - Clip property tools (new parity tools)

public static let setClipCrop = AIToolDefinition(
    name: "set_clip_crop",
    description: "Set the crop region of a clip. Values are normalized 0-1 relative to source frame. Use x=0, y=0, width=1, height=1 to clear crop (full frame).",
    parameters: .object([
        "clip_id": .init(type: "string", description: "UUID of the clip"),
        "x": .init(type: "number", description: "Left edge (0-1)"),
        "y": .init(type: "number", description: "Top edge (0-1)"),
        "width": .init(type: "number", description: "Width (0-1)"),
        "height": .init(type: "number", description: "Height (0-1)"),
    ], required: ["clip_id", "x", "y", "width", "height"])
)

public static let setClipBlendMode = AIToolDefinition(
    name: "set_clip_blend_mode",
    description: "Set how a clip composites over clips below it.",
    parameters: .object([
        "clip_id": .init(type: "string", description: "UUID of the clip"),
        "blend_mode": .init(type: "string", description: "Blend mode", enumValues: [
            "normal", "multiply", "screen", "overlay", "darken", "lighten",
            "colorDodge", "colorBurn", "softLight", "hardLight", "difference",
            "exclusion", "hue", "saturation", "color", "luminosity", "add",
        ]),
    ], required: ["clip_id", "blend_mode"])
)

public static let removeClipEffect = AIToolDefinition(
    name: "remove_clip_effect",
    description: "Remove a specific effect from a clip by effect ID. Use get_state to find effect IDs.",
    parameters: .object([
        "clip_id": .init(type: "string", description: "UUID of the clip"),
        "effect_id": .init(type: "string", description: "UUID of the effect to remove"),
    ], required: ["clip_id", "effect_id"])
)
```

Add to `allTools` array:
```swift
setClipCrop,
setClipBlendMode,
removeClipEffect,
```

- [ ] **Step 4: Add resolver cases in AIToolResolver.resolve()**

In the `resolve()` switch, before the `default:` case:

```swift
case "set_clip_crop":
    guard let clipIDStr = arguments["clip_id"] as? String, let clipID = UUID(uuidString: clipIDStr) else {
        throw AIToolError.invalidArgument("Missing or invalid clip_id")
    }
    guard let x = arguments["x"] as? Double,
          let y = arguments["y"] as? Double,
          let width = arguments["width"] as? Double,
          let height = arguments["height"] as? Double else {
        throw AIToolError.invalidArgument("Missing x, y, width, or height")
    }
    return [.setClipCrop(clipID: clipID, cropRect: CropRect(x: x, y: y, width: width, height: height))]

case "set_clip_blend_mode":
    guard let clipIDStr = arguments["clip_id"] as? String, let clipID = UUID(uuidString: clipIDStr) else {
        throw AIToolError.invalidArgument("Missing or invalid clip_id")
    }
    guard let modeStr = arguments["blend_mode"] as? String, let mode = BlendMode(rawValue: modeStr) else {
        throw AIToolError.invalidArgument("Missing or invalid blend_mode")
    }
    return [.setClipBlendMode(clipID: clipID, blendMode: mode)]

case "remove_clip_effect":
    guard let clipIDStr = arguments["clip_id"] as? String, let clipID = UUID(uuidString: clipIDStr) else {
        throw AIToolError.invalidArgument("Missing or invalid clip_id")
    }
    guard let effectIDStr = arguments["effect_id"] as? String, let effectID = UUID(uuidString: effectIDStr) else {
        throw AIToolError.invalidArgument("Missing or invalid effect_id")
    }
    return [.removeClipEffect(clipID: clipID, effectID: effectID)]
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd VideoEditor/Packages/EditorCore && swift test 2>&1 | tail -5`

Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add VideoEditor/Packages/AIServices/Sources/AIServices/Tools/AIToolRegistry.swift VideoEditor/Packages/AIServices/Tests/AIServicesTests/AIServicesTests.swift
git commit -m "feat(tools): add set_clip_crop, set_clip_blend_mode, remove_clip_effect tools"
```

---

### Task 2: Tool Definitions — Overlay Presentation (2 tools)

**Files:**
- Modify: `VideoEditor/Packages/AIServices/Sources/AIServices/Tools/AIToolRegistry.swift`
- Test: `VideoEditor/Packages/AIServices/Tests/AIServicesTests/AIServicesTests.swift`

- [ ] **Step 1: Write failing tests for set_clip_overlay_presentation and apply_pip_preset**

```swift
@MainActor
@Test("Overlay presentation tools resolve correctly")
func overlayPresentationToolResolution() throws {
    let resolver = AIToolResolver()
    let clipID = UUID()

    // set_clip_overlay_presentation
    let overlayIntents = try resolver.resolve(toolName: "set_clip_overlay_presentation", arguments: [
        "clip_id": clipID.uuidString,
        "mode": "pip",
        "shadow": "heavy",
        "corner_radius": 12.0,
        "mask_shape": "roundedRect",
        "border_visible": true,
        "border_width": 3.0,
    ])
    #expect(overlayIntents.count == 1)
    if case .setClipOverlayPresentation(let id, let pres) = overlayIntents[0] {
        #expect(id == clipID)
        #expect(pres.mode == .pip)
        #expect(pres.shadow == .heavy)
        #expect(pres.cornerRadius == 12.0)
        #expect(pres.maskShape == .roundedRect)
        #expect(pres.border.isVisible == true)
        #expect(pres.border.width == 3.0)
    } else {
        Issue.record("set_clip_overlay_presentation should resolve to setClipOverlayPresentation")
    }

    // apply_pip_preset
    let pipIntents = try resolver.resolve(toolName: "apply_pip_preset", arguments: [
        "clip_id": clipID.uuidString,
        "preset": "bottomRight",
    ])
    #expect(pipIntents.count == 1)
    if case .applyClipPiPPreset(let id, let preset) = pipIntents[0] {
        #expect(id == clipID)
        #expect(preset == .bottomRight)
    } else {
        Issue.record("apply_pip_preset should resolve to applyClipPiPPreset")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd VideoEditor/Packages/EditorCore && swift test 2>&1 | tail -5`

Expected: FAIL — "Unknown tool: set_clip_overlay_presentation"

- [ ] **Step 3: Add tool definitions**

```swift
public static let setClipOverlayPresentation = AIToolDefinition(
    name: "set_clip_overlay_presentation",
    description: "Configure how a clip is presented as an overlay. Set mode to 'pip' for picture-in-picture, 'inline' for normal. Control border, shadow, corner radius, and mask shape.",
    parameters: .object([
        "clip_id": .init(type: "string", description: "UUID of the clip"),
        "mode": .init(type: "string", description: "'inline' (default) or 'pip'", enumValues: ["inline", "pip"]),
        "border_visible": .init(type: "boolean", description: "Show border (default false)"),
        "border_width": .init(type: "number", description: "Border width in points (default 2)"),
        "shadow": .init(type: "string", description: "Shadow style", enumValues: ["none", "light", "medium", "heavy"]),
        "corner_radius": .init(type: "number", description: "Corner radius 0-50 (default 0)"),
        "mask_shape": .init(type: "string", description: "Mask shape", enumValues: ["rectangle", "roundedRect", "circle"]),
    ], required: ["clip_id"])
)

public static let applyPiPPreset = AIToolDefinition(
    name: "apply_pip_preset",
    description: "Quick PiP positioning. Sets overlay mode to pip and snaps the clip to a corner of the frame.",
    parameters: .object([
        "clip_id": .init(type: "string", description: "UUID of the clip"),
        "preset": .init(type: "string", description: "Corner position", enumValues: ["topLeft", "topRight", "bottomLeft", "bottomRight"]),
    ], required: ["clip_id", "preset"])
)
```

Add to `allTools`: `setClipOverlayPresentation, applyPiPPreset,`

- [ ] **Step 4: Add resolver cases**

```swift
case "set_clip_overlay_presentation":
    guard let clipIDStr = arguments["clip_id"] as? String, let clipID = UUID(uuidString: clipIDStr) else {
        throw AIToolError.invalidArgument("Missing or invalid clip_id")
    }
    let modeStr = (arguments["mode"] as? String) ?? "inline"
    let mode = OverlayPresentationMode(rawValue: modeStr) ?? .inline
    let borderVisible = (arguments["border_visible"] as? Bool) ?? false
    let borderWidth = (arguments["border_width"] as? Double) ?? 2.0
    let shadowStr = (arguments["shadow"] as? String) ?? "none"
    let shadow = OverlayShadowStyle(rawValue: shadowStr) ?? .none
    let cornerRadius = (arguments["corner_radius"] as? Double) ?? 0
    let maskStr = (arguments["mask_shape"] as? String) ?? "rectangle"
    let maskShape = OverlayMaskShape(rawValue: maskStr) ?? .rectangle
    let presentation = OverlayPresentation(
        mode: mode,
        border: borderVisible ? .visible(width: borderWidth) : .hidden,
        shadow: shadow,
        cornerRadius: cornerRadius,
        maskShape: maskShape
    )
    return [.setClipOverlayPresentation(clipID: clipID, presentation: presentation)]

case "apply_pip_preset":
    guard let clipIDStr = arguments["clip_id"] as? String, let clipID = UUID(uuidString: clipIDStr) else {
        throw AIToolError.invalidArgument("Missing or invalid clip_id")
    }
    guard let presetStr = arguments["preset"] as? String, let preset = OverlayPiPPreset(rawValue: presetStr) else {
        throw AIToolError.invalidArgument("Missing or invalid preset (topLeft, topRight, bottomLeft, bottomRight)")
    }
    return [.applyClipPiPPreset(clipID: clipID, preset: preset)]
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd VideoEditor/Packages/EditorCore && swift test 2>&1 | tail -5`

Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add VideoEditor/Packages/AIServices/Sources/AIServices/Tools/AIToolRegistry.swift VideoEditor/Packages/AIServices/Tests/AIServicesTests/AIServicesTests.swift
git commit -m "feat(tools): add set_clip_overlay_presentation, apply_pip_preset tools"
```

---

### Task 3: Tool Definitions — Track Management (3 tools)

**Files:**
- Modify: `VideoEditor/Packages/AIServices/Sources/AIServices/Tools/AIToolRegistry.swift`
- Test: `VideoEditor/Packages/AIServices/Tests/AIServicesTests/AIServicesTests.swift`

- [ ] **Step 1: Write failing tests for solo_track, rename_track, reorder_track**

```swift
@MainActor
@Test("Track management tools resolve correctly")
func trackManagementToolResolution() throws {
    let resolver = AIToolResolver()
    let trackID = UUID()

    // solo_track
    let soloIntents = try resolver.resolve(toolName: "solo_track", arguments: [
        "track_id": trackID.uuidString,
        "soloed": true,
    ])
    #expect(soloIntents.count == 1)
    if case .soloTrack(let id, let soloed) = soloIntents[0] {
        #expect(id == trackID)
        #expect(soloed == true)
    } else {
        Issue.record("solo_track should resolve to soloTrack")
    }

    // rename_track
    let renameIntents = try resolver.resolve(toolName: "rename_track", arguments: [
        "track_id": trackID.uuidString,
        "name": "Main Audio",
    ])
    #expect(renameIntents.count == 1)
    if case .renameTrack(let id, let name) = renameIntents[0] {
        #expect(id == trackID)
        #expect(name == "Main Audio")
    } else {
        Issue.record("rename_track should resolve to renameTrack")
    }

    // reorder_track
    let reorderIntents = try resolver.resolve(toolName: "reorder_track", arguments: [
        "track_id": trackID.uuidString,
        "new_index": 2,
    ])
    #expect(reorderIntents.count == 1)
    if case .reorderTrack(let id, let idx) = reorderIntents[0] {
        #expect(id == trackID)
        #expect(idx == 2)
    } else {
        Issue.record("reorder_track should resolve to reorderTrack")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd VideoEditor/Packages/EditorCore && swift test 2>&1 | tail -5`

Expected: FAIL

- [ ] **Step 3: Add tool definitions**

```swift
public static let soloTrack = AIToolDefinition(
    name: "solo_track",
    description: "Solo a track (mutes all other tracks). Set soloed=false to unsolo.",
    parameters: .object([
        "track_id": .init(type: "string", description: "UUID of the track"),
        "soloed": .init(type: "boolean", description: "true to solo, false to unsolo (default true)"),
    ], required: ["track_id"])
)

public static let renameTrack = AIToolDefinition(
    name: "rename_track",
    description: "Rename a track.",
    parameters: .object([
        "track_id": .init(type: "string", description: "UUID of the track"),
        "name": .init(type: "string", description: "New track name"),
    ], required: ["track_id", "name"])
)

public static let reorderTrack = AIToolDefinition(
    name: "reorder_track",
    description: "Move a track to a new position in the stack. Index 0 = bottom of stack.",
    parameters: .object([
        "track_id": .init(type: "string", description: "UUID of the track"),
        "new_index": .init(type: "number", description: "Target position (0-based)"),
    ], required: ["track_id", "new_index"])
)
```

Add to `allTools`: `soloTrack, renameTrack, reorderTrack,`

- [ ] **Step 4: Add resolver cases**

```swift
case "solo_track":
    guard let trackIDStr = arguments["track_id"] as? String, let trackID = UUID(uuidString: trackIDStr) else {
        throw AIToolError.invalidArgument("Missing or invalid track_id")
    }
    let soloed = (arguments["soloed"] as? Bool) ?? true
    return [.soloTrack(trackID: trackID, soloed: soloed)]

case "rename_track":
    guard let trackIDStr = arguments["track_id"] as? String, let trackID = UUID(uuidString: trackIDStr) else {
        throw AIToolError.invalidArgument("Missing or invalid track_id")
    }
    guard let name = arguments["name"] as? String, !name.isEmpty else {
        throw AIToolError.invalidArgument("Missing or empty name")
    }
    return [.renameTrack(trackID: trackID, name: name)]

case "reorder_track":
    guard let trackIDStr = arguments["track_id"] as? String, let trackID = UUID(uuidString: trackIDStr) else {
        throw AIToolError.invalidArgument("Missing or invalid track_id")
    }
    guard let newIndex = arguments["new_index"] as? Int else {
        throw AIToolError.invalidArgument("Missing new_index")
    }
    return [.reorderTrack(trackID: trackID, newIndex: newIndex)]
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd VideoEditor/Packages/EditorCore && swift test 2>&1 | tail -5`

Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add VideoEditor/Packages/AIServices/Sources/AIServices/Tools/AIToolRegistry.swift VideoEditor/Packages/AIServices/Tests/AIServicesTests/AIServicesTests.swift
git commit -m "feat(tools): add solo_track, rename_track, reorder_track tools"
```

---

### Task 4: Tool Definitions — Link Clips + Batch (2 tools)

**Files:**
- Modify: `VideoEditor/Packages/AIServices/Sources/AIServices/Tools/AIToolRegistry.swift`
- Test: `VideoEditor/Packages/AIServices/Tests/AIServicesTests/AIServicesTests.swift`

- [ ] **Step 1: Write failing tests for link_clips and batch**

```swift
@MainActor
@Test("Link clips tool resolves correctly")
func linkClipsToolResolution() throws {
    let resolver = AIToolResolver()
    let clip1 = UUID()
    let clip2 = UUID()

    // link
    let linkIntents = try resolver.resolve(toolName: "link_clips", arguments: [
        "clip_ids": [clip1.uuidString, clip2.uuidString],
        "link": true,
    ])
    #expect(linkIntents.count == 1)
    if case .linkClips(let ids, let groupID) = linkIntents[0] {
        #expect(ids.count == 2)
        #expect(ids.contains(clip1))
        #expect(ids.contains(clip2))
        #expect(groupID != nil)
    } else {
        Issue.record("link_clips with link=true should resolve to linkClips with non-nil groupID")
    }

    // unlink
    let unlinkIntents = try resolver.resolve(toolName: "link_clips", arguments: [
        "clip_ids": [clip1.uuidString],
        "link": false,
    ])
    if case .linkClips(_, let groupID) = unlinkIntents[0] {
        #expect(groupID == nil)
    } else {
        Issue.record("link_clips with link=false should have nil groupID")
    }
}

@MainActor
@Test("Batch tool resolves to batch intent with nested operations")
func batchToolResolution() throws {
    let resolver = AIToolResolver()
    let trackID = UUID()
    let clipID = UUID()

    let ops = """
    [{"tool":"solo_track","args":{"track_id":"\(trackID.uuidString)","soloed":true}},{"tool":"set_clip_volume","args":{"clip_id":"\(clipID.uuidString)","volume":0.5}}]
    """

    let intents = try resolver.resolve(toolName: "batch", arguments: [
        "operations": ops,
    ])
    #expect(intents.count == 1)
    if case .batch(let nested) = intents[0] {
        #expect(nested.count == 2)
        if case .soloTrack(let id, let soloed) = nested[0] {
            #expect(id == trackID)
            #expect(soloed == true)
        } else {
            Issue.record("First batch op should be soloTrack")
        }
        if case .setClipVolume(let id, let vol) = nested[1] {
            #expect(id == clipID)
            #expect(vol == 0.5)
        } else {
            Issue.record("Second batch op should be setClipVolume")
        }
    } else {
        Issue.record("batch should resolve to .batch")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd VideoEditor/Packages/EditorCore && swift test 2>&1 | tail -5`

Expected: FAIL

- [ ] **Step 3: Add tool definitions**

```swift
public static let linkClips = AIToolDefinition(
    name: "link_clips",
    description: "Link or unlink clips so edits propagate together (e.g. video+audio pair). Linked clips move, split, and delete as a group.",
    parameters: .object([
        "clip_ids": .init(type: "array", description: "UUIDs of clips to link/unlink", items: .init(type: "string")),
        "link": .init(type: "boolean", description: "true to link, false to unlink"),
    ], required: ["clip_ids", "link"])
)

public static let batch = AIToolDefinition(
    name: "batch",
    description: "Execute multiple tool calls as a single undoable operation. Only intent-backed tools are allowed (not undo, redo, play_pause, seek, toggle_loop, get_action_log).",
    parameters: .object([
        "operations": .init(type: "string", description: "JSON array of {\"tool\": \"tool_name\", \"args\": {...}} objects"),
    ], required: ["operations"])
)
```

Add to `allTools`: `linkClips, batch,`

- [ ] **Step 4: Add resolver cases**

```swift
case "link_clips":
    guard let idStrings = arguments["clip_ids"] as? [String] else {
        throw AIToolError.invalidArgument("Missing clip_ids array")
    }
    let ids = idStrings.compactMap { UUID(uuidString: $0) }
    guard !ids.isEmpty else { throw AIToolError.invalidArgument("No valid clip IDs") }
    guard let link = arguments["link"] as? Bool else {
        throw AIToolError.invalidArgument("Missing link parameter (true/false)")
    }
    return [.linkClips(clipIDs: ids, linkGroupID: link ? UUID() : nil)]

case "batch":
    guard let opsJSON = arguments["operations"] as? String,
          let data = opsJSON.data(using: .utf8),
          let ops = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
        throw AIToolError.invalidArgument("operations must be a valid JSON array string")
    }
    let appStateTools: Set<String> = ["undo", "redo", "play_pause", "seek", "toggle_loop", "get_action_log"]
    var allIntents: [EditorIntent] = []
    for op in ops {
        guard let toolName = op["tool"] as? String else {
            throw AIToolError.invalidArgument("Each operation must have a 'tool' field")
        }
        guard !appStateTools.contains(toolName) else {
            throw AIToolError.invalidArgument("'\(toolName)' cannot be used inside batch")
        }
        let opArgs = op["args"] as? [String: Any] ?? [:]
        let intents = try resolve(toolName: toolName, arguments: opArgs, assets: assets)
        allIntents.append(contentsOf: intents)
    }
    return [.batch(allIntents)]
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd VideoEditor/Packages/EditorCore && swift test 2>&1 | tail -5`

Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add VideoEditor/Packages/AIServices/Sources/AIServices/Tools/AIToolRegistry.swift VideoEditor/Packages/AIServices/Tests/AIServicesTests/AIServicesTests.swift
git commit -m "feat(tools): add link_clips and batch tools"
```

---

### Task 5: Tool Definitions — AppState Tools (6 tools)

**Files:**
- Modify: `VideoEditor/Packages/AIServices/Sources/AIServices/Tools/AIToolRegistry.swift`
- Test: `VideoEditor/Packages/AIServices/Tests/AIServicesTests/AIServicesTests.swift`

- [ ] **Step 1: Write failing test that AppState tools resolve to empty intents**

These tools are handled upstream (AIChatController/MCPServer) — the resolver just returns `[]`.

```swift
@MainActor
@Test("AppState tools resolve to empty intents (handled upstream)")
func appStateToolResolution() throws {
    let resolver = AIToolResolver()

    for toolName in ["undo", "redo", "play_pause", "seek", "toggle_loop", "get_action_log"] {
        let intents = try resolver.resolve(toolName: toolName, arguments: [:])
        #expect(intents.isEmpty, "'\(toolName)' should resolve to empty intents (handled upstream)")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd VideoEditor/Packages/EditorCore && swift test 2>&1 | tail -5`

Expected: FAIL — "Unknown tool: undo"

- [ ] **Step 3: Add tool definitions**

```swift
// MARK: - AppState tools (handled by AIChatController/MCPServer, not AIToolResolver)

public static let undo = AIToolDefinition(
    name: "undo",
    description: "Undo the last editing action. Returns what was undone.",
    parameters: .object([:])
)

public static let redo = AIToolDefinition(
    name: "redo",
    description: "Redo the last undone editing action. Returns what was redone.",
    parameters: .object([:])
)

public static let playPause = AIToolDefinition(
    name: "play_pause",
    description: "Control timeline playback. Returns current playback state.",
    parameters: .object([
        "action": .init(type: "string", description: "'play', 'pause', or 'toggle' (default 'toggle')", enumValues: ["play", "pause", "toggle"]),
    ])
)

public static let seek = AIToolDefinition(
    name: "seek",
    description: "Move the playhead to a specific time. Accepts seconds as a number, or 'start'/'end' as aliases.",
    parameters: .object([
        "time": .init(type: "string", description: "Time in seconds (number) or 'start'/'end'"),
    ], required: ["time"])
)

public static let toggleLoop = AIToolDefinition(
    name: "toggle_loop",
    description: "Enable or disable playback looping.",
    parameters: .object([
        "enabled": .init(type: "boolean", description: "true to enable loop, false to disable"),
    ], required: ["enabled"])
)

public static let getActionLog = AIToolDefinition(
    name: "get_action_log",
    description: "Get recent editing actions for debugging or review. Returns timestamp, action name, source (ai/user), and affected IDs.",
    parameters: .object([
        "limit": .init(type: "number", description: "Max entries to return (default 20)"),
    ])
)
```

Add to `allTools`: `undo, redo, playPause, seek, toggleLoop, getActionLog,`

- [ ] **Step 4: Add resolver cases**

```swift
// AppState tools — handled upstream in AIChatController/MCPServer, not via intents
case "undo", "redo", "play_pause", "seek", "toggle_loop", "get_action_log":
    return []
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd VideoEditor/Packages/EditorCore && swift test 2>&1 | tail -5`

Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add VideoEditor/Packages/AIServices/Sources/AIServices/Tools/AIToolRegistry.swift VideoEditor/Packages/AIServices/Tests/AIServicesTests/AIServicesTests.swift
git commit -m "feat(tools): add undo, redo, play_pause, seek, toggle_loop, get_action_log tool definitions"
```

---

### Task 6: IntentRouter — New Keywords and Subsets

**Files:**
- Modify: `VideoEditor/Packages/AIServices/Sources/AIServices/Routing/IntentRouter.swift`
- Test: `VideoEditor/Packages/AIServices/Tests/AIServicesTests/AIServicesTests.swift`

- [ ] **Step 1: Write failing tests for new routing**

```swift
@Suite("IntentRouter Tests")
struct IntentRouterTests {

    @Test("Playback keywords route to fast tier with playback tools")
    func playbackRouting() {
        let router = IntentRouter()

        for keyword in ["undo that", "redo", "play the timeline", "pause", "seek to 10", "jump to start", "loop this"] {
            let decision = router.route(keyword)
            #expect(decision.tier == .fast, "'\(keyword)' should route to fast tier")
            #expect(decision.toolSubset.contains("play_pause") || decision.toolSubset.contains("undo"),
                    "'\(keyword)' should include playback tools")
        }
    }

    @Test("New property keywords route correctly")
    func newPropertyRouting() {
        let router = IntentRouter()

        let decision = router.route("crop this clip to center")
        #expect(decision.tier == .fast)
        #expect(decision.toolSubset.contains("set_clip_crop"))

        let blendDecision = router.route("set blend mode to multiply")
        #expect(blendDecision.tier == .fast)
        #expect(blendDecision.toolSubset.contains("set_clip_blend_mode"))
    }

    @Test("New structural keywords route correctly")
    func newStructuralRouting() {
        let router = IntentRouter()

        let decision = router.route("reorder the tracks")
        #expect(decision.tier == .fast)
        #expect(decision.toolSubset.contains("reorder_track"))

        let linkDecision = router.route("link these clips together")
        #expect(linkDecision.tier == .fast)
        #expect(linkDecision.toolSubset.contains("link_clips"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd VideoEditor/Packages/EditorCore && swift test 2>&1 | tail -5`

Expected: FAIL

- [ ] **Step 3: Update IntentRouter.swift**

Replace the full file content of `IntentRouter.swift`:

```swift
import Foundation

/// Routes AI requests to the appropriate model tier and tool subset.
/// Zero-cost code-based classification — no LLM call needed.
public struct IntentRouter: Sendable {

    public enum ModelTier: String, Sendable {
        /// Haiku 4.5 — fast, cheap. Single-tool mechanical operations.
        case fast = "claude-haiku-4-5-20251001"
        /// Sonnet 4.6 — default. Multi-tool, ambiguous, content-aware.
        case standard = "claude-sonnet-4-6"
    }

    public struct RoutingDecision: Sendable {
        public let tier: ModelTier
        public let toolSubset: [String]  // Tool names to include
    }

    public init() {}

    /// Classify a user message and return routing decision.
    public func route(_ message: String) -> RoutingDecision {
        let lower = message.lowercased()

        // Content-aware operations → Sonnet + content tools
        if matchesAny(lower, keywords: contentKeywords) {
            return RoutingDecision(
                tier: .standard,
                toolSubset: contentTools
            )
        }

        // Multi-step editing operations → Sonnet + editing tools
        if matchesAny(lower, keywords: complexEditKeywords) {
            return RoutingDecision(
                tier: .standard,
                toolSubset: fullEditTools
            )
        }

        // Playback / undo / redo → Haiku + playback tools
        if matchesAny(lower, keywords: playbackKeywords) {
            return RoutingDecision(
                tier: .fast,
                toolSubset: playbackTools
            )
        }

        // Simple property changes → Haiku + property tools
        if matchesAny(lower, keywords: propertyKeywords) {
            return RoutingDecision(
                tier: .fast,
                toolSubset: propertyTools
            )
        }

        // Simple structural operations → Haiku + structural tools
        if matchesAny(lower, keywords: structuralKeywords) {
            return RoutingDecision(
                tier: .fast,
                toolSubset: structuralTools
            )
        }

        // Questions / conversation → Sonnet, no tools
        if matchesAny(lower, keywords: questionKeywords) {
            return RoutingDecision(tier: .standard, toolSubset: [])
        }

        // Default: Sonnet with ALL tools — agent has full access
        return RoutingDecision(tier: .standard, toolSubset: AIToolRegistry.allTools.map(\.name))
    }

    // MARK: - Keyword sets

    private let contentKeywords = [
        "transcript", "says", "said", "mention", "spoken", "talking",
        "silence", "silent", "filler", "um", "uh", "search",
        "find where", "what do i say", "what did i", "transcribe",
    ]

    private let complexEditKeywords = [
        "remove section", "remove all", "clean up", "highlight reel",
        "rearrange", "reorganize", "normalize", "fix the audio",
        "create a", "make a", "assemble", "compile",
    ]

    private let playbackKeywords = [
        "undo", "redo", "play", "pause", "stop",
        "seek", "go to", "jump to", "loop", "rewind",
    ]

    private let propertyKeywords = [
        "volume", "opacity", "speed", "mute", "unmute",
        "louder", "quieter", "softer", "faster", "slower",
        "fade", "transparent", "visible", "lock", "unlock",
        "crop", "blend", "composite", "solo", "unsolo",
    ]

    private let structuralKeywords = [
        "add track", "new track", "delete", "remove", "split",
        "cut", "trim", "move", "duplicate", "copy", "paste",
        "marker", "rename", "reorder", "link", "unlink", "group", "ungroup",
    ]

    private let questionKeywords = [
        "how many", "what tracks", "what clips", "how long",
        "tell me", "what is", "show me", "help", "hello",
        "thanks", "hi", "hey",
    ]

    // MARK: - Tool subsets

    private let contentTools = [
        "get_transcript", "transcribe_asset", "search_transcript",
        "remove_silence", "remove_section", "split_clip", "delete_clips",
    ]

    private let fullEditTools = [
        "add_track", "insert_clip", "move_clip", "delete_clips",
        "split_clip", "trim_clip", "remove_section", "ripple_delete",
        "normalize_audio", "set_clip_volume", "set_clip_speed",
        "duplicate_clip", "set_marker",
    ]

    private let playbackTools = [
        "play_pause", "seek", "toggle_loop", "undo", "redo",
    ]

    private let propertyTools = [
        "set_clip_volume", "set_clip_opacity", "set_clip_speed",
        "mute_track", "lock_track", "set_track_volume",
        "set_clip_transition", "rename_clip",
        "set_clip_crop", "set_clip_blend_mode", "solo_track", "rename_track",
    ]

    private let structuralTools = [
        "add_track", "remove_track", "insert_clip", "delete_clips",
        "split_clip", "trim_clip", "move_clip", "duplicate_clip",
        "ripple_delete", "set_marker", "delete_marker", "rename_clip",
        "reorder_track", "link_clips", "remove_clip_effect",
    ]

    private let coreTools = [
        "add_track", "insert_clip", "move_clip", "delete_clips",
        "split_clip", "trim_clip", "set_marker", "set_clip_volume",
        "mute_track", "remove_section", "ripple_delete",
        "get_transcript", "search_transcript",
    ]

    private func matchesAny(_ text: String, keywords: [String]) -> Bool {
        keywords.contains { text.contains($0) }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd VideoEditor/Packages/EditorCore && swift test 2>&1 | tail -5`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add VideoEditor/Packages/AIServices/Sources/AIServices/Routing/IntentRouter.swift VideoEditor/Packages/AIServices/Tests/AIServicesTests/AIServicesTests.swift
git commit -m "feat(routing): add playback keywords and new tool subsets to IntentRouter"
```

---

### Task 7: AIChatController — AppState Tool Handlers

**Files:**
- Modify: `VideoEditor/VideoEditor/App/AIChatController.swift:~280-390`

- [ ] **Step 1: Add handlePlaybackTool method**

Add this private method to AIChatController, after the existing `handleAnalysisTool` method:

```swift
// MARK: - Playback & undo tools

@MainActor
private func handlePlaybackTool(name: String, args: [String: Any], appState: AppState) -> String? {
    switch name {
    case "undo":
        guard appState.commandHistory.canUndo else { return "Nothing to undo." }
        do {
            try appState.undo()
            return "Undone. Timeline now has \(appState.timeline.tracks.flatMap(\.clips).count) clip(s)."
        } catch {
            return "Undo failed: \(error.localizedDescription)"
        }

    case "redo":
        guard appState.commandHistory.canRedo else { return "Nothing to redo." }
        do {
            try appState.redo()
            return "Redone. Timeline now has \(appState.timeline.tracks.flatMap(\.clips).count) clip(s)."
        } catch {
            return "Redo failed: \(error.localizedDescription)"
        }

    case "play_pause":
        let action = (args["action"] as? String) ?? "toggle"
        switch action {
        case "play":
            if !appState.playbackEngine.isPlaying { appState.playbackEngine.togglePlayPause() }
        case "pause":
            if appState.playbackEngine.isPlaying { appState.playbackEngine.togglePlayPause() }
        default:
            appState.playbackEngine.togglePlayPause()
        }
        let state = appState.playbackEngine.isPlaying ? "playing" : "paused"
        return "Playback \(state) at \(String(format: "%.1f", appState.playbackEngine.currentTime))s."

    case "seek":
        let time: Double
        if let t = args["time"] as? Double {
            time = t
        } else if let s = args["time"] as? String {
            switch s.lowercased() {
            case "start": time = 0
            case "end": time = appState.timeline.duration
            default:
                if let t = Double(s) { time = t }
                else { return "Error: Invalid time value '\(s)'. Use a number or 'start'/'end'." }
            }
        } else {
            return "Error: Missing time parameter."
        }
        appState.playbackEngine.seek(to: time)
        return "Playhead at \(String(format: "%.1f", time))s."

    case "toggle_loop":
        let enabled = (args["enabled"] as? Bool) ?? !appState.playbackEngine.loopEnabled
        appState.playbackEngine.loopEnabled = enabled
        return "Loop \(enabled ? "enabled" : "disabled")."

    case "get_action_log":
        let limit = (args["limit"] as? Int) ?? 20
        let events = appState.context.actionLog.recentActions(count: limit)
        if events.isEmpty { return "No actions recorded yet." }
        let lines = events.map { event in
            "\(event.timestamp) | \(event.source.rawValue) | \(event.action)"
        }
        return "Recent actions (\(events.count)):\n" + lines.joined(separator: "\n")

    default:
        return nil
    }
}
```

- [ ] **Step 2: Wire it into executeTool**

In `executeTool()`, add this block right before the MCPServer fallback (before line `// All other tools — route through MCPServer`):

```swift
// Playback & undo tools — need AppState directly
if let playbackResult = handlePlaybackTool(name: toolCall.name, args: args, appState: appState) {
    let isError = playbackResult.hasPrefix("Error:")
    return .init(toolName: toolCall.name, success: !isError, message: playbackResult)
}
```

- [ ] **Step 3: Add describeTool cases**

In the `describeTool` switch, before `default:`, add:

```swift
case "undo":
    return "Undone last action. Timeline has \(timeline.tracks.flatMap(\.clips).count) clip(s)."
case "redo":
    return "Redone. Timeline has \(timeline.tracks.flatMap(\.clips).count) clip(s)."
case "seek":
    let time = args["time"] as? Double ?? 0
    return "Playhead at \(String(format: "%.1f", time))s."
case "batch":
    return "Executed batch operation."
```

- [ ] **Step 4: Build to verify compilation**

Run: `cd VideoEditor && xcodebuild -scheme VideoEditor -destination 'platform=macOS' build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add VideoEditor/VideoEditor/App/AIChatController.swift
git commit -m "feat(agent): add playback, undo/redo, and action log tool handlers"
```

---

### Task 8: MCPServer — AppState Tool Handlers

**Files:**
- Modify: `VideoEditor/VideoEditor/App/MCPServer.swift:~590-843`

- [ ] **Step 1: Add AppState tool handlers in executeToolForAgent**

In `MCPServer.swift`, in the `executeToolForAgent` method, add these cases before the `AIToolResolver` fallback (before line `let toolResolver = AIToolResolver()`):

```swift
case "undo":
    guard appState.commandHistory.canUndo else { return "Nothing to undo." }
    do {
        try appState.undo()
        return stateSnapshot(appState)
    } catch {
        return "Error: \(error.localizedDescription)"
    }

case "redo":
    guard appState.commandHistory.canRedo else { return "Nothing to redo." }
    do {
        try appState.redo()
        return stateSnapshot(appState)
    } catch {
        return "Error: \(error.localizedDescription)"
    }

case "play_pause":
    let action = (arguments["action"] as? String) ?? "toggle"
    switch action {
    case "play":
        if !appState.playbackEngine.isPlaying { appState.playbackEngine.togglePlayPause() }
    case "pause":
        if appState.playbackEngine.isPlaying { appState.playbackEngine.togglePlayPause() }
    default:
        appState.playbackEngine.togglePlayPause()
    }
    let state = appState.playbackEngine.isPlaying ? "playing" : "paused"
    return "Playback \(state) at \(String(format: "%.1f", appState.playbackEngine.currentTime))s."

case "seek":
    let time: Double
    if let t = arguments["time"] as? Double {
        time = t
    } else if let s = arguments["time"] as? String {
        switch s.lowercased() {
        case "start": time = 0
        case "end": time = appState.timeline.duration
        default:
            if let t = Double(s) { time = t }
            else { return "Error: Invalid time '\(s)'. Use a number or 'start'/'end'." }
        }
    } else {
        return "Error: Missing time parameter."
    }
    appState.playbackEngine.seek(to: time)
    return "Playhead at \(String(format: "%.1f", time))s."

case "toggle_loop":
    let enabled = (arguments["enabled"] as? Bool) ?? !appState.playbackEngine.loopEnabled
    appState.playbackEngine.loopEnabled = enabled
    return "Loop \(enabled ? "enabled" : "disabled")."

case "get_action_log":
    let limit = (arguments["limit"] as? Int) ?? 20
    let events = appState.context.actionLog.recentActions(count: limit)
    if events.isEmpty { return "No actions recorded." }
    let lines = events.map { "\($0.timestamp) | \($0.source.rawValue) | \($0.action)" }
    return "Recent actions (\(events.count)):\n" + lines.joined(separator: "\n")
```

- [ ] **Step 2: Build to verify compilation**

Run: `cd VideoEditor && xcodebuild -scheme VideoEditor -destination 'platform=macOS' build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add VideoEditor/VideoEditor/App/MCPServer.swift
git commit -m "feat(mcp): add playback, undo/redo, and action log tool handlers"
```

---

### Task 9: Full Build + Test Verification

**Files:** None (verification only)

- [ ] **Step 1: Run EditorCore swift tests**

Run: `cd VideoEditor/Packages/EditorCore && swift test 2>&1 | tail -10`

Expected: All tests pass

- [ ] **Step 2: Run AIServices swift tests**

Run: `cd VideoEditor/Packages/EditorCore && swift test 2>&1 | grep -E "passed|failed|error"`

Expected: All new and existing tests pass

- [ ] **Step 3: Run full xcodebuild**

Run: `cd VideoEditor && xcodebuild -scheme VideoEditor -destination 'platform=macOS' build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

- [ ] **Step 4: Verify tool count**

Run: `cd VideoEditor && grep -c 'public static let' Packages/AIServices/Sources/AIServices/Tools/AIToolRegistry.swift`

Expected: Previous count (61) + 16 new = 77 static lets (some are internal like ParameterSchema helpers, so count may vary — verify the `allTools` array has 75 entries: 59 original + 16 new)

- [ ] **Step 5: Commit verification marker**

```bash
git add -A
git commit -m "chore: verify all 16 new tools compile and pass tests"
```
