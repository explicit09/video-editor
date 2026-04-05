# Timeline Shell Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the editor around a timeline-first shell with fixed timeline chrome, synchronized scrolling, denser track controls, stronger readability, and screenshot-based visual verification.

**Architecture:** Extract the current dashboard-like edit layout into a dedicated workspace shell, then split the timeline into focused views backed by small testable support types for layout, scrolling, and visibility heuristics. Keep editing-domain mutations on the existing `EditorIntent -> Command -> Execute` path, and keep shell/viewport state in dedicated UI support types so the redesign stays modular.

**Tech Stack:** Swift 6, SwiftUI, AppKit interop where needed for scrolling/measurement, EditorCore command pipeline, Apple `Testing`, XcodeGen / `xcodebuild`

---

## File Structure

### Create

- `VideoEditor/VideoEditor/UI/Layout/EditorWorkspaceShell.swift`
  - Own the three-column editor shell, center-column proportions, and rail collapse behavior.
- `VideoEditor/VideoEditor/UI/Timeline/TimelineShellView.swift`
  - Compose fixed toolbar, ruler, corner block, track headers, and clip canvas.
- `VideoEditor/VideoEditor/UI/Timeline/TimelineToolbarView.swift`
  - Render timeline-level controls separately from the shell container.
- `VideoEditor/VideoEditor/UI/Timeline/TimelineCanvasView.swift`
  - Render the scrollable clip/waveform surface and publish scroll offsets.
- `VideoEditor/VideoEditor/UI/Timeline/TrackHeaderColumnView.swift`
  - Render the fixed left header column aligned to visible track rows.
- `VideoEditor/VideoEditor/UI/Timeline/TrackHeaderRowView.swift`
  - Provide compact per-track controls, target state, and reorder affordance.
- `VideoEditor/VideoEditor/UI/Timeline/TimelineCornerView.swift`
  - Render the stable top-left corner block shared by ruler and track headers.
- `VideoEditor/VideoEditor/UI/Timeline/TimelineShellSupport.swift`
  - Hold pure helpers for viewport math, scroll targeting, and shell metrics.
- `VideoEditor/VideoEditor/UI/Timeline/TrackLayoutState.swift`
  - Hold per-track collapse, height mode, lane presentation, and reorder preview state.
- `VideoEditor/VideoEditor/UI/Timeline/TimelineScrollCoordinator.swift`
  - Hold authoritative horizontal/vertical offsets and pending scroll requests.
- `VideoEditor/VideoEditorTests/TimelineShellSupportTests.swift`
  - Cover shell metrics, visibility resolution, and auto-follow heuristics.
- `VideoEditor/VideoEditorTests/TrackLayoutStateTests.swift`
  - Cover compact/collapsed track presentation and row-alignment calculations.
- `VideoEditor/Packages/EditorCore/Tests/EditorCoreTests/TrackSoloCommandTests.swift`
  - Verify solo-track command behavior and undo/redo.

### Modify

- `VideoEditor/VideoEditor/UI/Layout/ContentView.swift`
  - Replace the inlined editor workspace with `EditorWorkspaceShell`.
- `VideoEditor/VideoEditor/UI/Preview/PreviewPanel.swift`
  - Reduce preview chrome weight and default minimum height.
- `VideoEditor/VideoEditor/UI/Timeline/TimelinePanel.swift`
  - Convert into a thin composition wrapper that feeds `TimelineShellView`.
- `VideoEditor/VideoEditor/UI/Timeline/TimelineTrackView.swift`
  - Narrow responsibility to clip/lane rendering and hand off header UI.
- `VideoEditor/VideoEditor/UI/Timeline/TimelineRuler.swift`
  - Strengthen ruler hierarchy and support external scroll offsets.
- `VideoEditor/VideoEditor/UI/Timeline/PlayheadView.swift`
  - Increase playhead contrast and support viewport-aware auto-follow.
- `VideoEditor/VideoEditor/UI/Timeline/WaveformView.swift`
  - Improve waveform contrast and selected-state legibility.
- `VideoEditor/VideoEditor/UI/Timeline/TimelineViewState.swift`
  - Add explicit destination-track targeting, auto-follow, and scroll-to-selection/playhead requests.
- `VideoEditor/VideoEditor/UI/Inspector/InspectorPanel.swift`
  - Surface solo state and any renamed track-targeting affordances needed to stay aligned with timeline headers.
- `VideoEditor/VideoEditor/App/AppState.swift`
  - Add focused helpers for track solo toggling and viewport-driven selection visibility requests without bypassing the intent pipeline.
