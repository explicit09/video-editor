# Layered Video And PiP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a real layered-video workflow where higher video tracks composite correctly, selected overlay clips can be manipulated in the program monitor, and PiP is exposed as polished presets and styling on ordinary video clips.

**Architecture:** Extend the existing clip model with overlay presentation state instead of inventing a new overlay object type. Keep layered compositing in `EditorCore`, add monitor manipulation support in `VideoEditor/UI/Panels`, and expose precise preset-driven controls in the inspector so timeline, monitor, and inspector all edit the same clip-owned state.

**Tech Stack:** Swift, SwiftUI, AVFoundation, CoreImage, EditorCore commands/intents/tests, VideoEditor UI tests/build verification

---

## File Map

### Existing files to modify

- `VideoEditor/Packages/EditorCore/Sources/EditorCore/Models/Clip.swift`
  - Add clip-owned overlay presentation state.
- `VideoEditor/Packages/EditorCore/Sources/EditorCore/Intents/EditorIntent.swift`
  - Add intents for overlay presentation and preset updates.
- `VideoEditor/Packages/EditorCore/Sources/EditorCore/Commands/PropertyCommands.swift`
  - Add undoable property commands for overlay presentation state.
- `VideoEditor/Packages/EditorCore/Sources/EditorCore/Playback/CompositionBuilder.swift`
  - Ensure multi-track overlay instructions are created in stable visual order.
- `VideoEditor/Packages/EditorCore/Sources/EditorCore/Playback/EffectCompositor.swift`
  - Apply overlay presentation styling, masking, snapping-safe transforms, and simple animation presets during compositing.
- `VideoEditor/VideoEditor/UI/Panels/ProgramMonitorPanel.swift`
  - Render monitor interaction overlay for selected overlay clips.
- `VideoEditor/VideoEditor/UI/Panels/MonitorViewport.swift`
  - Host transform handles, guides, and hit-testing layers above playback.
- `VideoEditor/VideoEditor/UI/Inspector/InspectorPanel.swift`
  - Add PiP preset and overlay presentation controls for a selected clip.
- `VideoEditor/VideoEditor/UI/Timeline/TimelineTrackView.swift`
  - Show layered-clip affordances without breaking ordinary timeline editing.
- `VideoEditor/VideoEditor/App/AppState.swift`
  - Route monitor edits and preset actions through existing intent execution.

### New files to create

- `VideoEditor/Packages/EditorCore/Sources/EditorCore/Models/OverlayPresentation.swift`
  - Clip-owned presentation model and animation/preset enums.
- `VideoEditor/Packages/EditorCore/Sources/EditorCore/Playback/OverlayGeometry.swift`
  - Shared geometry math for monitor manipulation, snapping, and safe margins.
- `VideoEditor/VideoEditor/UI/Panels/OverlayMonitorControls.swift`
  - SwiftUI overlay surface for move/resize handles and guides.
- `VideoEditor/VideoEditor/UI/Inspector/OverlayPresentationSection.swift`
  - Focused inspector section for PiP presets and overlay styling.

### Tests to add or extend

- `VideoEditor/Packages/EditorCore/Tests/EditorCoreTests/PropertyCommandTests.swift`
- `VideoEditor/Packages/EditorCore/Tests/EditorCoreTests/CompositionBuilderTests.swift`
- `VideoEditor/Packages/EditorCore/Tests/EditorCoreTests/EffectCompositorTests.swift`
- `VideoEditor/Packages/EditorCore/Tests/EditorCoreTests/OverlayGeometryTests.swift`
- `VideoEditor/VideoEditorTests/ProgramMonitorOverlayTests.swift`
- `VideoEditor/VideoEditorTests/InspectorOverlayPresetTests.swift`

---

### Task 1: Add Clip-Owned Overlay Presentation State

**Files:**
- Create: `VideoEditor/Packages/EditorCore/Sources/EditorCore/Models/OverlayPresentation.swift`
- Modify: `VideoEditor/Packages/EditorCore/Sources/EditorCore/Models/Clip.swift`
- Modify: `VideoEditor/Packages/EditorCore/Sources/EditorCore/Intents/EditorIntent.swift`
- Modify: `VideoEditor/Packages/EditorCore/Sources/EditorCore/Commands/PropertyCommands.swift`
- Test: `VideoEditor/Packages/EditorCore/Tests/EditorCoreTests/PropertyCommandTests.swift`

