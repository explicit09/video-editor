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

            // Send standard context (no transcripts — AI requests via tools if needed)
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
                    // Content tools — return data, don't modify timeline
                    if toolCall.name == "get_transcript" {
                        let result = try await handleGetTranscript(args: args, appState: appState)
                        toolResults.append(.init(toolName: toolCall.name, success: true, message: result))
                        continue
                    }
                    if toolCall.name == "transcribe_asset" {
                        let result = try await handleTranscribeAsset(args: args, appState: appState)
                        toolResults.append(.init(toolName: toolCall.name, success: true, message: result))
                        continue
                    }
                    if toolCall.name == "search_transcript" {
                        let result = handleSearchTranscript(args: args, appState: appState)
                        toolResults.append(.init(toolName: toolCall.name, success: true, message: result))
                        continue
                    }

                    // Editing tools — resolve to intents and execute
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

    // MARK: - Content tool handlers

    private func handleGetTranscript(args: [String: Any], appState: AppState) async throws -> String {
        guard let assetIDStr = args["asset_id"] as? String, let assetID = UUID(uuidString: assetIDStr) else {
            throw AIToolError.invalidArgument("Missing asset_id")
        }

        guard let asset = await appState.media.mediaManager.asset(id: assetID) else {
            throw AIToolError.invalidArgument("Asset not found")
        }

        // Check memory and disk — never triggers transcription
        if let result = await appState.media.transcriptionService.getTranscript(
            for: asset, bundleURL: appState.projectBundleURL
        ) {
            return "Transcript (\(result.words.count) words): \(result.text)"
        }

        return "No transcript for this asset. Use transcribe_asset to generate one."
    }

    private func handleTranscribeAsset(args: [String: Any], appState: AppState) async throws -> String {
        guard let assetIDStr = args["asset_id"] as? String, let assetID = UUID(uuidString: assetIDStr) else {
            throw AIToolError.invalidArgument("Missing asset_id")
        }

        guard let asset = await appState.media.mediaManager.asset(id: assetID) else {
            throw AIToolError.invalidArgument("Asset not found")
        }

        // Check if already transcribed — won't re-transcribe without force
        if await appState.media.transcriptionService.hasTranscript(
            for: asset, bundleURL: appState.projectBundleURL
        ) {
            return "Already transcribed. Use get_transcript to read the content."
        }

        let result = try await appState.media.transcriptionService.transcribe(
            asset: asset,
            mediaManager: appState.media.mediaManager,
            bundleURL: appState.projectBundleURL
        )

        if let result {
            await appState.media.refreshAssets()
            return "Transcribed (\(result.words.count) words, \(String(format: "%.1f", result.duration))s). Use get_transcript to read."
        } else {
            return "Transcription not configured. Add DEEPGRAM_API_KEY to .env file."
        }
    }

    private func handleSearchTranscript(args: [String: Any], appState: AppState) -> String {
        guard let query = args["query"] as? String, !query.isEmpty else {
            return "Missing search query."
        }

        let maxResults = (args["max_results"] as? Int) ?? 10
        let searchEngine = TranscriptSearchEngine()

        // Search specific asset or all assets
        let results: [SearchResult]
        if let assetIDStr = args["asset_id"] as? String, let assetID = UUID(uuidString: assetIDStr) {
            if let asset = appState.assets.first(where: { $0.id == assetID }) {
                results = searchEngine.searchAsset(query: query, asset: asset)
            } else {
                return "Asset not found."
            }
        } else {
            results = searchEngine.search(query: query, assets: appState.assets, maxResults: maxResults)
        }

        guard !results.isEmpty else {
            return "No matches found for '\(query)'. Make sure assets are transcribed first (use transcribe_asset)."
        }

        var output = "Found \(results.count) match(es) for '\(query)':\n\n"
        for (i, result) in results.prefix(maxResults).enumerated() {
            output += "\(i + 1). [\(result.assetName)] at \(result.formattedTime) — \"...\(result.contextText)...\"\n"
            output += "   Asset ID: \(result.assetID.uuidString), Time: \(String(format: "%.1f", result.matchTime))s\n\n"
        }
        return output
    }

    // MARK: - Argument fixup

    /// Fix up tool arguments by resolving invalid IDs.
    /// - track_id: safe to infer (for insert_clip after add_track)
    /// - clip_id/clip_ids: ONLY infer for non-destructive ops. Reject for destructive ones.
    private func fixupArguments(
        toolName: String,
        arguments: [String: Any],
        timeline: Timeline,
        assets: [MediaAsset]
    ) -> [String: Any] {
        var args = arguments
        let destructiveTools: Set<String> = ["delete_clips", "trim_clip", "split_clip", "move_clip"]

        // Fix track_id: safe to infer — used for insertion targets
        if let trackIDStr = args["track_id"] as? String {
            let trackExists = timeline.tracks.contains { $0.id.uuidString == trackIDStr }
            if !trackExists {
                let trackType = inferTrackType(args: args, assets: assets)
                if let realTrack = timeline.tracks.last(where: { $0.type == trackType }) {
                    args["track_id"] = realTrack.id.uuidString
                }
            }
        }

        // clip_id: only infer for NON-destructive tools (e.g., after insert_clip created a new clip)
        // For destructive tools, leave the invalid ID — the resolver will throw a clear error
        if let clipIDStr = args["clip_id"] as? String {
            let clipExists = timeline.tracks.flatMap(\.clips).contains { $0.id.uuidString == clipIDStr }
            if !clipExists && !destructiveTools.contains(toolName) {
                if let lastClip = timeline.tracks.flatMap(\.clips).last {
                    args["clip_id"] = lastClip.id.uuidString
                }
            }
            // For destructive tools: leave invalid ID, let resolver throw
        }

        // clip_ids: filter to valid IDs only. Never guess on destructive ops.
        if let clipIDStrs = args["clip_ids"] as? [String] {
            let allClipIDs = Set(timeline.tracks.flatMap(\.clips).map(\.id.uuidString))
            args["clip_ids"] = clipIDStrs.filter { allClipIDs.contains($0) }
            // If all IDs were invalid, leave empty array — resolver will throw
        }

        return args
    }

    private func inferTrackType(args: [String: Any], assets: [MediaAsset]) -> TrackType {
        if let assetIDStr = args["asset_id"] as? String,
           let asset = assets.first(where: { $0.id.uuidString == assetIDStr }) {
            return asset.type == .audio ? .audio : .video
        }
        return .video
    }
}