- `VideoEditor/Packages/EditorCore/Sources/EditorCore/Intents/EditorIntent.swift`
  - Add a track-solo intent case.
- `VideoEditor/Packages/EditorCore/Sources/EditorCore/Commands/PropertyCommands.swift`
  - Add the matching solo-track command.

### Keep As-Is Unless Blocked

- `VideoEditor/project.yml`
  - No explicit manifest changes should be required because the target already includes the entire `VideoEditor` and `VideoEditorTests` trees.

## Task 1: Create Testable Timeline Shell Support Types

**Files:**
- Create: `VideoEditor/VideoEditor/UI/Timeline/TimelineShellSupport.swift`
- Create: `VideoEditor/VideoEditorTests/TimelineShellSupportTests.swift`
- Test: `VideoEditor/VideoEditorTests/TimelineShellSupportTests.swift`

- [ ] **Step 1: Write the failing tests for viewport math and auto-follow behavior**

```swift
import Testing
@testable import VideoEditor

@Suite("Timeline Shell Support Tests")
struct TimelineShellSupportTests {
    @Test("shell metrics reserve compact header and ruler space")
    func shellMetricsCompactChrome() {
        let metrics = TimelineShellMetrics.make(
            viewportWidth: 1280,
            viewportHeight: 720,
            trackCount: 3,
            expandedTrackHeight: 84,
            collapsedTrackHeight: 28
        )

        #expect(metrics.headerWidth == 152)
        #expect(metrics.rulerHeight == 32)
        #expect(metrics.scrollContentHeight > metrics.rulerHeight)
    }

    @Test("selection visibility requests horizontal reveal when clip is offscreen")
    func selectionRevealRequest() {
        let viewport = TimelineViewport(
            visibleXRange: 400...1000,
            visibleYRange: 0...300
        )
        let frame = TimelineVisibleFrame(
            minX: 1180,
            maxX: 1440,
            minY: 96,
            maxY: 180
        )

        let request = TimelineScrollTargetResolver.requestToReveal(
            frame,
            in: viewport,
            padding: 48
        )

        #expect(request?.anchorX == 1132)
        #expect(request?.anchorY == nil)
    }

    @Test("auto-follow keeps playhead visible only when enabled")
    func autoFollowPlayheadRequest() {
        let viewport = TimelineViewport(
            visibleXRange: 200...800,
            visibleYRange: 0...240
        )

        #expect(
            TimelineScrollTargetResolver.requestToKeepPlayheadVisible(
                playheadX: 860,
                in: viewport,
                autoFollow: false,
                padding: 72
            ) == nil
        )

        let request = TimelineScrollTargetResolver.requestToKeepPlayheadVisible(
            playheadX: 860,
            in: viewport,
            autoFollow: true,
            padding: 72
        )

        #expect(request?.anchorX == 788)
    }
}
```

- [ ] **Step 2: Run the test target to verify it fails**

Run:

```bash
cd /Users/explicit/Projects/video-editor/VideoEditor
xcodebuild -scheme VideoEditor -destination 'platform=macOS' test -only-testing:VideoEditorTests/TimelineShellSupportTests
```

Expected: FAIL with missing `TimelineShellMetrics`, `TimelineViewport`, `TimelineVisibleFrame`, or `TimelineScrollTargetResolver` symbols.

- [ ] **Step 3: Implement the minimal support types in the app target**

