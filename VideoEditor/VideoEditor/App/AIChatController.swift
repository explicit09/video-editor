import Foundation
import EditorCore
import AIServices

/// Orchestrates AI chat: builds context, sends to provider, executes tool calls.
@MainActor @Observable
final class AIChatController {
    private(set) var messages: [ChatMessage] = []
    private(set) var isProcessing = false

    private let contextBuilder = AIContextBuilder()
    private let toolResolver = AIToolResolver()
    private var provider: (any AIProvider)?

    struct ChatMessage: Identifiable {
        let id = UUID()
        let role: Role
        let content: String
        let toolResults: [ToolResult]

        enum Role { case user, assistant, system }

        struct ToolResult {
            let toolName: String
            let success: Bool
            let message: String
        }
    }

    func configure(provider: any AIProvider) {
        self.provider = provider
    }

    /// Send a user message and get AI response with tool execution.
    func send(
        message: String,
        appState: AppState
    ) async {
        guard let provider else {
            messages.append(ChatMessage(role: .system, content: "No AI provider configured. Set ANTHROPIC_API_KEY environment variable.", toolResults: []))
            return
        }

        // Add user message
        messages.append(ChatMessage(role: .user, content: message, toolResults: []))
        isProcessing = true

        do {
            // Build editor context
            let recentActions = await appState.context.actionLog.recentActions(count: 10)
            let context = contextBuilder.buildContext(
                timeline: appState.timeline,
                assets: appState.assets,
                playheadPosition: appState.timelineViewState.playheadPosition,
                selectedClipIDs: appState.timelineViewState.selectedClipIDs,
                recentActions: recentActions
            )

            // Build messages for API
            var apiMessages: [AIMessage] = []

            // Inject editor context as first user message
            apiMessages.append(AIMessage(
                role: "user",
                content: "Current editor state:\n```json\n\(context.toJSON())\n```\n\nUser request: \(message)"
            ))

            // Send to AI
            let response = try await provider.complete(
                messages: apiMessages,
                tools: AIToolRegistry.allTools
            )

            // Execute tool calls
            var toolResults: [ChatMessage.ToolResult] = []
            for toolCall in response.toolCalls {
                let args = toolCall.parsedArguments()
                do {
                    let intents = try toolResolver.resolve(toolName: toolCall.name, arguments: args)
                    for intent in intents {
                        try appState.perform(intent)
                    }
                    toolResults.append(.init(toolName: toolCall.name, success: true, message: "Done"))
                } catch {
                    toolResults.append(.init(toolName: toolCall.name, success: false, message: error.localizedDescription))
                }
            }

            // Add assistant response
            let responseContent = response.content.isEmpty && !toolResults.isEmpty
                ? "Executed \(toolResults.count) editing operation(s)."
                : response.content
            messages.append(ChatMessage(role: .assistant, content: responseContent, toolResults: toolResults))

        } catch {
            messages.append(ChatMessage(role: .system, content: "Error: \(error.localizedDescription)", toolResults: []))
        }

        isProcessing = false
    }

    func clearHistory() {
        messages.removeAll()
    }
}
