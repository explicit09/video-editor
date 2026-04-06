# Panel Workspace Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current fixed-shell, cinematic editor UI with a drag-and-drop dockable panel system, workspace-specific layouts, a utilitarian design system, dual monitors in `Edit`, and corrected selection/inspector behavior across all major workspaces.

**Architecture:** Introduce a dedicated docking subsystem that owns panel definitions, dock layout trees, drag/drop coordination, and persisted workspace layouts. Rebuild each workspace on top of that system, starting with shared chrome and layout infrastructure, then `Edit`, then `Media`, `Transcript`/`AI`, and `Deliver`, while keeping editing-domain mutations on the existing `EditorIntent -> Command -> Execute` path and keeping panel/layout state separate from editor-core state.

**Tech Stack:** Swift 6, SwiftUI, AppKit interop for measurement/drag support where necessary, EditorCore command pipeline, Apple `Testing`, XcodeGen / `xcodebuild`

---

## File Structure

### Create

- `VideoEditor/VideoEditor/UI/Docking/DockLayoutModel.swift`
  - Define `PanelID`, `PanelDefinition`, `DockLayoutNode`, `DockWorkspaceLayout`, and supporting model types.
- `VideoEditor/VideoEditor/UI/Docking/DockingCoordinator.swift`
  - Hold drag state, drop previews, active panel focus, and docking mutations.
- `VideoEditor/VideoEditor/UI/Docking/WorkspaceLayoutStore.swift`
  - Load, save, validate, reset, and migrate workspace-specific layouts.
- `VideoEditor/VideoEditor/UI/Docking/PanelRegistry.swift`
  - Register first-class panel definitions and default workspace layouts.
- `VideoEditor/VideoEditor/UI/Docking/DockHostView.swift`
  - Render split containers, tab stacks, and panel hosts from a `DockLayoutNode`.
- `VideoEditor/VideoEditor/UI/Docking/DockTabStripView.swift`
  - Render draggable tabs, overflow behavior, and active panel affordances.
- `VideoEditor/VideoEditor/UI/Docking/DockDropOverlayView.swift`
  - Render split/tab drop previews during docking.
- `VideoEditor/VideoEditor/UI/Layout/WorkspacePageBar.swift`
  - Replace the current oversized left-side workspace rail with a top workspace/page bar.
- `VideoEditor/VideoEditor/UI/Theme/UtilityDesignSystem.swift`
  - Introduce flatter surfaces, denser controls, tab chrome, and compact panel header primitives.
- `VideoEditor/VideoEditor/UI/Panels/SourceMonitorPanel.swift`
  - Provide a dedicated source monitor panel for source-side viewing and mark in/out behavior.
- `VideoEditor/VideoEditor/UI/Panels/ProgramMonitorPanel.swift`
  - Provide a dedicated program monitor panel for timeline/program output.
- `VideoEditor/VideoEditor/UI/Panels/EffectsPanel.swift`
  - Provide a dockable effects/tools panel for `Edit`.
- `VideoEditor/VideoEditor/UI/Panels/DeliverPanel.swift`
  - Provide a dockable deliver/export surface.
- `VideoEditor/VideoEditorTests/DockLayoutModelTests.swift`
  - Cover dock-tree creation, mutation, and serialization.
- `VideoEditor/VideoEditorTests/DockingCoordinatorTests.swift`
  - Cover docking previews, split targets, tab targets, and minimum-size enforcement.
- `VideoEditor/VideoEditorTests/WorkspaceLayoutStoreTests.swift`
  - Cover workspace-specific persistence, reset, and migration fallback.
- `VideoEditor/VideoEditorTests/SelectionBehaviorTests.swift`
  - Cover single selection, modifier multi-selection, linked clip behavior, and inspector context resolution.

### Modify

- `VideoEditor/VideoEditor/UI/Layout/ContentView.swift`
  - Replace hardcoded workspace composition with the new page bar plus dock-host wiring.
- `VideoEditor/VideoEditor/UI/Theme/DesignSystem.swift`
  - Either slim this down to compatibility helpers or remove usages in favor of the new utility system.
- `VideoEditor/VideoEditor/UI/Preview/PreviewPanel.swift`
  - Extract reusable monitor content needed by source/program monitor panels.