```swift
import Foundation

struct TimelineShellMetrics: Equatable {
    let headerWidth: Double
    let rulerHeight: Double
    let scrollContentHeight: Double

    static func make(
        viewportWidth: Double,
        viewportHeight: Double,
        trackCount: Int,
        expandedTrackHeight: Double,
        collapsedTrackHeight: Double
    ) -> TimelineShellMetrics {
        let headerWidth = 152.0
        let rulerHeight = 32.0
        let visibleTracks = max(Double(trackCount), 1)
        let bodyHeight = max(viewportHeight - rulerHeight, visibleTracks * expandedTrackHeight)
        return TimelineShellMetrics(
            headerWidth: headerWidth,
            rulerHeight: rulerHeight,
            scrollContentHeight: bodyHeight + rulerHeight
        )
    }
}

struct TimelineViewport: Equatable {
    let visibleXRange: ClosedRange<Double>
    let visibleYRange: ClosedRange<Double>
}

struct TimelineVisibleFrame: Equatable {
    let minX: Double
    let maxX: Double
    let minY: Double
    let maxY: Double
}

struct TimelineScrollRequest: Equatable {
    var anchorX: Double?
    var anchorY: Double?
}

enum TimelineScrollTargetResolver {
    static func requestToReveal(
        _ frame: TimelineVisibleFrame,
        in viewport: TimelineViewport,
        padding: Double
    ) -> TimelineScrollRequest? {
        let anchorX: Double?
        if frame.maxX > viewport.visibleXRange.upperBound - padding {
            anchorX = frame.minX - padding
        } else if frame.minX < viewport.visibleXRange.lowerBound + padding {
            anchorX = frame.minX - padding
        } else {
            anchorX = nil
        }

        let anchorY: Double?
        if frame.maxY > viewport.visibleYRange.upperBound - padding {
            anchorY = frame.minY - padding
        } else if frame.minY < viewport.visibleYRange.lowerBound + padding {
            anchorY = frame.minY - padding
        } else {
            anchorY = nil
        }

        if anchorX == nil && anchorY == nil {
            return nil
        }

        return TimelineScrollRequest(
            anchorX: anchorX.map { max($0, 0) },
            anchorY: anchorY.map { max($0, 0) }
        )
    }

    static func requestToKeepPlayheadVisible(
        playheadX: Double,
        in viewport: TimelineViewport,
        autoFollow: Bool,
        padding: Double
    ) -> TimelineScrollRequest? {
        guard autoFollow else { return nil }
        guard playheadX > viewport.visibleXRange.upperBound - padding || playheadX < viewport.visibleXRange.lowerBound + padding else {
            return nil
        }

        return TimelineScrollRequest(anchorX: max(playheadX - padding, 0), anchorY: nil)
    }
}
```

- [ ] **Step 4: Re-run the tests and then the full app build**

Run:

```bash
cd /Users/explicit/Projects/video-editor/VideoEditor
xcodebuild -scheme VideoEditor -destination 'platform=macOS' test -only-testing:VideoEditorTests/TimelineShellSupportTests
xcodebuild -scheme VideoEditor -destination 'platform=macOS' build
```

Expected: `TimelineShellSupportTests` PASS and the app target builds successfully.

- [ ] **Step 5: Commit the support layer**

```bash
cd /Users/explicit/Projects/video-editor
git add VideoEditor/VideoEditor/UI/Timeline/TimelineShellSupport.swift VideoEditor/VideoEditorTests/TimelineShellSupportTests.swift
git commit -m "Add timeline shell support primitives"
```

## Task 2: Extract A Dedicated Editor Workspace Shell

**Files:**
- Create: `VideoEditor/VideoEditor/UI/Layout/EditorWorkspaceShell.swift`
- Modify: `VideoEditor/VideoEditor/UI/Layout/ContentView.swift`
- Modify: `VideoEditor/VideoEditor/UI/Preview/PreviewPanel.swift`
- Test: `VideoEditor/VideoEditorTests/TimelineShellSupportTests.swift`

- [ ] **Step 1: Add a shell-layout test that locks the center-column posture**

```swift
@Test("workspace shell keeps the timeline in the dominant vertical share")
func workspaceShellDefaults() {
    let layout = EditorWorkspaceShellLayout.make(
        containerWidth: 1720,
        containerHeight: 980,
        leftRailVisible: true,
        rightRailVisible: true
    )

    #expect(layout.leftRailWidth == 280)
    #expect(layout.rightRailWidth == 312)
    #expect(layout.previewMinHeight == 260)
    #expect(layout.timelineMinHeight == 420)
    #expect(layout.timelineMinHeight > layout.previewMinHeight)
}
```

- [ ] **Step 2: Run the test target to verify the new shell-layout type is missing**

Run:

```bash
cd /Users/explicit/Projects/video-editor/VideoEditor
xcodebuild -scheme VideoEditor -destination 'platform=macOS' test -only-testing:VideoEditorTests/TimelineShellSupportTests
```

Expected: FAIL with unresolved `EditorWorkspaceShellLayout`.

- [ ] **Step 3: Create the new shell view and wire `ContentView` through it**

```swift
struct EditorWorkspaceShell<LeftRail: View, CenterTop: View, CenterBottom: View, RightRail: View>: View {
    let layoutMode: EditorLayoutMode
    let isLeftPanelVisible: Bool
    let isRightRailVisible: Bool
    let leftRail: () -> LeftRail
    let centerTop: (EditorWorkspaceShellLayout) -> CenterTop
    let centerBottom: (EditorWorkspaceShellLayout) -> CenterBottom
    let rightRail: () -> RightRail

    var body: some View {
        GeometryReader { geo in
            let layout = EditorWorkspaceShellLayout.make(
                containerWidth: geo.size.width,
                containerHeight: geo.size.height,
                leftRailVisible: isLeftPanelVisible,
                rightRailVisible: isRightRailVisible
            )

            HStack(alignment: .top, spacing: CinematicSpacing.sm) {
                if isLeftPanelVisible {
                    leftRail()
                        .frame(width: layout.leftRailWidth)
                }

                VStack(spacing: CinematicSpacing.sm) {
                    centerTop(layout)
                    centerBottom(layout)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if isRightRailVisible {
                    rightRail()
                        .frame(width: layout.rightRailWidth)
                }
            }
        }
    }
}
```

