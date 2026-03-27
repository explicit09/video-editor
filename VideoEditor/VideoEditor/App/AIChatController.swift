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

        messages.append(ChatMessage(role: .user, content: message, toolResults: []))
        isProcessing = true

        do {
            let recentActions = await appState.context.actionLog.recentActions(count: 10)
            let context = contextBuilder.buildContext(
                timeline: appState.timeline,
                assets: appState.assets,
                playheadPosition: appState.timelineViewState.playheadPosition,
                selectedClipIDs: appState.timelineViewState.selectedClipIDs,
                recentActions: recentActions
            )

            let apiMessages = [
                AIMessage(
                    role: "user",
                    content: "Current editor state:\n```json\n\(context.toJSON())\n```\n\nUser request: \(message)"
                )
            ]

            let response = try await provider.complete(
                messages: apiMessages,
                tools: AIToolRegistry.allTools
            )

            // Execute tool calls sequentially with ID remapping.
            // The AI generates IDs for new objects (tracks, clips) that don't match
            // the real IDs created by commands. We track the mapping and remap
            // subsequent tool call arguments so they reference real objects.
            var toolResults: [ChatMessage.ToolResult] = []
            var idMap: [String: String] = [:]  // AI-generated ID → real ID

            for toolCall in response.toolCalls {
                var args = toolCall.parsedArguments()

                // Remap all UUID-like string arguments through the ID map
                args = remapIDs(args, idMap: idMap)

                // Snapshot state before execution to detect new objects
                let tracksBefore = Set(appState.timeline.tracks.map(\.id))
                let clipsBefore = Set(appState.timeline.tracks.flatMap(\.clips).map(\.id))

                do {
                    let intents = try toolResolver.resolve(toolName: toolCall.name, arguments: args, assets: appState.assets)
                    for intent in intents {
                        try appState.perform(intent)
                    }

                    // Detect newly created objects and map AI IDs to real IDs
                    let tracksAfter = Set(appState.timeline.tracks.map(\.id))
                    let clipsAfter = Set(appState.timeline.tracks.flatMap(\.clips).map(\.id))

                    let newTracks = tracksAfter.subtracting(tracksBefore)
                    let newClips = clipsAfter.subtracting(clipsBefore)

                    // Map: if AI provided a track_id that doesn't exist, map it to the new track
                    if let aiTrackID = originalID(for: "track_id", in: toolCall.parsedArguments()),
                       let newTrack = newTracks.first {
                        idMap[aiTrackID] = newTrack.uuidString
                    }
                    if let aiClipID = originalID(for: "clip_id", in: toolCall.parsedArguments()),
                       let newClip = newClips.first {
                        idMap[aiClipID] = newClip.uuidString
                    }

                    toolResults.append(.init(toolName: toolCall.name, success: true, message: "Done"))
                } catch {
                    toolResults.append(.init(toolName: toolCall.name, success: false, message: error.localizedDescription))
                }
            }

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

    // MARK: - ID remapping

    /// Remap all string values in arguments that exist in the ID map.
    private func remapIDs(_ args: [String: Any], idMap: [String: String]) -> [String: Any] {
        guard !idMap.isEmpty else { return args }
        var result = args
        for (key, value) in args {
            if let str = value as? String, let mapped = idMap[str] {
                result[key] = mapped
            } else if let array = value as? [String] {
                result[key] = array.map { idMap[$0] ?? $0 }
            }
        }
        return result
    }

    /// Extract the original (un-remapped) ID value for a given key.
    private func originalID(for key: String, in args: [String: Any]) -> String? {
        args[key] as? String
    }
}
