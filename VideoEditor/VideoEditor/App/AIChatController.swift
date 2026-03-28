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
    private(set) var lastSearchQuery: String?
    private(set) var lastSearchResults: [SearchResult]?

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

        // Clear previous search results when starting new request
        lastSearchQuery = nil
        lastSearchResults = nil

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

            for turn in 0..<maxTurns {
                processingStatus = turn == 0 ? "Thinking..." : "AI planning next step..."
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

            processingStatus = nil
            let responseContent = finalText.isEmpty && !allToolResults.isEmpty
                ? "Executed \(allToolResults.count) editing operation(s)."
                : finalText
            messages.append(ChatMessage(role: .assistant, content: responseContent, toolResults: allToolResults))

        } catch {
            processingStatus = nil
            messages.append(ChatMessage(role: .system, content: "Error: \(error.localizedDescription)", toolResults: []))
        }

        isProcessing = false
    }

    func clearHistory() {
        messages.removeAll()
    }

    // MARK: - Tool execution

    private func executeTool(toolCall: AIToolCall, appState: AppState) async -> ChatMessage.ToolResult {
        // Show what tool is running
        processingStatus = "Running \(toolCall.name)..."

        let args = fixupArguments(
            toolName: toolCall.name,
            arguments: toolCall.parsedArguments(),
            timeline: appState.timeline,
            assets: appState.assets
        )

        do {
            if toolCall.name == "get_transcript" {
                processingStatus = "Reading transcript..."
                let result = try await handleGetTranscript(args: args, appState: appState)
                return .init(toolName: toolCall.name, success: true, message: result)
            }
            if toolCall.name == "transcribe_asset" {
                // Status updates happen inside handleTranscribeAsset
                let result = try await handleTranscribeAsset(args: args, appState: appState)
                return .init(toolName: toolCall.name, success: true, message: result)
            }
            if toolCall.name == "search_transcript" {
                processingStatus = "Searching transcripts..."
                let result = await handleSearchTranscript(args: args, appState: appState)
                return .init(toolName: toolCall.name, success: true, message: result)
            }
            if toolCall.name == "remove_silence" {
                processingStatus = "Removing silent segments..."
                let result = try handleRemoveSilence(args: args, appState: appState)
                return .init(toolName: toolCall.name, success: true, message: result)
            }

            // Editing tools
            processingStatus = "Executing \(toolCall.name)..."

            // Special case: insert_clip for video assets — create linked audio track
            if toolCall.name == "insert_clip",
               let assetIDStr = args["asset_id"] as? String,
               let assetID = UUID(uuidString: assetIDStr),
               let asset = appState.assets.first(where: { $0.id == assetID }),
               asset.type == .video {
                let startTime = args["start_time"] as? Double
                let preferredTrack = (args["track_id"] as? String).flatMap { UUID(uuidString: $0) }
                await appState.addAssetToTimeline(asset, source: .ai, preferredTrackID: preferredTrack, startTime: startTime)
            } else {
                let intents = try toolResolver.resolve(toolName: toolCall.name, arguments: args, assets: appState.assets)
                for intent in intents {
                    try appState.perform(intent, source: .ai)
                }
            }

            // Return detailed feedback for destructive operations
            let feedback = describeTool(toolCall.name, args: args, timeline: appState.timeline)
            return .init(toolName: toolCall.name, success: true, message: feedback)
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

        processingStatus = "Extracting audio from \(asset.name)..."

        let result = try await appState.media.transcriptionService.transcribe(
            asset: asset,
            mediaManager: appState.media.mediaManager,
            bundleURL: appState.projectBundleURL,
            onStatus: { [weak self] status in
                Task { @MainActor in self?.processingStatus = status }
            }
        )

        processingStatus = nil

        if let result {
            await appState.media.refreshAssets()
            return "Transcribed (\(result.words.count) words, \(String(format: "%.1f", result.duration))s). Use get_transcript to read."
        } else {
            return "Transcription not configured. Add DEEPGRAM_API_KEY to .env file."
        }
    }

    private func handleSearchTranscript(args: [String: Any], appState: AppState) async -> String {
        guard let query = args["query"] as? String, !query.isEmpty else {
            return "Missing search query."
        }
        let maxResults = (args["max_results"] as? Int) ?? 10
        let searchEngine = TranscriptSearchEngine()

        // Enrich assets with disk-persisted transcripts if not in memory
        var searchableAssets = appState.assets
        for i in searchableAssets.indices {
            if searchableAssets[i].analysis?.transcript == nil || searchableAssets[i].analysis!.transcript!.isEmpty {
                if let diskResult = await appState.media.transcriptionService.loadTranscript(
                    for: searchableAssets[i].id, bundleURL: appState.projectBundleURL
                ) {
                    var analysis = searchableAssets[i].analysis ?? MediaAnalysis()
                    analysis.transcript = diskResult.words
                    searchableAssets[i].analysis = analysis
                }
            }
        }

        let results: [SearchResult]
        if let assetIDStr = args["asset_id"] as? String, let assetID = UUID(uuidString: assetIDStr) {
            if let asset = searchableAssets.first(where: { $0.id == assetID }) {
                results = searchEngine.searchAsset(query: query, asset: asset)
            } else { return "Asset not found." }
        } else {
            results = searchEngine.search(query: query, assets: searchableAssets, maxResults: maxResults)
        }

        guard !results.isEmpty else {
            lastSearchQuery = nil
            lastSearchResults = nil
            return "No matches found for '\(query)'. Make sure assets are transcribed first."
        }

        // Store for visual display in SearchResultsView
        lastSearchQuery = query
        lastSearchResults = results

        var output = "Found \(results.count) match(es) for '\(query)':\n\n"
        for (i, result) in results.enumerated() {
            output += "\(i + 1). [\(result.assetName)] at \(result.formattedTime) — \"...\(result.contextText)...\"\n"
            output += "   Asset ID: \(result.assetID.uuidString), Time: \(String(format: "%.1f", result.matchTime))s\n\n"
        }
        return output
    }

    private func handleRemoveSilence(args: [String: Any], appState: AppState) throws -> String {
        let timeline = appState.timeline

        // Parse optional threshold/duration filters
        let minDuration = (args["min_duration"] as? Double) ?? 0.5

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

            // Map silence ranges to timeline time and filter by min duration
            var silenceInClip: [TimeRange] = []
            for silence in silenceRanges {
                let overlapStart = max(silence.start, clipSourceStart)
                let overlapEnd = min(silence.end, clipSourceEnd)
                let duration = overlapEnd - overlapStart
                guard duration >= minDuration else { continue }
                silenceInClip.append(TimeRange(start: overlapStart + timelineOffset, end: overlapEnd + timelineOffset))
            }

            guard !silenceInClip.isEmpty else { continue }

            // Process silence ranges from end to start so earlier splits don't shift later positions
            let sorted = silenceInClip.sorted { $0.start > $1.start }

            for silence in sorted {
                // Find the clip that currently contains this silence range
                let allClips = appState.timeline.tracks.flatMap(\.clips)
                guard let containingClip = allClips.first(where: {
                    $0.assetID == clip.assetID &&
                    $0.timelineRange.start <= silence.start + 0.01 &&
                    $0.timelineRange.end >= silence.end - 0.01
                }) else { continue }

                let containingID = containingClip.id

                // Split at silence end (if not at clip end)
                if silence.end < containingClip.timelineRange.end - 0.01 {
                    try? appState.perform(.splitClip(clipID: containingID, at: silence.end), source: .ai)
                }

                // Split at silence start (if not at clip start)
                // After the end split, the original clipID still refers to the head piece
                if silence.start > containingClip.timelineRange.start + 0.01 {
                    try? appState.perform(.splitClip(clipID: containingID, at: silence.start), source: .ai)
                }

                // Find the silent segment by matching time range
                let postSplitClips = appState.timeline.tracks.flatMap(\.clips)
                for c in postSplitClips {
                    if abs(c.timelineRange.start - silence.start) < 0.02 &&
                       abs(c.timelineRange.end - silence.end) < 0.02 {
                        clipsToDelete.append(c.id)
                    }
                }
                totalRemoved += 1
            }
        }

        if !clipsToDelete.isEmpty {
            try? appState.perform(.deleteClips(clipIDs: clipsToDelete), source: .ai)
        }

        if totalRemoved == 0 {
            return "No silence ranges found (min duration: \(String(format: "%.1f", minDuration))s)."
        }
        return "Removed \(totalRemoved) silent segment(s), deleted \(clipsToDelete.count) clip(s)."
    }

    // MARK: - Tool result feedback

    /// Describe what a tool did — gives the AI detailed feedback so it knows the current state.
    private func describeTool(_ name: String, args: [String: Any], timeline: Timeline) -> String {
        switch name {
        case "add_track":
            if let track = timeline.tracks.last {
                return "Added track '\(track.name)' (ID: \(track.id.uuidString)). Timeline now has \(timeline.tracks.count) track(s)."
            }
            return "Done"

        case "insert_clip":
            // Report all clips added (video + linked audio for video assets)
            let assetIDStr = args["asset_id"] as? String ?? ""
            let recentClips = timeline.tracks.flatMap { track in
                track.clips.compactMap { clip -> String? in
                    guard clip.assetID.uuidString == assetIDStr else { return nil }
                    let trackName = track.name
                    return "'\(clip.metadata.label ?? "Clip")' (ID: \(clip.id.uuidString)) on \(trackName) at \(String(format: "%.1f", clip.timelineRange.start))s-\(String(format: "%.1f", clip.timelineRange.end))s"
                }
            }
            if !recentClips.isEmpty {
                return "Inserted: \(recentClips.joined(separator: "; ")). Total clips: \(timeline.tracks.flatMap(\.clips).count)."
            }
            return "Done"

        case "split_clip":
            let clipID = args["clip_id"] as? String ?? ""
            let at = args["at"] as? Double ?? 0
            // After split, find the two clips near the split point
            let allClips = timeline.tracks.flatMap(\.clips)
            let nearSplit = allClips.filter { abs($0.timelineRange.end - at) < 0.1 || abs($0.timelineRange.start - at) < 0.1 }
            let clipIDs = nearSplit.map { "\($0.id.uuidString) (\(String(format: "%.1f", $0.timelineRange.start))s-\(String(format: "%.1f", $0.timelineRange.end))s)" }
            return "Split at \(String(format: "%.1f", at))s. Resulting clips: \(clipIDs.joined(separator: ", ")). Total clips on timeline: \(allClips.count)."

        case "delete_clips":
            let remaining = timeline.tracks.flatMap(\.clips).count
            return "Deleted. Timeline now has \(remaining) clip(s) remaining."

        case "move_clip":
            let clipID = args["clip_id"] as? String ?? ""
            if let clip = timeline.tracks.flatMap(\.clips).first(where: { $0.id.uuidString == clipID }) {
                return "Moved clip to \(String(format: "%.1f", clip.timelineRange.start))s-\(String(format: "%.1f", clip.timelineRange.end))s."
            }
            return "Done"

        default:
            return "Done"
        }
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