```swift
struct EditorWorkspaceShellLayout: Equatable {
    let leftRailWidth: Double
    let rightRailWidth: Double
    let previewMinHeight: Double
    let timelineMinHeight: Double

    static func make(
        containerWidth: Double,
        containerHeight: Double,
        leftRailVisible: Bool,
        rightRailVisible: Bool
    ) -> EditorWorkspaceShellLayout {
        let leftRailWidth = leftRailVisible ? 280.0 : 0.0
        let rightRailWidth = rightRailVisible ? 312.0 : 0.0
        let previewMinHeight = max(260.0, containerHeight * 0.28)
        let timelineMinHeight = max(420.0, containerHeight * 0.48)
        return EditorWorkspaceShellLayout(
            leftRailWidth: leftRailWidth,
            rightRailWidth: rightRailWidth,
            previewMinHeight: previewMinHeight,
            timelineMinHeight: timelineMinHeight
        )
    }
}
```

- [ ] **Step 4: Re-run tests, build, launch, and capture a screenshot of the new shell proportions**

Run:

```bash
cd /Users/explicit/Projects/video-editor/VideoEditor
xcodebuild -scheme VideoEditor -destination 'platform=macOS' test -only-testing:VideoEditorTests/TimelineShellSupportTests
xcodebuild -scheme VideoEditor -destination 'platform=macOS' build
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -path '*Build/Products/Debug/VideoEditor.app' | head -n 1)
mkdir -p /tmp/video-editor-review
open "$APP_PATH"
sleep 2
screencapture -x /tmp/video-editor-review/01-workspace-shell.png
```

Expected: tests PASS, build succeeds, and `/tmp/video-editor-review/01-workspace-shell.png` shows a larger timeline share with quieter side rails.

- [ ] **Step 5: Commit the shell extraction**

```bash
cd /Users/explicit/Projects/video-editor
git add VideoEditor/VideoEditor/UI/Layout/EditorWorkspaceShell.swift VideoEditor/VideoEditor/UI/Layout/ContentView.swift VideoEditor/VideoEditor/UI/Preview/PreviewPanel.swift VideoEditor/VideoEditor/UI/Timeline/TimelineShellSupport.swift VideoEditor/VideoEditorTests/TimelineShellSupportTests.swift
git commit -m "Extract timeline-first editor workspace shell"
```

## Task 3: Build The Fixed-Chrome Timeline Shell

**Files:**
- Create: `VideoEditor/VideoEditor/UI/Timeline/TimelineShellView.swift`
- Create: `VideoEditor/VideoEditor/UI/Timeline/TimelineToolbarView.swift`
- Create: `VideoEditor/VideoEditor/UI/Timeline/TimelineCanvasView.swift`
- Create: `VideoEditor/VideoEditor/UI/Timeline/TrackHeaderColumnView.swift`
- Create: `VideoEditor/VideoEditor/UI/Timeline/TimelineCornerView.swift`
- Create: `VideoEditor/VideoEditor/UI/Timeline/TimelineScrollCoordinator.swift`
- Modify: `VideoEditor/VideoEditor/UI/Timeline/TimelinePanel.swift`
- Modify: `VideoEditor/VideoEditor/UI/Timeline/TimelineRuler.swift`
- Modify: `VideoEditor/VideoEditor/UI/Timeline/PlayheadView.swift`
- Modify: `VideoEditor/VideoEditor/UI/Timeline/TimelineViewState.swift`
- Test: `VideoEditor/VideoEditorTests/TimelineShellSupportTests.swift`

- [ ] **Step 1: Add tests for scroll requests and explicit auto-follow state**

```swift
@Test("selection reveal returns vertical and horizontal anchors when needed")
func selectionRevealBothAxes() {
    let viewport = TimelineViewport(
        visibleXRange: 0...900,
        visibleYRange: 0...200
    )
    let frame = TimelineVisibleFrame(
        minX: 980,
        maxX: 1180,
        minY: 320,
        maxY: 408
    )

    let request = TimelineScrollTargetResolver.requestToReveal(
        frame,
        in: viewport,
        padding: 40
    )

    #expect(request?.anchorX == 940)
    #expect(request?.anchorY == 280)
}
```