- [ ] **Step 1: Write the failing property-command tests**

```swift
@Test
func setClipOverlayPresentation() throws {
    let clip = Clip(assetID: UUID(), sourceRange: .init(start: 0, duration: 5), timelineRange: .init(start: 0, duration: 5))
    let track = Track(name: "Video 1", type: .video, clips: [clip])
    let context = EditingContext(timelineState: .init(timeline: .init(tracks: [track])))
    let resolver = IntentResolver()

    let presentation = OverlayPresentation(
        mode: .pip,
        border: .init(isVisible: true, width: 6, colorHex: "#FFFFFF"),
        shadow: .medium,
        cornerRadius: 18,
        maskShape: .roundedRect,
        entranceAnimation: .scaleIn,
        exitAnimation: .fadeOut
    )

    var command = try resolver.resolve(.setClipOverlayPresentation(clipID: clip.id, presentation: presentation))
    try command.execute(context: context)

    #expect(context.timelineState.timeline.tracks[0].clips[0].overlayPresentation == presentation)
}

@Test
func applyPiPPresetUpdatesTransformAndPresentation() throws {
    let clip = Clip(assetID: UUID(), sourceRange: .init(start: 0, duration: 5), timelineRange: .init(start: 0, duration: 5))
    let track = Track(name: "Video 2", type: .video, clips: [clip])
    let context = EditingContext(timelineState: .init(timeline: .init(tracks: [track])))
    let resolver = IntentResolver()

    var command = try resolver.resolve(.applyClipPiPPreset(clipID: clip.id, preset: .bottomRight))
    try command.execute(context: context)

    let updated = context.timelineState.timeline.tracks[0].clips[0]
    #expect(updated.overlayPresentation.mode == .pip)
    #expect(updated.transform.scaleX < 1.0)
    #expect(updated.transform.positionX > 0)
    #expect(updated.transform.positionY < 0)
}
```

- [ ] **Step 2: Run the targeted tests to verify they fail**

Run: `xcodebuild -scheme EditorCore -destination 'platform=macOS' test -only-testing:EditorCoreTests/PropertyCommandTests`

Expected: FAIL with missing `OverlayPresentation`, `setClipOverlayPresentation`, and `applyClipPiPPreset`.

- [ ] **Step 3: Add the overlay presentation model**

```swift
public struct OverlayPresentation: Codable, Equatable, Sendable {
    public var mode: OverlayPresentationMode
    public var border: OverlayBorderStyle
    public var shadow: OverlayShadowStyle
    public var cornerRadius: Double
    public var maskShape: OverlayMaskShape
    public var snapsToSafeMargins: Bool
    public var entranceAnimation: OverlayAnimationPreset
    public var exitAnimation: OverlayAnimationPreset

    public static let `default` = OverlayPresentation(
        mode: .inline,
        border: .hidden,
        shadow: .none,
        cornerRadius: 0,
        maskShape: .rectangle,
        snapsToSafeMargins: true,
        entranceAnimation: .none,
        exitAnimation: .none
    )
}
```

- [ ] **Step 4: Thread the model through clip state and intents**

```swift
public struct Clip: Codable, Identifiable, Sendable {
    // existing fields...
    public var overlayPresentation: OverlayPresentation

    public init(
        // existing args...
        overlayPresentation: OverlayPresentation = .default
    ) {
        // existing assignments...
        self.overlayPresentation = overlayPresentation
    }
}

public enum EditorIntent: Sendable {
    // existing cases...
    case setClipOverlayPresentation(clipID: UUID, presentation: OverlayPresentation)
    case applyClipPiPPreset(clipID: UUID, preset: OverlayPiPPreset)
}
```

- [ ] **Step 5: Add undoable commands with minimal preset resolution**

