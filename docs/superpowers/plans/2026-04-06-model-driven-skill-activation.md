# Model-Driven Skill Activation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace keyword-based skill matching with model-driven activation so the in-app agent discovers and uses workflow skills the same way external MCP agents do.

**Architecture:** Add an `activate_skill` tool to AIToolRegistry. Include a dynamically-generated skill catalog in ClaudeProvider's system prompt. The model calls `activate_skill` when it recognizes a workflow match. Remove the old keyword-matching code from AIChatController.

**Tech Stack:** Swift, AIServices package, EditorCore types

**Spec:** `docs/superpowers/specs/2026-04-06-model-driven-skill-activation-design.md`

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `VideoEditor/Packages/AIServices/Sources/AIServices/Skills/SkillRegistry.swift` | Modify | Add `skillCatalog()` method |
| `VideoEditor/Packages/AIServices/Sources/AIServices/Providers/ClaudeProvider.swift` | Modify | Add `skillCatalog` property, include in system prompt |
| `VideoEditor/Packages/AIServices/Sources/AIServices/Tools/AIToolRegistry.swift` | Modify | Add `activateSkill` tool definition + resolver case |
| `VideoEditor/VideoEditor/App/AIChatController.swift` | Modify | Remove keyword matching, add `activate_skill` handler, pass catalog to provider |
| `VideoEditor/Packages/AIServices/Tests/AIServicesTests/AIServicesTests.swift` | Modify | Tests for skill catalog and activate_skill resolver |

---

### Task 1: SkillRegistry — Add `skillCatalog()` method

**Files:**
- Modify: `VideoEditor/Packages/AIServices/Sources/AIServices/Skills/SkillRegistry.swift`
- Test: `VideoEditor/Packages/AIServices/Tests/AIServicesTests/AIServicesTests.swift`

- [ ] **Step 1: Write failing test**

Add a new test suite at the end of `AIServicesTests.swift`:

```swift
@Suite("SkillRegistry Tests")
struct SkillRegistryTests {

    @Test("skillCatalog returns formatted catalog of loaded skills")
    func skillCatalog() {
        let registry = SkillRegistry()

        // Load skills from the project's .claude/skills directory
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // AIServicesTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // AIServices (the package)
            .deletingLastPathComponent()  // Packages
            .deletingLastPathComponent()  // VideoEditor
            .deletingLastPathComponent()  // VideoEditor (project root)
        let skillsDir = projectRoot.appendingPathComponent(".claude/skills")
        registry.loadSkills(from: skillsDir)

        let catalog = registry.skillCatalog()

        // Should contain the XML wrapper
        #expect(catalog.contains("<available_skills>"))
        #expect(catalog.contains("</available_skills>"))

        // Should contain at least the podcast-episode-producer skill
        #expect(catalog.contains("podcast-episode-producer"))

        // Should contain the instruction to call activate_skill
        #expect(catalog.contains("activate_skill"))
    }

    @Test("skillCatalog returns empty string when no skills loaded")
    func emptyCatalog() {
        let registry = SkillRegistry()
        let catalog = registry.skillCatalog()
        #expect(catalog.isEmpty)
    }

    @Test("skill(named:) returns skill by name")
    func skillLookup() {
        let registry = SkillRegistry()
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let skillsDir = projectRoot.appendingPathComponent(".claude/skills")
        registry.loadSkills(from: skillsDir)

        let skill = registry.skill(named: "podcast-episode-producer")
        #expect(skill != nil)
        #expect(skill?.name == "podcast-episode-producer")
        #expect(skill?.content.contains("Step 0") == true || skill?.content.contains("Step 1") == true)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/explicit/Projects/video-editor/VideoEditor/Packages/EditorCore && swift test 2>&1 | tail -5`

Expected: FAIL — `skillCatalog()` method doesn't exist yet.

- [ ] **Step 3: Implement `skillCatalog()` method**

In `SkillRegistry.swift`, add this method after the existing `skill(named:)` method (around line 72):