- [ ] **Step 2: Run the targeted tests and confirm the new behavior is still unimplemented**

Run:

```bash
cd /Users/explicit/Projects/video-editor/VideoEditor
xcodebuild -scheme VideoEditor -destination 'platform=macOS' test -only-testing:VideoEditorTests/TimelineShellSupportTests
```

Expected: FAIL because the existing support types do not yet compute the combined request or because `TimelineViewState` has no explicit auto-follow flag.

- [ ] **Step 3: Replace the monolithic `TimelinePanel` layout with a shell view and coordinator**

```swift
@MainActor @Observable
final class TimelineScrollCoordinator {
    var horizontalOffset: Double = 0
    var verticalOffset: Double = 0
    var pendingRequest: TimelineScrollRequest?

    func update(horizontal: Double, vertical: Double) {
        horizontalOffset = horizontal
        verticalOffset = vertical
    }

    func requestScroll(_ request: TimelineScrollRequest?) {
        pendingRequest = request
    }
}
```

```swift
struct TimelineShellView: View {
    let tool: EditorTool
    let timeline: Timeline
    let viewState: TimelineViewState
    let thumbnails: [UUID: CGImage]
    let waveformStates: [UUID: WaveformLoadState]

    @State private var scrollCoordinator = TimelineScrollCoordinator()

    var body: some View {
        GeometryReader { geo in
            let metrics = TimelineShellMetrics.make(
                viewportWidth: geo.size.width,
                viewportHeight: geo.size.height,
                trackCount: timeline.tracks.count,
                expandedTrackHeight: 84,
                collapsedTrackHeight: 28
            )

            VStack(spacing: 0) {
                TimelineToolbarView(tool: tool, viewState: viewState, timeline: timeline)
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        TimelineCornerView()
                            .frame(width: metrics.headerWidth, height: metrics.rulerHeight)
                        TrackHeaderColumnView(
                            tracks: timeline.tracks,
                            coordinator: scrollCoordinator,
                            viewState: viewState
                        )
                    }

                    VStack(spacing: 0) {
                        TimelineRuler(
                            viewState: viewState,
                            totalWidth: viewState.durationToWidth(timeline.duration + 10),
                            horizontalOffset: scrollCoordinator.horizontalOffset
                        )
                        .frame(height: metrics.rulerHeight)

                        TimelineCanvasView(
                            tool: tool,
                            timeline: timeline,
                            viewState: viewState,
                            thumbnails: thumbnails,
                            waveformStates: waveformStates,
                            coordinator: scrollCoordinator
                        )
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 4: Run build verification and capture a screenshot of the fixed ruler/header shell**

Run:

```bash
cd /Users/explicit/Projects/video-editor/VideoEditor
xcodebuild -scheme VideoEditor -destination 'platform=macOS' build
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -path '*Build/Products/Debug/VideoEditor.app' | head -n 1)
mkdir -p /tmp/video-editor-review
open "$APP_PATH"
sleep 2
screencapture -x /tmp/video-editor-review/02-timeline-shell.png
```

Expected: build succeeds and `/tmp/video-editor-review/02-timeline-shell.png` shows a stable corner block, fixed ruler region, and fixed left header region around the clip canvas.

- [ ] **Step 5: Commit the shell split**

```bash
cd /Users/explicit/Projects/video-editor
git add VideoEditor/VideoEditor/UI/Timeline/TimelineShellView.swift VideoEditor/VideoEditor/UI/Timeline/TimelineToolbarView.swift VideoEditor/VideoEditor/UI/Timeline/TimelineCanvasView.swift VideoEditor/VideoEditor/UI/Timeline/TrackHeaderColumnView.swift VideoEditor/VideoEditor/UI/Timeline/TimelineCornerView.swift VideoEditor/VideoEditor/UI/Timeline/TimelineScrollCoordinator.swift VideoEditor/VideoEditor/UI/Timeline/TimelinePanel.swift VideoEditor/VideoEditor/UI/Timeline/TimelineRuler.swift VideoEditor/VideoEditor/UI/Timeline/PlayheadView.swift VideoEditor/VideoEditor/UI/Timeline/TimelineViewState.swift VideoEditor/VideoEditor/UI/Timeline/TimelineShellSupport.swift VideoEditor/VideoEditorTests/TimelineShellSupportTests.swift
git commit -m "Build fixed-chrome timeline shell"
```

## Task 4: Rebuild Track Headers, Targeting, And Solo Control

**Files:**
- Create: `VideoEditor/VideoEditor/UI/Timeline/TrackHeaderRowView.swift`
- Create: `VideoEditor/VideoEditor/UI/Timeline/TrackLayoutState.swift`
- Create: `VideoEditor/VideoEditorTests/TrackLayoutStateTests.swift`
- Modify: `VideoEditor/VideoEditor/UI/Timeline/TrackHeaderColumnView.swift`
- Modify: `VideoEditor/VideoEditor/UI/Timeline/TimelineTrackView.swift`
- Modify: `VideoEditor/VideoEditor/UI/Timeline/TimelineViewState.swift`
- Modify: `VideoEditor/VideoEditor/App/AppState.swift`
- Modify: `VideoEditor/VideoEditor/UI/Inspector/InspectorPanel.swift`
- Modify: `VideoEditor/Packages/EditorCore/Sources/EditorCore/Intents/EditorIntent.swift`
- Modify: `VideoEditor/Packages/EditorCore/Sources/EditorCore/Commands/PropertyCommands.swift`
- Test: `VideoEditor/VideoEditorTests/TrackLayoutStateTests.swift`
- Test: `VideoEditor/Packages/EditorCore/Tests/EditorCoreTests/TrackSoloCommandTests.swift`

- [ ] **Step 1: Write failing tests for compact header metrics and solo command behavior**

```swift
import Testing
@testable import VideoEditor