```swift
public struct SetClipOverlayPresentationCommand: Command {
    public let name = "Set Clip Overlay Presentation"
    public let clipID: UUID
    public let presentation: OverlayPresentation
    private var previousPresentation: OverlayPresentation?

    public mutating func execute(context: EditingContext) throws {
        try modifyClip(id: clipID, context: context) { clip in
            previousPresentation = clip.overlayPresentation
            clip.overlayPresentation = presentation
        }
    }

    public func undo(context: EditingContext) throws {
        guard let previousPresentation else { return }
        try modifyClip(id: clipID, context: context) { $0.overlayPresentation = previousPresentation }
    }
}
```

- [ ] **Step 6: Re-run the targeted tests**

Run: `xcodebuild -scheme EditorCore -destination 'platform=macOS' test -only-testing:EditorCoreTests/PropertyCommandTests`

Expected: PASS for the new property and preset tests.

- [ ] **Step 7: Commit**

```bash
git add VideoEditor/Packages/EditorCore/Sources/EditorCore/Models/OverlayPresentation.swift \
  VideoEditor/Packages/EditorCore/Sources/EditorCore/Models/Clip.swift \
  VideoEditor/Packages/EditorCore/Sources/EditorCore/Intents/EditorIntent.swift \
  VideoEditor/Packages/EditorCore/Sources/EditorCore/Commands/PropertyCommands.swift \
  VideoEditor/Packages/EditorCore/Tests/EditorCoreTests/PropertyCommandTests.swift
git commit -m "Add clip overlay presentation model"
```

### Task 2: Make Multi-Track Video Composite In Stable Layer Order

**Files:**
- Modify: `VideoEditor/Packages/EditorCore/Sources/EditorCore/Playback/CompositionBuilder.swift`
- Modify: `VideoEditor/Packages/EditorCore/Sources/EditorCore/Playback/EffectCompositor.swift`
- Test: `VideoEditor/Packages/EditorCore/Tests/EditorCoreTests/CompositionBuilderTests.swift`
- Test: `VideoEditor/Packages/EditorCore/Tests/EditorCoreTests/EffectCompositorTests.swift`

- [ ] **Step 1: Write failing compositing-order tests**

```swift
@Test
func overlayInstructionOrdersHigherTracksAboveLowerTracks() async throws {
    let baseClip = makeVideoClip(start: 0, duration: 5)
    let overlayClip = makeVideoClip(start: 0, duration: 5, transform: .init(scaleX: 0.5, scaleY: 0.5))
    let timeline = Timeline(tracks: [
        Track(name: "Video 1", type: .video, clips: [baseClip]),
        Track(name: "Video 2", type: .video, clips: [overlayClip]),
    ])

    let result = await CompositionBuilder().build(timeline: timeline, assets: fixtures.assets)
    let instruction = try #require(result.videoComposition?.instructions.first as? OverlayInstruction)

    #expect(instruction.layers.map(\.trackOrder) == [0, 1])
}
```

- [ ] **Step 2: Run the playback tests to verify failure**

Run: `xcodebuild -scheme EditorCore -destination 'platform=macOS' test -only-testing:EditorCoreTests/CompositionBuilderTests -only-testing:EditorCoreTests/EffectCompositorTests`

Expected: FAIL because overlay track ordering and presentation fields are not yet asserted correctly.

- [ ] **Step 3: Make the builder produce stable ordered overlay layers**

```swift
let orderedVideoTracks = timeline.tracks.enumerated().filter { $0.element.type == .video }

for (trackOrder, track) in orderedVideoTracks {
    // existing clip iteration...
    overlayLayers.append(OverlayLayerInstruction(
        trackID: compTrack.trackID,
        trackOrder: trackOrder,
        opacity: Float(clip.opacity * track.opacity),
        transform: clip.transform,
        cropRect: clip.cropRect,
        blendMode: clip.blendMode,
        presentation: clip.overlayPresentation
    ))
}

overlayLayers.sort { $0.trackOrder < $1.trackOrder }
```

- [ ] **Step 4: Apply ordered layer compositing and presentation hooks in the compositor**