```swift
/// Generate a formatted skill catalog for inclusion in the AI system prompt.
/// Returns empty string if no skills are loaded.
public func skillCatalog() -> String {
    guard !skills.isEmpty else { return "" }

    var lines = [
        "<available_skills>",
        "When you recognize a task matches one of these workflows, call activate_skill",
        "to get the full step-by-step workflow before proceeding.",
        "",
    ]

    for skill in skills {
        lines.append("- \(skill.name): \(skill.description)")
    }

    lines.append("</available_skills>")
    return lines.joined(separator: "\n")
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/explicit/Projects/video-editor/VideoEditor/Packages/EditorCore && swift test 2>&1 | tail -10`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add VideoEditor/Packages/AIServices/Sources/AIServices/Skills/SkillRegistry.swift VideoEditor/Packages/AIServices/Tests/AIServicesTests/AIServicesTests.swift
git commit -m "feat(skills): add skillCatalog() method for model-driven activation"
```

---

### Task 2: ClaudeProvider — Accept and include skill catalog

**Files:**
- Modify: `VideoEditor/Packages/AIServices/Sources/AIServices/Providers/ClaudeProvider.swift`

- [ ] **Step 1: Add `skillCatalog` property**

In `ClaudeProvider`, add a mutable property after the existing private properties (after line 10):

```swift
/// Skill catalog text to include in the system prompt.
/// Set by the app layer after loading skills from disk.
public var skillCatalog: String = ""
```

- [ ] **Step 2: Include catalog in system prompt**

In the `systemPrompt` computed property (around line 143), add the skill catalog block at the end, before the closing `"""`:

Change the system prompt getter from:

```swift
private var systemPrompt: String {
    """
    <role>
    ...
    </context_guide>
    """
}
```

to:

```swift
private var systemPrompt: String {
    var prompt = """
    <role>
    You are an AI editing copilot inside a native video editor. You execute real-time \
    editing operations using tools. The user sees results instantly.
    </role>

    <principles>
    - Act first, explain briefly after. Chain all needed tool calls.
    - Use UUIDs and durations from the editor context — never invent values.
    - Prefer compound tools (remove_section, ripple_delete, normalize_audio) over \
    manual multi-step sequences. They are faster and less error-prone.
    - Only confirm before destructive bulk operations.
    - After any tool call, read the result carefully — it contains the current state.
    </principles>

    <editing_rules>
    - ALWAYS read the transcript (get_transcript or analyze_transcript) before making \
    content-based edits. Never edit blind.
    - NEVER run auto_cut on a raw unprocessed recording. First use analyze_transcript \
    to find episode boundaries, then trim to the episode, THEN auto_cut.
    - For podcast/long recordings: analyze_transcript FIRST to understand structure, \
    then extract episodes, then clean up with auto_cut.
    - Video clips have linked audio — editing video automatically affects linked audio.
    - After completing an edit session, run verify_playback to confirm integrity.
    - When setting overlay config, the episode must already be trimmed and cleaned.
    </editing_rules>

    <context_guide>
    - Track/clip IDs, asset IDs, and durations are in the editor context.
    - Transcripts are NOT in the context by default. Call get_transcript to read content.
    - Assets with hasTranscript=true can be searched with search_transcript.
    - Assets with hasAnalysis=true have silence data for remove_silence.
    - Video clips have linked audio clips — editing one automatically affects the other.
    - Use get_state to see current timeline structure before editing.
    - Use analyze_transcript to understand content structure of long recordings.
    </context_guide>
    """
    if !skillCatalog.isEmpty {
        prompt += "\n\n\(skillCatalog)"
    }
    return prompt
}
```

- [ ] **Step 3: Remove `<skill>` injection from `complete()` method**

In the `complete()` method (around line 98-101), remove the skill prompt injection:

Change:

```swift
// System prompt as cacheable content block
var fullSystemPrompt = systemPrompt
if let skillPrompt = additionalSystemPrompt, !skillPrompt.isEmpty {
    fullSystemPrompt += "\n\n<skill>\n\(skillPrompt)\n</skill>"
}
```

to:

```swift
// System prompt as cacheable content block
let fullSystemPrompt = systemPrompt
```

Note: keep the `additionalSystemPrompt` parameter on the `complete()` method signature — it's part of the `AIProvider` protocol. Just stop using it for skill injection. The parameter can still be used for other purposes (like the PlanGenerator).

Actually, the PlanGenerator might still pass an additionalSystemPrompt. Let me check. Read the current PlanGenerator usage:

The `AIChatController` passes `additionalSystemPrompt: turn == 0 ? skillPrompt : nil` on line 221. After our changes, `skillPrompt` will always be nil. But the `additionalSystemPrompt` parameter should remain functional for future use. So keep the injection logic but it will just be nil:

```swift
// System prompt as cacheable content block
var fullSystemPrompt = systemPrompt
if let additional = additionalSystemPrompt, !additional.isEmpty {
    fullSystemPrompt += "\n\n\(additional)"
}
```

This removes the `<skill>` wrapper tags (the content now comes via tool results, not system prompt injection) but keeps the generic additionalSystemPrompt mechanism working.

- [ ] **Step 4: Build to verify compilation**

Run: `cd /Users/explicit/Projects/video-editor/VideoEditor/Packages/EditorCore && swift test 2>&1 | tail -5`

Expected: PASS (all existing tests still pass)

- [ ] **Step 5: Commit**

```bash
git add VideoEditor/Packages/AIServices/Sources/AIServices/Providers/ClaudeProvider.swift
git commit -m "feat(provider): include skill catalog in system prompt"
```

---

### Task 3: AIToolRegistry — Add `activate_skill` tool

**Files:**
- Modify: `VideoEditor/Packages/AIServices/Sources/AIServices/Tools/AIToolRegistry.swift`
- Test: `VideoEditor/Packages/AIServices/Tests/AIServicesTests/AIServicesTests.swift`

- [ ] **Step 1: Write failing test**

Add to `AIServicesTests.swift`:

```swift
@MainActor
@Test("activate_skill resolves to empty intents (handled upstream)")
func activateSkillToolResolution() throws {
    let resolver = AIToolResolver()
    let intents = try resolver.resolve(toolName: "activate_skill", arguments: [
        "name": "podcast-episode-producer",
    ])
    #expect(intents.isEmpty, "activate_skill should resolve to empty intents (handled upstream)")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/explicit/Projects/video-editor/VideoEditor/Packages/EditorCore && swift test 2>&1 | tail -5`

Expected: FAIL — "Unknown tool: activate_skill"

- [ ] **Step 3: Add tool definition**

In `AIToolRegistry.swift`, add this static after the other AppState tool definitions (after `getActionLog`):

```swift
public static let activateSkill = AIToolDefinition(
    name: "activate_skill",
    description: "Activate a workflow skill for the current task. Returns the full step-by-step workflow with tool usage rules and safety boundaries. Always activate the relevant skill before starting a complex editing workflow. Call again with a different name to switch workflows.",
    parameters: .object([
        "name": .init(type: "string", description: "Skill name from the available_skills list in your instructions"),
    ], required: ["name"])
)
```

Add to `allTools` array:

```swift
activateSkill,
```

- [ ] **Step 4: Add resolver case**

In `AIToolResolver.resolve()`, add to the existing AppState tools case:

Change:

```swift
case "undo", "redo", "play_pause", "seek", "toggle_loop", "get_action_log":
    return []
```

to:

```swift
case "undo", "redo", "play_pause", "seek", "toggle_loop", "get_action_log", "activate_skill":
    return []
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd /Users/explicit/Projects/video-editor/VideoEditor/Packages/EditorCore && swift test 2>&1 | tail -5`

Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add VideoEditor/Packages/AIServices/Sources/AIServices/Tools/AIToolRegistry.swift VideoEditor/Packages/AIServices/Tests/AIServicesTests/AIServicesTests.swift
git commit -m "feat(tools): add activate_skill tool definition"
```

---

### Task 4: AIChatController — Wire up skill activation + remove keyword matching

**Files:**
- Modify: `VideoEditor/VideoEditor/App/AIChatController.swift`

- [ ] **Step 1: Pass skill catalog to provider**

In the `configure(provider:)` method (line 50), and in `loadSkills(from:)` (line 55), update so the provider gets the catalog:

```swift
func configure(provider: any AIProvider) {
    self.provider = provider
    updateProviderSkillCatalog()
}

/// Load editing skills from the project's .claude/skills/ directory.
func loadSkills(from skillsDir: URL) {
    skillRegistry.loadSkills(from: skillsDir)
    updateProviderSkillCatalog()
}

private func updateProviderSkillCatalog() {
    if let claude = provider as? ClaudeProvider {
        claude.skillCatalog = skillRegistry.skillCatalog()
    }
}
```

- [ ] **Step 2: Remove keyword-based skill matching**

In the `send(message:appState:)` method, find and remove the entire skill matching block (approximately lines 191-206):

Remove this:

```swift
// Skill matching: check if user's message activates a skill
var skillPrompt: String? = nil
if let skill = skillRegistry.match(message) {
    activeSkill = skill.name
    skillPrompt = skill.content
    // Override tools to the skill's recommended set if specified
    if !skill.tools.isEmpty {
        selectedTools = allAvailableTools.filter { skill.tools.contains($0.name) }
    }
    // Skills always use standard model (complex workflows)
    if skill.model == "standard" {
        currentModel = IntentRouter.ModelTier.standard.rawValue
    }
} else {
    activeSkill = nil
}
```

Replace with just:

```swift
activeSkill = nil
```

- [ ] **Step 3: Remove skillPrompt from complete() call**

Find the `complete()` call (around line 221):

Change:

```swift
let response = try await provider.complete(
    messages: conversation,
    tools: selectedTools,
    modelOverride: currentModel,
    additionalSystemPrompt: turn == 0 ? skillPrompt : nil
)
```

to:

```swift
let response = try await provider.complete(
    messages: conversation,
    tools: selectedTools,
    modelOverride: currentModel
)
```

- [ ] **Step 4: Add `activate_skill` handler**

In the `handlePlaybackTool` method (or add a new handler before the MCPServer fallback), add handling for `activate_skill`. Find the block in `executeTool` that says `// Playback & undo tools — need AppState directly` and add the skill handler BEFORE it:

```swift
// Skill activation — look up and return skill content
if toolCall.name == "activate_skill" {
    let skillName = args["name"] as? String ?? ""
    if let skill = skillRegistry.skill(named: skillName) {
        activeSkill = skill.name
        var result = "Skill activated: \(skill.name)\n\n"
        if !skill.tools.isEmpty {
            result += "Recommended tools for this workflow: \(skill.tools.joined(separator: ", "))\n"
            result += "(Additional tools beyond this list are available if needed.)\n\n"
        }
        result += "---\n\(skill.content)"
        return .init(toolName: toolCall.name, success: true, message: result)
    } else {
        let available = skillRegistry.availableSkills.joined(separator: ", ")
        return .init(toolName: toolCall.name, success: false, message: "Unknown skill '\(skillName)'. Available skills: \(available)")
    }
}
```

- [ ] **Step 5: Build to verify compilation**

Run: `cd /Users/explicit/Projects/video-editor/VideoEditor && xcodegen generate && xcodebuild -scheme VideoEditor -destination 'platform=macOS' build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git add VideoEditor/VideoEditor/App/AIChatController.swift
git commit -m "feat(agent): model-driven skill activation replaces keyword matching"
```

---

### Task 5: Verification

**Files:** None (verification only)

- [ ] **Step 1: Run all package tests**

Run: `cd /Users/explicit/Projects/video-editor/VideoEditor/Packages/EditorCore && swift test 2>&1 | tail -10`

Expected: All tests pass

- [ ] **Step 2: Run full build**

Run: `cd /Users/explicit/Projects/video-editor/VideoEditor && xcodegen generate && xcodebuild -scheme VideoEditor -destination 'platform=macOS' build 2>&1 | tail -5`

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Verify tool count**

Run: `cd /Users/explicit/Projects/video-editor && grep -c 'public static let' VideoEditor/Packages/AIServices/Sources/AIServices/Tools/AIToolRegistry.swift`

Expected: Previous count + 1 for `activateSkill`

- [ ] **Step 4: Verify skill catalog in system prompt**

Run the app and check the console for the `[Claude] Request size:` log. The request size should be slightly larger than before (skill catalog adds ~500 tokens). Alternatively, add a temporary print statement to verify the catalog is included.

- [ ] **Step 5: Commit verification**

```bash
git add -A
git commit -m "chore: verify model-driven skill activation compiles and passes tests"
```