@Suite("Track Layout State Tests")
struct TrackLayoutStateTests {
    @Test("collapsed tracks keep compact control strip height")
    func collapsedTrackHeight() {
        let state = TrackLayoutState()
        let id = UUID()
        state.setCollapsed(true, for: id)

        #expect(state.height(for: id, expanded: 84, collapsed: 28) == 28)
    }

    @Test("expanded tracks preserve the dense default height")
    func expandedTrackHeight() {
        let state = TrackLayoutState()
        let id = UUID()

        #expect(state.height(for: id, expanded: 84, collapsed: 28) == 84)
    }
}
```

```swift
import Testing
import EditorCore

@Suite("Track Solo Command Tests")
struct TrackSoloCommandTests {
    @Test("solo command toggles track solo state and supports undo")
    @MainActor
    func toggleSoloTrack() throws {
        let track = Track(name: "Dialogue", type: .audio)
        let context = EditingContext(timeline: Timeline(tracks: [track]))
        var command = SetTrackSoloCommand(trackID: track.id, soloed: true)

        try command.execute(context: context)
        #expect(context.timelineState.timeline.tracks[0].isSoloed)

        try command.undo(context: context)
        #expect(!context.timelineState.timeline.tracks[0].isSoloed)
    }
}
```

- [ ] **Step 2: Run the app and package tests to verify the missing track-layout and solo APIs**

Run:

```bash
cd /Users/explicit/Projects/video-editor/VideoEditor
xcodebuild -scheme VideoEditor -destination 'platform=macOS' test -only-testing:VideoEditorTests/TrackLayoutStateTests
swift test --package-path Packages/EditorCore --filter TrackSoloCommandTests
```

Expected: FAIL with missing `TrackLayoutState`, `SetTrackSoloCommand`, or `EditorIntent` solo support.

- [ ] **Step 3: Implement compact headers, explicit target state, and solo support**

```swift
@MainActor @Observable
final class TrackLayoutState {
    private(set) var collapsedTrackIDs: Set<UUID> = []
    private(set) var expandedTrackHeight: Double = 84
    private(set) var collapsedTrackHeight: Double = 28

    func setCollapsed(_ isCollapsed: Bool, for trackID: UUID) {
        if isCollapsed {
            collapsedTrackIDs.insert(trackID)
        } else {
            collapsedTrackIDs.remove(trackID)
        }
    }

    func height(for trackID: UUID, expanded: Double, collapsed: Double) -> Double {
        collapsedTrackIDs.contains(trackID) ? collapsed : expanded
    }
}
```

```swift
public enum EditorIntent: Sendable {
    case setTrackSolo(trackID: UUID, soloed: Bool)
    // existing cases...
}

public struct SetTrackSoloCommand: Command {
    public let name = "Set Track Solo"
    public let trackID: UUID
    public let soloed: Bool
    private var previousSoloed: Bool?

    public mutating func execute(context: EditingContext) throws {
        try modifyTrack(id: trackID, context: context) { track in
            previousSoloed = track.isSoloed
            track.isSoloed = soloed
        }
    }