```swift
for layer in instruction.layers.sorted(by: { $0.trackOrder < $1.trackOrder }) {
    guard let sourceBuffer = request.sourceFrame(byTrackID: layer.trackID) else { continue }
    var layerImage = CIImage(cvPixelBuffer: sourceBuffer)
    layerImage = Self.applyCropRect(layer.cropRect, to: layerImage)
    layerImage = Self.applyTransform(layer.transform, to: layerImage, renderSize: renderSize)
    layerImage = Self.applyOverlayPresentation(layer.presentation, to: layerImage, renderSize: renderSize)
    image = Self.composite(layerImage, over: image, blendMode: layer.blendMode, opacity: layer.opacity)
}
```

- [ ] **Step 5: Re-run the playback tests**

Run: `xcodebuild -scheme EditorCore -destination 'platform=macOS' test -only-testing:EditorCoreTests/CompositionBuilderTests -only-testing:EditorCoreTests/EffectCompositorTests`

Expected: PASS for ordered overlays and presentation-aware layer rendering.

- [ ] **Step 6: Commit**

```bash
git add VideoEditor/Packages/EditorCore/Sources/EditorCore/Playback/CompositionBuilder.swift \
  VideoEditor/Packages/EditorCore/Sources/EditorCore/Playback/EffectCompositor.swift \
  VideoEditor/Packages/EditorCore/Tests/EditorCoreTests/CompositionBuilderTests.swift \
  VideoEditor/Packages/EditorCore/Tests/EditorCoreTests/EffectCompositorTests.swift
git commit -m "Fix layered video compositing order"
```

### Task 3: Add On-Canvas Overlay Manipulation In The Program Monitor

**Files:**
- Create: `VideoEditor/Packages/EditorCore/Sources/EditorCore/Playback/OverlayGeometry.swift`
- Create: `VideoEditor/VideoEditor/UI/Panels/OverlayMonitorControls.swift`
- Modify: `VideoEditor/VideoEditor/UI/Panels/MonitorViewport.swift`
- Modify: `VideoEditor/VideoEditor/UI/Panels/ProgramMonitorPanel.swift`
- Modify: `VideoEditor/VideoEditor/App/AppState.swift`
- Test: `VideoEditor/Packages/EditorCore/Tests/EditorCoreTests/OverlayGeometryTests.swift`
- Test: `VideoEditor/VideoEditorTests/ProgramMonitorOverlayTests.swift`

- [ ] **Step 1: Write failing geometry and monitor tests**

```swift
@Test
func pipPresetFrameFitsInsideSafeMargins() {
    let frame = OverlayGeometry.presetFrame(.bottomRight, canvasSize: CGSize(width: 1920, height: 1080))
    #expect(frame.maxX <= 1920 - OverlayGeometry.safeMargin)
    #expect(frame.minY >= OverlayGeometry.safeMargin)
}

@Test
func draggingMonitorOverlayProducesUpdatedTransform() {
    let initial = Transform2D.identity
    let updated = OverlayGeometry.transformByTranslating(initial, delta: CGSize(width: 120, height: -60), canvasSize: CGSize(width: 1920, height: 1080))
    #expect(updated.positionX > initial.positionX)
    #expect(updated.positionY < initial.positionY)
}
```

- [ ] **Step 2: Run the new targeted tests**

Run: `xcodebuild -scheme VideoEditor -destination 'platform=macOS' test -only-testing:EditorCoreTests/OverlayGeometryTests -only-testing:VideoEditorTests/ProgramMonitorOverlayTests`

Expected: FAIL with missing geometry helpers and monitor overlay view.

- [ ] **Step 3: Add shared geometry helpers**

```swift
public enum OverlayGeometry {
    public static let safeMargin: CGFloat = 48

    public static func presetFrame(_ preset: OverlayPiPPreset, canvasSize: CGSize) -> CGRect { /* deterministic layout math */ }

    public static func transformByTranslating(_ transform: Transform2D, delta: CGSize, canvasSize: CGSize) -> Transform2D { /* normalized position math */ }

    public static func transformByScaling(_ transform: Transform2D, anchor: CGPoint, delta: CGSize) -> Transform2D { /* proportional scale math */ }
}
```

- [ ] **Step 4: Add a dedicated monitor interaction overlay**