- `VideoEditor/VideoEditor/UI/MediaBrowser/MediaBrowserPanel.swift`
  - Adapt to the new panel header and compact-rail behavior.
- `VideoEditor/VideoEditor/UI/MediaBrowser/MediaWorkspacePanel.swift`
  - Break out media-specific panel composition to fit the dock system.
- `VideoEditor/VideoEditor/UI/Transcript/TranscriptPanel.swift`
  - Adapt transcript interactions and layout assumptions for dock-host embedding.
- `VideoEditor/VideoEditor/UI/Inspector/InspectorPanel.swift`
  - Rebuild inspector sections for denser utilitarian presentation and new multi-select posture.
- `VideoEditor/VideoEditor/UI/Timeline/TimelinePanel.swift`
  - Embed timeline into dock panels and preserve timeline-shell behavior inside the new system.
- `VideoEditor/VideoEditor/App/AppState.swift`
  - Correct linked-selection semantics and expose workspace-layout coordination hooks without mixing layout state into the editor core.
- `VideoEditor/VideoEditor/UI/Layout/EditorWorkspaceShell.swift`
  - Remove or replace with dock-host composition once the new system is active.

### Keep As-Is Unless Blocked

- `VideoEditor/Packages/EditorCore/**`
  - Avoid command-pipeline changes unless required for selection semantics or dual-monitor source/program support.
- `VideoEditor/project.yml`
  - Only update if new explicit file references or groups are required after adding the docking subsystem.

---

## Task 1: Build the Dock Layout Model and Persistence Foundation

**Files:**
- Create: `VideoEditor/VideoEditor/UI/Docking/DockLayoutModel.swift`
- Create: `VideoEditor/VideoEditor/UI/Docking/WorkspaceLayoutStore.swift`
- Test: `VideoEditor/VideoEditorTests/DockLayoutModelTests.swift`
- Test: `VideoEditor/VideoEditorTests/WorkspaceLayoutStoreTests.swift`

- [ ] **Step 1: Write the failing model and persistence tests**

```swift
import Foundation
import Testing
@testable import VideoEditor

@Suite("Dock Layout Model Tests")
struct DockLayoutModelTests {
    @Test("dock layout encodes and decodes split and tab nodes")
    func dockLayoutRoundTrip() throws {
        let layout = DockWorkspaceLayout(
            workspaceID: "edit",
            root: .split(
                axis: .vertical,
                ratio: 0.62,
                leading: .tabs(activePanelID: .programMonitor, panelIDs: [.sourceMonitor, .programMonitor]),
                trailing: .panel(.timeline)
            )
        )

        let data = try JSONEncoder().encode(layout)
        let decoded = try JSONDecoder().decode(DockWorkspaceLayout.self, from: data)

        #expect(decoded == layout)
    }

    @Test("workspace layout store falls back to defaults when persisted layout references unknown panels")
    func workspaceLayoutFallback() throws {
        let defaults = WorkspaceDefaultLayouts.make()
        let store = WorkspaceLayoutStore(
            defaults: defaults,
            fileManager: .default,
            baseURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )

        try store.save(
            DockWorkspaceLayout(
                workspaceID: "edit",
                root: .tabs(activePanelID: PanelID(rawValue: "missing"), panelIDs: [PanelID(rawValue: "missing")])
            )
        )

        let resolved = try store.loadLayout(for: "edit")

        #expect(resolved == defaults["edit"])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
cd /Users/explicit/Projects/video-editor/.worktrees/timeline-shell-redesign/VideoEditor
xcodebuild -scheme VideoEditor -destination 'platform=macOS' test \
  -only-testing:VideoEditorTests/DockLayoutModelTests \
  -only-testing:VideoEditorTests/WorkspaceLayoutStoreTests
```

Expected: FAIL with missing `DockWorkspaceLayout`, `PanelID`, `WorkspaceLayoutStore`, or `WorkspaceDefaultLayouts` symbols.

- [ ] **Step 3: Implement the minimal dock model and workspace store**