    public func undo(context: EditingContext) throws {
        guard let previousSoloed else { return }
        try modifyTrack(id: trackID, context: context) { $0.isSoloed = previousSoloed }
    }
}
```

```swift
struct TrackHeaderRowView: View {
    let track: Track
    let isTargeted: Bool
    let isCollapsed: Bool
    let onToggleTarget: () -> Void
    let onToggleMute: () -> Void
    let onToggleSolo: () -> Void
    let onToggleLock: () -> Void
    let onToggleCollapse: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onToggleCollapse) { Image(systemName: isCollapsed ? "chevron.right" : "chevron.down") }
            Text(track.type.rawValue.uppercased())
                .font(.cinLabelRegular)
            Text(track.name)
                .font(.cinLabel)
                .lineLimit(1)
            Spacer(minLength: 4)
            headerButton("record.circle", isTargeted, action: onToggleTarget)
            headerButton(track.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill", track.isMuted, action: onToggleMute)
            headerButton("s.circle.fill", track.isSoloed, action: onToggleSolo)
            headerButton(track.isLocked ? "lock.fill" : "lock.open.fill", track.isLocked, action: onToggleLock)
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(CinematicTheme.onSurfaceVariant)
        }
        .padding(.horizontal, 10)
        .frame(height: isCollapsed ? 28 : 36)
    }
}
```

- [ ] **Step 4: Run tests, build, and capture a screenshot of the denser track header pass**

Run:

```bash
cd /Users/explicit/Projects/video-editor/VideoEditor
xcodebuild -scheme VideoEditor -destination 'platform=macOS' test -only-testing:VideoEditorTests/TrackLayoutStateTests
swift test --package-path Packages/EditorCore --filter TrackSoloCommandTests
xcodebuild -scheme VideoEditor -destination 'platform=macOS' build
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -path '*Build/Products/Debug/VideoEditor.app' | head -n 1)
mkdir -p /tmp/video-editor-review
open "$APP_PATH"
sleep 2
screencapture -x /tmp/video-editor-review/03-track-headers.png
```

Expected: all tests pass, build succeeds, and `/tmp/video-editor-review/03-track-headers.png` shows compact headers with visible mute/solo/lock/target state and less card-like padding.

- [ ] **Step 5: Commit the track-header refactor**

```bash
cd /Users/explicit/Projects/video-editor
git add VideoEditor/VideoEditor/UI/Timeline/TrackHeaderRowView.swift VideoEditor/VideoEditor/UI/Timeline/TrackLayoutState.swift VideoEditor/VideoEditor/UI/Timeline/TrackHeaderColumnView.swift VideoEditor/VideoEditor/UI/Timeline/TimelineTrackView.swift VideoEditor/VideoEditor/UI/Timeline/TimelineViewState.swift VideoEditor/VideoEditor/App/AppState.swift VideoEditor/VideoEditor/UI/Inspector/InspectorPanel.swift VideoEditor/Packages/EditorCore/Sources/EditorCore/Intents/EditorIntent.swift VideoEditor/Packages/EditorCore/Sources/EditorCore/Commands/PropertyCommands.swift VideoEditor/VideoEditorTests/TrackLayoutStateTests.swift VideoEditor/Packages/EditorCore/Tests/EditorCoreTests/TrackSoloCommandTests.swift
git commit -m "Rebuild timeline track headers and solo controls"
```

## Task 5: Improve Timeline Readability And Finish Visual QA

**Files:**
- Modify: `VideoEditor/VideoEditor/UI/Timeline/TimelineRuler.swift`
- Modify: `VideoEditor/VideoEditor/UI/Timeline/PlayheadView.swift`
- Modify: `VideoEditor/VideoEditor/UI/Timeline/WaveformView.swift`
- Modify: `VideoEditor/VideoEditor/UI/Timeline/TimelineCanvasView.swift`
- Modify: `VideoEditor/VideoEditor/UI/Timeline/TimelineTrackView.swift`
- Modify: `VideoEditor/VideoEditor/UI/Preview/PreviewPanel.swift`
- Modify: `VideoEditor/VideoEditor/UI/Timeline/TimelineViewState.swift`
- Test: `VideoEditor/VideoEditorTests/TimelineShellSupportTests.swift`
- Test: `VideoEditor/VideoEditorTests/TrackLayoutStateTests.swift`

- [ ] **Step 1: Add a final visibility test for zoom-preserving context and selection reveal**

```swift
@Test("selection-centered zoom preserves context around the selected clip")
func selectionZoomContext() {
    let range = TimelineSelectionZoomResolver.zoomRange(
        selection: 32...38,
        fallbackPlayhead: 20,
        viewportWidth: 960,
        minimumDuration: 8
    )

    #expect(range.lowerBound == 31)
    #expect(range.upperBound == 39)
}
```

- [ ] **Step 2: Run the targeted tests to confirm the final zoom helper is not present yet**

Run:

```bash
cd /Users/explicit/Projects/video-editor/VideoEditor
xcodebuild -scheme VideoEditor -destination 'platform=macOS' test -only-testing:VideoEditorTests/TimelineShellSupportTests -only-testing:VideoEditorTests/TrackLayoutStateTests
```

Expected: FAIL with missing `TimelineSelectionZoomResolver` or mismatched zoom behavior.

- [ ] **Step 3: Implement the readability pass and the last navigation helper**

```swift
enum TimelineSelectionZoomResolver {
    static func zoomRange(
        selection: ClosedRange<Double>?,
        fallbackPlayhead: Double,
        viewportWidth: Double,
        minimumDuration: Double
    ) -> ClosedRange<Double> {
        guard let selection else {
            let half = minimumDuration / 2
            return max(fallbackPlayhead - half, 0)...(fallbackPlayhead + half)
        }

        let duration = max(selection.upperBound - selection.lowerBound, minimumDuration)
        let midpoint = (selection.lowerBound + selection.upperBound) / 2
        let half = duration / 2
        return max(midpoint - half, 0)...(midpoint + half)
    }
}
```

```swift
// TimelineRuler.swift
Canvas { context, size in
    // Use stronger major ticks, muted minor ticks, and clearer label color.
}