```swift
struct OverlayMonitorControls: View {
    let clip: Clip
    let onMove: (CGSize) -> Void
    let onScale: (CGSize) -> Void

    var body: some View {
        GeometryReader { proxy in
            let frame = OverlayGeometry.displayFrame(for: clip, canvasSize: proxy.size)
            ZStack(alignment: .topLeading) {
                Rectangle().stroke(UtilityTheme.accent, lineWidth: 2)
                OverlayCornerHandles(frame: frame, onScale: onScale)
            }
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
            .gesture(DragGesture().onChanged { onMove($0.translation) })
        }
        .allowsHitTesting(true)
    }
}
```

- [ ] **Step 5: Wire the monitor overlay into the program monitor**

```swift
MonitorViewport(player: player, emptyState: emptyState) {
    if let clip = appState.selectedVideoOverlayClip {
        OverlayMonitorControls(
            clip: clip,
            onMove: { delta in appState.updateOverlayClipPosition(clip.id, delta: delta) },
            onScale: { delta in appState.updateOverlayClipScale(clip.id, delta: delta) }
        )
    }
}
```

- [ ] **Step 6: Re-run the targeted monitor tests**

Run: `xcodebuild -scheme VideoEditor -destination 'platform=macOS' test -only-testing:EditorCoreTests/OverlayGeometryTests -only-testing:VideoEditorTests/ProgramMonitorOverlayTests`

Expected: PASS for geometry helpers and monitor interaction rendering.

- [ ] **Step 7: Commit**

```bash
git add VideoEditor/Packages/EditorCore/Sources/EditorCore/Playback/OverlayGeometry.swift \
  VideoEditor/VideoEditor/UI/Panels/OverlayMonitorControls.swift \
  VideoEditor/VideoEditor/UI/Panels/MonitorViewport.swift \
  VideoEditor/VideoEditor/UI/Panels/ProgramMonitorPanel.swift \
  VideoEditor/VideoEditor/App/AppState.swift \
  VideoEditor/Packages/EditorCore/Tests/EditorCoreTests/OverlayGeometryTests.swift \
  VideoEditor/VideoEditorTests/ProgramMonitorOverlayTests.swift
git commit -m "Add program monitor overlay controls"
```

### Task 4: Add Inspector PiP Presets And Presentation Controls

**Files:**
- Create: `VideoEditor/VideoEditor/UI/Inspector/OverlayPresentationSection.swift`
- Modify: `VideoEditor/VideoEditor/UI/Inspector/InspectorPanel.swift`
- Modify: `VideoEditor/VideoEditor/App/AppState.swift`
- Test: `VideoEditor/VideoEditorTests/InspectorOverlayPresetTests.swift`

- [ ] **Step 1: Write failing inspector preset tests**

```swift
@Test
func inspectorPresetButtonsApplyPiPMode() throws {
    let appState = AppState.previewWithVideoClip()
    let clipID = try #require(appState.timeline.tracks.first?.clips.first?.id)

    try appState.perform(.applyClipPiPPreset(clipID: clipID, preset: .topRight))

    let updated = try #require(appState.timeline.tracks.first?.clips.first)
    #expect(updated.overlayPresentation.mode == .pip)
    #expect(updated.overlayPresentation.shadow != .none)
}
```

- [ ] **Step 2: Run the targeted UI tests**

Run: `xcodebuild -scheme VideoEditor -destination 'platform=macOS' test -only-testing:VideoEditorTests/InspectorOverlayPresetTests`

Expected: FAIL because the inspector section and preset bindings do not exist.

- [ ] **Step 3: Add a focused overlay inspector section**

```swift
struct OverlayPresentationSection: View {
    let clip: Clip
    let applyPreset: (OverlayPiPPreset) -> Void
    let updatePresentation: (OverlayPresentation) -> Void

    var body: some View {
        CinematicCard {
            VStack(alignment: .leading, spacing: CinematicSpacing.md) {
                presetButtons
                positionScaleControls
                styleControls
                cropMaskControls
                blendAndOpacityControls
            }
        }
    }
}
```

- [ ] **Step 4: Mount the section for selected video clips**

```swift
if clip.isVideoLike {
    OverlayPresentationSection(
        clip: clip,
        applyPreset: { preset in try? appState.perform(.applyClipPiPPreset(clipID: clip.id, preset: preset)) },
        updatePresentation: { presentation in try? appState.perform(.setClipOverlayPresentation(clipID: clip.id, presentation: presentation)) }
    )
}
```

