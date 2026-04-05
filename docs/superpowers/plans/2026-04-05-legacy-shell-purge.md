# Legacy Shell Purge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the last pre-dock shell architecture and shell-owned chrome from the redesign branch so the codebase describes one docked workspace system instead of a mixed legacy/new shell.

**Architecture:** First delete whole obsolete shell files that have no live references. Then replace the remaining shell-owned visual helpers in currently live panels with utility-first equivalents in the existing utility design system. Finally, delete the old shared shell helpers from the cinematic design system once all references are gone.

**Tech Stack:** SwiftUI, XcodeGen, XCTest/Testing, ripgrep, xcodebuild

---

## File Structure

### Delete

- `VideoEditor/VideoEditor/UI/Layout/EditorWorkspaceShell.swift`
- `VideoEditor/VideoEditor/UI/Layout/EmptyStateView.swift`
- `VideoEditor/VideoEditor/UI/Preview/PreviewPanel.swift`

### Modify

- `VideoEditor/VideoEditor/UI/Theme/UtilityDesignSystem.swift`
- `VideoEditor/VideoEditor/UI/Theme/DesignSystem.swift`
- `VideoEditor/VideoEditor/UI/Layout/ContentView.swift`
- `VideoEditor/VideoEditor/UI/Inspector/InspectorPanel.swift`
- `VideoEditor/VideoEditor/UI/Inspector/SearchResultsView.swift`
- `VideoEditor/VideoEditor/UI/MediaBrowser/MediaBrowserPanel.swift`
- `VideoEditor/VideoEditor/UI/MediaBrowser/MediaWorkspacePanel.swift`
- `VideoEditor/VideoEditor/UI/MediaBrowser/ProjectBrowserPanel.swift`
- `VideoEditor/VideoEditor/UI/MediaBrowser/SettingsPanel.swift`
- `VideoEditor/VideoEditor/UI/Transcript/TranscriptPanel.swift`
- `VideoEditor/VideoEditor/UI/Timeline/TimelineToolbarView.swift`
- `VideoEditor/VideoEditorTests/EditorStabilizationSupportTests.swift`
- `project.yml`

### Verification targets

- `xcodegen generate`
- `xcodebuild -scheme VideoEditor -destination 'platform=macOS' test -only-testing:VideoEditorTests/EditorStabilizationSupportTests`
- `xcodebuild -scheme VideoEditor -destination 'platform=macOS' build`
- `git diff --check`

---

### Task 1: Delete Obsolete Shell Files

**Files:**
- Delete: `VideoEditor/VideoEditor/UI/Layout/EditorWorkspaceShell.swift`
- Delete: `VideoEditor/VideoEditor/UI/Layout/EmptyStateView.swift`
- Delete: `VideoEditor/VideoEditor/UI/Preview/PreviewPanel.swift`
- Modify: `project.yml`

- [ ] **Step 1: Reconfirm the files are truly unreferenced before deleting**

Run:

```bash
rg -n "EditorWorkspaceShell(Layout)?|EmptyStateView|PreviewPanel\\(" \
  /Users/explicit/Projects/video-editor/.worktrees/timeline-shell-redesign/VideoEditor/VideoEditor \
  /Users/explicit/Projects/video-editor/.worktrees/timeline-shell-redesign/VideoEditor/VideoEditorTests
```

Expected:
- `EditorWorkspaceShell.swift` only matches its own definitions
- `EmptyStateView.swift` only matches its own definition
- `PreviewPanel.swift` only matches its own definition

- [ ] **Step 2: Delete the obsolete files**

Run:

```bash
rm /Users/explicit/Projects/video-editor/.worktrees/timeline-shell-redesign/VideoEditor/VideoEditor/UI/Layout/EditorWorkspaceShell.swift
rm /Users/explicit/Projects/video-editor/.worktrees/timeline-shell-redesign/VideoEditor/VideoEditor/UI/Layout/EmptyStateView.swift
rm /Users/explicit/Projects/video-editor/.worktrees/timeline-shell-redesign/VideoEditor/VideoEditor/UI/Preview/PreviewPanel.swift
```