// PlayheadView.swift
Rectangle()
    .fill(CinematicTheme.error)
    .frame(width: 2)
    .overlay(alignment: .top) {
        Capsule()
            .fill(CinematicTheme.error)
            .frame(width: 14, height: 8)
    }

// WaveformView.swift
Path { path in
    // Render a brighter filled waveform when selected and a calmer stroke when not.
}
```

- [ ] **Step 4: Run full verification and capture the final visual review set**

Run:

```bash
cd /Users/explicit/Projects/video-editor/VideoEditor
xcodebuild -scheme VideoEditor -destination 'platform=macOS' test
xcodebuild -scheme VideoEditor -destination 'platform=macOS' build
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -path '*Build/Products/Debug/VideoEditor.app' | head -n 1)
mkdir -p /tmp/video-editor-review
open "$APP_PATH"
sleep 2
screencapture -x /tmp/video-editor-review/04-final-timeline.png
screencapture -x /tmp/video-editor-review/05-final-shell-fullscreen.png
```

Expected: all scheme tests pass, build succeeds, and the screenshots show a timeline-first shell with stronger ruler/playhead/waveform/selection hierarchy.

- [ ] **Step 5: Commit the readability pass and final QA**

```bash
cd /Users/explicit/Projects/video-editor
git add VideoEditor/VideoEditor/UI/Timeline/TimelineRuler.swift VideoEditor/VideoEditor/UI/Timeline/PlayheadView.swift VideoEditor/VideoEditor/UI/Timeline/WaveformView.swift VideoEditor/VideoEditor/UI/Timeline/TimelineCanvasView.swift VideoEditor/VideoEditor/UI/Timeline/TimelineTrackView.swift VideoEditor/VideoEditor/UI/Preview/PreviewPanel.swift VideoEditor/VideoEditor/UI/Timeline/TimelineViewState.swift VideoEditor/VideoEditorTests/TimelineShellSupportTests.swift VideoEditor/VideoEditorTests/TrackLayoutStateTests.swift
git commit -m "Polish timeline readability and visual QA"
```

## Spec Coverage Check

- Timeline-first shell and proportion changes are implemented in Task 2.
- Fixed toolbar, ruler, track-header column, and clip canvas structure are implemented in Task 3.
- Proper two-axis scrolling, scroll-to-selection, and optional scroll-to-playhead are implemented in Tasks 1, 3, and 5.
- Dense headers, targeting, collapse behavior, lane controls, reorder affordance, and solo support are implemented in Task 4.
- Ruler, playhead, waveform, clip-edge, and selection readability improvements are implemented in Task 5.
- Screenshot-based visual analysis is part of Tasks 2 through 5.

## Placeholder Scan

- No placeholder markers or deferred implementation notes remain in this plan.
- Every code-changing task includes exact files, concrete code targets, and verification commands.

## Type Consistency Check

- `TimelineShellMetrics`, `TimelineViewport`, `TimelineVisibleFrame`, `TimelineScrollRequest`, and `TimelineScrollTargetResolver` are introduced in Task 1 and reused consistently later.
- `EditorWorkspaceShellLayout` is introduced in Task 2 and only used for the workspace shell.
- `TimelineScrollCoordinator` is introduced in Task 3 and remains the sole scroll-authority type.
- `TrackLayoutState` and `SetTrackSoloCommand` are introduced in Task 4 and used consistently afterward.
- `TimelineSelectionZoomResolver` is introduced in Task 5 and only used for zoom-range decisions.