- [ ] **Step 5: Re-run the inspector tests**

Run: `xcodebuild -scheme VideoEditor -destination 'platform=macOS' test -only-testing:VideoEditorTests/InspectorOverlayPresetTests`

Expected: PASS for preset application and inspector binding behavior.

- [ ] **Step 6: Commit**

```bash
git add VideoEditor/VideoEditor/UI/Inspector/OverlayPresentationSection.swift \
  VideoEditor/VideoEditor/UI/Inspector/InspectorPanel.swift \
  VideoEditor/VideoEditor/App/AppState.swift \
  VideoEditor/VideoEditorTests/InspectorOverlayPresetTests.swift
git commit -m "Add inspector PiP preset controls"
```

### Task 5: Add Snapping, Safe Margins, And Simple Animation Presets

**Files:**
- Modify: `VideoEditor/Packages/EditorCore/Sources/EditorCore/Models/OverlayPresentation.swift`
- Modify: `VideoEditor/Packages/EditorCore/Sources/EditorCore/Playback/OverlayGeometry.swift`
- Modify: `VideoEditor/Packages/EditorCore/Sources/EditorCore/Playback/EffectCompositor.swift`
- Modify: `VideoEditor/VideoEditor/UI/Panels/OverlayMonitorControls.swift`
- Test: `VideoEditor/Packages/EditorCore/Tests/EditorCoreTests/OverlayGeometryTests.swift`
- Test: `VideoEditor/Packages/EditorCore/Tests/EditorCoreTests/EffectCompositorTests.swift`

- [ ] **Step 1: Write failing snapping and animation tests**

```swift
@Test
func translationSnapsToSafeMarginWhenEnabled() {
    let transform = Transform2D(positionX: 910, positionY: -500, scaleX: 0.4, scaleY: 0.4, rotation: 0)
    let snapped = OverlayGeometry.snapped(transform, canvasSize: CGSize(width: 1920, height: 1080), snapsToSafeMargins: true)
    #expect(snapped.positionX != transform.positionX)
}

@Test
func fadeInPresetReducesOpacityAtClipStart() {
    let value = EffectCompositor.presentationOpacity(
        baseOpacity: 1,
        entrance: .fadeIn,
        exit: .none,
        compositionTime: 0.05,
        clipDuration: 5
    )
    #expect(value < 1)
}
```

- [ ] **Step 2: Run the targeted tests**

Run: `xcodebuild -scheme EditorCore -destination 'platform=macOS' test -only-testing:EditorCoreTests/OverlayGeometryTests -only-testing:EditorCoreTests/EffectCompositorTests`

Expected: FAIL because snapping and animation-preset logic are not implemented.

- [ ] **Step 3: Add snapping helpers and guide-ready results**

```swift
public struct OverlaySnapResult: Equatable, Sendable {
    public let transform: Transform2D
    public let verticalGuide: CGFloat?
    public let horizontalGuide: CGFloat?
}

public static func snapped(_ transform: Transform2D, canvasSize: CGSize, snapsToSafeMargins: Bool) -> OverlaySnapResult { /* center and safe-margin snapping */ }
```

- [ ] **Step 4: Apply simple entrance and exit animation presets in the compositor**

```swift
static func presentationOpacity(
    baseOpacity: Float,
    entrance: OverlayAnimationPreset,
    exit: OverlayAnimationPreset,
    compositionTime: TimeInterval,
    clipDuration: TimeInterval
) -> Float {
    // minimal fade/scale timing logic
}
```

- [ ] **Step 5: Re-run the targeted snapping and animation tests**

Run: `xcodebuild -scheme EditorCore -destination 'platform=macOS' test -only-testing:EditorCoreTests/OverlayGeometryTests -only-testing:EditorCoreTests/EffectCompositorTests`

Expected: PASS for snapping and preset animation behavior.

- [ ] **Step 6: Commit**