```swift
import Foundation

struct PanelID: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    let rawValue: String

    init(rawValue: String) { self.rawValue = rawValue }
    init(stringLiteral value: String) { self.rawValue = value }

    static let projectBin: PanelID = "project-bin"
    static let sourceMonitor: PanelID = "source-monitor"
    static let programMonitor: PanelID = "program-monitor"
    static let timeline: PanelID = "timeline"
    static let inspector: PanelID = "inspector"
}

enum DockAxis: String, Codable, Sendable {
    case horizontal
    case vertical
}

indirect enum DockLayoutNode: Codable, Equatable, Sendable {
    case panel(PanelID)
    case tabs(activePanelID: PanelID, panelIDs: [PanelID])
    case split(axis: DockAxis, ratio: Double, leading: DockLayoutNode, trailing: DockLayoutNode)
}

struct DockWorkspaceLayout: Codable, Equatable, Sendable {
    let workspaceID: String
    let root: DockLayoutNode
}

enum WorkspaceDefaultLayouts {
    static func make() -> [String: DockWorkspaceLayout] {
        [
            "edit": DockWorkspaceLayout(
                workspaceID: "edit",
                root: .split(
                    axis: .vertical,
                    ratio: 0.64,
                    leading: .split(
                        axis: .horizontal,
                        ratio: 0.5,
                        leading: .tabs(activePanelID: .sourceMonitor, panelIDs: [.projectBin, .sourceMonitor]),
                        trailing: .panel(.programMonitor)
                    ),
                    trailing: .panel(.timeline)
                )
            )
        ]
    }
}

struct WorkspaceLayoutStore {
    let defaults: [String: DockWorkspaceLayout]
    let fileManager: FileManager
    let baseURL: URL

    func loadLayout(for workspaceID: String) throws -> DockWorkspaceLayout {
        let url = baseURL.appendingPathComponent("\(workspaceID).json")
        guard fileManager.fileExists(atPath: url.path) else {
            return defaults[workspaceID]!
        }

        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode(DockWorkspaceLayout.self, from: data)
        return validate(decoded) ? decoded : defaults[workspaceID]!
    }

    func save(_ layout: DockWorkspaceLayout) throws {
        try fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(layout)
        try data.write(to: baseURL.appendingPathComponent("\(layout.workspaceID).json"))
    }

    private func validate(_ layout: DockWorkspaceLayout) -> Bool {
        let knownPanels: Set<PanelID> = [.projectBin, .sourceMonitor, .programMonitor, .timeline, .inspector]
        return layout.root.panelIDs.allSatisfy(knownPanels.contains)
    }
}

private extension DockLayoutNode {
    var panelIDs: [PanelID] {
        switch self {
        case let .panel(id): [id]
        case let .tabs(_, panelIDs): panelIDs
        case let .split(_, _, leading, trailing): leading.panelIDs + trailing.panelIDs
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:

```bash
cd /Users/explicit/Projects/video-editor/.worktrees/timeline-shell-redesign/VideoEditor
xcodebuild -scheme VideoEditor -destination 'platform=macOS' test \
  -only-testing:VideoEditorTests/DockLayoutModelTests \
  -only-testing:VideoEditorTests/WorkspaceLayoutStoreTests
```

Expected: PASS for the new dock-model and workspace-layout tests.

- [ ] **Step 5: Commit**

```bash
git -C /Users/explicit/Projects/video-editor/.worktrees/timeline-shell-redesign add \
  VideoEditor/VideoEditor/UI/Docking/DockLayoutModel.swift \
  VideoEditor/VideoEditor/UI/Docking/WorkspaceLayoutStore.swift \
  VideoEditor/VideoEditorTests/DockLayoutModelTests.swift \
  VideoEditor/VideoEditorTests/WorkspaceLayoutStoreTests.swift
git -C /Users/explicit/Projects/video-editor/.worktrees/timeline-shell-redesign commit -m "Add dock layout model and workspace persistence"
```

---

## Task 2: Build the Docking Coordinator, Tab Strip, and Drop Overlay

**Files:**
- Create: `VideoEditor/VideoEditor/UI/Docking/DockingCoordinator.swift`
- Create: `VideoEditor/VideoEditor/UI/Docking/DockTabStripView.swift`
- Create: `VideoEditor/VideoEditor/UI/Docking/DockDropOverlayView.swift`
- Test: `VideoEditor/VideoEditorTests/DockingCoordinatorTests.swift`

- [ ] **Step 1: Write the failing docking-coordination tests**

```swift
import Testing
@testable import VideoEditor

