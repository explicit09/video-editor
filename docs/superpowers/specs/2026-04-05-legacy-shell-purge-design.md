# Legacy Shell Purge

Date: 2026-04-05
Status: Approved in conversation, pending written-spec review

## Summary

Purge the remaining pre-dock editor shell architecture from the redesign branch. This is not a dead-code sweep based only on reference count. It is an architectural cleanup pass that removes obsolete shell files, shell-owned helpers, and shell-specific visual components that survived the docked workspace migration.

The purpose is to leave the branch with one clear UI architecture: the docked workspace system. Anything that still belongs to the replaced fixed-shell editor should be deleted or replaced in the same pass.

## Problem Statement

The branch now has a working docked workspace system, but parts of the old shell still remain:

- obsolete shell files are still present in the project
- some shell-specific helpers survived because current views were not fully rewired away from them
- the codebase still implies two UI architectures instead of one
- future cleanup gets harder if transitional code is preserved as “maybe later” inventory

This creates avoidable drag:

- harder reasoning about what the real shell is
- larger files and weaker ownership boundaries
- more chances for regressions when old and new layout concepts coexist
- more visual and structural debt hiding inside the branch

## Goals

- Remove the remaining pre-dock shell architecture from the branch
- Delete obsolete shell files and project references
- Re-home any still-needed behavior into dock-first or utility-first support layers
- Remove shell-specific visual components that only served the old editor model
- Leave only one coherent workspace architecture in the codebase
- Verify the purge incrementally with tests, build, and project regeneration

## Non-Goals

- A full design-system rewrite
- A full visual polish pass across the whole app
- Rewriting currently-serving neutral primitives just because they look old
- Bundling unrelated product changes into the purge

## Removal Rule

Code should be removed when any of the following is true:

- it was built for the pre-dock shell
- it exists to support editor chrome that has been replaced
- it survives only because a current view has not yet been rewired away from it
- rebuilding it later in the new architecture would be cleaner than preserving it now

Code should stay only when all of the following are true:

- it is actively serving the docked UI
- it is structurally neutral rather than shell-specific
- it is still the correct abstraction in the new architecture

Live references are not enough protection by themselves. If a current view still points at an old shell helper, this pass should replace that helper instead of preserving it.

## Purge Target

The purge targets the old shell layer, not the entire UI indiscriminately.

### Remove outright

- old workspace shell layout files
- obsolete empty-state/onboarding shell files
- dead shell-specific control bars, rails, and chrome helpers
- project references to those deleted files

Known starting candidates:

- [EditorWorkspaceShell.swift](/Users/explicit/Projects/video-editor/.worktrees/timeline-shell-redesign/VideoEditor/VideoEditor/UI/Layout/EditorWorkspaceShell.swift)
- [EmptyStateView.swift](/Users/explicit/Projects/video-editor/.worktrees/timeline-shell-redesign/VideoEditor/VideoEditor/UI/Layout/EmptyStateView.swift)

### Replace where needed

- shell-specific sizing helpers that a live docked view still depends on
- shell-owned layout abstractions whose remaining behavior belongs in dock support or workspace support
- shell-specific visual primitives that exist only to preserve the old editor frame

### Keep for now

- reusable primitives still serving the docked UI
- panel-level components that are currently part of the new architecture
- neutral theme utilities that are not shell-owned

## Execution Shape

The purge should happen in three slices.

### Slice 1: Remove obsolete files

- delete whole obsolete shell files
- regenerate the Xcode project
- fix compile breaks immediately

This establishes a hard boundary: if the docked app still depended on a deleted shell file, the dependency must now be made explicit and replaced properly.

### Slice 2: Replace lingering shell dependencies

- find current views still leaning on old shell-owned helpers
- move the necessary behavior into dock-first support files or workspace support files
- prefer small utility-first replacements over preserving old abstractions

This is where the branch stops “compiling through legacy.”

### Slice 3: Sweep shell-owned visual helpers

- remove visual components that only served the old shell architecture
- keep panel-level and neutral primitives that the docked UI still uses correctly
- stop short of rewriting the entire visual system in one pass

This keeps the purge aggressive but controlled.

## Verification

Verification should run after each slice as needed, and fully at the end.

Required checks:

- `xcodegen generate`
- targeted tests for touched support layers
- `xcodebuild -scheme VideoEditor -destination 'platform=macOS' build`
- `git diff --check`

Where a slice affects persistence or layout support, targeted tests should be added or updated before implementation.

## Acceptance Criteria

The purge is complete when:

- obsolete shell files are removed from the project and repository
- surviving workspace code no longer depends on the replaced shell architecture
- the docked app compiles and targeted tests pass
- no dead transitional shell path remains in the active workspace composition layer
- the remaining UI codebase clearly describes one architecture, not two

## Risks And Mitigations

### Risk: removing shell files exposes hidden dependencies

Mitigation:

- delete in slices
- regenerate project files early
- replace dependencies immediately instead of re-adding legacy code

### Risk: accidental removal of still-serving primitives

Mitigation:

- apply the ownership rule rather than deleting by naming convention
- keep neutral primitives until they are intentionally replaced

### Risk: turning the purge into a full redesign

Mitigation:

- keep scope centered on shell ownership and architecture
- do not opportunistically rewrite unrelated panels or theme code