Expected:
- files no longer exist on disk

- [ ] **Step 3: Regenerate the Xcode project so deleted files disappear from the build graph**

Run:

```bash
cd /Users/explicit/Projects/video-editor/.worktrees/timeline-shell-redesign/VideoEditor
xcodegen generate
```

Expected:
- `Created project at .../VideoEditor.xcodeproj`

- [ ] **Step 4: Run a full build to surface any hidden compile-time legacy dependencies**

Run:

```bash
cd /Users/explicit/Projects/video-editor/.worktrees/timeline-shell-redesign/VideoEditor
xcodebuild -scheme VideoEditor -destination 'platform=macOS' build
```

Expected:
- if build fails, failures should point at lingering code paths that still depend on deleted shell files
- if build passes, Task 1 is complete

- [ ] **Step 5: Commit the hard deletions**

```bash
cd /Users/explicit/Projects/video-editor/.worktrees/timeline-shell-redesign
git add project.yml VideoEditor/VideoEditor/UI/Layout VideoEditor/VideoEditor/UI/Preview
git commit -m "Remove obsolete pre-dock shell files"
```

---

### Task 2: Add Utility-First Replacements For Remaining Shell Chrome

**Files:**
- Modify: `VideoEditor/VideoEditor/UI/Theme/UtilityDesignSystem.swift`
- Test: `VideoEditor/VideoEditorTests/EditorStabilizationSupportTests.swift`

- [ ] **Step 1: Write the failing tests for the new utility chrome helpers**

Add these tests to `VideoEditor/VideoEditorTests/EditorStabilizationSupportTests.swift`:

```swift
    @Test("utility status badge metrics keep compact height for short labels")
    func utilityStatusBadgeMetricsUseCompactHeight() {
        let metrics = UtilityStatusBadgeMetrics.make(text: "AI", showsIcon: true)

        #expect(metrics.height == UtilityMetrics.controlHeight - 4)
        #expect(metrics.horizontalPadding == UtilitySpacing.sm)
    }

    @Test("utility segmented control metrics collapse labels on narrow widths")
    func utilitySegmentedControlMetricsCollapseLabels() {
        let metrics = UtilitySegmentedControlMetrics.make(
            availableWidth: 180,
            itemCount: 3
        )

        #expect(metrics.showsLabels == false)
        #expect(metrics.controlHeight == UtilityMetrics.controlHeight)
    }
```

Expected failure:
- `Cannot find 'UtilityStatusBadgeMetrics' in scope`
- `Cannot find 'UtilitySegmentedControlMetrics' in scope`

- [ ] **Step 2: Run the targeted test command to verify the red state**

Run:

```bash
cd /Users/explicit/Projects/video-editor/.worktrees/timeline-shell-redesign/VideoEditor
xcodebuild -scheme VideoEditor -destination 'platform=macOS' test \
  -only-testing:VideoEditorTests/EditorStabilizationSupportTests
```

Expected:
- FAIL with missing utility helper types

- [ ] **Step 3: Add the minimal utility-first chrome helpers**

Implement in `VideoEditor/VideoEditor/UI/Theme/UtilityDesignSystem.swift`:

```swift
struct UtilityStatusBadgeMetrics: Equatable, Sendable {
    let height: CGFloat
    let horizontalPadding: CGFloat

    static func make(text: String, showsIcon: Bool) -> Self {
        Self(
            height: UtilityMetrics.controlHeight - 4,
            horizontalPadding: showsIcon || text.count > 2 ? UtilitySpacing.sm : UtilitySpacing.xs
        )
    }
}

struct UtilitySegmentedControlMetrics: Equatable, Sendable {
    let showsLabels: Bool
    let controlHeight: CGFloat

    static func make(availableWidth: CGFloat, itemCount: Int) -> Self {
        let widthPerItem = availableWidth / max(CGFloat(itemCount), 1)
        return Self(
            showsLabels: widthPerItem >= 76,
            controlHeight: UtilityMetrics.controlHeight
        )
    }
}

struct UtilityStatusBadge: View {
    let text: String
    var icon: String? = nil
    var isAccent = false

    var body: some View {
        let metrics = UtilityStatusBadgeMetrics.make(text: text, showsIcon: icon != nil)

        HStack(spacing: UtilitySpacing.xxs) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
            }

            Text(text)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(isAccent ? UtilityTheme.accentText : UtilityTheme.textMuted)
        .padding(.horizontal, metrics.horizontalPadding)
        .frame(height: metrics.height)
        .background(isAccent ? UtilityTheme.accent : UtilityTheme.chrome)
        .clipShape(Capsule())
    }
}

struct UtilitySegmentedControl<Item: Hashable>: View {
    let items: [Item]
    @Binding var selection: Item
    let availableWidth: CGFloat
    let label: (Item) -> String
    var icon: ((Item) -> String?)? = nil

    var body: some View {
        let metrics = UtilitySegmentedControlMetrics.make(
            availableWidth: availableWidth,
            itemCount: items.count
        )

        HStack(spacing: UtilitySpacing.xs) {
            ForEach(items, id: \.self) { item in
                Button {
                    selection = item
                } label: {
                    HStack(spacing: UtilitySpacing.xxs) {
                        if let iconName = icon?(item) {
                            Image(systemName: iconName)
                                .font(.system(size: 11, weight: .semibold))
                        }

                        if metrics.showsLabels {
                            Text(label(item))
                                .font(.system(size: 10, weight: .semibold))
                        }
                    }
                    .foregroundStyle(selection == item ? UtilityTheme.accentText : UtilityTheme.text)
                    .padding(.horizontal, UtilitySpacing.sm)
                    .frame(height: metrics.controlHeight)
                    .frame(maxWidth: .infinity)
                    .background(selection == item ? UtilityTheme.accent : UtilityTheme.chrome)
                    .clipShape(RoundedRectangle(cornerRadius: UtilityRadius.sm))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(UtilitySpacing.xxs)
        .background(UtilityTheme.recessed)
        .clipShape(RoundedRectangle(cornerRadius: UtilityRadius.md))
    }
}
```

- [ ] **Step 4: Re-run the targeted tests to verify the new helpers**

Run:

```bash
cd /Users/explicit/Projects/video-editor/.worktrees/timeline-shell-redesign/VideoEditor
xcodebuild -scheme VideoEditor -destination 'platform=macOS' test \
  -only-testing:VideoEditorTests/EditorStabilizationSupportTests
```

Expected:
- PASS

- [ ] **Step 5: Commit the utility replacement primitives**

```bash
cd /Users/explicit/Projects/video-editor/.worktrees/timeline-shell-redesign
git add VideoEditor/VideoEditor/UI/Theme/UtilityDesignSystem.swift VideoEditor/VideoEditorTests/EditorStabilizationSupportTests.swift
git commit -m "Add utility replacements for legacy shell chrome"
```

---

### Task 3: Migrate Live Panels Off Shell-Owned Cinematic Chrome

**Files:**
- Modify: `VideoEditor/VideoEditor/UI/Layout/ContentView.swift`
- Modify: `VideoEditor/VideoEditor/UI/Inspector/InspectorPanel.swift`
- Modify: `VideoEditor/VideoEditor/UI/Inspector/SearchResultsView.swift`
- Modify: `VideoEditor/VideoEditor/UI/MediaBrowser/MediaBrowserPanel.swift`
- Modify: `VideoEditor/VideoEditor/UI/MediaBrowser/MediaWorkspacePanel.swift`
- Modify: `VideoEditor/VideoEditor/UI/MediaBrowser/ProjectBrowserPanel.swift`
- Modify: `VideoEditor/VideoEditor/UI/MediaBrowser/SettingsPanel.swift`
- Modify: `VideoEditor/VideoEditor/UI/Transcript/TranscriptPanel.swift`
- Modify: `VideoEditor/VideoEditor/UI/Timeline/TimelineToolbarView.swift`
- Test: `VideoEditor/VideoEditorTests/EditorStabilizationSupportTests.swift`

