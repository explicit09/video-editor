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

    func send(message: String, appState: AppState) async {
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

            // Auto-transcribe assets on the timeline before AI processes them
            let assetIDs = Set(appState.timeline.tracks.flatMap(\.clips).map(\.assetID))
            if !assetIDs.isEmpty {
                await appState.media.ensureTranscripts(for: Array(assetIDs))
                // Rebuild context with updated transcripts
            }

            // Rebuild context after transcription (may have new transcript data)
            let updatedContext = contextBuilder.buildContext(
                timeline: appState.timeline,
                assets: appState.assets,
                playheadPosition: appState.timelineViewState.playheadPosition,
                selectedClipIDs: appState.timelineViewState.selectedClipIDs,
                recentActions: recentActions
            )

            let apiMessages = [
                AIMessage(
                    role: "user",
                    content: "Current editor state:\n```json\n\(updatedContext.toJSON())\n```\n\nUser request: \(message)"
                )
            ]

            let response = try await provider.complete(
                messages: apiMessages,
                tools: AIToolRegistry.allTools
            )

            // Execute tool calls sequentially.
            // After each call, the timeline state is updated, so subsequent calls
            // can reference objects created by earlier calls.
            // We fix up invalid IDs by inferring what the AI meant from context.
            var toolResults: [ChatMessage.ToolResult] = []

            for toolCall in response.toolCalls {
                let args = fixupArguments(
                    toolName: toolCall.name,
                    arguments: toolCall.parsedArguments(),
                    timeline: appState.timeline,
                    assets: appState.assets
                )

                do {
                    let intents = try toolResolver.resolve(toolName: toolCall.name, arguments: args, assets: appState.assets)
                    for intent in intents {
                        try appState.perform(intent)
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

    // MARK: - Argument fixup

    /// Fix up tool arguments by resolving invalid IDs to real objects.
    /// The AI generates fake UUIDs that don't exist. Instead of mapping them,
    /// we infer what the AI meant from the current timeline state.
    private func fixupArguments(
        toolName: String,
        arguments: [String: Any],
        timeline: Timeline,
        assets: [MediaAsset]
    ) -> [String: Any] {
        var args = arguments

        // Fix track_id: if it doesn't exist, use the last track of the appropriate type
        if let trackIDStr = args["track_id"] as? String {
            let trackExists = timeline.tracks.contains { $0.id.uuidString == trackIDStr }
            if !trackExists {
                // Infer the right track type from context
                let trackType = inferTrackType(toolName: toolName, args: args, assets: assets)
                if let realTrack = timeline.tracks.last(where: { $0.type == trackType }) {
                    args["track_id"] = realTrack.id.uuidString
                }
            }
        }

        // Fix clip_id: if it doesn't exist, infer from context
        if let clipIDStr = args["clip_id"] as? String {
            let clipExists = timeline.tracks.flatMap(\.clips).contains { $0.id.uuidString == clipIDStr }
            if !clipExists {
                // Use the most recently added clip (last clip on last non-empty track)
                if let lastClip = timeline.tracks.flatMap(\.clips).last {
                    args["clip_id"] = lastClip.id.uuidString
                }
            }
        }

        // Fix clip_ids array: filter to existing IDs, fall back to all clips if none valid
        if let clipIDStrs = args["clip_ids"] as? [String] {
            let allClipIDs = Set(timeline.tracks.flatMap(\.clips).map(\.id.uuidString))
            let validIDs = clipIDStrs.filter { allClipIDs.contains($0) }
            if validIDs.isEmpty && !clipIDStrs.isEmpty {
                // AI referenced clips that don't exist — try to infer
                // "delete the second clip" → the AI probably means the last clip
                if let lastClip = timeline.tracks.flatMap(\.clips).last {
                    args["clip_ids"] = [lastClip.id.uuidString]
                }
            } else {
                args["clip_ids"] = validIDs
            }
        }

        return args
    }

    private func inferTrackType(toolName: String, args: [String: Any], assets: [MediaAsset]) -> TrackType {
        // If inserting a clip, check what type the asset is
        if let assetIDStr = args["asset_id"] as? String,
           let asset = assets.first(where: { $0.id.uuidString == assetIDStr }) {
            return asset.type == .audio ? .audio : .video
        }
        return .video
    }
}
