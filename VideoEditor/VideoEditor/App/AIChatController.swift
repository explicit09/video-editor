import Foundation
import EditorCore
import AIServices

/// Orchestrates AI chat: builds context, sends to provider, executes tool calls.
/// Supports multi-turn tool execution — sends results back to Claude until it's done.
@MainActor @Observable
final class AIChatController {
    private(set) var messages: [ChatMessage] = []
    private(set) var isProcessing = false
    private(set) var processingStatus: String?

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

            // Build initial conversation
            var conversation: [AIMessage] = [
                AIMessage(
                    role: "user",
                    content: "Current editor state:\n```json\n\(context.toJSON())\n```\n\nUser request: \(message)"
                )
            ]

            // Multi-turn loop: send → get response → if tools, execute and send results back → repeat
            var allToolResults: [ChatMessage.ToolResult] = []
            var finalText = ""
            let maxTurns = 10 // Safety limit

            for _ in 0..<maxTurns {
                let response = try await provider.complete(
                    messages: conversation,
                    tools: AIToolRegistry.allTools
                )

                if !response.content.isEmpty {
                    finalText = response.content
                }

                // If no tool calls, we're done
                guard !response.toolCalls.isEmpty else { break }

                // Add assistant response with raw content blocks (includes tool_use blocks)
                // Claude needs to see its own tool_use blocks before the tool_result
                conversation.append(AIMessage(
                    role: "assistant",
                    content: response.content,
                    toolResultID: response.rawContentJSON // Reuse field to carry raw JSON
                ))

                // Execute each tool call and send results back
                for toolCall in response.toolCalls {
                    let result = await executeTool(toolCall: toolCall, appState: appState)
                    allToolResults.append(result)

                    conversation.append(AIMessage(
                        role: "user",
                        content: result.message,
                        toolResultID: toolCall.id,
                        isToolResult: true
                    ))
                }

                if response.stopReason != "tool_use" { break }
            }