@Suite("Docking Coordinator Tests")
struct DockingCoordinatorTests {
    @Test("drop target resolves tab insertion inside a tab strip")
    func tabInsertionTarget() {
        let coordinator = DockingCoordinator()
        let target = coordinator.resolveDropTarget(
            point: CGPoint(x: 120, y: 16),
            frame: CGRect(x: 0, y: 0, width: 240, height: 32),
            allowedBehavior: .tabs
        )

        #expect(target == .tabStack)
    }

    @Test("drop target resolves edge split when hovering near a panel edge")
    func edgeSplitTarget() {
        let coordinator = DockingCoordinator()
        let target = coordinator.resolveDropTarget(
            point: CGPoint(x: 8, y: 120),
            frame: CGRect(x: 0, y: 0, width: 320, height: 240),
            allowedBehavior: .splitOrTabs
        )

        #expect(target == .splitLeading)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
cd /Users/explicit/Projects/video-editor/.worktrees/timeline-shell-redesign/VideoEditor
xcodebuild -scheme VideoEditor -destination 'platform=macOS' test -only-testing:VideoEditorTests/DockingCoordinatorTests
```

Expected: FAIL with missing `DockingCoordinator`, `DockDropBehavior`, or `DockDropTarget` symbols.

- [ ] **Step 3: Implement the minimal coordinator and overlay contracts**

```swift
import CoreGraphics
import Foundation

enum DockDropBehavior {
    case tabs
    case splitOrTabs
}

enum DockDropTarget: Equatable {
    case tabStack
    case splitLeading
    case splitTrailing
    case splitTop
    case splitBottom
}

@MainActor
final class DockingCoordinator: ObservableObject {
    @Published var activeDropTarget: DockDropTarget?
    @Published var draggedPanelID: PanelID?

    func beginDrag(panelID: PanelID) {
        draggedPanelID = panelID
    }

    func endDrag() {
        draggedPanelID = nil
        activeDropTarget = nil
    }

    func resolveDropTarget(
        point: CGPoint,
        frame: CGRect,
        allowedBehavior: DockDropBehavior
    ) -> DockDropTarget? {
        let inset = min(frame.width, frame.height) * 0.18
        if allowedBehavior == .tabs,
           CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: 36).contains(point) {
            return .tabStack
        }
        if point.x <= frame.minX + inset { return .splitLeading }
        if point.x >= frame.maxX - inset { return .splitTrailing }
        if point.y <= frame.minY + inset { return .splitTop }
        if point.y >= frame.maxY - inset { return .splitBottom }
        return allowedBehavior == .splitOrTabs ? .tabStack : nil
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:

```bash
cd /Users/explicit/Projects/video-editor/.worktrees/timeline-shell-redesign/VideoEditor
xcodebuild -scheme VideoEditor -destination 'platform=macOS' test -only-testing:VideoEditorTests/DockingCoordinatorTests
```

Expected: PASS for drop-target resolution tests.

- [ ] **Step 5: Commit**

```bash
git -C /Users/explicit/Projects/video-editor/.worktrees/timeline-shell-redesign add \
  VideoEditor/VideoEditor/UI/Docking/DockingCoordinator.swift \
  VideoEditor/VideoEditor/UI/Docking/DockTabStripView.swift \
  VideoEditor/VideoEditor/UI/Docking/DockDropOverlayView.swift \
  VideoEditor/VideoEditorTests/DockingCoordinatorTests.swift
git -C /Users/explicit/Projects/video-editor/.worktrees/timeline-shell-redesign commit -m "Add docking coordinator and drop-target support"
```

---

## Task 3: Replace the Current Workspace Chrome With a Utility-First Shell

**Files:**
- Create: `VideoEditor/VideoEditor/UI/Layout/WorkspacePageBar.swift`
- Create: `VideoEditor/VideoEditor/UI/Theme/UtilityDesignSystem.swift`
- Modify: `VideoEditor/VideoEditor/UI/Layout/ContentView.swift`
- Modify: `VideoEditor/VideoEditor/UI/Theme/DesignSystem.swift`
- Test: `VideoEditor/VideoEditorTests/EditorStabilizationSupportTests.swift`

- [ ] **Step 1: Write the failing layout-support test for top-page navigation**

```swift
import Testing
@testable import VideoEditor

@Suite("Workspace Page Bar Tests")
struct WorkspacePageBarTests {
    @Test("workspace bar preserves compact height and does not require the legacy side rail")
    func workspaceBarMetrics() {
        let metrics = WorkspacePageBarMetrics.make(containerWidth: 1440)

        #expect(metrics.barHeight == 36)
        #expect(metrics.showsLabels == true)
        #expect(metrics.usesVerticalRail == false)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
cd /Users/explicit/Projects/video-editor/.worktrees/timeline-shell-redesign/VideoEditor
xcodebuild -scheme VideoEditor -destination 'platform=macOS' test -only-testing:VideoEditorTests/EditorStabilizationSupportTests
```

Expected: FAIL with missing `WorkspacePageBarMetrics` symbols until the new page-bar support types exist.

- [ ] **Step 3: Implement the page bar and swap out the legacy side navigation**

```swift
struct WorkspacePageBar: View {
    let workspaces: [ContentView.Workspace]
    let selection: ContentView.Workspace
    let onSelect: (ContentView.Workspace) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(workspaces, id: \.self) { workspace in
                Button(workspace.rawValue) { onSelect(workspace) }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: selection == workspace ? .semibold : .medium))
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(selection == workspace ? Color(nsColor: .controlAccentColor).opacity(0.14) : .clear)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(selection == workspace ? Color(nsColor: .controlAccentColor) : .clear)
                            .frame(height: 2)
                    }
            }
            Spacer(minLength: 0)
        }
        .frame(height: 36)
        .padding(.horizontal, 10)
    }
}
```

- [ ] **Step 4: Run build and targeted tests to verify the shell still compiles**

Run:

```bash
cd /Users/explicit/Projects/video-editor/.worktrees/timeline-shell-redesign/VideoEditor
xcodebuild -scheme VideoEditor -destination 'platform=macOS' build
```

Expected: BUILD SUCCEEDED with the left vertical workspace rail removed from the main window shell.

- [ ] **Step 5: Commit**

```bash
git -C /Users/explicit/Projects/video-editor/.worktrees/timeline-shell-redesign add \
  VideoEditor/VideoEditor/UI/Layout/WorkspacePageBar.swift \
  VideoEditor/VideoEditor/UI/Theme/UtilityDesignSystem.swift \
  VideoEditor/VideoEditor/UI/Layout/ContentView.swift \
  VideoEditor/VideoEditor/UI/Theme/DesignSystem.swift
git -C /Users/explicit/Projects/video-editor/.worktrees/timeline-shell-redesign commit -m "Replace workspace chrome with top page bar"
```

---

## Task 4: Rebuild `Edit` on the Dock Host and Fix Selection Semantics

**Files:**
- Create: `VideoEditor/VideoEditor/UI/Panels/SourceMonitorPanel.swift`
- Create: `VideoEditor/VideoEditor/UI/Panels/ProgramMonitorPanel.swift`
- Create: `VideoEditor/VideoEditor/UI/Panels/EffectsPanel.swift`
- Modify: `VideoEditor/VideoEditor/UI/Layout/ContentView.swift`
- Modify: `VideoEditor/VideoEditor/UI/Preview/PreviewPanel.swift`
- Modify: `VideoEditor/VideoEditor/App/AppState.swift`
- Modify: `VideoEditor/VideoEditor/UI/Inspector/InspectorPanel.swift`
- Test: `VideoEditor/VideoEditorTests/SelectionBehaviorTests.swift`

- [ ] **Step 1: Write the failing tests for single-click selection and linked-clip behavior**

```swift
import Foundation
import Testing
@testable import EditorCore
@testable import VideoEditor

@Suite("Selection Behavior Tests")
struct SelectionBehaviorTests {
    @MainActor
    @Test("normal clip selection keeps focus on the clicked clip even when clips are linked")
    func singleSelectionDoesNotPromoteToLinkedGroup() {
        let appState = AppState()
        let groupID = UUID()
        let video = Clip(assetID: UUID(), timelineRange: .init(start: 0, end: 5), sourceRange: .init(start: 0, end: 5), linkGroupID: groupID)
        let audio = Clip(assetID: UUID(), timelineRange: .init(start: 0, end: 5), sourceRange: .init(start: 0, end: 5), linkGroupID: groupID)
        appState.context.timelineState.timeline = Timeline(tracks: [
            Track(name: "Video", type: .video, clips: [video]),
            Track(name: "Audio", type: .audio, clips: [audio])
        ])

        appState.toggleClipSelection(video.id, extend: false)

        #expect(appState.timelineViewState.selectedClipIDs == [video.id])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
cd /Users/explicit/Projects/video-editor/.worktrees/timeline-shell-redesign/VideoEditor
xcodebuild -scheme VideoEditor -destination 'platform=macOS' test -only-testing:VideoEditorTests/SelectionBehaviorTests
```

Expected: FAIL because `toggleClipSelection` currently promotes ordinary selection to the full linked group.

- [ ] **Step 3: Implement the `Edit` dock defaults and correct selection semantics**

```swift
func toggleClipSelection(_ clipID: UUID, extend: Bool) {
    guard let selectedTrackID = trackID(for: clipID) else { return }

    if extend {
        let clipIDs = linkedSelectionIDs(for: clipID)
        let isEntireGroupSelected = clipIDs.allSatisfy { timelineViewState.selectedClipIDs.contains($0) }
        if isEntireGroupSelected {
            clipIDs.forEach { timelineViewState.selectedClipIDs.remove($0) }
        } else {
            clipIDs.forEach { timelineViewState.selectedClipIDs.insert($0) }
        }
        timelineViewState.selectedTrackID = selectedTrackID
    } else {
        timelineViewState.selectClip(clipID, in: selectedTrackID)
    }

    timelineViewState.lastSelectedClipID = clipID
}
```

- [ ] **Step 4: Run targeted tests, build, and capture the first visual checkpoint**

Run:

```bash
cd /Users/explicit/Projects/video-editor/.worktrees/timeline-shell-redesign/VideoEditor
xcodebuild -scheme VideoEditor -destination 'platform=macOS' test -only-testing:VideoEditorTests/SelectionBehaviorTests
xcodebuild -scheme VideoEditor -destination 'platform=macOS' build
```

Expected: PASS for the selection tests, BUILD SUCCEEDED, and the `Edit` workspace should show source/program monitors with the workspace page bar active.

Screenshot checkpoint:

- Capture `Edit` workspace full window
- Capture single-clip inspector state
- Capture dock-tab drag preview if available

- [ ] **Step 5: Commit**

```bash
git -C /Users/explicit/Projects/video-editor/.worktrees/timeline-shell-redesign add \
  VideoEditor/VideoEditor/UI/Panels/SourceMonitorPanel.swift \
  VideoEditor/VideoEditor/UI/Panels/ProgramMonitorPanel.swift \
  VideoEditor/VideoEditor/UI/Panels/EffectsPanel.swift \
  VideoEditor/VideoEditor/UI/Layout/ContentView.swift \
  VideoEditor/VideoEditor/UI/Preview/PreviewPanel.swift \
  VideoEditor/VideoEditor/App/AppState.swift \
  VideoEditor/VideoEditor/UI/Inspector/InspectorPanel.swift \
  VideoEditor/VideoEditorTests/SelectionBehaviorTests.swift
git -C /Users/explicit/Projects/video-editor/.worktrees/timeline-shell-redesign commit -m "Rebuild edit workspace on dock host"
```

---

## Task 5: Rebuild `Media`, `Transcript`, and `AI` Workspaces on the Shared Dock System

**Files:**
- Modify: `VideoEditor/VideoEditor/UI/MediaBrowser/MediaBrowserPanel.swift`
- Modify: `VideoEditor/VideoEditor/UI/MediaBrowser/MediaWorkspacePanel.swift`
- Modify: `VideoEditor/VideoEditor/UI/Transcript/TranscriptPanel.swift`
- Modify: `VideoEditor/VideoEditor/UI/Layout/ContentView.swift`
- Modify: `VideoEditor/VideoEditor/UI/Inspector/InspectorPanel.swift`
- Test: `VideoEditor/Packages/EditorCore/Tests/EditorCoreTests/MediaManagementTests.swift`
- Test: `VideoEditor/Packages/EditorCore/Tests/EditorCoreTests/CompositionBuilderTests.swift`

- [ ] **Step 1: Write the failing UI-support tests for compact panel header reflow**

```swift
import Testing
@testable import VideoEditor

@Suite("Compact Panel Header Tests")
struct CompactPanelHeaderTests {
    @Test("panel header collapses badges before clipping the primary action")
    func compactHeaderPriority() {
        let layout = CompactPanelHeaderLayout.make(availableWidth: 220, badgeCount: 2, showsPrimaryAction: true)

        #expect(layout.showsPrimaryAction == true)
        #expect(layout.showsSecondaryBadges == false)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
cd /Users/explicit/Projects/video-editor/.worktrees/timeline-shell-redesign/VideoEditor
xcodebuild -scheme VideoEditor -destination 'platform=macOS' test -only-testing:VideoEditorTests/EditorStabilizationSupportTests
```

Expected: FAIL with missing `CompactPanelHeaderLayout` until compact header priorities are implemented.

- [ ] **Step 3: Implement the workspace migrations and compact-rail behavior**

```swift
struct CompactPanelHeaderLayout {
    let showsPrimaryAction: Bool
    let showsSecondaryBadges: Bool

    static func make(availableWidth: Double, badgeCount: Int, showsPrimaryAction: Bool) -> CompactPanelHeaderLayout {
        if availableWidth < 236 {
            return CompactPanelHeaderLayout(
                showsPrimaryAction: showsPrimaryAction,
                showsSecondaryBadges: false
            )
        }
        return CompactPanelHeaderLayout(
            showsPrimaryAction: showsPrimaryAction,
            showsSecondaryBadges: badgeCount > 0
        )
    }
}
```

- [ ] **Step 4: Run workspace regression tests and build**

Run:

```bash
cd /Users/explicit/Projects/video-editor/.worktrees/timeline-shell-redesign/VideoEditor
xcodebuild -scheme VideoEditor -destination 'platform=macOS' test \
  -only-testing:EditorCoreTests/MediaManagementTests \
  -only-testing:EditorCoreTests/CompositionBuilderTests
xcodebuild -scheme VideoEditor -destination 'platform=macOS' build
```

Expected: PASS for media thumbnails and preview-quality tests, BUILD SUCCEEDED, and the `Media`, `Transcript`, and `AI` workspaces should all be available as docked layouts.

Screenshot checkpoints:

- `Media` workspace at normal width
- `Media` workspace at reduced width, confirming header reflow
- `Transcript` workspace with transcript-primary layout
- `AI` workspace with AI dominant and hidden by default from `Edit`

- [ ] **Step 5: Commit**

```bash
git -C /Users/explicit/Projects/video-editor/.worktrees/timeline-shell-redesign add \
  VideoEditor/VideoEditor/UI/MediaBrowser/MediaBrowserPanel.swift \
  VideoEditor/VideoEditor/UI/MediaBrowser/MediaWorkspacePanel.swift \
  VideoEditor/VideoEditor/UI/Transcript/TranscriptPanel.swift \
  VideoEditor/VideoEditor/UI/Layout/ContentView.swift \
  VideoEditor/VideoEditor/UI/Inspector/InspectorPanel.swift
git -C /Users/explicit/Projects/video-editor/.worktrees/timeline-shell-redesign commit -m "Migrate media transcript and AI workspaces to dock system"
```

---

## Task 6: Rebuild `Deliver`, Add Reset/Restore Commands, and Run Full Verification

**Files:**
- Create: `VideoEditor/VideoEditor/UI/Panels/DeliverPanel.swift`
- Modify: `VideoEditor/VideoEditor/UI/Layout/ContentView.swift`
- Modify: `VideoEditor/VideoEditor/UI/Docking/WorkspaceLayoutStore.swift`
- Modify: `VideoEditor/VideoEditor/App/VideoEditorApp.swift`
- Test: `VideoEditor/VideoEditorTests/WorkspaceLayoutStoreTests.swift`

- [ ] **Step 1: Write the failing tests for workspace reset and layout restore**

```swift
import Foundation
import Testing
@testable import VideoEditor

@Suite("Workspace Layout Reset Tests")
struct WorkspaceLayoutResetTests {
    @Test("reset restores the default layout for a customized workspace")
    func workspaceResetRestoresDefaults() throws {
        let defaults = WorkspaceDefaultLayouts.make()
        let store = WorkspaceLayoutStore(
            defaults: defaults,
            fileManager: .default,
            baseURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )

        try store.save(
            DockWorkspaceLayout(workspaceID: "deliver", root: .panel(.inspector))
        )

        try store.resetLayout(for: "deliver")

        let resolved = try store.loadLayout(for: "deliver")
        #expect(resolved == defaults["deliver"])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
cd /Users/explicit/Projects/video-editor/.worktrees/timeline-shell-redesign/VideoEditor
xcodebuild -scheme VideoEditor -destination 'platform=macOS' test -only-testing:VideoEditorTests/WorkspaceLayoutStoreTests
```

Expected: FAIL because `resetLayout(for:)` and a `deliver` default layout do not exist yet.

- [ ] **Step 3: Implement deliver layout, restore actions, and workspace reset**

```swift
extension WorkspaceLayoutStore {
    func resetLayout(for workspaceID: String) throws {
        let url = baseURL.appendingPathComponent("\(workspaceID).json")
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }
}

extension WorkspaceDefaultLayouts {
    static func make() -> [String: DockWorkspaceLayout] {
        [
            "deliver": DockWorkspaceLayout(
                workspaceID: "deliver",
                root: .split(
                    axis: .horizontal,
                    ratio: 0.68,
                    leading: .panel(.programMonitor),
                    trailing: .tabs(activePanelID: .inspector, panelIDs: [.deliverPanel, .inspector])
                )
            )
        ]
    }
}
```

- [ ] **Step 4: Run full verification**

Run:

```bash
cd /Users/explicit/Projects/video-editor/.worktrees/timeline-shell-redesign/VideoEditor
xcodebuild -scheme VideoEditor -destination 'platform=macOS' test
xcodebuild -scheme VideoEditor -destination 'platform=macOS' build
```

Expected: `** TEST SUCCEEDED **` and `** BUILD SUCCEEDED **`.

Final screenshot checkpoints:

- `Edit` workspace full window with dual monitors and top page bar
- `Media` workspace reduced-width behavior
- `Transcript` workspace
- `AI` workspace
- `Deliver` workspace
- Dock drag preview and restored default layout

- [ ] **Step 5: Commit**

```bash
git -C /Users/explicit/Projects/video-editor/.worktrees/timeline-shell-redesign add \
  VideoEditor/VideoEditor/UI/Panels/DeliverPanel.swift \
  VideoEditor/VideoEditor/UI/Layout/ContentView.swift \
  VideoEditor/VideoEditor/UI/Docking/WorkspaceLayoutStore.swift \
  VideoEditor/VideoEditor/App/VideoEditorApp.swift \
  VideoEditor/VideoEditorTests/WorkspaceLayoutStoreTests.swift
git -C /Users/explicit/Projects/video-editor/.worktrees/timeline-shell-redesign commit -m "Complete docked workspace redesign and verification"
```

---

## Self-Review

### Spec coverage

- Docking engine and layout persistence: covered by Tasks 1, 2, and 6
- Top page bar and utility-first visual system: covered by Task 3
- Dual-monitor `Edit`: covered by Task 4
- Selection and inspector behavior correction: covered by Task 4
- Workspace-specific layouts for `Media`, `Transcript`, `AI`, and `Deliver`: covered by Tasks 5 and 6
- Resize/reflow and compact control behavior: covered by Tasks 3 and 5
- Verification after each slice: included in every task with explicit test/build/screenshot gates

### Placeholder scan

- No `TODO`, `TBD`, or “implement later” placeholders remain in task steps.
- Every task has explicit file paths, concrete code blocks, verification commands, and commit commands.

### Type consistency

- The plan uses one consistent family of docking names: `PanelID`, `DockLayoutNode`, `DockWorkspaceLayout`, `WorkspaceLayoutStore`, and `DockingCoordinator`.
- The selection fix consistently uses existing `toggleClipSelection` and `TimelineViewState.selectClip`.