- [ ] **Step 1: Add the failing test for workspace top-bar badge sizing after migration**

Add this test to `VideoEditor/VideoEditorTests/EditorStabilizationSupportTests.swift`:

```swift
    @Test("utility status badge metrics handle longer toolbar labels without growing taller")
    func utilityStatusBadgeMetricsKeepFixedHeightForToolbarLabels() {
        let metrics = UtilityStatusBadgeMetrics.make(text: "EXPANDED", showsIcon: true)

        #expect(metrics.height == UtilityMetrics.controlHeight - 4)
        #expect(metrics.horizontalPadding == UtilitySpacing.sm)
    }
```

Expected:
- PASS once Task 2 exists; this protects the toolbar/status migration from reintroducing cinematic sizing assumptions

- [ ] **Step 2: Replace shell-owned badges and segmented tabs in live views**

Make these replacements:

```swift
// ContentView.swift
CinematicStatusPill(...) -> UtilityStatusBadge(...)

// InspectorPanel.swift
CinematicSegmentedTabBar(...) -> UtilitySegmentedControl(
    items: ...,
    selection: ...,
    availableWidth: 220,
    label: ...,
    icon: ...
)
CinematicStatusPill(...) -> UtilityStatusBadge(...)

// SearchResultsView.swift, MediaBrowserPanel.swift, MediaWorkspacePanel.swift,
// ProjectBrowserPanel.swift, SettingsPanel.swift, TranscriptPanel.swift,
// TimelineToolbarView.swift
CinematicStatusPill(...) -> UtilityStatusBadge(...)
```

Rules:
- prefer `UtilityPanelHeader` where the view currently uses a shell-owned header surface
- keep panel copy and behavior unchanged
- do not redesign layouts in this task; only remove shell-owned chrome dependencies

- [ ] **Step 3: Run targeted stabilization tests**

Run:

```bash
cd /Users/explicit/Projects/video-editor/.worktrees/timeline-shell-redesign/VideoEditor
xcodebuild -scheme VideoEditor -destination 'platform=macOS' test \
  -only-testing:VideoEditorTests/EditorStabilizationSupportTests
```

Expected:
- PASS

- [ ] **Step 4: Run a full build to catch migrated file regressions**

Run:

```bash
cd /Users/explicit/Projects/video-editor/.worktrees/timeline-shell-redesign/VideoEditor
xcodebuild -scheme VideoEditor -destination 'platform=macOS' build
```

Expected:
- PASS

- [ ] **Step 5: Commit the live-view migration**

```bash
cd /Users/explicit/Projects/video-editor/.worktrees/timeline-shell-redesign
git add \
  VideoEditor/VideoEditor/UI/Layout/ContentView.swift \
  VideoEditor/VideoEditor/UI/Inspector/InspectorPanel.swift \
  VideoEditor/VideoEditor/UI/Inspector/SearchResultsView.swift \
  VideoEditor/VideoEditor/UI/MediaBrowser/MediaBrowserPanel.swift \
  VideoEditor/VideoEditor/UI/MediaBrowser/MediaWorkspacePanel.swift \
  VideoEditor/VideoEditor/UI/MediaBrowser/ProjectBrowserPanel.swift \
  VideoEditor/VideoEditor/UI/MediaBrowser/SettingsPanel.swift \
  VideoEditor/VideoEditor/UI/Transcript/TranscriptPanel.swift \
  VideoEditor/VideoEditor/UI/Timeline/TimelineToolbarView.swift \
  VideoEditor/VideoEditorTests/EditorStabilizationSupportTests.swift
git commit -m "Migrate docked panels off legacy shell chrome"
```

---

### Task 4: Delete Shared Legacy Shell Components From The Cinematic Design System

**Files:**
- Modify: `VideoEditor/VideoEditor/UI/Theme/DesignSystem.swift`

- [ ] **Step 1: Reconfirm no live references remain to the shell-owned cinematic helpers**

Run:

```bash
rg -n "CinematicPanelHeader|CinematicStatusPill|CinematicSegmentedTabBar" \
  /Users/explicit/Projects/video-editor/.worktrees/timeline-shell-redesign/VideoEditor/VideoEditor \
  /Users/explicit/Projects/video-editor/.worktrees/timeline-shell-redesign/VideoEditor/VideoEditorTests
```

Expected:
- no matches outside `DesignSystem.swift`

- [ ] **Step 2: Delete the legacy shell-owned helper views from the design system**

Remove these definitions from `VideoEditor/VideoEditor/UI/Theme/DesignSystem.swift`:

```swift
struct CinematicPanelHeader<LeadingAccessory: View, TrailingAccessory: View>: View { ... }
struct CinematicStatusPill: View { ... }
struct CinematicSegmentedTabBar<Item: Hashable>: View { ... }
```

Leave in place:
- `CinematicToolbarButton`
- `CinematicEmptyStateBlock`
- `CinematicInspectorFieldRow`
- any panel-surface or typography primitives still actively used by non-shell panels

- [ ] **Step 3: Run the full build**

Run:

```bash
cd /Users/explicit/Projects/video-editor/.worktrees/timeline-shell-redesign/VideoEditor
xcodebuild -scheme VideoEditor -destination 'platform=macOS' build
```

Expected:
- PASS

- [ ] **Step 4: Commit the design-system purge**

```bash
cd /Users/explicit/Projects/video-editor/.worktrees/timeline-shell-redesign
git add VideoEditor/VideoEditor/UI/Theme/DesignSystem.swift
git commit -m "Remove legacy shell helpers from design system"
```

---

### Task 5: Final Verification And Residual Sweep

**Files:**
- Modify as needed from earlier tasks only

- [ ] **Step 1: Re-run the dead-reference audit**

Run:

```bash
rg -n "EditorWorkspaceShell|EmptyStateView|PreviewPanel\\(|CinematicPanelHeader|CinematicStatusPill|CinematicSegmentedTabBar" \
  /Users/explicit/Projects/video-editor/.worktrees/timeline-shell-redesign/VideoEditor/VideoEditor \
  /Users/explicit/Projects/video-editor/.worktrees/timeline-shell-redesign/VideoEditor/VideoEditorTests
```

Expected:
- no live matches for deleted files or removed shell-owned helper views

- [ ] **Step 2: Regenerate the project one last time**

Run:

```bash
cd /Users/explicit/Projects/video-editor/.worktrees/timeline-shell-redesign/VideoEditor
xcodegen generate
```

Expected:
- project regenerates cleanly

- [ ] **Step 3: Run targeted tests and full build**

Run:

```bash
cd /Users/explicit/Projects/video-editor/.worktrees/timeline-shell-redesign/VideoEditor
xcodebuild -scheme VideoEditor -destination 'platform=macOS' test \
  -only-testing:VideoEditorTests/EditorStabilizationSupportTests
xcodebuild -scheme VideoEditor -destination 'platform=macOS' build
git -C /Users/explicit/Projects/video-editor/.worktrees/timeline-shell-redesign diff --check
```

Expected:
- targeted tests PASS
- build PASS
- `git diff --check` prints no output

- [ ] **Step 4: Commit any final residual cleanup**

```bash
cd /Users/explicit/Projects/video-editor/.worktrees/timeline-shell-redesign
git add -A
git commit -m "Finish legacy shell purge"
```

---

## Self-Review

### Spec coverage

- Remove obsolete shell files: covered by Task 1
- Replace lingering shell dependencies: covered by Tasks 2 and 3
- Sweep shell-owned visual helpers: covered by Task 4
- Regenerate/build/test incrementally: covered by Tasks 1 through 5

### Placeholder scan

- No `TODO`, `TBD`, or “similar to above” placeholders remain
- Every task names exact files and exact commands

### Type consistency

- New helper names are consistent across tasks:
  - `UtilityStatusBadgeMetrics`
  - `UtilitySegmentedControlMetrics`
  - `UtilityStatusBadge`
  - `UtilitySegmentedControl`