            let responseContent = finalText.isEmpty && !allToolResults.isEmpty
                ? "Executed \(allToolResults.count) editing operation(s)."
                : finalText
            messages.append(ChatMessage(role: .assistant, content: responseContent, toolResults: allToolResults))

        } catch {
            messages.append(ChatMessage(role: .system, content: "Error: \(error.localizedDescription)", toolResults: []))
        }

        isProcessing = false
    }

    func clearHistory() {
        messages.removeAll()
    }

    // MARK: - Tool execution

    private func executeTool(toolCall: AIToolCall, appState: AppState) async -> ChatMessage.ToolResult {
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
                return .init(toolName: toolCall.name, success: true, message: result)
            }
            if toolCall.name == "transcribe_asset" {
                let result = try await handleTranscribeAsset(args: args, appState: appState)
                return .init(toolName: toolCall.name, success: true, message: result)
            }
            if toolCall.name == "search_transcript" {
                let result = handleSearchTranscript(args: args, appState: appState)
                return .init(toolName: toolCall.name, success: true, message: result)
            }
            if toolCall.name == "remove_silence" {
                let result = try handleRemoveSilence(args: args, appState: appState)
                return .init(toolName: toolCall.name, success: true, message: result)
            }

            // Editing tools — resolve to intents and execute
            let intents = try toolResolver.resolve(toolName: toolCall.name, arguments: args, assets: appState.assets)
            for intent in intents {
                try appState.perform(intent, source: .ai)
            }
            return .init(toolName: toolCall.name, success: true, message: "Done")
        } catch {
            return .init(toolName: toolCall.name, success: false, message: error.localizedDescription)
        }
    }

    // MARK: - Content tool handlers

    private func handleGetTranscript(args: [String: Any], appState: AppState) async throws -> String {
        guard let assetIDStr = args["asset_id"] as? String, let assetID = UUID(uuidString: assetIDStr) else {
            throw AIToolError.invalidArgument("Missing asset_id")
        }
        guard let asset = await appState.media.mediaManager.asset(id: assetID) else {
            throw AIToolError.invalidArgument("Asset not found")
        }
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
        await appState.media.ensureTranscriptionConfigured()

        if await appState.media.transcriptionService.hasTranscript(
            for: asset, bundleURL: appState.projectBundleURL
        ) {
            return "Already transcribed. Use get_transcript to read the content."
        }

        // Show status while transcribing
        processingStatus = "Transcribing \(asset.name) via Deepgram..."

        let result = try await appState.media.transcriptionService.transcribe(
            asset: asset,
            mediaManager: appState.media.mediaManager,
            bundleURL: appState.projectBundleURL
        )

        processingStatus = nil

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

        let results: [SearchResult]
        if let assetIDStr = args["asset_id"] as? String, let assetID = UUID(uuidString: assetIDStr) {
            if let asset = appState.assets.first(where: { $0.id == assetID }) {
                results = searchEngine.searchAsset(query: query, asset: asset)
            } else { return "Asset not found." }
        } else {
            results = searchEngine.search(query: query, assets: appState.assets, maxResults: maxResults)
        }

        guard !results.isEmpty else {
            return "No matches found for '\(query)'. Make sure assets are transcribed first."
        }

        var output = "Found \(results.count) match(es) for '\(query)':\n\n"
        for (i, result) in results.prefix(maxResults).enumerated() {
            output += "\(i + 1). [\(result.assetName)] at \(result.formattedTime) — \"...\(result.contextText)...\"\n"
            output += "   Asset ID: \(result.assetID.uuidString), Time: \(String(format: "%.1f", result.matchTime))s\n\n"
        }
        return output
    }

    private func handleRemoveSilence(args: [String: Any], appState: AppState) throws -> String {
        let timeline = appState.timeline

        let targetClips: [Clip]
        if let clipIDStrs = args["clip_ids"] as? [String], !clipIDStrs.isEmpty {
            let clipIDs = Set(clipIDStrs.compactMap { UUID(uuidString: $0) })
            targetClips = timeline.tracks.flatMap(\.clips).filter { clipIDs.contains($0.id) }
        } else {
            targetClips = timeline.tracks.flatMap(\.clips)
        }

        guard !targetClips.isEmpty else { return "No clips to process." }

        var totalRemoved = 0
        var clipsToDelete: [UUID] = []

        for clip in targetClips {
            guard let asset = appState.assets.first(where: { $0.id == clip.assetID }),
                  let silenceRanges = asset.analysis?.silenceRanges, !silenceRanges.isEmpty else { continue }

            let clipSourceStart = clip.sourceRange.start
            let clipSourceEnd = clip.sourceRange.end
            let timelineOffset = clip.timelineRange.start - clipSourceStart

            var silenceInClip: [TimeRange] = []
            for silence in silenceRanges {
                let overlapStart = max(silence.start, clipSourceStart)
                let overlapEnd = min(silence.end, clipSourceEnd)
                guard overlapStart < overlapEnd else { continue }
                silenceInClip.append(TimeRange(start: overlapStart + timelineOffset, end: overlapEnd + timelineOffset))
            }

            guard !silenceInClip.isEmpty else { continue }

            let sorted = silenceInClip.sorted { $0.start > $1.start }
            var currentClipID = clip.id

            for silence in sorted {
                if silence.end < clip.timelineRange.end {
                    try? appState.perform(.splitClip(clipID: currentClipID, at: silence.end), source: .ai)
                }
                if silence.start > clip.timelineRange.start {
                    try? appState.perform(.splitClip(clipID: currentClipID, at: silence.start), source: .ai)
                }

                let updatedTimeline = appState.timeline
                for track in updatedTimeline.tracks {
                    for c in track.clips {
                        if abs(c.timelineRange.start - silence.start) < 0.01 && abs(c.timelineRange.end - silence.end) < 0.01 {
                            clipsToDelete.append(c.id)
                        }
                    }
                }
                totalRemoved += 1
            }
        }

        if !clipsToDelete.isEmpty {
            try? appState.perform(.deleteClips(clipIDs: clipsToDelete), source: .ai)
        }

        if totalRemoved == 0 {
            return "No silence ranges found. Silence detection runs automatically on import."
        }
        return "Removed \(totalRemoved) silent segment(s), deleted \(clipsToDelete.count) clip(s)."
    }

    // MARK: - Argument fixup

    private func fixupArguments(
        toolName: String,
        arguments: [String: Any],
        timeline: Timeline,
        assets: [MediaAsset]
    ) -> [String: Any] {
        var args = arguments
        let destructiveTools: Set<String> = ["delete_clips", "trim_clip", "split_clip", "move_clip"]

        if let trackIDStr = args["track_id"] as? String {
            let trackExists = timeline.tracks.contains { $0.id.uuidString == trackIDStr }
            if !trackExists {
                let trackType = inferTrackType(args: args, assets: assets)
                if let realTrack = timeline.tracks.last(where: { $0.type == trackType }) {
                    args["track_id"] = realTrack.id.uuidString
                }
            }
        }

        if let clipIDStr = args["clip_id"] as? String {
            let clipExists = timeline.tracks.flatMap(\.clips).contains { $0.id.uuidString == clipIDStr }
            if !clipExists && !destructiveTools.contains(toolName) {
                if let lastClip = timeline.tracks.flatMap(\.clips).last {
                    args["clip_id"] = lastClip.id.uuidString
                }
            }
        }

        if let clipIDStrs = args["clip_ids"] as? [String] {
            let allClipIDs = Set(timeline.tracks.flatMap(\.clips).map(\.id.uuidString))
            args["clip_ids"] = clipIDStrs.filter { allClipIDs.contains($0) }
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
