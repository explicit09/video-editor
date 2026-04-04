import Foundation
import EditorCore

/// Generates an EditingPlan by calling Claude Sonnet with the editor state
/// and user request. Uses a single `propose_plan` tool to force structured output.
public struct PlanGenerator: Sendable {

    public init() {}

    /// Generate an editing plan from a user request and editor context.
    public func generate(
        request: String,
        editorState: String,
        skillContent: String?,
        provider: any AIProvider
    ) async throws -> EditingPlan {
        let systemPrompt = buildSystemPrompt(skillContent: skillContent)
        let userPrompt = """
        Editor state:
        \(editorState)

        User request: \(request)

        Generate an editing plan. Consider what assets exist, whether transcripts are available, \
        and what the user is trying to achieve. Follow the editing rules strictly.
        """

        // Define the propose_plan tool to force structured JSON output
        let planTool = AIToolDefinition(
            name: "propose_plan",
            description: "Propose an editing plan for the user to approve.",
            parameters: .object([
                "summary": .init(type: "string", description: "One-line summary of the plan"),
                "steps": .init(type: "array", description: "Ordered list of plan steps"),
            ], required: ["summary", "steps"])
        )

        let response = try await provider.complete(
            messages: [AIMessage(role: "user", content: userPrompt)],
            tools: [planTool],
            modelOverride: ModelTier.standard.rawValue,
            additionalSystemPrompt: systemPrompt
        )

        // Parse the tool call response into an EditingPlan
        if let toolCall = response.toolCalls.first, toolCall.name == "propose_plan" {
            return parsePlan(from: toolCall.arguments)
        }

        // Fallback: Claude responded with text instead of tool call
        return EditingPlan(
            summary: "Edit based on your request",
            steps: [
                PlanStep(id: 1, description: "Analyze the content", tools: ["get_state", "get_transcript"], modelTier: .standard, category: .analyze),
                PlanStep(id: 2, description: "Execute edits based on analysis", tools: [], modelTier: .standard, category: .edit),
                PlanStep(id: 3, description: "Verify the result", tools: ["verify_playback"], modelTier: .fast, category: .verify),
            ]
        )
    }

    // MARK: - System Prompt

    private func buildSystemPrompt(skillContent: String?) -> String {
        var prompt = """
        You are a video editing planner. Given the editor state and a user request, \
        create a step-by-step editing plan using the propose_plan tool.

        RULES:
        1. Always read the transcript before content-based edits (analyze_transcript or get_transcript)
        2. Never auto_cut a raw recording — extract the episode first
        3. For podcasts: analyze_transcript → find episode boundaries → trim → auto_cut → overlay → verify
        4. Always end with verify_playback
        5. Use Haiku (fast) for simple operations: trim, split, move, delete, set properties
        6. Use Sonnet (standard) for: analyze_transcript, auto_cut, content analysis, overlay config

        STEP FORMAT:
        Each step needs: id (1-based), description, tools (array of tool names), \
        modelTier ("fast" or "standard"), category ("analyze", "edit", "property", "verify", "overlay")

        AVAILABLE TOOLS:
        \(AIToolRegistry.toolCatalog)
        """

        if let skill = skillContent {
            prompt += "\n\nSKILL WORKFLOW (follow this if relevant):\n\(skill)"
        }

        return prompt
    }

    // MARK: - Parse Plan

    private func parsePlan(from jsonString: String) -> EditingPlan {
        guard let data = jsonString.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return fallbackPlan()
        }

        let summary = dict["summary"] as? String ?? "Editing plan"
        let stepsArray = dict["steps"] as? [[String: Any]] ?? []

        let steps: [PlanStep] = stepsArray.enumerated().map { (i, stepDict) in
            let description = stepDict["description"] as? String ?? "Step \(i + 1)"
            let tools = stepDict["tools"] as? [String] ?? []
            let tierStr = stepDict["modelTier"] as? String ?? stepDict["model_tier"] as? String ?? "standard"
            let tier: ModelTier = tierStr == "fast" ? .fast : .standard
            let catStr = stepDict["category"] as? String ?? "edit"
            let category: PlanStep.StepCategory = PlanStep.StepCategory(rawValue: catStr) ?? .edit

            return PlanStep(
                id: i + 1,
                description: description,
                tools: tools,
                modelTier: tier,
                category: category
            )
        }

        return EditingPlan(summary: summary, steps: steps.isEmpty ? fallbackPlan().steps : steps)
    }

    private func fallbackPlan() -> EditingPlan {
        EditingPlan(
            summary: "Edit the content",
            steps: [
                PlanStep(id: 1, description: "Analyze content", tools: ["get_state"], modelTier: .standard, category: .analyze),
                PlanStep(id: 2, description: "Verify result", tools: ["verify_playback"], modelTier: .fast, category: .verify),
            ]
        )
    }
}
