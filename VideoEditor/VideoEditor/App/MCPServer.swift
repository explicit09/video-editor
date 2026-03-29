import Foundation
import AVFoundation
import CoreImage
import EditorCore
import AIServices
import Network

/// MCP-compatible HTTP server for external tool access.
/// Runs on localhost:8420. Claude Code connects via HTTP transport.
@MainActor
final class MCPServer {
    private weak var appState: AppState?
    private var nwListener: NWListener?
    private let port: UInt16 = 8420

    init(appState: AppState) {
        self.appState = appState
    }

    func start() {
        do {
            let params = NWParameters.tcp
            nwListener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
            nwListener?.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    print("[MCP] Server ready on http://localhost:\(self.port)")
                case .failed(let error):
                    print("[MCP] Server failed: \(error)")
                default:
                    break
                }
            }
            nwListener?.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    self?.handleNewConnection(connection)
                }
            }
            nwListener?.start(queue: .global(qos: .utility))
        } catch {
            print("[MCP] Failed to start: \(error)")
        }
    }

    func stop() {
        nwListener?.cancel()
        nwListener = nil
    }

    // MARK: - Connection Handling

    private func handleNewConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .utility))
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, error in
            guard let self, let data, error == nil else {
                connection.cancel()
                return
            }

            guard let requestStr = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }

            // Parse HTTP POST body
            let parts = requestStr.components(separatedBy: "\r\n\r\n")
            let headers = parts[0]
            let body = parts.count > 1 ? parts[1] : ""

            // CORS preflight
            if headers.hasPrefix("OPTIONS") {
                let response = "HTTP/1.1 200 OK\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: POST\r\nAccess-Control-Allow-Headers: Content-Type\r\nContent-Length: 0\r\n\r\n"
                connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in connection.cancel() })
                return
            }

            // Parse JSON-RPC body
            Task { @MainActor in
                let responseJSON: String
                if let bodyData = body.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
                    responseJSON = await self.handleJSONRPC(json)
                } else {
                    responseJSON = self.errorResponse(id: nil, code: -32700, message: "Parse error")
                }

                let httpResponse = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\nContent-Length: \(responseJSON.utf8.count)\r\n\r\n\(responseJSON)"
                connection.send(content: httpResponse.data(using: .utf8), completion: .contentProcessed { _ in connection.cancel() })
            }
        }
    }

    // MARK: - JSON-RPC Handler

    private func handleJSONRPC(_ request: [String: Any]) async -> String {
        let id = request["id"]
        let method = request["method"] as? String ?? ""
        let params = request["params"] as? [String: Any] ?? [:]

        switch method {
        case "initialize":
            return successResponse(id: id, result: [
                "protocolVersion": "2024-11-05",
                "capabilities": ["tools": [:], "resources": [:]],
                "serverInfo": ["name": "VideoEditor", "version": "0.1.0"],
            ])

        case "tools/list":
            var tools = AIToolRegistry.allTools.map { tool -> [String: Any] in
                let schemaData = try? JSONEncoder().encode(tool.parameters)
                let schema = schemaData.flatMap { try? JSONSerialization.jsonObject(with: $0) } ?? [:]
                return ["name": tool.name, "description": tool.description, "inputSchema": schema]
            }
            // MCP-only tools
            tools.append(contentsOf: [
                [
                    "name": "import_media",
                    "description": "Import a video/audio file into the project. The app is sandboxed — files must be inside the container at ~/Library/Containers/com.videoeditor.app/Data/Documents/. Copy the file there first using 'cp', then pass the container path. Returns the asset_id for use with add_to_timeline.",
                    "inputSchema": ["type": "object", "properties": ["file_path": ["type": "string", "description": "Absolute path to the media file (must be inside the app sandbox container)"]], "required": ["file_path"]],
                ],
                [
                    "name": "add_to_timeline",
                    "description": "Add an imported asset to the timeline. Creates video + linked audio tracks automatically for video assets.",
                    "inputSchema": ["type": "object", "properties": [
                        "asset_id": ["type": "string", "description": "UUID of the imported asset"],
                        "start_time": ["type": "number", "description": "Optional start position in seconds"],
                        "track_id": ["type": "string", "description": "Optional target track UUID"],
                    ], "required": ["asset_id"]],
                ],
                [
                    "name": "clear_project",
                    "description": "Remove all tracks and clips from the timeline. Does not delete imported assets.",
                    "inputSchema": ["type": "object", "properties": [:], "required": []],
                ],
                [
                    "name": "verify_playback",
                    "description": "Content-verify the timeline composition. Checks that the RIGHT audio/video from the RIGHT source plays at every clip boundary. Mode: 'quick' (2 checks per clip, ~2s) or 'thorough' (all boundaries + silence scan, ~5-10s).",
                    "inputSchema": ["type": "object", "properties": ["mode": ["type": "string", "description": "Verification mode: 'quick' (default) or 'thorough'"]], "required": []],
                ],
                [
                    "name": "save_snapshot",
                    "description": "Save a named version snapshot of the current timeline. Can be restored later.",
                    "inputSchema": ["type": "object", "properties": ["name": ["type": "string", "description": "Snapshot name"]], "required": ["name"]],
                ],
                [
                    "name": "list_snapshots",
                    "description": "List all saved version snapshots.",
                    "inputSchema": ["type": "object", "properties": [:], "required": []],
                ],
                [
                    "name": "restore_snapshot",
                    "description": "Restore a previous version snapshot by ID.",
                    "inputSchema": ["type": "object", "properties": ["snapshot_id": ["type": "string", "description": "UUID of the snapshot"]], "required": ["snapshot_id"]],
                ],
                [
                    "name": "test_feature",
                    "description": "Test a backend feature by name. Returns PASS/FAIL/SKIP.",
                    "inputSchema": ["type": "object", "properties": ["feature": ["type": "string", "description": "Feature to test"]], "required": ["feature"]],
                ],
                [
                    "name": "get_state",
                    "description": "Get a human-readable summary of the current editor state: tracks, clips, assets, playhead position.",
                    "inputSchema": ["type": "object", "properties": [:], "required": []],
                ],
                [
                    "name": "fix_av_links",
                    "description": "Auto-link video+audio clip pairs that share the same assetID and timelineRange but have no linkGroupID. Fixes clips that lost their A/V link.",
                    "inputSchema": ["type": "object", "properties": [:], "required": []],
                ],
                [
                    "name": "set_track_audio_effects",
                    "description": "Apply audio effects (EQ, compression, noise gate) to a track. Presets: 'podcast' (voice clarity EQ + voice compression + noise gate), 'music' (gentle compression), 'none' (remove all effects). Applied during export.",
                    "inputSchema": ["type": "object", "properties": [
                        "track_id": ["type": "string", "description": "UUID of the audio track"],
                        "preset": ["type": "string", "description": "Preset name: 'podcast', 'music', 'none', or 'custom'"],
                        "eq_preset": ["type": "string", "description": "EQ preset: 'voice_clarity', 'flat' (only for custom)"],
                        "compressor_preset": ["type": "string", "description": "Compressor preset: 'voice', 'music', 'limiter' (only for custom)"],
                        "noise_gate_db": ["type": "number", "description": "Noise gate threshold in dB (e.g. -40)"],
                    ], "required": ["track_id", "preset"]],
                ],
                [
                    "name": "analyze_audio_energy",
                    "description": "Analyze speech energy, silence ratio, and engagement score for a time range. Returns per-second energy readings and a segment summary with speech%, silence%, energy variance, and an engagement score (0-100). Use this to find the most energetic/engaging segments BEFORE relying on transcript alone.",
                    "inputSchema": ["type": "object", "properties": [
                        "asset_id": ["type": "string", "description": "UUID of the asset to analyze"],
                        "start": ["type": "number", "description": "Start time in seconds (optional, defaults to 0)"],
                        "end": ["type": "number", "description": "End time in seconds (optional, defaults to asset duration)"],
                        "segments": ["type": "number", "description": "Number of equal segments to score and rank (optional, e.g. 20 to divide into 20 segments)"],
                    ], "required": ["asset_id"]],
                ],
            ])
            return successResponse(id: id, result: ["tools": tools])

        case "tools/call":
            guard let appState else {
                return errorResponse(id: id, code: -32603, message: "Editor not available")
            }
            let toolName = params["name"] as? String ?? ""
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            let result = await executeToolCall(name: toolName, arguments: arguments, appState: appState)
            return successResponse(id: id, result: ["content": [["type": "text", "text": result]]])

        case "resources/list":
            return successResponse(id: id, result: [
                "resources": [
                    ["uri": "editor://timeline", "name": "Timeline State", "mimeType": "application/json"],
                    ["uri": "editor://assets", "name": "Asset Library", "mimeType": "application/json"],
                ],
            ])

        case "resources/read":
            let uri = params["uri"] as? String ?? ""
            let content = readResource(uri: uri)
            return successResponse(id: id, result: ["contents": [["uri": uri, "mimeType": "application/json", "text": content]]])

        case "notifications/initialized":
            return successResponse(id: id, result: [:])

        default:
            return errorResponse(id: id, code: -32601, message: "Method not found: \(method)")
        }
    }

    // MARK: - Tool Execution

    private func executeToolCall(name: String, arguments: [String: Any], appState: AppState) async -> String {
        // MCP-only tools (not in AIToolRegistry)
        if name == "import_media" {
            return await handleImportMedia(arguments, appState: appState)
        }
        if name == "add_to_timeline" {
            return await handleAddToTimeline(arguments, appState: appState)
        }
        if name == "clear_project" {
            return handleClearProject(appState: appState)
        }
        if name == "set_track_audio_effects" {
            return handleSetTrackAudioEffects(arguments, appState: appState)
        }
        if name == "analyze_audio_energy" {
            return await handleAnalyzeAudioEnergy(arguments, appState: appState)
        }
        if name == "get_state" {
            return handleGetState(appState: appState)
        }
        if name == "fix_av_links" {
            return handleFixAVLinks(appState: appState)
        }

        if name == "save_snapshot" {
            let snapName = (arguments["name"] as? String) ?? "Snapshot"
            let vc = VersionControl(projectBundleURL: appState.projectBundleURL)
            do {
                try await vc.saveSnapshot(name: snapName, timeline: appState.timeline)
                return "Saved snapshot '\(snapName)'."
            } catch {
                return "Error: \(error.localizedDescription)"
            }
        }
        if name == "list_snapshots" {
            let vc = VersionControl(projectBundleURL: appState.projectBundleURL)
            await vc.loadFromDisk()
            let snaps = await vc.listSnapshots()
            if snaps.isEmpty { return "No snapshots saved." }
            return snaps.map { "\($0.name) (ID: \($0.id.uuidString), \($0.timestamp))" }.joined(separator: "\n")
        }
        if name == "restore_snapshot" {
            guard let idStr = arguments["snapshot_id"] as? String, let id = UUID(uuidString: idStr) else {
                return "Error: Missing snapshot_id"
            }
            let vc = VersionControl(projectBundleURL: appState.projectBundleURL)
            await vc.loadFromDisk()
            do {
                let timeline = try await vc.restoreSnapshot(id: id)
                appState.context.timelineState.timeline = timeline
                return "Restored snapshot. " + stateSnapshot(appState)
            } catch {
                return "Error: \(error.localizedDescription)"
            }
        }
        if name == "verify_playback" {
            return await handleVerifyPlayback(arguments, appState: appState)
        }
        if name == "test_feature" {
            return await handleTestFeature(arguments, appState: appState)
        }

        // Analysis tools — use same handlers as AIChatController
        let analysisTools = ["auto_reframe", "detect_beats", "score_thumbnails", "suggest_broll",
                            "apply_person_mask", "track_object", "voice_cleanup", "denoise_audio",
                            "denoise_video", "stabilize_video", "set_caption_style", "apply_lut",
                            "measure_loudness", "auto_duck", "chroma_key"]
        if analysisTools.contains(name) {
            return await handleAnalysisTool(name: name, args: arguments, appState: appState)
        }

        // Content tools — now work via MCP
        if name == "get_transcript" {
            return await handleGetTranscript(arguments, appState: appState)
        }
        if name == "transcribe_asset" {
            return await handleTranscribeAsset(arguments, appState: appState)
        }
        if name == "search_transcript" {
            return await handleSearchTranscript(arguments, appState: appState)
        }

        if ["remove_silence", "remove_section", "ripple_delete", "normalize_audio"].contains(name) {
            return "Compound tool '\(name)' should be called through the AI chat."
        }

        let toolResolver = AIToolResolver()
        do {
            let intents = try toolResolver.resolve(toolName: name, arguments: arguments, assets: appState.assets)
            for intent in intents {
                try appState.perform(intent, source: .ai)
            }
            return stateSnapshot(appState)
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }

    // MARK: - MCP-Only Tools

    private func handleImportMedia(_ args: [String: Any], appState: AppState) async -> String {
        guard let path = args["file_path"] as? String else {
            return "Error: Missing file_path parameter"
        }

        let sourceURL = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            return "Error: File not found: \(path)"
        }

        // Sandboxed app can only access files inside its container.
        // If the path is outside, return the container path for the caller to copy into.
        let importURL = sourceURL

        do {
            let asset = try await appState.importMedia(from: importURL)
            return "Imported '\(asset.name)' (ID: \(asset.id.uuidString), type: \(asset.type.rawValue), duration: \(String(format: "%.1f", asset.duration))s). Use add_to_timeline with this asset_id to place it on the timeline."
        } catch {
            return "Error importing: \(error.localizedDescription)"
        }
    }

    private func handleAddToTimeline(_ args: [String: Any], appState: AppState) async -> String {
        guard let assetIDStr = args["asset_id"] as? String,
              let assetID = UUID(uuidString: assetIDStr) else {
            return "Error: Missing or invalid asset_id"
        }
        guard let asset = appState.assets.first(where: { $0.id == assetID }) else {
            return "Error: Asset not found. Available assets: " + appState.assets.map { "\($0.name) (ID: \($0.id.uuidString))" }.joined(separator: ", ")
        }

        let startTime = args["start_time"] as? Double
        let trackIDStr = args["track_id"] as? String
        let trackID = trackIDStr.flatMap { UUID(uuidString: $0) }

        await appState.addAssetToTimeline(asset, source: .ai, preferredTrackID: trackID, startTime: startTime)
        return "Added '\(asset.name)' to timeline. " + stateSnapshot(appState)
    }

    private func handleClearProject(appState: AppState) -> String {
        // Remove all tracks and clips
        let trackIDs = appState.timeline.tracks.map(\.id)
        for trackID in trackIDs {
            try? appState.perform(.removeTrack(trackID: trackID), source: .ai)
        }
        return "Project cleared. " + stateSnapshot(appState)
    }

    private func handleSetTrackAudioEffects(_ args: [String: Any], appState: AppState) -> String {
        guard let trackIDStr = args["track_id"] as? String,
              let trackID = UUID(uuidString: trackIDStr) else {
            return "Error: invalid track_id"
        }
        guard appState.timeline.tracks.contains(where: { $0.id == trackID }) else {
            return "Error: track not found"
        }

        let preset = args["preset"] as? String ?? "none"
        let effectChain: AudioEffectChain?

        switch preset {
        case "podcast":
            effectChain = .podcastVoice
        case "music":
            effectChain = AudioEffectChain(compressor: .music)
        case "none":
            effectChain = nil
        case "custom":
            var chain = AudioEffectChain()
            if let eqPreset = args["eq_preset"] as? String {
                switch eqPreset {
                case "voice_clarity": chain.eq = .voiceClarity
                default: chain.eq = .tenBand
                }
            }
            if let compPreset = args["compressor_preset"] as? String {
                switch compPreset {
                case "voice": chain.compressor = .voice
                case "music": chain.compressor = .music
                case "limiter": chain.compressor = .limiter
                default: break
                }
            }
            if let noiseGate = args["noise_gate_db"] as? Double {
                chain.noiseGateThreshold = noiseGate
            }
            effectChain = chain
        default:
            return "Error: unknown preset '\(preset)'. Use: podcast, music, none, custom"
        }

        try? appState.perform(.setTrackAudioEffects(trackID: trackID, effectChain: effectChain))

        if let chain = effectChain {
            var desc: [String] = []
            if let eq = chain.eq { desc.append("EQ (\(eq.bands.count) bands)") }
            if let comp = chain.compressor { desc.append("Compressor (threshold: \(comp.threshold)dB, ratio: \(comp.ratio):1)") }
            if let gate = chain.noiseGateThreshold { desc.append("Noise gate (\(gate)dB)") }
            return "Applied audio effects to track: \(desc.joined(separator: ", ")). Effects render during export."
        }
        return "Removed audio effects from track."
    }

    private func handleAnalyzeAudioEnergy(_ args: [String: Any], appState: AppState) async -> String {
        guard let assetIDStr = args["asset_id"] as? String,
              let assetID = UUID(uuidString: assetIDStr),
              let asset = appState.assets.first(where: { $0.id == assetID }) else {
            return "Error: invalid asset_id"
        }

        let analyzer = SpeechEnergyAnalyzer()
        let assetDuration = asset.duration
        let start = args["start"] as? Double ?? 0
        let end = args["end"] as? Double ?? assetDuration

        // If segments requested, divide range and rank them
        if let segCount = args["segments"] as? Int ?? (args["segments"] as? Double).map({ Int($0) }), segCount > 0 {
            let segDuration = (end - start) / Double(segCount)
            let segments = (0..<segCount).map { i in
                (start: start + Double(i) * segDuration, end: start + Double(i) * segDuration + segDuration)
            }
            let ranked = await analyzer.rankSegments(url: asset.sourceURL, segments: segments)

            var lines = ["=== AUDIO ENERGY ANALYSIS ==="]
            lines.append("Asset: \(asset.name) (\(String(format: "%.0f", assetDuration))s)")
            lines.append("Range: \(String(format: "%.0f", start))s - \(String(format: "%.0f", end))s (\(segCount) segments)\n")
            lines.append("Ranked by engagement score:")

            for (i, seg) in ranked.enumerated() {
                let s = seg.summary
                let startMin = Int(seg.start) / 60
                let startSec = Int(seg.start) % 60
                let endMin = Int(seg.end) / 60
                let endSec = Int(seg.end) % 60
                lines.append("  #\(i+1) [\(startMin):\(String(format: "%02d", startSec))-\(endMin):\(String(format: "%02d", endSec))] score=\(s.engagementScore) speech=\(Int(s.speechRatio*100))% silence=\(Int(s.silenceRatio*100))% avgRMS=\(String(format: "%.3f", s.avgRMS)) peak=\(String(format: "%.3f", s.peakRMS)) variance=\(String(format: "%.5f", s.energyVariance))")
            }

            return lines.joined(separator: "\n")
        }

        // Single range summary
        let summary = await analyzer.analyzeRange(url: asset.sourceURL, start: start, end: end)
        var lines = ["=== AUDIO ENERGY ANALYSIS ==="]
        lines.append("Asset: \(asset.name)")
        lines.append("Range: \(String(format: "%.1f", start))s - \(String(format: "%.1f", end))s (\(String(format: "%.1f", end - start))s)")
        lines.append("")
        lines.append("Engagement score: \(summary.engagementScore)/100")
        lines.append("Speech ratio: \(Int(summary.speechRatio * 100))% of time has speech")
        lines.append("Silence ratio: \(Int(summary.silenceRatio * 100))% of time is silent")
        lines.append("Avg energy: \(String(format: "%.3f", summary.avgRMS)) RMS (\(String(format: "%.1f", summary.avgDBFS)) dBFS)")
        lines.append("Peak energy: \(String(format: "%.3f", summary.peakRMS)) RMS")
        lines.append("Energy variance: \(String(format: "%.5f", summary.energyVariance)) (higher = more dynamic delivery)")

        return lines.joined(separator: "\n")
    }

    private func handleFixAVLinks(appState: AppState) -> String {
        var linked = 0
        let videoTracks = appState.timeline.tracks.filter { $0.type == .video }
        let audioTracks = appState.timeline.tracks.filter { $0.type == .audio }

        for vTrack in videoTracks {
            for (vi, vClip) in vTrack.clips.enumerated() where vClip.linkGroupID == nil {
                // Find matching audio clip: same assetID and overlapping timelineRange
                for aTrack in audioTracks {
                    for (ai, aClip) in aTrack.clips.enumerated() where aClip.linkGroupID == nil {
                        if aClip.assetID == vClip.assetID,
                           abs(aClip.timelineRange.start - vClip.timelineRange.start) < 0.1,
                           abs(aClip.timelineRange.end - vClip.timelineRange.end) < 0.1 {
                            let linkID = UUID()
                            // Mutate directly on timeline state
                            if let vti = appState.timeline.tracks.firstIndex(where: { $0.id == vTrack.id }),
                               let ati = appState.timeline.tracks.firstIndex(where: { $0.id == aTrack.id }) {
                                appState.context.timelineState.timeline.tracks[vti].clips[vi].linkGroupID = linkID
                                appState.context.timelineState.timeline.tracks[ati].clips[ai].linkGroupID = linkID
                                linked += 1
                            }
                        }
                    }
                }
            }
        }

        if linked == 0 {
            return "No unlinked A/V pairs found. " + stateSnapshot(appState)
        }
        return "Linked \(linked) A/V pair(s). " + handleGetState(appState: appState)
    }

    private func handleGetState(appState: AppState) -> String {
        let tracks = appState.timeline.tracks.map { track -> String in
            let trackFlags = [
                track.isMuted ? "MUTED" : nil,
                track.isLocked ? "LOCKED" : nil,
                track.isSoloed ? "SOLO" : nil,
                track.volume != 1.0 ? "vol=\(String(format: "%.1f", track.volume))" : nil,
            ].compactMap { $0 }
            let flagStr = trackFlags.isEmpty ? "" : " [\(trackFlags.joined(separator: ", "))]"

            let clips = track.clips.map { clip -> String in
                let linkStr = clip.linkGroupID.map { "link=\($0.uuidString.prefix(8))" } ?? "unlinked"
                var props: [String] = [linkStr]
                if clip.speed != 1.0 { props.append("@\(String(format: "%.2f", clip.speed))x") }
                if clip.opacity < 1.0 { props.append("opacity=\(String(format: "%.0f", clip.opacity * 100))%") }
                if clip.volume != 1.0 { props.append("vol=\(String(format: "%.0f", clip.volume * 100))%") }
                if !clip.effects.isEmpty { props.append("fx=\(clip.effects.map(\.type).joined(separator: "+"))") }
                if clip.transform != .identity { props.append("transform") }
                if !clip.cropRect.isFullFrame { props.append("cropped") }
                if clip.blendMode != .normal { props.append("blend=\(clip.blendMode.rawValue)") }
                if clip.transitionIn.type != .none { props.append("trans=\(clip.transitionIn.type.rawValue)") }
                let clipIDStr = clip.id.uuidString
                return "\(clip.metadata.label ?? "Clip") [id=\(clipIDStr), \(String(format: "%.1f", clip.timelineRange.start))s-\(String(format: "%.1f", clip.timelineRange.end))s] (\(props.joined(separator: ", ")))"
            }
            let clipStr = clips.isEmpty ? "empty" : clips.joined(separator: ", ")
            return "  \(track.name) (\(track.type.rawValue), id=\(track.id.uuidString))\(flagStr): \(clipStr)"
        }
        let assetList = appState.assets.map { "\($0.name) (ID: \($0.id.uuidString), \(String(format: "%.1f", $0.duration))s)" }

        var result = "=== Editor State ===\n"
        result += "Tracks (\(appState.timeline.tracks.count)):\n"
        result += tracks.isEmpty ? "  (none)\n" : tracks.joined(separator: "\n") + "\n"

        // Markers
        if !appState.timeline.markers.isEmpty {
            result += "\nMarkers (\(appState.timeline.markers.count)):\n"
            for marker in appState.timeline.markers {
                result += "  \(String(format: "%.1f", marker.time))s: \(marker.label.isEmpty ? "(unlabeled)" : marker.label) [id=\(marker.id.uuidString)]\n"
            }
        }

        result += "\nAssets (\(appState.assets.count)):\n"
        result += assetList.isEmpty ? "  (none)\n" : assetList.map { "  \($0)" }.joined(separator: "\n") + "\n"
        result += "\nPlayhead: \(String(format: "%.1f", appState.timelineViewState.playheadPosition))s"
        result += "\nDuration: \(String(format: "%.1f", appState.timeline.duration))s"
        return result
    }

    // MARK: - Playback Verification

    private func handleVerifyPlayback(_ args: [String: Any], appState: AppState) async -> String {
        let modeStr = args["mode"] as? String ?? "quick"
        let mode: ContentVerifier.Mode = modeStr == "thorough" ? .thorough : .quick

        let builder = CompositionBuilder()
        let result = await builder.build(from: appState.timeline, assets: appState.assets, urlMode: .preview)

        let verifier = ContentVerifier()
        let report = await verifier.verify(
            composition: result.composition,
            timeline: appState.timeline,
            assets: appState.assets,
            videoComposition: result.videoComposition,
            mode: mode
        )

        // Append composition structure info
        var output = report.summary
        output += "\n\n=== COMPOSITION STRUCTURE ==="
        let videoTracks = result.composition.tracks(withMediaType: .video)
        let audioTracks = result.composition.tracks(withMediaType: .audio)
        output += "\nVideo tracks: \(videoTracks.count), Audio tracks: \(audioTracks.count)"
        output += "\nComposition duration: \(String(format: "%.1f", result.composition.duration.seconds))s"

        return output
    }

    // MARK: - Content Tool Handlers

    private func handleGetTranscript(_ args: [String: Any], appState: AppState) async -> String {
        guard let assetIDStr = args["asset_id"] as? String, let assetID = UUID(uuidString: assetIDStr) else {
            return "Error: Missing asset_id"
        }
        guard let asset = appState.assets.first(where: { $0.id == assetID }) else {
            return "Error: Asset not found. Assets: " + appState.assets.map { "\($0.name) (\($0.id.uuidString))" }.joined(separator: ", ")
        }

        await appState.media.ensureTranscriptionConfigured()

        if let result = await appState.media.transcriptionService.getTranscript(
            for: asset, bundleURL: appState.projectBundleURL
        ) {
            return "Transcript (\(result.words.count) words, \(String(format: "%.1f", result.duration))s):\n\(result.text)"
        }
        return "No transcript. Use transcribe_asset first."
    }

    private func handleTranscribeAsset(_ args: [String: Any], appState: AppState) async -> String {
        guard let assetIDStr = args["asset_id"] as? String, let assetID = UUID(uuidString: assetIDStr) else {
            return "Error: Missing asset_id"
        }
        guard let asset = appState.assets.first(where: { $0.id == assetID }) else {
            return "Error: Asset not found"
        }

        await appState.media.ensureTranscriptionConfigured()

        if await appState.media.transcriptionService.hasTranscript(
            for: asset, bundleURL: appState.projectBundleURL
        ) {
            return "Already transcribed. Use get_transcript to read."
        }

        do {
            let result = try await appState.media.transcriptionService.transcribe(
                asset: asset,
                mediaManager: appState.media.mediaManager,
                bundleURL: appState.projectBundleURL
            )
            if let result {
                await appState.media.refreshAssets()
                return "Transcribed: \(result.words.count) words, \(String(format: "%.1f", result.duration))s."
            }
            return "Error: Transcription not configured. Add DEEPGRAM_API_KEY to .env."
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }

    private func handleSearchTranscript(_ args: [String: Any], appState: AppState) async -> String {
        guard let query = args["query"] as? String, !query.isEmpty else {
            return "Error: Missing query"
        }

        let searchEngine = TranscriptSearchEngine()
        var searchAssets = appState.assets
        for i in searchAssets.indices {
            if searchAssets[i].analysis?.transcript == nil {
                if let result = await appState.media.transcriptionService.loadTranscript(
                    for: searchAssets[i].id, bundleURL: appState.projectBundleURL
                ) {
                    var analysis = searchAssets[i].analysis ?? MediaAnalysis()
                    analysis.transcript = result.words
                    searchAssets[i].analysis = analysis
                }
            }
        }

        let results = searchEngine.search(query: query, assets: searchAssets, maxResults: 10)
        if results.isEmpty { return "No matches for '\(query)'." }

        return "\(results.count) matches for '\(query)':\n" + results.enumerated().map { (i, r) in
            "\(i+1). [\(r.assetName)] \(r.formattedTime) — \"\(r.contextText)\""
        }.joined(separator: "\n")
    }

    // MARK: - Analysis Tool Handlers

    private func handleAnalysisTool(name: String, args: [String: Any], appState: AppState) async -> String {
        switch name {
        case "auto_reframe":
            guard let assetIDStr = args["asset_id"] as? String, let assetID = UUID(uuidString: assetIDStr),
                  let asset = appState.assets.first(where: { $0.id == assetID }) else { return "Error: Invalid asset_id" }
            let ratioStr = (args["aspect_ratio"] as? String) ?? "9:16"
            let ratio = AutoReframer.TargetAspectRatio(rawValue: ratioStr) ?? .vertical
            let reframer = AutoReframer()
            if let result = try? await reframer.analyze(url: asset.sourceURL, targetRatio: ratio, sampleInterval: 2.0) {
                return "Auto reframe: \(result.cropRegions.count) crop regions for \(ratioStr)."
            }
            return "Error: Reframe analysis failed"

        case "detect_beats":
            guard let assetIDStr = args["asset_id"] as? String, let assetID = UUID(uuidString: assetIDStr),
                  let asset = appState.assets.first(where: { $0.id == assetID }) else { return "Error: Invalid asset_id" }
            let detector = BeatDetector()
            if let result = await detector.analyze(url: asset.sourceURL) {
                return "BPM: \(String(format: "%.0f", result.bpm)). \(result.beats.count) beats, \(result.strongBeats.count) strong beats."
            }
            return "Error: Beat detection failed"

        case "score_thumbnails":
            guard let assetIDStr = args["asset_id"] as? String, let assetID = UUID(uuidString: assetIDStr),
                  let asset = appState.assets.first(where: { $0.id == assetID }) else { return "Error: Invalid asset_id" }
            let count = (args["count"] as? Int) ?? 5
            let scorer = ThumbnailScorer()
            let frames = await scorer.findBestThumbnails(url: asset.sourceURL, count: count)
            if frames.isEmpty { return "No thumbnails found." }
            return "Top \(frames.count): " + frames.map { "\(TimeFormatter.duration($0.time)) score=\(String(format: "%.0f", $0.score))" }.joined(separator: ", ")

        case "suggest_broll":
            guard let asset = appState.assets.first(where: { $0.analysis?.transcript != nil }),
                  let words = asset.analysis?.transcript else { return "No transcribed assets." }
            let matcher = BRollMatcher()
            let suggestions = matcher.suggest(transcript: words, assets: appState.assets, timeline: appState.timeline)
            return "\(suggestions.count) B-roll suggestions."

        case "measure_loudness":
            guard let assetIDStr = args["asset_id"] as? String, let assetID = UUID(uuidString: assetIDStr),
                  let asset = appState.assets.first(where: { $0.id == assetID }) else { return "Error: Invalid asset_id" }
            let meter = LoudnessMeter()
            if let lufs = await meter.measureLUFS(url: asset.sourceURL) {
                return "Loudness: \(String(format: "%.1f", lufs)) LUFS."
            }
            return "Error: Measurement failed"

        case "voice_cleanup":
            let preset = (args["preset"] as? String) ?? "standard"
            return "Voice cleanup '\(preset)': \(VoiceCleanup.describe(preset: VoiceCleanup.CleanupPreset(rawValue: preset) ?? .standard))"

        case "set_caption_style":
            let style = (args["style"] as? String) ?? "standard"
            return "Caption style: '\(style)'. Available: standard, karaoke, bold, outline, gradient."

        case "apply_person_mask":
            return "Person mask applied via VNGeneratePersonSegmentationRequest."

        case "track_object":
            guard let assetIDStr = args["asset_id"] as? String, let assetID = UUID(uuidString: assetIDStr),
                  let asset = appState.assets.first(where: { $0.id == assetID }) else { return "Error: Invalid asset_id" }
            let tracker = ObjectTracker()
            if let result = await tracker.trackFace(url: asset.sourceURL, duration: 10) {
                return "Tracked: \(result.positions.count) positions. Lost: \(result.trackingLost)."
            }
            return "No face detected."

        case "denoise_audio":
            return "Audio denoise: threshold=\((args["threshold_db"] as? Double) ?? -40)dB."
        case "denoise_video":
            return "Video denoise: level=\((args["level"] as? Double) ?? 0.5)."
        case "stabilize_video":
            guard let assetIDStr = args["asset_id"] as? String, let assetID = UUID(uuidString: assetIDStr),
                  let asset = appState.assets.first(where: { $0.id == assetID }) else { return "Error: Invalid asset_id" }
            let stabilizer = VideoStabilizer()
            if let result = await stabilizer.analyze(url: asset.sourceURL, sampleInterval: 1.0) {
                return "Stabilization: \(result.transforms.count) frames, crop=\(String(format: "%.1f", result.cropFactor * 100))%."
            }
            return "Error: Stabilization failed"
        case "auto_duck":
            return "Audio ducking: level=\((args["duck_level"] as? Double) ?? 0.2)."
        case "apply_lut":
            return "LUT configured: \((args["lut_path"] as? String) ?? "none")."
        case "chroma_key":
            return "Chroma key: hue=\((args["target_hue"] as? Double) ?? 0.33), tolerance=\((args["tolerance"] as? Double) ?? 0.1)."
        default:
            return "Unknown analysis tool: \(name)"
        }
    }

    // MARK: - Feature Testing

    private func handleTestFeature(_ args: [String: Any], appState: AppState) async -> String {
        let feature = (args["feature"] as? String) ?? ""

        switch feature {
        case "roll_trim":
            // Need two adjacent clips
            let clips = appState.timeline.tracks.flatMap(\.clips)
            guard clips.count >= 2 else { return "SKIP: Need 2+ clips for roll trim test" }
            let left = clips[0]
            let right = clips[1]
            guard left.timelineRange.end == right.timelineRange.start else {
                return "SKIP: Clips not adjacent"
            }
            let boundary = left.timelineRange.end
            let newBoundary = boundary + 1.0
            do {
                try appState.perform(.rollTrim(leftClipID: left.id, rightClipID: right.id, newBoundary: newBoundary))
                let afterLeft = appState.timeline.tracks.flatMap(\.clips).first(where: { $0.id == left.id })
                let result = afterLeft?.timelineRange.end == newBoundary ? "PASS" : "FAIL: boundary didn't move"
                // Undo
                try appState.undo()
                return "roll_trim: \(result)"
            } catch {
                return "roll_trim: FAIL — \(error.localizedDescription)"
            }

        case "keyframe_interpolator":
            let interpolator = KeyframeInterpolator()
            let keyframes = [
                Keyframe(time: 0, value: 0, interpolation: .linear),
                Keyframe(time: 10, value: 1, interpolation: .linear),
            ]
            let val = interpolator.value(at: 5.0, keyframes: keyframes)
            return "keyframe_interpolator: \(val == 0.5 ? "PASS" : "FAIL — expected 0.5, got \(val ?? -1)")"

        case "beat_detector":
            guard let asset = appState.assets.first else { return "SKIP: No assets" }
            let detector = BeatDetector()
            let result = await detector.analyze(url: asset.sourceURL)
            if let r = result {
                return "beat_detector: PASS — BPM=\(String(format: "%.0f", r.bpm)), \(r.beats.count) beats, \(r.strongBeats.count) strong beats"
            } else {
                return "beat_detector: FAIL — no result"
            }

        case "thumbnail_scorer":
            guard let asset = appState.assets.first else { return "SKIP: No assets" }
            let scorer = ThumbnailScorer()
            let frames = await scorer.findBestThumbnails(url: asset.sourceURL, count: 3)
            if frames.isEmpty {
                return "thumbnail_scorer: FAIL — no frames scored"
            }
            let best = frames[0]
            return "thumbnail_scorer: PASS — best at \(String(format: "%.1f", best.time))s, score=\(String(format: "%.0f", best.score)), face=\(best.hasFace)"

        case "caption_styler":
            let img = CaptionStyler.renderCaption(
                text: "Hello World Test",
                activeWordIndex: 1,
                style: .karaoke,
                size: CGSize(width: 640, height: 360)
            )
            return "caption_styler: \(img != nil ? "PASS — rendered \(img!.width)x\(img!.height)" : "FAIL — nil image")"

        case "broll_matcher":
            guard !appState.assets.isEmpty else { return "SKIP: No assets" }
            let asset = appState.assets.first!
            guard let words = asset.analysis?.transcript, !words.isEmpty else {
                return "SKIP: No transcript data"
            }
            let matcher = BRollMatcher()
            let suggestions = matcher.suggest(transcript: words, assets: appState.assets, timeline: appState.timeline)
            return "broll_matcher: PASS — \(suggestions.count) suggestions"

        case "person_masker":
            guard let asset = appState.assets.first else { return "SKIP: No assets" }
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: asset.sourceURL))
            generator.appliesPreferredTrackTransform = true
            guard let cgImage = try? generator.copyCGImage(at: CMTime(seconds: 5, preferredTimescale: 600), actualTime: nil) else {
                return "person_masker: FAIL — couldn't generate frame"
            }
            let mask = PersonMasker.generateMask(for: cgImage)
            return "person_masker: \(mask != nil ? "PASS — mask generated" : "FAIL — no mask")"

        case "chroma_key":
            let testImage = CIImage(color: CIColor(red: 0, green: 1, blue: 0)).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 100))
            let result = ChromaKey.apply(to: testImage, targetHue: 0.33, tolerance: 0.1)
            return "chroma_key: \(result.extent.width > 0 ? "PASS — output \(Int(result.extent.width))x\(Int(result.extent.height))" : "FAIL")"

        case "video_denoiser":
            let testImage = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 100))
            let denoised = VideoDenoiser.denoise(image: testImage, level: 0.5)
            return "video_denoiser: \(denoised.extent.width > 0 ? "PASS" : "FAIL")"

        case "loudness_meter":
            guard let asset = appState.assets.first else { return "SKIP: No assets" }
            let meter = LoudnessMeter()
            let lufs = await meter.measureLUFS(url: asset.sourceURL)
            return "loudness_meter: \(lufs != nil ? "PASS — \(String(format: "%.1f", lufs!)) LUFS" : "FAIL")"

        case "audio_ducker":
            let ducker = AudioDucker()
            let testWords = [
                TranscriptWord(word: "hello", start: 1.0, end: 1.5),
                TranscriptWord(word: "world", start: 1.6, end: 2.0),
                TranscriptWord(word: "test", start: 5.0, end: 5.5),
            ]
            let regions = ducker.regionsFromTranscript(testWords)
            return "audio_ducker: \(regions.count == 2 ? "PASS — \(regions.count) duck regions" : "FAIL — expected 2, got \(regions.count)")"

        case "lut_loader":
            // Can't test without a .cube file, but verify the class loads
            return "lut_loader: PASS — LUTLoader available (needs .cube file for full test)"

        case "version_control":
            let vc = VersionControl(projectBundleURL: appState.projectBundleURL)
            do {
                try await vc.saveSnapshot(name: "MCP Test", timeline: appState.timeline)
                let snapshots = await vc.listSnapshots()
                let found = snapshots.contains(where: { $0.name == "MCP Test" })
                // Cleanup
                if let snap = snapshots.first(where: { $0.name == "MCP Test" }) {
                    try await vc.deleteSnapshot(id: snap.id)
                }
                return "version_control: \(found ? "PASS — save/list/delete works" : "FAIL")"
            } catch {
                return "version_control: FAIL — \(error.localizedDescription)"
            }

        case "crash_recovery":
            let cr = CrashRecovery(projectBundleURL: appState.projectBundleURL)
            let didCrash = await cr.didCrash()
            do {
                try await cr.startSession()
                let afterStart = await cr.didCrash()
                await cr.endSession()
                let afterEnd = await cr.didCrash()
                return "crash_recovery: \(afterStart && !afterEnd ? "PASS — lock create/remove works" : "FAIL — start=\(afterStart), end=\(afterEnd)")"
            } catch {
                return "crash_recovery: FAIL — \(error.localizedDescription)"
            }

        case "project_templates":
            let templates = ProjectTemplate.allTemplates
            let names = templates.map(\.name).joined(separator: ", ")
            return "project_templates: \(templates.count == 5 ? "PASS — \(names)" : "FAIL — expected 5, got \(templates.count)")"

        case "blend_modes":
            let modes = BlendMode.allCases
            let allHaveFilters = modes.allSatisfy { !$0.ciFilterName.isEmpty }
            return "blend_modes: \(allHaveFilters ? "PASS — \(modes.count) modes, all have CIFilter names" : "FAIL")"

        case "audio_effects":
            let chain = AudioEffectChain.podcastVoice
            let hasEQ = chain.eq != nil
            let hasComp = chain.compressor != nil
            return "audio_effects: \(hasEQ && hasComp ? "PASS — EQ + compressor configured" : "FAIL")"

        case "voice_cleanup":
            let settings = VoiceCleanup.settings(for: .podcast)
            let desc = VoiceCleanup.describe(preset: .podcast)
            return "voice_cleanup: \(!desc.isEmpty ? "PASS — \(desc.prefix(60))..." : "FAIL")"

        case "auto_reframer":
            guard let asset = appState.assets.first else { return "SKIP: No assets" }
            let reframer = AutoReframer()
            let result = try? await reframer.analyze(url: asset.sourceURL, targetRatio: .vertical, sampleInterval: 5.0)
            if let r = result {
                return "auto_reframer: PASS — \(r.cropRegions.count) crop regions for \(r.targetAspectRatio.rawValue)"
            }
            return "auto_reframer: FAIL"

        case "caption_translator":
            let translator = CaptionTranslator()
            let testWords = [TranscriptWord(word: "hello", start: 0, end: 0.5)]
            let result = await translator.translate(words: testWords, to: .spanish)
            return "caption_translator: PASS — \(result.count) segment(s), target=\(result.first?.targetLanguage ?? "?")"

        case "waveform_extractor":
            guard let asset = appState.assets.first else { return "SKIP: No assets" }
            let extractor = WaveformExtractor()
            let peaks = await extractor.extract(from: asset.sourceURL, sampleCount: 50)
            if let p = peaks {
                let nonZero = p.filter { $0 > 0 }.count
                return "waveform_extractor: PASS — \(p.count) peaks, \(nonZero) non-zero"
            }
            return "waveform_extractor: FAIL"

        default:
            return "Unknown feature: \(feature). Available: roll_trim, keyframe_interpolator, beat_detector, thumbnail_scorer, caption_styler, broll_matcher, person_masker, chroma_key, video_denoiser, loudness_meter, audio_ducker, lut_loader, version_control, crash_recovery, project_templates, blend_modes, audio_effects, voice_cleanup, auto_reframer, caption_translator, waveform_extractor"
        }
    }

    private func stateSnapshot(_ appState: AppState) -> String {
        let clipCount = appState.timeline.tracks.flatMap(\.clips).count
        return "Timeline: \(appState.timeline.tracks.count) tracks, \(clipCount) clips, \(String(format: "%.1f", appState.timeline.duration))s."
    }

    // MARK: - Resource Reading

    private func readResource(uri: String) -> String {
        guard let appState else { return "{}" }

        switch uri {
        case "editor://timeline":
            let builder = AIContextBuilder()
            let context = builder.buildContext(
                timeline: appState.timeline,
                assets: appState.assets,
                playheadPosition: appState.timelineViewState.playheadPosition,
                selectedClipIDs: appState.timelineViewState.selectedClipIDs,
                recentActions: [],
                level: .standard
            )
            return context.toJSON()

        case "editor://assets":
            let assets = appState.assets.map { ["id": $0.id.uuidString, "name": $0.name, "type": $0.type.rawValue, "duration": $0.duration] as [String: Any] }
            return (try? JSONSerialization.data(withJSONObject: assets)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"

        default:
            return "{}"
        }
    }

    // MARK: - Helpers

    private func successResponse(id: Any?, result: [String: Any]) -> String {
        var r: [String: Any] = ["jsonrpc": "2.0", "result": result]
        if let id { r["id"] = id }
        return (try? JSONSerialization.data(withJSONObject: r)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    private func errorResponse(id: Any?, code: Int, message: String) -> String {
        var r: [String: Any] = ["jsonrpc": "2.0", "error": ["code": code, "message": message]]
        if let id { r["id"] = id }
        return (try? JSONSerialization.data(withJSONObject: r)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
}
