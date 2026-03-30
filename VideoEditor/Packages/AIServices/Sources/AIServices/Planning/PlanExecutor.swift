import Foundation
import EditorCore

/// Executes an approved EditingPlan step by step.
/// Each step runs with the appropriate model tier and tool subset.
/// Results from previous steps feed into the next step's context.
public actor PlanExecutor {

    public typealias StepHandler = @Sendable (String, [String: Any]) async -> String
    public typealias StatusHandler = @Sendable (String) -> Void

    private var stepResults: [Int: String] = [:]

    public init() {}

    /// Execute all steps of a plan sequentially.
    /// - Parameters:
    ///   - plan: The approved editing plan
    ///   - executeStep: Closure that executes a single tool call (name, args) → result string
    ///   - onStatus: Called with status updates for each step
    /// - Returns: Summary of all step results
    public func execute(
        plan: EditingPlan,
        provider: any AIProvider,
        editorState: @Sendable () async -> String,
        executeToolCall: @escaping StepHandler,
        onStatus: @escaping StatusHandler
    ) async -> String {
        var results: [String] = []

        for step in plan.steps {
            onStatus("Step \(step.id)/\(plan.steps.count): \(step.description)...")

            let state = await editorState()
            let previousSummary = results.isEmpty ? "" : "\nPrevious results:\n" + results.joined(separator: "\n")

            let stepPrompt = """
            You are executing step \(step.id) of \(plan.steps.count) in an editing plan.

            OVERALL GOAL: \(plan.summary)
            THIS STEP: \(step.description)
            TOOLS AVAILABLE: \(step.tools.joined(separator: ", "))
            \(previousSummary)

            Editor state:
            \(state)

            Execute this step using the available tools. Be concise.
            """

            // Build tool definitions for this step
            let stepTools = AIToolRegistry.allTools.filter { step.tools.contains($0.name) }

            do {
                let response = try await provider.complete(
                    messages: [AIMessage(role: "user", content: stepPrompt)],
                    tools: stepTools,
                    modelOverride: step.modelTier.rawValue
                )

                // Execute any tool calls
                var stepResult = response.content
                for toolCall in response.toolCalls {
                    let args = toolCall.parsedArguments()
                    let toolResult = await executeToolCall(toolCall.name, args)
                    stepResult += "\n[\(toolCall.name)]: \(toolResult.prefix(500))"
                }

                stepResults[step.id] = stepResult
                results.append("Step \(step.id) (\(step.description)): Done")

            } catch {
                let errorMsg = "Step \(step.id) failed: \(error.localizedDescription)"
                results.append(errorMsg)

                // If Haiku failed, don't retry — just note it and continue
                if step.modelTier == .fast {
                    results.append("(Haiku step failed — may need manual attention)")
                }
            }
        }

        onStatus("Plan complete")
        return "=== PLAN EXECUTION COMPLETE ===\n\(plan.summary)\n\n" + results.joined(separator: "\n")
    }
}