```bash
git add VideoEditor/Packages/EditorCore/Sources/EditorCore/Models/OverlayPresentation.swift \
  VideoEditor/Packages/EditorCore/Sources/EditorCore/Playback/OverlayGeometry.swift \
  VideoEditor/Packages/EditorCore/Sources/EditorCore/Playback/EffectCompositor.swift \
  VideoEditor/VideoEditor/UI/Panels/OverlayMonitorControls.swift \
  VideoEditor/Packages/EditorCore/Tests/EditorCoreTests/OverlayGeometryTests.swift \
  VideoEditor/Packages/EditorCore/Tests/EditorCoreTests/EffectCompositorTests.swift
git commit -m "Add overlay snapping and animation presets"
```

### Task 6: Polish Timeline Behavior And Run End-To-End Verification

**Files:**
- Modify: `VideoEditor/VideoEditor/UI/Timeline/TimelineTrackView.swift`
- Modify: `VideoEditor/VideoEditor/UI/Panels/ProgramMonitorPanel.swift`
- Modify: `VideoEditor/VideoEditor/UI/Inspector/InspectorPanel.swift`
- Test: `VideoEditor/VideoEditorTests/SelectionBehaviorTests.swift`
- Test: `VideoEditor/VideoEditorTests/TimelineShellSupportTests.swift`

- [ ] **Step 1: Add failing selection and polish tests where needed**

```swift
@Test
func selectingOverlayClipStillTargetsSingleClip() {
    let state = TimelineViewState()
    let clipID = UUID()
    let trackID = UUID()

    state.selectClip(clipID, in: trackID)

    #expect(state.selectedClipIDs == [clipID])
    #expect(state.selectedTrackID == trackID)
}
```

- [ ] **Step 2: Run the targeted timeline tests**

Run: `xcodebuild -scheme VideoEditor -destination 'platform=macOS' test -only-testing:VideoEditorTests/SelectionBehaviorTests -only-testing:VideoEditorTests/TimelineShellSupportTests`

Expected: PASS or narrow FAIL only if layered-clip affordances disturb selection. Fix any regression before moving on.

- [ ] **Step 3: Add timeline affordances without changing core clip interaction**

```swift
if clip.overlayPresentation.mode == .pip {
    OverlayClipBadge(text: "PiP")
        .allowsHitTesting(false)
}
```

- [ ] **Step 4: Run full verification**

Run: `xcodebuild -scheme VideoEditor -destination 'platform=macOS' test`

Expected: PASS

Run: `xcodebuild -scheme VideoEditor -destination 'platform=macOS' build`

Expected: `** BUILD SUCCEEDED **`

Run: `git diff --check`

Expected: no output

- [ ] **Step 5: Perform manual validation in the running app**

Run:

```bash
open -na /Users/explicit/Library/Developer/Xcode/DerivedData/VideoEditor-goxpvvzfscqvrnfineenalwxonum/Build/Products/Debug/VideoEditor.app
```

Validate:
- higher video track renders above lower video track
- selected overlay clip shows monitor handles
- drag moves overlay clip
- corner resize works
- PiP presets update clip placement and styling
- blend mode and opacity visibly affect the overlay
- snapping and safe margins appear during movement

- [ ] **Step 6: Commit**

```bash
git add VideoEditor/VideoEditor/UI/Timeline/TimelineTrackView.swift \
  VideoEditor/VideoEditor/UI/Panels/ProgramMonitorPanel.swift \
  VideoEditor/VideoEditor/UI/Inspector/InspectorPanel.swift \
  VideoEditor/VideoEditorTests/SelectionBehaviorTests.swift \
  VideoEditor/VideoEditorTests/TimelineShellSupportTests.swift
git commit -m "Polish layered video PiP workflow"
```

---

## Self-Review

### Spec coverage

- Multi-track compositing order: Task 2
- On-canvas overlay manipulation: Task 3
- Inspector presets and precise controls: Task 4
- Snapping, safe margins, simple animations: Task 5
- Timeline polish and end-to-end validation: Task 6

### Placeholder scan

- No `TODO`, `TBD`, or deferred “write tests later” steps remain.
- Every code-changing task includes concrete files, code snippets, and verification commands.

### Type consistency

- `OverlayPresentation`, `OverlayPiPPreset`, and `OverlayAnimationPreset` are introduced in Task 1 and reused consistently in later tasks.
- Geometry helpers are introduced in Task 3 and extended in Task 5 without renaming.
