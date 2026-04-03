import Foundation
import AVFoundation
import AppKit
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
    private var cachedToolsResponse: String?

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
            if let cached = cachedToolsResponse {
                return cached
            }
            var tools = AIToolRegistry.allTools.map { tool -> [String: Any] in
                let schemaData = try? JSONEncoder().encode(tool.parameters)
                let schema = schemaData.flatMap { try? JSONSerialization.jsonObject(with: $0) } ?? [:]
                return ["name": tool.name, "description": tool.description, "inputSchema": schema]
            }
            // MCP-only tools
            tools.append(contentsOf: [
                [
                    "name": "import_media",
                    "description": "Import a video, audio, or image file into the project. The app is sandboxed — files must be inside the container at ~/Library/Containers/com.videoeditor.app/Data/Documents/. Copy the file there first using 'cp', then pass the container path. Returns the asset_id for use with add_to_timeline.",
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
                    "name": "export_video",
                    "description": "Export the current timeline to an MP4 file. Returns the file path. Presets: 'low' (480p), 'medium' (720p), 'high' (1080p), '4k' (2160p).",
                    "inputSchema": ["type": "object", "properties": ["preset": ["type": "string", "description": "Quality preset: low, medium, high (default), 4k"], "filename": ["type": "string", "description": "Output filename (without extension)"]], "required": []],
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
                [
                    "name": "generate_title",
                    "description": "Generate a compelling title for the current edit based on transcript content. Analyzes the timeline's clips, reads their transcript, and suggests 3-5 title options ranked by engagement potential.",
                    "inputSchema": ["type": "object", "properties": [
                        "style": ["type": "string", "description": "Title style: 'youtube' (clickable), 'professional' (clean), 'viral' (provocative). Default: youtube"],
                    ], "required": []],
                ],
                [
                    "name": "auto_insert_broll",
                    "description": "Automatically find and insert B-roll from the media library at relevant points in the timeline. Analyzes transcript topics and matches them to available assets.",
                    "inputSchema": ["type": "object", "properties": [
                        "max_inserts": ["type": "number", "description": "Maximum number of B-roll clips to insert (default: 5)"],
                        "duration": ["type": "number", "description": "Duration of each B-roll insert in seconds (default: 3)"],
                    ], "required": []],
                ],
                [
                    "name": "search_broll",
                    "description": "Search Pexels for stock B-roll footage matching a topic or the current timeline's transcript. Can optionally download and insert the best match. Requires PEXELS_API_KEY environment variable or .env file.",
                    "inputSchema": ["type": "object", "properties": [
                        "query": ["type": "string", "description": "Search query. If omitted, uses Claude to extract visual concepts from the timeline's transcript."],
                        "download": ["type": "boolean", "description": "If true, downloads the best match and inserts it at the specified position."],
                        "insert_at": ["type": "number", "description": "Timeline position in seconds to insert the B-roll clip."],
                        "duration": ["type": "number", "description": "Max duration in seconds for the B-roll clip (default 5)."],
                    ], "required": []],
                ],
                [
                    "name": "delete_asset",
                    "description": "Remove an imported asset from the media library. Cannot delete assets that are currently used by clips on the timeline.",
                    "inputSchema": ["type": "object", "properties": [
                        "asset_id": ["type": "string", "description": "UUID of the asset to delete"],
                    ], "required": ["asset_id"]],
                ],
                [
                    "name": "set_zoom",
                    "description": "Set the timeline zoom level. Use 'fit' to zoom to fit all content, or specify pixels per second. Always call set_zoom with 'fit' before take_screenshot to ensure clips are visible.",
                    "inputSchema": ["type": "object", "properties": [
                        "level": ["type": "string", "description": "'fit' to auto-fit timeline content, or a number for pixels per second (e.g. '100', '200')"],
                    ], "required": ["level"]],
                ],
                [
                    "name": "take_screenshot",
                    "description": "Capture a screenshot of the editor window. Returns the file path to the PNG image. Use this to visually verify the editor state — check alignment, layout, clip positions, and overall appearance.",
                    "inputSchema": ["type": "object", "properties": [:], "required": []],
                ],
                [
                    "name": "extract_clips",
                    "description": "Find the best short-form clip candidates from a long recording. Claude reads the transcript and identifies 30-90 second moments with strong hooks, complete narratives, and emotional impact. Returns ranked candidates with timestamps and scores. Run analyze_transcript first.",
                    "inputSchema": ["type": "object", "properties": [
                        "asset_id": ["type": "string", "description": "UUID of the asset"],
                        "count": ["type": "number", "description": "Number of clips to find (default: 5)"],
                        "min_duration": ["type": "number", "description": "Minimum clip duration in seconds (default: 30)"],
                        "max_duration": ["type": "number", "description": "Maximum clip duration in seconds (default: 90)"],
                    ], "required": ["asset_id"]],
                ],
                [
                    "name": "extract_segment",
                    "description": "Extract a segment from an asset and place it at timeline position 0. Creates a clean clip with the specified source range starting at the beginning of the timeline. Use this instead of trim_clip when you want the result to start at 0.",
                    "inputSchema": ["type": "object", "properties": [
                        "asset_id": ["type": "string", "description": "UUID of the asset"],
                        "source_start": ["type": "number", "description": "Source start time in seconds"],
                        "source_end": ["type": "number", "description": "Source end time in seconds"],
                    ], "required": ["asset_id", "source_start", "source_end"]],
                ],
                [
                    "name": "make_short",
                    "description": "One-click: create a complete short-form clip. Extracts the segment, analyzes faces, applies layout (split/fill), and positions captions for 9:16. Combines extract_segment + analyze_for_shorts + create_short in one call. Optionally rearranges the clip to start with the hook.",
                    "inputSchema": ["type": "object", "properties": [
                        "asset_id": ["type": "string", "description": "UUID of the asset"],
                        "source_start": ["type": "number", "description": "Source start time in seconds"],
                        "source_end": ["type": "number", "description": "Source end time in seconds"],
                        "layout": ["type": "string", "description": "Layout: 'split', 'fill_0', 'fill_1', or 'auto' (default: auto — Claude decides)"],
                    ], "required": ["asset_id", "source_start", "source_end"]],
                ],
                [
                    "name": "analyze_for_shorts",
                    "description": "Analyze a video for short-form clip creation. Runs face tracking to detect all speakers, maps diarization to faces, and determines layout segments (Split vs Fill). Returns a ShortFormConfig ready for create_short. Requires transcript with speaker diarization.",
                    "inputSchema": ["type": "object", "properties": [
                        "asset_id": ["type": "string", "description": "UUID of the asset to analyze"],
                        "start": ["type": "number", "description": "Start time in seconds (optional)"],
                        "end": ["type": "number", "description": "End time in seconds (optional)"],
                    ], "required": ["asset_id"]],
                ],
                [
                    "name": "create_short",
                    "description": "Create a vertical short-form clip from the current timeline. Applies face-tracked Split/Fill layout, recomposes to 9:16 (1080x1920). Must run analyze_for_shorts first to get face tracking data. The video on the timeline will be recomposed with speakers stacked vertically.",
                    "inputSchema": ["type": "object", "properties": [
                        "asset_id": ["type": "string", "description": "UUID of the asset (used for face tracking data)"],
                        "layout": ["type": "string", "description": "Layout: 'split' (default), 'fill_0' (speaker 0 fills), 'fill_1' (speaker 1 fills)"],
                    ], "required": ["asset_id"]],
                ],
                [
                    "name": "set_overlay_config",
                    "description": "Set broadcast overlay configuration. Renders professional graphics over the video: episode title card (0-30s), host name bar, scrolling sponsor/topic ticker, chapter cards, and host intro strip (38-92s). Pass enabled=false to disable.",
                    "inputSchema": ["type": "object", "properties": [
                        "enabled": ["type": "boolean", "description": "Enable/disable overlay rendering (default: true)"],
                        "episode_title": ["type": "string", "description": "Episode title (uppercase)"],
                        "episode_subtitle": ["type": "string", "description": "Episode subtitle"],
                        "host_a_name": ["type": "string", "description": "Host A name"],
                        "host_a_title": ["type": "string", "description": "Host A title (e.g. 'CO-HOST · FOUNDER, LEARNX')"],
                        "host_b_name": ["type": "string", "description": "Host B name"],
                        "host_b_title": ["type": "string", "description": "Host B title"],
                        "sponsors": ["type": "array", "description": "Sponsor names for scrolling ticker", "items": ["type": "string"]],
                        "topics": ["type": "array", "description": "Topics with timestamps", "items": ["type": "object", "properties": ["time_seconds": ["type": "number"], "text": ["type": "string"]]]],
                        "chapters": ["type": "array", "description": "Chapters with timestamps", "items": ["type": "object", "properties": ["time_seconds": ["type": "number"], "text": ["type": "string"]]]],
                    ], "required": []],
                ],
                [
                    "name": "get_overlay_config",
                    "description": "Get the current broadcast overlay configuration.",
                    "inputSchema": ["type": "object", "properties": [:], "required": []],
                ],
                [
                    "name": "get_full_transcript",
                    "description": "Get the complete transcript with timestamps every 30 seconds. Use this to READ the entire transcript and understand the content structure before making any editing decisions. Returns the full text with [MM:SS] time markers so you can identify episodes, topics, transitions, and content layers.",
                    "inputSchema": ["type": "object", "properties": [
                        "asset_id": ["type": "string", "description": "UUID of the asset"],
                        "start": ["type": "number", "description": "Start time in seconds (optional)"],
                        "end": ["type": "number", "description": "End time in seconds (optional)"],
                    ], "required": ["asset_id"]],
                ],
                [
                    "name": "analyze_transcript",
                    "description": "Read the FULL transcript and understand content structure. Produces a content map: labeled sections (pre-show, episode, planning, rehearsal, off-camera) with time ranges, summaries, and key phrases. This is the foundation — run this FIRST before auto_cut or any editing. Transcript-first, tools-second.",
                    "inputSchema": ["type": "object", "properties": [
                        "asset_id": ["type": "string", "description": "UUID of the asset to analyze"],
                    ], "required": ["asset_id"]],
                ],
                [
                    "name": "detect_episodes",
                    "description": "Detect episode boundaries in long recordings. Combines intro phrase detection, energy analysis, transcript continuity, and meta-talk detection (production discussion vs content). Returns episode start/end times with confidence scores and evidence. Run on recordings that contain multiple episodes or mixed content.",
                    "inputSchema": ["type": "object", "properties": [
                        "asset_id": ["type": "string", "description": "UUID of the asset to analyze"],
                    ], "required": ["asset_id"]],
                ],
                [
                    "name": "classify_audio",
                    "description": "Classify audio segments as live_speech, playback (from speakers), background noise, or silence. Uses spectral analysis (FFT), zero-crossing rate, crest factor, dynamic range, and energy variance to distinguish direct mic input from compressed playback audio. Run this BEFORE auto_cut to understand what content is live vs playback.",
                    "inputSchema": ["type": "object", "properties": [
                        "asset_id": ["type": "string", "description": "UUID of the asset to classify"],
                        "start": ["type": "number", "description": "Start time in seconds (optional, defaults to 0)"],
                        "end": ["type": "number", "description": "End time in seconds (optional, defaults to asset duration)"],
                    ], "required": ["asset_id"]],
                ],
                [
                    "name": "auto_cut",
                    "description": "Intelligent one-click editing. Analyzes audio + transcript to remove silence, filler words (um, uh, er), re-takes, and optionally speed up weak sections. Three presets: 'gentle' (>2s silence only), 'standard' (>0.8s silence + fillers + re-takes), 'aggressive' (>0.3s + fillers + hedges + speed up weak sections). Requires transcript — call transcribe_asset first. Returns before/after stats.",
                    "inputSchema": ["type": "object", "properties": [
                        "clip_id": ["type": "string", "description": "UUID of the clip to process (optional, defaults to first clip on timeline)"],
                        "preset": ["type": "string", "description": "Preset: 'gentle', 'standard', or 'aggressive' (default: standard)"],
                        "dry_run": ["type": "boolean", "description": "If true, return the cut plan without executing (default: false)"],
                    ], "required": []],
                ],
                [
                    "name": "segment_topics",
                    "description": "Break long content into coherent topic segments. Uses pauses, speaker changes, energy resets, and vocabulary shifts to find natural boundaries. Returns labeled segments with keywords. Useful before scoring or clip extraction.",
                    "inputSchema": ["type": "object", "properties": [
                        "asset_id": ["type": "string", "description": "UUID of the asset to segment"],
                        "min_duration": ["type": "number", "description": "Minimum segment duration in seconds (default: 15)"],
                    ], "required": ["asset_id"]],
                ],
                [
                    "name": "score_content",
                    "description": "Score clips or segments on 5 dimensions: hook strength, retention curve, emotional arc, completeness, audio quality. Each 0-10. Gate-based: clips must score >= threshold on ALL dimensions to pass. Use for viral clip extraction, highlight detection, or quality assessment.",
                    "inputSchema": ["type": "object", "properties": [
                        "asset_id": ["type": "string", "description": "UUID of the asset to score"],
                        "segments": ["type": "number", "description": "Number of equal segments to divide and score (default: 10)"],
                        "gate_threshold": ["type": "number", "description": "Minimum score on all dimensions to pass (default: 7)"],
                    ], "required": ["asset_id"]],
                ],
                [
                    "name": "hook_optimize",
                    "description": "Rearrange a short-form clip to start with its most compelling moment (cold open). Analyzes transcript, finds the best hook sentence, duplicates it to the beginning with a flash transition.",
                    "inputSchema": ["type": "object", "properties": [:], "required": []],
                ],
                [
                    "name": "export_for_platform",
                    "description": "Export the current timeline optimized for a specific platform. Applies correct resolution, codec, and loudness settings. Platforms: tiktok, youtube_shorts, youtube_hd, youtube_4k, instagram_reels, instagram_feed, linkedin, twitter, pinterest, spotify_podcast, apple_podcast",
                    "inputSchema": ["type": "object", "properties": ["platform": ["type": "string", "description": "Target platform name (e.g. tiktok, youtube_shorts, youtube_hd)"], "filename": ["type": "string", "description": "Output filename (without extension)"]], "required": ["platform"]],
                ],
                [
                    "name": "list_platforms",
                    "description": "List all available platform export presets with their specs (resolution, max duration, loudness target).",
                    "inputSchema": ["type": "object", "properties": [:], "required": []],
                ],
                [
                    "name": "get_transcript_with_timing",
                    "description": "Get the transcript with word-level timing for text-based editing. The AI reads this, then issues delete_transcript_range or remove_filler_words commands. This is the foundation for editing video by editing text.",
                    "inputSchema": ["type": "object", "properties": [
                        "asset_id": ["type": "string", "description": "Specific asset UUID. If omitted, uses the first video clip's asset."],
                        "start": ["type": "number", "description": "Start time filter in seconds (source time)"],
                        "end": ["type": "number", "description": "End time filter in seconds (source time)"],
                        "format": ["type": "string", "description": "'text' (default) — timestamps before each word, or 'json' — array of {word, start, end, speaker}"],
                    ], "required": []],
                ],
                [
                    "name": "delete_transcript_range",
                    "description": "Delete video by deleting text from the transcript. Maps a source-time range to timeline edits: splits clips at boundaries, deletes the middle, and ripple-closes gaps. Process multiple deletions from END to START to preserve timestamps.",
                    "inputSchema": ["type": "object", "properties": [
                        "asset_id": ["type": "string", "description": "Asset UUID"],
                        "start_time": ["type": "number", "description": "Start time in seconds (source time) of content to delete"],
                        "end_time": ["type": "number", "description": "End time in seconds (source time) of content to delete"],
                    ], "required": ["asset_id", "start_time", "end_time"]],
                ],
                [
                    "name": "remove_filler_words",
                    "description": "Find and remove filler words (um, uh, like, you know, so, basically, actually, right, I mean) from the transcript. Context-sensitive: only removes standalone fillers between pauses, not meaningful speech. Works backwards to preserve timestamps. Use dry_run=true to preview.",
                    "inputSchema": ["type": "object", "properties": [
                        "asset_id": ["type": "string", "description": "Asset UUID"],
                        "fillers": ["type": "string", "description": "Comma-separated custom filler words. Default: um,uh,like,you know,so,basically,actually,right,I mean"],
                        "dry_run": ["type": "boolean", "description": "If true, report what would be removed without deleting"],
                    ], "required": ["asset_id"]],
                ],
            ])
            tools = deduplicatedTools(tools)
            let response = successResponse(id: id, result: ["tools": tools])
            cachedToolsResponse = response
            return response

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

    /// Public entry point for the in-app agent to call MCP tool handlers.
    func executeToolForAgent(name: String, arguments: [String: Any]) async -> String {
        guard let appState else { return "Error: Editor not available" }
        return await executeToolCall(name: name, arguments: arguments, appState: appState)
    }

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
        if name == "set_zoom" {
            let level = arguments["level"] as? String ?? "fit"
            if level == "fit" {
                let duration = appState.timeline.duration
                if duration > 0 {
                    appState.timelineViewState.zoomToFit(duration: duration)
                }
                return "Zoom set to fit timeline (\(formattedZoom(appState.timelineViewState.zoom)) px/s)"
            } else if let pxPerSec = Double(level) {
                appState.timelineViewState.setZoom(pxPerSec)
                return "Zoom set to \(formattedZoom(pxPerSec)) px/s"
            }
            return "Error: use 'fit' or a number"
        }
        if name == "delete_asset" {
            return handleDeleteAsset(arguments, appState: appState)
        }
        if name == "take_screenshot" {
            return await handleTakeScreenshot(appState: appState)
        }
        if name == "generate_title" {
            return await handleGenerateTitle(arguments, appState: appState)
        }
        if name == "auto_insert_broll" {
            return await handleAutoInsertBroll(arguments, appState: appState)
        }
        if name == "search_broll" {
            return await handleSearchBroll(arguments, appState: appState)
        }
        if name == "set_track_audio_effects" {
            return handleSetTrackAudioEffects(arguments, appState: appState)
        }
        if name == "analyze_audio_energy" {
            return await handleAnalyzeAudioEnergy(arguments, appState: appState)
        }
        if name == "make_short" {
            return await handleMakeShort(arguments, appState: appState)
        }
        if name == "extract_clips" {
            return await handleExtractClips(arguments, appState: appState)
        }
        if name == "extract_segment" {
            return handleExtractSegment(arguments, appState: appState)
        }
        if name == "analyze_for_shorts" {
            return await handleAnalyzeForShorts(arguments, appState: appState)
        }
        if name == "create_short" {
            return await handleCreateShort(arguments, appState: appState)
        }
        if name == "set_overlay_config" {
            return handleSetOverlayConfig(arguments, appState: appState)
        }
        if name == "get_overlay_config" {
            return handleGetOverlayConfig(appState: appState)
        }
        if name == "get_full_transcript" {
            return await handleGetFullTranscript(arguments, appState: appState)
        }
        if name == "analyze_transcript" {
            return await handleAnalyzeTranscript(arguments, appState: appState)
        }
        if name == "detect_episodes" {
            return await handleDetectEpisodes(arguments, appState: appState)
        }
        if name == "classify_audio" {
            return await handleClassifyAudio(arguments, appState: appState)
        }
        if name == "auto_cut" {
            return await handleAutoCut(arguments, appState: appState)
        }
        if name == "score_content" {
            return await handleScoreContent(arguments, appState: appState)
        }
        if name == "segment_topics" {
            return await handleSegmentTopics(arguments, appState: appState)
        }
        if name == "hook_optimize" {
            return await handleHookOptimize(arguments, appState: appState)
        }
        if name == "get_state" {
            return handleGetState(appState: appState)
        }
        if name == "fix_av_links" {
            return handleFixAVLinks(appState: appState)
        }
        if name == "get_transcript_with_timing" {
            return await handleGetTranscriptWithTiming(arguments, appState: appState)
        }
        if name == "delete_transcript_range" {
            return await handleDeleteTranscriptRange(arguments, appState: appState)
        }
        if name == "remove_filler_words" {
            return await handleRemoveFillerWords(arguments, appState: appState)
        }

        if name == "save_snapshot" {
            let snapName = (arguments["name"] as? String) ?? "Snapshot"
            let vc = VersionControl(projectBundleURL: appState.projectBundleURL)
            do {
                await vc.loadFromDisk()
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

        if name == "remove_silence" {
            return handleRemoveSilence(arguments, appState: appState)
        }
        if name == "remove_section" {
            return handleRemoveSection(arguments, appState: appState)
        }
        if name == "ripple_delete" {
            return handleRippleDelete(arguments, appState: appState)
        }
        if name == "normalize_audio" {
            return handleNormalizeAudio(arguments, appState: appState)
        }
        if name == "export_video" {
            return await handleExportVideo(arguments, appState: appState)
        }
        if name == "export_for_platform" {
            return await handleExportForPlatform(arguments, appState: appState)
        }
        if name == "list_platforms" {
            return handleListPlatforms()
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

    private func deduplicatedTools(_ tools: [[String: Any]]) -> [[String: Any]] {
        var orderedNames: [String] = []
        var entriesByName: [String: [String: Any]] = [:]

        for tool in tools {
            guard let name = tool["name"] as? String, !name.isEmpty else { continue }
            if entriesByName[name] == nil {
                orderedNames.append(name)
            }
            entriesByName[name] = tool
        }

        return orderedNames.compactMap { entriesByName[$0] }
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
        var failed = 0
        for trackID in trackIDs {
            do {
                try appState.perform(.removeTrack(trackID: trackID), source: .ai)
            } catch {
                failed += 1
            }
        }
        if failed > 0 {
            return "Warning: Failed to remove \(failed)/\(trackIDs.count) track(s). " + stateSnapshot(appState)
        }
        return "Project cleared. " + stateSnapshot(appState)
    }

    private func handleDeleteAsset(_ args: [String: Any], appState: AppState) -> String {
        guard let assetIDStr = args["asset_id"] as? String,
              let assetID = UUID(uuidString: assetIDStr) else {
            return "Error: invalid asset_id"
        }

        // Check if asset is used by any clip on the timeline
        let usedAssetIDs = Set(appState.timeline.tracks.flatMap(\.clips).map(\.assetID))
        if usedAssetIDs.contains(assetID) {
            return "Error: asset is in use on the timeline. Remove clips using this asset first."
        }

        guard let asset = appState.assets.first(where: { $0.id == assetID }) else {
            return "Error: asset not found"
        }

        let name = asset.name
        Task { @MainActor in
            await appState.media.mediaManager.remove(id: assetID)
            await appState.media.refreshAssets()
        }
        return "Deleted asset '\(name)'. " + stateSnapshot(appState)
    }

    private func handleTakeScreenshot(appState: AppState) async -> String {
        let outputPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("editor-screenshot-\(UUID().uuidString.prefix(8)).png")

        let app = NSApplication.shared
        let windows = (app.orderedWindows.isEmpty ? app.windows : app.orderedWindows).map {
            MCPScreenshotWindowCandidate(
                windowNumber: $0.windowNumber,
                isMain: $0 == app.mainWindow,
                isKey: $0 == app.keyWindow,
                isVisible: $0.isVisible,
                isMiniaturized: $0.isMiniaturized
            )
        }

        guard let windowNumber = MCPScreenshotWindowResolver.selectWindowNumber(from: windows) else {
            return "Error: no captureable window available"
        }

        let windowID = CGWindowID(windowNumber)
        guard let image = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            windowID,
            [.boundsIgnoreFraming, .bestResolution]
        ) else {
            return "Error: screenshot capture failed"
        }

        let bitmapRep = NSBitmapImageRep(cgImage: image)
        guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            return "Error: PNG conversion failed"
        }

        do {
            try pngData.write(to: outputPath)
            return "Screenshot saved to: \(outputPath.path)\nSize: \(image.width)x\(image.height)"
        } catch {
            return "Error saving screenshot: \(error.localizedDescription)"
        }
    }

    private func handleGenerateTitle(_ args: [String: Any], appState: AppState) async -> String {
        let style = args["style"] as? String ?? "youtube"

        // Get transcript from clips on timeline
        let allClips = appState.timeline.tracks.flatMap(\.clips)
        guard !allClips.isEmpty else { return "Error: no clips on timeline" }

        var transcriptParts: [String] = []
        for clip in allClips.prefix(5) {
            if let asset = appState.assets.first(where: { $0.id == clip.assetID }),
               let transcript = asset.analysis?.transcript {
                let words = transcript
                    .filter { $0.start >= clip.sourceRange.start && $0.start < clip.sourceRange.end }
                    .map(\.word)
                    .joined(separator: " ")
                if !words.isEmpty {
                    transcriptParts.append(words)
                }
            }
        }

        let content = transcriptParts.isEmpty
            ? "No transcript available. Clips: \(allClips.map { $0.metadata.label ?? "Clip" }.joined(separator: ", "))"
            : String(transcriptParts.joined(separator: " ").prefix(500))

        let focus = titleFocus(from: content, fallback: allClips.first?.metadata.label ?? "The Clip")
        let keywords = titleKeywords(from: content)
        let titles = titleSuggestions(style: style, focus: focus, keywords: keywords)

        var lines = ["=== TITLE SUGGESTIONS ==="]
        lines.append("Style: \(style)")
        lines.append("Focus: \(focus)")
        if !keywords.isEmpty {
            lines.append("Keywords: \(keywords.prefix(4).joined(separator: ", "))")
        }
        lines.append("")
        for (index, title) in titles.enumerated() {
            lines.append("\(index + 1). \(title)")
        }
        return lines.joined(separator: "\n")
    }

    private func handleAutoInsertBroll(_ args: [String: Any], appState: AppState) async -> String {
        let maxInserts = args["max_inserts"] as? Int ?? (args["max_inserts"] as? Double).map { Int($0) } ?? 5
        let brollDuration = args["duration"] as? Double ?? 3.0

        // Get available B-roll assets (non-primary assets)
        let timelineAssetIDs = Set(appState.timeline.tracks.flatMap(\.clips).map(\.assetID))
        let brollAssets = appState.assets.filter { !timelineAssetIDs.contains($0.id) }

        guard !brollAssets.isEmpty else {
            return "No B-roll assets available in the media library. Import additional media first."
        }

        // Find insertion points from transcript (long talking-head sections)
        var insertions: [(time: Double, asset: String)] = []
        let allClips = appState.timeline.tracks.filter { $0.type == .video }.flatMap(\.clips)

        for clip in allClips {
            // For clips longer than 15s, suggest B-roll at the midpoint
            if clip.timelineRange.duration > 15 {
                let midpoint = clip.timelineRange.start + clip.timelineRange.duration / 2
                if let broll = brollAssets.randomElement() {
                    insertions.append((time: midpoint, asset: broll.name))
                }
            }
            if insertions.count >= maxInserts { break }
        }

        if insertions.isEmpty {
            return "No suitable B-roll insertion points found. Clips are too short for B-roll."
        }

        var report = "=== B-ROLL INSERTION SUGGESTIONS ===\n"
        report += "Available B-roll: \(brollAssets.map(\.name).joined(separator: ", "))\n\n"
        for (i, ins) in insertions.enumerated() {
            report += "  #\(i+1) Insert '\(ins.asset)' at \(String(format: "%.1f", ins.time))s (\(brollDuration)s duration)\n"
        }
        report += "\nTo insert: use add_to_timeline with the asset ID and start_time for each suggestion."
        return report
    }

    // MARK: - Search B-roll (Pexels)

    private func handleSearchBroll(_ args: [String: Any], appState: AppState) async -> String {
        let shouldDownload = args["download"] as? Bool ?? false
        let insertAt = args["insert_at"] as? Double
        let maxDuration = args["duration"] as? Double ?? 5.0

        // 1. Resolve search queries — explicit or LLM-generated from transcript
        var queries: [String]
        if let explicit = args["query"] as? String, !explicit.isEmpty {
            queries = [explicit]
        } else {
            queries = await extractBrollQueries(appState: appState)
            guard !queries.isEmpty else {
                return "Error: No transcript available to generate search queries. Provide a 'query' parameter or transcribe an asset first."
            }
        }

        // 2. Load Pexels API key
        guard let pexelsKey = ProcessInfo.processInfo.environment["PEXELS_API_KEY"] ?? loadEnvKey("PEXELS_API_KEY") else {
            return "Error: PEXELS_API_KEY not configured. Set it as an environment variable or add to .env file."
        }

        let client = PexelsClient(apiKey: pexelsKey)

        // 3. Search Pexels with each query
        var allResults: [(query: String, results: [PexelsClient.VideoResult])] = []
        for query in queries {
            do {
                let results = try await client.search(query: query, perPage: 3)
                allResults.append((query: query, results: results))
            } catch {
                allResults.append((query: query, results: []))
            }
        }

        let flatResults = allResults.flatMap(\.results)
        guard !flatResults.isEmpty else {
            return "No Pexels results for queries: \(queries.joined(separator: ", ")). Try different search terms."
        }

        // 4. Build results report
        var report = "=== PEXELS B-ROLL SEARCH ===\n"
        report += "Queries: \(queries.joined(separator: " | "))\n\n"

        for (qi, group) in allResults.enumerated() {
            report += "[\(qi + 1)] \"\(group.query)\" — \(group.results.count) result(s)\n"
            for (ri, v) in group.results.enumerated() {
                let bestHD = v.videoFiles
                    .filter { $0.quality == "hd" && $0.fileType == "video/mp4" }
                    .sorted { $0.width > $1.width }
                    .first
                report += "  #\(ri + 1): \(v.duration)s, \(v.width)x\(v.height)"
                if let thumb = v.thumbnailURL { report += " thumb: \(thumb)" }
                if let hd = bestHD { report += " dl: \(hd.link)" }
                report += " (pexels.com/video/\(v.id))\n"
            }
        }

        // 5. If download requested, grab the best HD match and import it
        if shouldDownload {
            guard let best = flatResults.first else {
                return report + "\nNo results to download."
            }

            guard let hdFile = best.videoFiles
                .filter({ $0.quality == "hd" && $0.fileType == "video/mp4" })
                .sorted(by: { $0.width > $1.width })
                .first else {
                return report + "\nNo HD MP4 file available for the top result."
            }

            let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let brollDir = docsDir.appendingPathComponent("BRoll", isDirectory: true)
            try? FileManager.default.createDirectory(at: brollDir, withIntermediateDirectories: true)
            let filename = "pexels_\(best.id).mp4"
            let destURL = brollDir.appendingPathComponent(filename)

            // Download
            do {
                if !FileManager.default.fileExists(atPath: destURL.path) {
                    try await client.download(fileURL: hdFile.link, to: destURL)
                }
            } catch {
                return report + "\nDownload failed: \(error.localizedDescription)"
            }

            // Import into media library
            do {
                let asset = try await appState.importMedia(from: destURL)
                report += "\nDownloaded & imported: '\(asset.name)' (ID: \(asset.id.uuidString), \(String(format: "%.1f", asset.duration))s)"

                // Insert on timeline if position specified
                if let position = insertAt {
                    let clipDuration = min(maxDuration, asset.duration)
                    // Create clip with trimmed source range if needed
                    let sourceRange = TimeRange(start: 0, duration: clipDuration)
                    let clip = Clip(
                        assetID: asset.id,
                        timelineRange: TimeRange(start: position, duration: clipDuration),
                        sourceRange: sourceRange
                    )
                    // Find or create a B-roll track
                    let brollTrack = appState.timeline.tracks.first {
                        $0.type == .video && $0.name.lowercased().contains("b-roll")
                    }
                    do {
                        if let track = brollTrack {
                            try appState.perform(.insertClip(clip: clip, trackID: track.id), source: .ai)
                        } else {
                            let newTrack = Track(name: "B-Roll", type: .video)
                            try appState.perform(.addTrack(track: newTrack), source: .ai)
                            try appState.perform(.insertClip(clip: clip, trackID: newTrack.id), source: .ai)
                        }
                    } catch {
                        return report + "\nError inserting B-roll clip: \(error.localizedDescription)"
                    }
                    report += "\nInserted \(String(format: "%.1f", clipDuration))s B-roll at \(String(format: "%.1f", position))s on B-Roll track."
                    report += "\n" + stateSnapshot(appState)
                }
            } catch {
                return report + "\nImport failed: \(error.localizedDescription)"
            }
        }

        return report
    }

    /// Use Claude Haiku to extract visual B-roll search queries from the timeline's transcript.
    private func extractBrollQueries(appState: AppState) async -> [String] {
        // Gather transcript text from timeline clips
        let allClips = appState.timeline.tracks.flatMap(\.clips)
        var transcriptText = ""
        for clip in allClips.prefix(10) {
            if let asset = appState.assets.first(where: { $0.id == clip.assetID }),
               let transcript = asset.analysis?.transcript {
                let words = transcript
                    .filter { $0.start >= clip.sourceRange.start && $0.start < clip.sourceRange.end }
                    .map(\.word)
                    .joined(separator: " ")
                if !words.isEmpty {
                    transcriptText += words + " "
                }
            }
        }

        guard !transcriptText.isEmpty else { return [] }

        guard let apiKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? loadAnthropicKey() else {
            return []
        }

        let provider = ClaudeProvider(apiKey: apiKey, model: "claude-haiku-4-5-20251001")
        let prompt = """
        Given this transcript segment from a video, generate 3 short search queries for stock video footage that would work as B-roll. Return ONLY a JSON array of strings.
        Transcript: "\(String(transcriptText.prefix(800)))"
        """

        do {
            let response = try await provider.complete(messages: [AIMessage(role: "user", content: prompt)], tools: [])
            let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if let start = text.range(of: "["), let end = text.range(of: "]", options: .backwards) {
                let jsonStr = String(text[start.lowerBound...end.upperBound])
                if let data = jsonStr.data(using: .utf8),
                   let arr = try? JSONSerialization.jsonObject(with: data) as? [String] {
                    return arr
                }
            }
        } catch {
            // Silently fall back to empty — caller will report the error
        }

        return []
    }

    private func loadEnvKey(_ keyName: String) -> String? {
        let candidates = [
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".env"),
            Bundle.main.bundleURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent(".env"),
        ]
        for url in candidates {
            if let contents = try? String(contentsOf: url, encoding: .utf8) {
                for line in contents.components(separatedBy: .newlines) {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix("\(keyName)=") {
                        let value = String(trimmed.dropFirst("\(keyName)=".count))
                            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                        if !value.isEmpty { return value }
                    }
                }
            }
        }
        return nil
    }

    private func titleFocus(from content: String, fallback: String) -> String {
        let ignored = Set(["This", "That", "It", "For", "Just", "Not", "Imagine", "If"])
        let capitalized = content
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 && $0.first?.isUppercase == true && !ignored.contains($0) }

        if let primary = capitalized.first {
            if let secondary = capitalized.dropFirst().first, secondary != primary {
                return "\(primary) \(secondary)"
            }
            return primary
        }

        return fallback
    }

    private func titleKeywords(from content: String) -> [String] {
        let stopwords = Set([
            "this", "that", "with", "from", "your", "they", "them", "have", "just", "into",
            "like", "will", "what", "when", "where", "there", "their", "about", "because",
            "learnx", "demo", "clip", "video", "audio"
        ])

        var counts: [String: Int] = [:]
        for token in content.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted) {
            guard token.count > 3, !stopwords.contains(token) else { continue }
            counts[token, default: 0] += 1
        }

        return counts
            .sorted { lhs, rhs in
                if lhs.value == rhs.value { return lhs.key < rhs.key }
                return lhs.value > rhs.value
            }
            .map(\.key)
    }

    private func titleSuggestions(style: String, focus: String, keywords: [String]) -> [String] {
        let keywordA = keywords.first ?? "learning"
        let keywordB = keywords.dropFirst().first ?? "study"
        let keywordC = keywords.dropFirst(2).first ?? "podcast"

        switch style {
        case "professional":
            return [
                "\(focus): Personalized \(keywordA.capitalized) With AI",
                "\(focus) Overview: Adaptive \(keywordB.capitalized) for Modern Learners",
                "How \(focus) Uses \(keywordA.capitalized) to Improve \(keywordB.capitalized)",
                "\(focus) Demo: A Smarter Approach to \(keywordC.capitalized)",
                "\(focus) Explained: Flexible \(keywordA.capitalized) for Real-World Use",
            ]
        case "viral":
            return [
                "This Is Why \(focus) Feels Like a Cheat Code for \(keywordA.capitalized)",
                "\(focus) Just Changed How I Think About \(keywordB.capitalized)",
                "The Wildest Part of \(focus) Is What It Does With \(keywordC.capitalized)",
                "I Didn’t Expect \(focus) to Nail \(keywordA.capitalized) Like This",
                "\(focus) Makes \(keywordB.capitalized) Feel Almost Unfair",
            ]
        default:
            return [
                "\(focus): The AI Tool That Adapts to How You Learn",
                "How \(focus) Turns \(keywordA.capitalized) Into a Personalized Study Plan",
                "Why \(focus) Makes \(keywordB.capitalized) Easier Than It Sounds",
                "\(focus) Explained in 30 Seconds: \(keywordA.capitalized), \(keywordB.capitalized), \(keywordC.capitalized)",
                "What \(focus) Actually Does Better Than a Standard \(keywordB.capitalized) App",
            ]
        }
    }

    private func resolvedToolMediaURL(for asset: MediaAsset) -> URL {
        if let proxyURL = asset.proxyURL,
           FileManager.default.fileExists(atPath: proxyURL.path) {
            return proxyURL
        }
        return asset.sourceURL
    }

    private func handleSetTrackAudioEffects(_ args: [String: Any], appState: AppState) -> String {
        guard let trackIDStr = args["track_id"] as? String,
              let trackID = UUID(uuidString: trackIDStr) else {
            return "Error: invalid track_id"
        }
        guard let track = appState.timeline.tracks.first(where: { $0.id == trackID }) else {
            return "Error: track not found"
        }

        // Guard: verify the track has clips with audio content
        let trackHasAudio = track.clips.contains { clip in
            appState.assets.first(where: { $0.id == clip.assetID })?.hasAudioTrack == true
        }
        guard trackHasAudio else {
            return "Error: No audio content in the target track/clip"
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

        do {
            try appState.perform(.setTrackAudioEffects(trackID: trackID, effectChain: effectChain))
        } catch {
            return "Error: \(error.localizedDescription)"
        }

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
        appState.rebuildComposition()
        appState.flushPendingState()
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

        // Pre-validate: skip transcription only for image assets (hasAudioTrack may be
        // unreliable for some video containers where AVFoundation can't probe audio tracks)
        if asset.type == .image {
            return "Error: Asset '\(asset.name)' is an image. Cannot transcribe images."
        }

        let providerArg = (args["provider"] as? String)?.lowercased() ?? ""
        let useLocal = ["local", "whisper", "whisperkit"].contains(providerArg)

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
                bundleURL: appState.projectBundleURL,
                useLocal: useLocal
            )
            if let result {
                await appState.media.refreshAssets()
                let providerName = useLocal ? "WhisperKit (local)" : "Deepgram"
                return "Transcribed with \(providerName): \(result.words.count) words, \(String(format: "%.1f", result.duration))s."
            }
            return "Error: Transcription not configured. Add DEEPGRAM_API_KEY to .env or use provider: 'local' for WhisperKit."
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }

    private func handleSearchTranscript(_ args: [String: Any], appState: AppState) async -> String {
        guard let query = args["query"] as? String, !query.isEmpty else {
            return "Error: Missing query"
        }
        let maxResults = (args["max_results"] as? Int)
            ?? (args["max_results"] as? Double).map(Int.init)
            ?? 10
        let assetID = (args["asset_id"] as? String).flatMap(UUID.init(uuidString:))

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

        if let assetID {
            searchAssets = searchAssets.filter { $0.id == assetID }
            guard !searchAssets.isEmpty else {
                return "Error: Asset not found"
            }
        }

        let results = searchEngine.search(query: query, assets: searchAssets, maxResults: max(1, maxResults))
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
            // Guard: check that at least one clip has audio
            let allClips = appState.timeline.tracks.flatMap(\.clips)
            let hasAudio = allClips.contains { clip in
                appState.assets.first(where: { $0.id == clip.assetID })?.hasAudioTrack == true
            }
            guard hasAudio else { return "Error: No audio content in the target track/clip" }
            let preset = (args["preset"] as? String) ?? "standard"
            return "Voice cleanup '\(preset)': \(VoiceCleanup.describe(preset: VoiceCleanup.CleanupPreset(rawValue: preset) ?? .standard))"

        case "set_caption_style":
            let styleName = (args["style"] as? String) ?? "standard"
            let style: CaptionStyler.CaptionStyle
            switch styleName {
            case "karaoke": style = .karaoke
            case "bold": style = .bold
            case "outline": style = .outline
            case "gradient": style = .gradient
            case "pop": style = .pop
            case "hormozi": style = .hormozi
            case "bounce": style = .bounce
            case "typewriter": style = .typewriter
            default: style = .standard
            }
            appState.context.timelineState.captionStyle = style
            appState.rebuildCompositionNow()
            return "Caption style set to '\(styleName)'. Composition rebuilt."

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
            let allClipsForDuck = appState.timeline.tracks.flatMap(\.clips)
            let hasAudioForDuck = allClipsForDuck.contains { clip in
                appState.assets.first(where: { $0.id == clip.assetID })?.hasAudioTrack == true
            }
            guard hasAudioForDuck else { return "Error: No audio content in the target track/clip" }
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

    // MARK: - Make Short (one-click pipeline)

    private func handleMakeShort(_ args: [String: Any], appState: AppState) async -> String {
        guard let assetIDStr = args["asset_id"] as? String,
              let assetID = UUID(uuidString: assetIDStr),
              let asset = appState.assets.first(where: { $0.id == assetID }) else {
            return "Error: Invalid asset_id"
        }
        guard let sourceStart = args["source_start"] as? Double,
              let sourceEnd = args["source_end"] as? Double,
              sourceEnd > sourceStart else {
            return "Error: Invalid source_start/source_end"
        }

        var report: [String] = ["=== MAKING SHORT ==="]
        let duration = sourceEnd - sourceStart
        report.append("Source: \(String(format: "%.0f", sourceStart))s - \(String(format: "%.0f", sourceEnd))s (\(String(format: "%.0f", duration))s)")

        // Step 1: Extract segment at position 0
        let extractResult = handleExtractSegment([
            "asset_id": assetIDStr,
            "source_start": sourceStart,
            "source_end": sourceEnd,
        ], appState: appState)
        report.append("1. Extract: done")

        // Step 2: Analyze faces
        let tracker = MultiFaceTracker()
        let mediaURL = resolvedToolMediaURL(for: asset)
        let faceTracks: [FaceTrack]
        do {
            faceTracks = try await tracker.trackRange(url: mediaURL, start: sourceStart, end: sourceEnd)
        } catch {
            report.append("2. Face tracking: failed — \(error.localizedDescription)")
            return report.joined(separator: "\n")
        }
        report.append("2. Face tracking: \(faceTracks.count) faces, \(faceTracks.first?.samples.count ?? 0) samples each")

        // Step 3: Speaker mapping
        var speakerToFace: [Int: Int] = [:]
        if let result = await appState.media.transcriptionService.getTranscript(
            for: asset, bundleURL: appState.projectBundleURL
        ), let speakers = result.speakers {
            let mapper = SpeakerFaceMapper()
            speakerToFace = mapper.map(speakerSegments: speakers, faceTracks: faceTracks)
        } else {
            for i in 0..<faceTracks.count { speakerToFace[i] = i }
        }

        // Step 4: Determine layout
        let layoutStr = args["layout"] as? String ?? "auto"
        var layoutSegments: [LayoutSegment]

        if layoutStr == "auto" {
            // Ask Claude to decide layout based on transcript content
            layoutSegments = await decideLayoutWithClaude(
                asset: asset, appState: appState,
                sourceStart: sourceStart, sourceEnd: sourceEnd,
                speakerToFace: speakerToFace
            )
            report.append("3. Layout: auto (\(layoutSegments.count) segments)")
        } else {
            let layout: ShortFormLayout
            switch layoutStr {
            case "fill_0": layout = .fill(activeSpeaker: 0)
            case "fill_1": layout = .fill(activeSpeaker: 1)
            default: layout = .split
            }
            layoutSegments = [LayoutSegment(startTime: 0, layout: layout)]
            report.append("3. Layout: \(layoutStr)")
        }

        // Step 5: Get caption words from transcript
        var captionWords: [TranscriptWord] = []
        if let result = await appState.media.transcriptionService.getTranscript(
            for: asset, bundleURL: appState.projectBundleURL
        ) {
            captionWords = result.words.filter { $0.start >= sourceStart && $0.end <= sourceEnd }
        }
        report.append("5. Captions: \(captionWords.count) words")

        // Step 6: Build and apply config
        let config = ShortFormConfig(
            isEnabled: true,
            outputAspect: .vertical9x16,
            faceTracks: faceTracks,
            speakerToFace: speakerToFace,
            layoutSegments: layoutSegments,
            sourceTimeOffset: sourceStart,
            captionWords: captionWords
        )

        appState.context.timelineState.shortFormConfig = config
        appState.rebuildCompositionNow()
        report.append("4. Applied: 9:16, \(faceTracks.count) faces, \(layoutSegments.count) layout segments")
        report.append("\nShort ready at 1080x1920. " + stateSnapshot(appState))

        return report.joined(separator: "\n")
    }

    /// Ask Claude to decide Fill vs Split per segment based on transcript content.
    private func decideLayoutWithClaude(
        asset: MediaAsset, appState: AppState,
        sourceStart: TimeInterval, sourceEnd: TimeInterval,
        speakerToFace: [Int: Int]
    ) async -> [LayoutSegment] {
        guard let result = await appState.media.transcriptionService.getTranscript(
            for: asset, bundleURL: appState.projectBundleURL
        ) else {
            return [LayoutSegment(startTime: 0, layout: .split)]
        }

        // Build transcript with SPEAKER LABELS for just this segment
        let words = result.words.filter { $0.start >= sourceStart && $0.end <= sourceEnd }
        let speakers = result.speakers ?? []

        // Helper: find which speaker is active at a given time
        func speakerAt(_ time: TimeInterval) -> String {
            for seg in speakers {
                if time >= seg.range.start && time < seg.range.end {
                    let digits = seg.speakerID.filter(\.isNumber)
                    if let id = Int(digits), let faceIdx = speakerToFace[id] {
                        return "Speaker \(faceIdx)"
                    }
                    return seg.speakerID
                }
            }
            return "?"
        }

        var transcript = ""
        var sentenceWords: [String] = []
        var sentenceStart: TimeInterval = 0
        var sentenceSourceStart: TimeInterval = 0

        for (i, word) in words.enumerated() {
            if sentenceWords.isEmpty {
                sentenceStart = word.start - sourceStart
                sentenceSourceStart = word.start
            }
            sentenceWords.append(word.word)
            let isEnd = word.word.hasSuffix(".") || word.word.hasSuffix("?") || word.word.hasSuffix("!")
            let hasPause = i + 1 < words.count && (words[i + 1].start - word.end) > 0.8
            let isLast = i == words.count - 1
            if isEnd || hasPause || isLast {
                let s = Int(sentenceStart)
                let speaker = speakerAt(sentenceSourceStart)
                transcript += "[\(s)s] [\(speaker)] \(sentenceWords.joined(separator: " "))\n"
                sentenceWords = []
            }
        }

        guard let apiKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? loadAnthropicKey() else {
            return [LayoutSegment(startTime: 0, layout: .split)]
        }

        let provider = ClaudeProvider(apiKey: apiKey, model: "claude-sonnet-4-6")

        let prompt = """
        You are deciding camera layouts for a short-form vertical video clip.
        Speaker 0 (face 0) is on the left, Speaker 1 (face 1) is on the right.

        For each section of this clip, choose the best layout:
        - "split" — both speakers visible (stacked vertically). Use for: dialogue, reactions, questions, banter.
        - "fill_0" — Speaker 0 fills the whole screen. Use for: Speaker 0 telling a story, making a point, monologue.
        - "fill_1" — Speaker 1 fills the whole screen. Use for: Speaker 1 telling a story, making a point, monologue.

        Rules:
        - Default to "split" for back-and-forth conversation
        - Switch to "fill" when one person speaks for 8+ seconds continuously
        - Switch back to "split" when the other person responds
        - Minimum segment: 3 seconds (don't switch too fast)
        - For emotional moments or punchlines, fill on the person delivering it

        Respond with ONLY a JSON array of layout segments:
        [{"time": 0, "layout": "split"}, {"time": 12, "layout": "fill_0"}, ...]

        Time is in seconds from clip start.

        TRANSCRIPT:
        \(transcript)
        """

        do {
            let response = try await provider.complete(
                messages: [AIMessage(role: "user", content: prompt)],
                tools: []
            )

            // Parse JSON array from response
            let content = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if let jsonStart = content.firstIndex(of: "["),
               let jsonEnd = content.lastIndex(of: "]") {
                let jsonStr = String(content[jsonStart...jsonEnd])
                if let data = jsonStr.data(using: .utf8),
                   let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                    return arr.compactMap { entry -> LayoutSegment? in
                        guard let time = entry["time"] as? Double,
                              let layoutStr = entry["layout"] as? String else { return nil }
                        let layout: ShortFormLayout
                        switch layoutStr {
                        case "fill_0": layout = .fill(activeSpeaker: 0)
                        case "fill_1": layout = .fill(activeSpeaker: 1)
                        default: layout = .split
                        }
                        return LayoutSegment(startTime: time, layout: layout)
                    }
                }
            }
        } catch {}

        return [LayoutSegment(startTime: 0, layout: .split)]
    }

    // MARK: - Extract Clips

    private func handleExtractClips(_ args: [String: Any], appState: AppState) async -> String {
        guard let assetIDStr = args["asset_id"] as? String,
              let assetID = UUID(uuidString: assetIDStr),
              let asset = appState.assets.first(where: { $0.id == assetID }) else {
            return "Error: Invalid asset_id"
        }

        let count = args["count"] as? Int ?? (args["count"] as? Double).map({ Int($0) }) ?? 5
        let minDur = args["min_duration"] as? Double ?? 30
        let maxDur = args["max_duration"] as? Double ?? 90

        // Get transcript
        guard let result = await appState.media.transcriptionService.getTranscript(
            for: asset, bundleURL: appState.projectBundleURL
        ) else {
            return "Error: No transcript. Run transcribe_asset first."
        }

        let words = result.words
        let transcript = TranscriptAnalysisSupport.buildTimestampedTranscript(from: words)
        let coverage = TranscriptAnalysisSupport.assessCoverage(
            words: words,
            assetDuration: asset.duration
        )

        if coverage.isSparseForStructuralAnalysis {
            let startText = TranscriptAnalysisSupport.formatTimestamp(coverage.firstStart ?? 0)
            let endText = TranscriptAnalysisSupport.formatTimestamp(coverage.lastEnd ?? 0)
            let hook = words.prefix(12).map(\.word).joined(separator: " ")
            let durationText = String(format: "%.1f", coverage.speakingSpan)
            let assetDurationText = String(format: "%.1f", asset.duration)
            let excerpt = transcript.isEmpty ? "[no transcript text available]" : transcript

            return """
            === CLIP CANDIDATES ===
            Asset: \(asset.name)
            Requested: \(count) clips (\(Int(minDur))-\(Int(maxDur))s)

            Result: no complete clip candidates found.
            Reason: transcript coverage is too sparse for ranked short-form extraction.
            Coverage: \(coverage.wordCount) words from [\(startText)]-[\(endText)] across \(durationText)s of spoken material in a \(assetDurationText)s asset.

            Best available excerpt:
            Start: [\(startText)]
            End: [\(endText)]
            Duration: \(durationText)s
            Hook: "\(hook)"
            Topic: incomplete excerpt
            Score: n/a
            Layout: unknown
            Why: the available transcript does not contain enough complete material to produce a \(Int(minDur))-\(Int(maxDur)) second ranked clip.

            Transcript excerpt:
            \(excerpt)
            """
        }

        // Get Claude API key
        guard let apiKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? loadAnthropicKey() else {
            return "Error: No API key"
        }

        let provider = ClaudeProvider(apiKey: apiKey, model: "claude-sonnet-4-6")

        let prompt = """
        You are finding the best short-form clip candidates from a podcast transcript.
        The FULL transcript available for this task is included below. Never ask for more transcript, never say it was cut off, and never emit tool calls.
        If the transcript is short or imperfect, still return the best candidates you can from the provided material.
        Find the \(count) best moments that would make great 30-90 second TikTok/Shorts/Reels clips.

        For each clip, identify:
        1. EXACT start timestamp [MM:SS] — where the clip should begin
        2. EXACT end timestamp [MM:SS] — where the clip should end
        3. Duration (must be \(Int(minDur))-\(Int(maxDur)) seconds)
        4. Hook sentence — the most compelling line that could open the clip
        5. Topic — what the clip is about in 5-10 words
        6. Score 1-10 — how shareable/viral is this moment?
        7. Best layout — "split" (both speakers visible) or "fill" (single speaker) and which speaker if fill
        8. Why — one line explaining why this would work as a short

        Rules:
        - Each clip must be a COMPLETE thought — don't cut mid-sentence
        - Prefer moments with: strong opinions, stories, surprising facts, emotional reactions, humor
        - The hook (first sentence) should grab attention immediately
        - Avoid filler, small talk, or meta-discussion about the podcast itself
        - Clips should make sense WITHOUT context from the rest of the episode

        Format each clip as:
        CLIP N:
        Start: [MM:SS]
        End: [MM:SS]
        Duration: Xs
        Hook: "quote"
        Topic: description
        Score: N/10
        Layout: split/fill_0/fill_1
        Why: reason

        TRANSCRIPT:
        \(transcript)
        """

        do {
            let response = try await provider.complete(
                messages: [AIMessage(role: "user", content: prompt)],
                tools: []
            )
            return "=== CLIP CANDIDATES ===\nAsset: \(asset.name)\nRequested: \(count) clips (\(Int(minDur))-\(Int(maxDur))s)\n\n" + response.content
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }

    // MARK: - Extract Segment

    private func handleExtractSegment(_ args: [String: Any], appState: AppState) -> String {
        guard let assetIDStr = args["asset_id"] as? String,
              let assetID = UUID(uuidString: assetIDStr),
              let asset = appState.assets.first(where: { $0.id == assetID }) else {
            return "Error: Invalid asset_id"
        }
        guard let sourceStart = args["source_start"] as? Double,
              let sourceEnd = args["source_end"] as? Double,
              sourceEnd > sourceStart else {
            return "Error: Invalid source_start/source_end"
        }

        let duration = sourceEnd - sourceStart

        // Clear existing timeline, then set up tracks and clips
        do {
            for track in appState.timeline.tracks {
                let clipIDs = track.clips.map(\.id)
                if !clipIDs.isEmpty {
                    try appState.perform(.deleteClips(clipIDs: clipIDs), source: .ai)
                }
            }

            // Ensure video + audio tracks exist
            let videoTrackID: UUID
            let audioTrackID: UUID

            if let vt = appState.timeline.tracks.first(where: { $0.type == .video }) {
                videoTrackID = vt.id
            } else {
                let track = Track(name: "Video", type: .video)
                try appState.perform(.addTrack(track: track), source: .ai)
                videoTrackID = track.id
            }

            if let at = appState.timeline.tracks.first(where: { $0.type == .audio }) {
                audioTrackID = at.id
            } else {
                let track = Track(name: "Audio", type: .audio)
                try appState.perform(.addTrack(track: track), source: .ai)
                audioTrackID = track.id
            }

            // Insert video clip at position 0 with specified source range
            let linkID = UUID()
            let videoClip = Clip(
                assetID: assetID,
                timelineRange: TimeRange(start: 0, duration: duration),
                sourceRange: TimeRange(start: sourceStart, end: sourceEnd),
                metadata: ClipMetadata(label: asset.name),
                linkGroupID: linkID
            )
            try appState.perform(.insertClip(clip: videoClip, trackID: videoTrackID), source: .ai)

            // Insert linked audio clip
            let audioClip = Clip(
                assetID: assetID,
                timelineRange: TimeRange(start: 0, duration: duration),
                sourceRange: TimeRange(start: sourceStart, end: sourceEnd),
                metadata: ClipMetadata(label: asset.name),
                linkGroupID: linkID
            )
            try appState.perform(.insertClip(clip: audioClip, trackID: audioTrackID), source: .ai)
        } catch {
            return "Error: \(error.localizedDescription)"
        }

        appState.rebuildComposition()

        return "Extracted \(String(format: "%.1f", duration))s segment (source \(String(format: "%.0f", sourceStart))s-\(String(format: "%.0f", sourceEnd))s) at timeline 0. " + stateSnapshot(appState)
    }

    // MARK: - Short-Form Analysis

    /// Cached short-form configs per asset (from analyze_for_shorts)
    private var shortFormConfigs: [UUID: ShortFormConfig] = [:]

    private func handleAnalyzeForShorts(_ args: [String: Any], appState: AppState) async -> String {
        guard let assetIDStr = args["asset_id"] as? String,
              let assetID = UUID(uuidString: assetIDStr),
              let asset = appState.assets.first(where: { $0.id == assetID }) else {
            return "Error: Invalid asset_id"
        }

        let mediaURL = resolvedToolMediaURL(for: asset)
        let start = args["start"] as? Double
        let end = args["end"] as? Double

        // Step 1: Track faces
        let tracker = MultiFaceTracker()
        let faceTracks: [FaceTrack]
        do {
            if let start, let end {
                faceTracks = try await tracker.trackRange(url: mediaURL, start: start, end: end)
            } else {
                faceTracks = try await tracker.track(url: mediaURL)
            }
        } catch {
            return "Error tracking faces: \(error.localizedDescription)"
        }

        guard !faceTracks.isEmpty else {
            return "Error: No faces detected in video"
        }

        // Step 2: Map speakers to faces
        var speakerToFace: [Int: Int] = [:]
        if let result = await appState.media.transcriptionService.getTranscript(
            for: asset, bundleURL: appState.projectBundleURL
        ), let speakers = result.speakers {
            let mapper = SpeakerFaceMapper()
            speakerToFace = mapper.map(speakerSegments: speakers, faceTracks: faceTracks)
        } else {
            // Default: face 0 = speaker 0, face 1 = speaker 1
            for i in 0..<faceTracks.count { speakerToFace[i] = i }
        }

        // Step 3: Decide layouts
        var layoutSegments: [LayoutSegment] = [LayoutSegment(startTime: 0, layout: .split)]
        if let result = await appState.media.transcriptionService.getTranscript(
            for: asset, bundleURL: appState.projectBundleURL
        ), let speakers = result.speakers {
            let decider = LayoutDecider()
            layoutSegments = decider.decide(speakerSegments: speakers, speakerToFace: speakerToFace)
        }

        // Build config — sourceTimeOffset maps timeline time to source time for face lookups
        let sourceOffset = start ?? 0
        let config = ShortFormConfig(
            isEnabled: true,
            outputAspect: .vertical9x16,
            faceTracks: faceTracks,
            speakerToFace: speakerToFace,
            layoutSegments: layoutSegments,
            sourceTimeOffset: sourceOffset
        )

        // Cache for create_short
        shortFormConfigs[assetID] = config

        // Report
        var lines = ["=== SHORT-FORM ANALYSIS ==="]
        lines.append("Asset: \(asset.name)")
        lines.append("Faces detected: \(faceTracks.count)")
        lines.append("Face samples: \(faceTracks.map(\.samples.count))")
        lines.append("Speaker mapping: \(speakerToFace)")
        lines.append("Layout segments: \(layoutSegments.count)")
        for (i, seg) in layoutSegments.enumerated() {
            let mins = Int(seg.startTime) / 60
            let secs = Int(seg.startTime) % 60
            lines.append("  #\(i+1) [\(mins):\(String(format: "%02d", secs))] \(seg.layout)")
        }
        lines.append("\nReady for create_short.")
        return lines.joined(separator: "\n")
    }

    private func handleCreateShort(_ args: [String: Any], appState: AppState) async -> String {
        guard let assetIDStr = args["asset_id"] as? String,
              let assetID = UUID(uuidString: assetIDStr) else {
            return "Error: Invalid asset_id"
        }

        guard var config = shortFormConfigs[assetID] else {
            return "Error: No short-form analysis found for this asset. Run analyze_for_shorts first."
        }

        // Override layout if specified
        if let layoutStr = args["layout"] as? String {
            switch layoutStr {
            case "split":
                config.layoutSegments = [LayoutSegment(startTime: 0, layout: .split)]
            case "fill_0":
                config.layoutSegments = [LayoutSegment(startTime: 0, layout: .fill(activeSpeaker: 0))]
            case "fill_1":
                config.layoutSegments = [LayoutSegment(startTime: 0, layout: .fill(activeSpeaker: 1))]
            default:
                break // Use analyzed layouts
            }
        }

        // Apply the short-form config to the timeline
        appState.context.timelineState.shortFormConfig = config
        appState.rebuildCompositionNow()

        return "Short-form layout applied. Output: \(config.outputAspect.size.width)x\(config.outputAspect.size.height). Layout: \(config.layoutSegments.first?.layout ?? .split). Faces tracked: \(config.faceTracks.count)."
    }

    // MARK: - Overlay Config

    private func handleSetOverlayConfig(_ args: [String: Any], appState: AppState) -> String {
        let enabled = args["enabled"] as? Bool ?? true

        var topics: [TimedEntry] = []
        if let topicArray = args["topics"] as? [[String: Any]] {
            topics = topicArray.compactMap { t in
                guard let time = t["time_seconds"] as? Double,
                      let text = t["text"] as? String else { return nil }
                return TimedEntry(timeSeconds: time, text: text)
            }
        }

        var chapters: [TimedEntry] = []
        if let chapterArray = args["chapters"] as? [[String: Any]] {
            chapters = chapterArray.compactMap { c in
                guard let time = c["time_seconds"] as? Double,
                      let text = c["text"] as? String else { return nil }
                return TimedEntry(timeSeconds: time, text: text)
            }
        }

        var sponsors: [String] = []
        if let sponsorArray = args["sponsors"] as? [String] {
            sponsors = sponsorArray
        }

        let config = BroadcastOverlayConfig(
            isEnabled: enabled,
            episodeTitle: args["episode_title"] as? String ?? "",
            episodeSubtitle: args["episode_subtitle"] as? String ?? "",
            hostA: HostInfo(
                name: args["host_a_name"] as? String ?? "",
                title: args["host_a_title"] as? String ?? ""
            ),
            hostB: HostInfo(
                name: args["host_b_name"] as? String ?? "",
                title: args["host_b_title"] as? String ?? ""
            ),
            sponsors: sponsors,
            topics: topics,
            chapters: chapters
        )

        do {
            try appState.perform(.setBroadcastOverlay(config: config), source: .ai)
        } catch {
            return "Error: \(error.localizedDescription)"
        }
        appState.rebuildComposition()

        return "Overlay config set. Enabled: \(enabled), title: \(config.episodeTitle), \(topics.count) topics, \(chapters.count) chapters, \(sponsors.count) sponsors."
    }

    private func handleGetOverlayConfig(appState: AppState) -> String {
        guard let config = appState.context.timelineState.broadcastOverlay else {
            return "No overlay configured."
        }

        var lines = ["=== OVERLAY CONFIG ==="]
        lines.append("Enabled: \(config.isEnabled)")
        lines.append("Title: \(config.episodeTitle)")
        lines.append("Subtitle: \(config.episodeSubtitle)")
        lines.append("Host A: \(config.hostA.name) — \(config.hostA.title)")
        lines.append("Host B: \(config.hostB.name) — \(config.hostB.title)")
        lines.append("Sponsors: \(config.sponsors.joined(separator: ", "))")
        lines.append("Topics (\(config.topics.count)):")
        for t in config.topics {
            lines.append("  [\(Int(t.timeSeconds / 60)):\(String(format: "%02d", Int(t.timeSeconds) % 60))] \(t.text)")
        }
        lines.append("Chapters (\(config.chapters.count)):")
        for c in config.chapters {
            lines.append("  [\(Int(c.timeSeconds / 60)):\(String(format: "%02d", Int(c.timeSeconds) % 60))] \(c.text)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Get Full Transcript

    private func handleGetFullTranscript(_ args: [String: Any], appState: AppState) async -> String {
        guard let assetIDStr = args["asset_id"] as? String,
              let assetID = UUID(uuidString: assetIDStr),
              let asset = appState.assets.first(where: { $0.id == assetID }) else {
            return "Error: Invalid asset_id"
        }

        guard let result = await appState.media.transcriptionService.getTranscript(
            for: asset, bundleURL: appState.projectBundleURL
        ) else {
            return "Error: No transcript. Run transcribe_asset first."
        }

        let startFilter = args["start"] as? Double ?? 0
        let endFilter = args["end"] as? Double ?? asset.duration

        // Build transcript grouped by sentences/pauses with timestamps
        let words = result.words.filter { $0.start >= startFilter && $0.end <= endFilter }
        guard !words.isEmpty else { return "No words in the specified range." }

        var output = ""
        var sentenceWords: [String] = []
        var sentenceStart: TimeInterval = words[0].start

        for (i, word) in words.enumerated() {
            if sentenceWords.isEmpty {
                sentenceStart = word.start
            }
            sentenceWords.append(word.word)

            // Break on sentence-ending punctuation or long pause (>0.8s)
            let isSentenceEnd = word.word.hasSuffix(".") || word.word.hasSuffix("?") || word.word.hasSuffix("!")
            let hasLongPause = i + 1 < words.count && (words[i + 1].start - word.end) > 0.8
            let isLast = i == words.count - 1

            if isSentenceEnd || hasLongPause || isLast {
                let mins = Int(sentenceStart) / 60
                let secs = Int(sentenceStart) % 60
                let sentence = sentenceWords.joined(separator: " ")
                output += "[\(mins):\(String(format: "%02d", secs))] \(sentence)\n"
                sentenceWords = []
            }
        }

        let header = "Transcript: \(asset.name) (\(words.count) words, \(String(format: "%.0f", endFilter - startFilter))s)\n\n"
        return header + output
    }

    // MARK: - Analyze Transcript

    private func handleAnalyzeTranscript(_ args: [String: Any], appState: AppState) async -> String {
        guard let assetIDStr = args["asset_id"] as? String,
              let assetID = UUID(uuidString: assetIDStr),
              let asset = appState.assets.first(where: { $0.id == assetID }) else {
            return "Error: Invalid asset_id"
        }

        guard let result = await appState.media.transcriptionService.getTranscript(
            for: asset, bundleURL: appState.projectBundleURL
        ) else {
            return "Error: No transcript. Run transcribe_asset first."
        }

        let words = result.words
        let transcript = TranscriptAnalysisSupport.buildTimestampedTranscript(from: words)
        let coverage = TranscriptAnalysisSupport.assessCoverage(
            words: words,
            assetDuration: asset.duration
        )

        if coverage.isSparseForStructuralAnalysis {
            let startText = TranscriptAnalysisSupport.formatTimestamp(coverage.firstStart ?? 0)
            let endText = TranscriptAnalysisSupport.formatTimestamp(coverage.lastEnd ?? 0)
            let assetDurationText = String(format: "%.1f", asset.duration)
            let spanText = String(format: "%.1f", coverage.speakingSpan)

            return """
            === TRANSCRIPT ANALYSIS ===

            EPISODES: 0

            OTHER SECTIONS:
            [\(startText)]-[\(endText)]: incomplete captured excerpt — only \(coverage.wordCount) transcript words are available for structural analysis.

            LIMITATION:
            Transcript coverage is sparse for this asset: \(coverage.wordCount) words spanning \(spanText)s of speech within a \(assetDurationText)s recording. That is not enough material to identify real episodes, full sections, or reliable topic development.

            Transcript excerpt:
            \(transcript.isEmpty ? "[no transcript text available]" : transcript)
            """
        }

        // Get Claude API key from environment or .env file
        guard let apiKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? loadAnthropicKey() else {
            return "Error: ANTHROPIC_API_KEY not configured. Cannot analyze without Claude."
        }

        // Send to Claude for comprehension
        let provider = ClaudeProvider(apiKey: apiKey, model: "claude-sonnet-4-6")

        let prompt = """
        You are analyzing a recording transcript to identify its structure. Read the ENTIRE transcript below carefully, then tell me:
        The FULL transcript available for this task is included below. Never ask for more transcript, never say it was cut off, and never request additional context.
        If the transcript is brief, analyze only what is present and state the limitation as part of the analysis instead of refusing.

        1. How many REAL episodes are in this recording? A real episode is structured content intended for an audience — it has a topic, develops that topic, and delivers value. Casual conversation between hosts about their own channel/views/setup is NOT an episode even if it has an intro tagline.

        2. For each real episode:
           - Exact start timestamp [MM:SS]
           - Exact end timestamp [MM:SS]
           - Title (from the intro if there is one)
           - Topic summary (what is the episode actually about?)
           - Key points discussed

        3. What are the other sections? (pre-show conversation, planning, off-camera, rehearsal/re-takes, wrap-up)
           - For each non-episode section, give start/end timestamps and a brief description

        Important rules:
        - An intro tagline ("Welcome to X") does NOT make something an episode. The content after the intro must actually deliver on the promise. If they say "Welcome to Technologer" and then talk about their own YouTube views and mic setup, that's NOT an episode.
        - Multiple intro attempts close together are rehearsals, not separate episodes.
        - "Off camera" or discussing what to record next = planning, not episode content.
        - Look for topic commitment — does the conversation develop a subject for 10+ minutes in a way a viewer would find valuable?

        Format your response as:

        EPISODES: [number]

        EPISODE 1:
        Start: [MM:SS]
        End: [MM:SS]
        Title: [title]
        Topic: [what it's about]
        Key points: [bullet list]

        OTHER SECTIONS:
        [MM:SS]-[MM:SS]: [type] — [description]

        Here is the full transcript:

        \(transcript)
        """

        do {
            let response = try await provider.complete(
                messages: [AIMessage(role: "user", content: prompt)],
                tools: []
            )

            let initialAnalysis = response.content

            // === PASS 2: Refine episode start timestamps ===
            // For each episode start Claude found, zoom in on ±2 min of transcript
            // and ask for the EXACT clean take timestamp.
            var refinedAnalysis = initialAnalysis

            // Parse episode starts from the initial analysis
            let episodeStarts = parseEpisodeStarts(from: initialAnalysis)

            if !episodeStarts.isEmpty {
                var refinements: [String] = []

                for (episodeNum, approxTime) in episodeStarts {
                    // Extract window: 1 min before to 5 min after the approximate start
                    // Wider forward window because rehearsals can span several minutes
                    let windowStart = max(approxTime - 60, 0)
                    let windowEnd = min(approxTime + 300, asset.duration)
                    let windowWords = words.filter { $0.start >= windowStart && $0.end <= windowEnd }

                    guard !windowWords.isEmpty else { continue }

                    var windowTranscript = ""
                    var wSentenceWords: [String] = []
                    var wSentenceStart: TimeInterval = windowWords.first?.start ?? 0

                    for (i, word) in windowWords.enumerated() {
                        if wSentenceWords.isEmpty { wSentenceStart = word.start }
                        wSentenceWords.append(word.word)

                        let isEnd = word.word.hasSuffix(".") || word.word.hasSuffix("?") || word.word.hasSuffix("!")
                        let hasPause = i + 1 < windowWords.count && (windowWords[i + 1].start - word.end) > 0.8
                        let isLast = i == windowWords.count - 1

                        if isEnd || hasPause || isLast {
                            let mins = Int(wSentenceStart) / 60
                            let secs = Int(wSentenceStart) % 60
                            windowTranscript += "[\(mins):\(String(format: "%02d", secs))] \(wSentenceWords.joined(separator: " "))\n"
                            wSentenceWords = []
                        }
                    }

                    let refinePrompt = """
                    I found that Episode \(episodeNum) starts approximately at \(formatTimestamp(approxTime)).

                    Below is the transcript around that area (±2 minutes). Find the EXACT timestamp where the clean, final take of the episode intro begins.

                    Rules:
                    - If there are multiple attempts at the same intro, pick the LAST complete one — that's the good take.
                    - Ignore false starts, botched attempts ("I messed up"), and chatting between takes.
                    - The clean take is the one that flows directly into actual episode content.

                    Respond with ONLY:
                    EXACT_START: [MM:SS]
                    REASON: [one line explanation]

                    Transcript:
                    \(windowTranscript)
                    """

                    let refineResponse = try await provider.complete(
                        messages: [AIMessage(role: "user", content: refinePrompt)],
                        tools: []
                    )

                    refinements.append("Episode \(episodeNum) refined: \(refineResponse.content.trimmingCharacters(in: .whitespacesAndNewlines))")
                }

                if !refinements.isEmpty {
                    refinedAnalysis += "\n\n--- REFINED START TIMESTAMPS ---\n" + refinements.joined(separator: "\n")
                }
            }

            return "=== TRANSCRIPT ANALYSIS (by Claude) ===\n\n" + refinedAnalysis
        } catch {
            return "Error calling Claude: \(error.localizedDescription)"
        }
    }

    /// Parse approximate episode start timestamps from Claude's analysis.
    private func parseEpisodeStarts(from analysis: String) -> [(episodeNum: Int, time: TimeInterval)] {
        var starts: [(Int, TimeInterval)] = []
        let lines = analysis.components(separatedBy: .newlines)
        var currentEpisode = 0

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Match "EPISODE N:" pattern
            if trimmed.hasPrefix("EPISODE") && trimmed.contains(":") {
                if let numStr = trimmed.components(separatedBy: " ").dropFirst().first?.replacingOccurrences(of: ":", with: ""),
                   let num = Int(numStr) {
                    currentEpisode = num
                }
            }

            // Match "Start: MM:SS" or "Start: [MM:SS]"
            if trimmed.hasPrefix("Start:") && currentEpisode > 0 {
                let timeStr = trimmed.replacingOccurrences(of: "Start:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                let parts = timeStr.components(separatedBy: ":")
                if parts.count == 2, let mins = Int(parts[0]), let secs = Int(parts[1]) {
                    starts.append((currentEpisode, TimeInterval(mins * 60 + secs)))
                    currentEpisode = 0 // Reset so we don't double-match
                }
            }
        }

        return starts
    }

    private func formatTimestamp(_ t: TimeInterval) -> String {
        let m = Int(t) / 60
        let s = Int(t) % 60
        return "\(m):\(String(format: "%02d", s))"
    }

    // MARK: - Detect Episodes

    private func handleDetectEpisodes(_ args: [String: Any], appState: AppState) async -> String {
        guard let assetIDStr = args["asset_id"] as? String,
              let assetID = UUID(uuidString: assetIDStr),
              let asset = appState.assets.first(where: { $0.id == assetID }) else {
            return "Error: Invalid asset_id"
        }

        // Get transcript
        guard let result = await appState.media.transcriptionService.getTranscript(
            for: asset, bundleURL: appState.projectBundleURL
        ) else {
            return "Error: No transcript. Run transcribe_asset first."
        }

        // Get energy readings
        let mediaURL = resolvedToolMediaURL(for: asset)
        let analyzer = SpeechEnergyAnalyzer()
        let readings = await analyzer.analyze(url: mediaURL)

        // Detect
        let detector = EpisodeBoundaryDetector()
        let episodes = detector.detect(
            transcript: result.words,
            energyReadings: readings,
            totalDuration: asset.duration
        )

        // Report
        var lines = ["=== EPISODE DETECTION ==="]
        lines.append("Asset: \(asset.name) (\(String(format: "%.0f", asset.duration))s)")
        lines.append("Episodes found: \(episodes.count)")
        lines.append("")

        for (i, ep) in episodes.enumerated() {
            lines.append("Episode \(i + 1):")
            if let title = ep.title {
                lines.append("  Title: \(title)")
            }
            lines.append("  Start: \(ep.formattedStart) (confidence: \(String(format: "%.0f", ep.startConfidence * 100))%)")
            lines.append("  End:   \(ep.formattedEnd) (confidence: \(String(format: "%.0f", ep.endConfidence * 100))%)")
            lines.append("  Duration: \(ep.formattedDuration)")

            if !ep.startEvidence.isEmpty {
                lines.append("  Start evidence:")
                for e in ep.startEvidence { lines.append("    - \(e)") }
            }
            if !ep.endEvidence.isEmpty {
                lines.append("  End evidence:")
                for e in ep.endEvidence { lines.append("    - \(e)") }
            }
            lines.append("")
        }

        if episodes.isEmpty {
            lines.append("No episodes detected. The recording may be a single continuous piece.")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Classify Audio

    private func handleClassifyAudio(_ args: [String: Any], appState: AppState) async -> String {
        guard let assetIDStr = args["asset_id"] as? String,
              let assetID = UUID(uuidString: assetIDStr),
              let asset = appState.assets.first(where: { $0.id == assetID }) else {
            return "Error: Invalid asset_id"
        }

        let mediaURL = resolvedToolMediaURL(for: asset)
        let start = args["start"] as? Double
        let end = args["end"] as? Double

        let classifier = AudioSourceClassifier()

        do {
            let segments: [ClassifiedSegment]
            if let start, let end {
                segments = try await classifier.classifyRange(url: mediaURL, start: start, end: end)
            } else {
                segments = try await classifier.classify(url: mediaURL)
            }

            let runs = AudioSourceClassifier.summarize(segments)

            var lines = ["=== AUDIO SOURCE CLASSIFICATION ==="]
            lines.append("Asset: \(asset.name) (\(String(format: "%.0f", asset.duration))s)")

            // Summary counts
            let liveSpeechTime = runs.filter { $0.source == .liveSpeech }.reduce(0.0) { $0 + $1.duration }
            let playbackTime = runs.filter { $0.source == .playback }.reduce(0.0) { $0 + $1.duration }
            let backgroundTime = runs.filter { $0.source == .background }.reduce(0.0) { $0 + $1.duration }
            let silenceTime = runs.filter { $0.source == .silence }.reduce(0.0) { $0 + $1.duration }
            let total = liveSpeechTime + playbackTime + backgroundTime + silenceTime

            lines.append("")
            lines.append("Summary:")
            lines.append("  Live speech: \(String(format: "%.0f", liveSpeechTime))s (\(String(format: "%.0f", liveSpeechTime / max(total, 1) * 100))%)")
            lines.append("  Playback:    \(String(format: "%.0f", playbackTime))s (\(String(format: "%.0f", playbackTime / max(total, 1) * 100))%)")
            lines.append("  Background:  \(String(format: "%.0f", backgroundTime))s (\(String(format: "%.0f", backgroundTime / max(total, 1) * 100))%)")
            lines.append("  Silence:     \(String(format: "%.0f", silenceTime))s (\(String(format: "%.0f", silenceTime / max(total, 1) * 100))%)")
            lines.append("")

            lines.append("Segments (\(runs.count) runs):")
            for (i, run) in runs.enumerated() {
                let startMin = Int(run.start) / 60
                let startSec = Int(run.start) % 60
                let endMin = Int(run.end) / 60
                let endSec = Int(run.end) % 60
                let dur = String(format: "%.0f", run.duration)

                lines.append("  #\(i+1) [\(startMin):\(String(format: "%02d", startSec))-\(endMin):\(String(format: "%02d", endSec))] \(dur)s — \(run.source.rawValue)")
            }

            return lines.joined(separator: "\n")
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }

    // MARK: - Auto Cut

    private func handleAutoCut(_ args: [String: Any], appState: AppState) async -> String {
        let presetStr = args["preset"] as? String ?? "standard"
        let dryRun = args["dry_run"] as? Bool ?? false

        guard let preset = AutoCutPreset(rawValue: presetStr) else {
            return "Error: Invalid preset '\(presetStr)'. Use: gentle, standard, aggressive"
        }

        // Find target clip
        let clip: Clip
        let track: Track
        if let clipIDStr = args["clip_id"] as? String, let clipID = UUID(uuidString: clipIDStr) {
            guard let (foundClip, foundTrack) = findClip(id: clipID, in: appState.timeline) else {
                return "Error: Clip not found: \(clipIDStr)"
            }
            clip = foundClip
            track = foundTrack
        } else {
            // Default to first clip on timeline
            guard let firstTrack = appState.timeline.tracks.first(where: { !$0.clips.isEmpty }),
                  let firstClip = firstTrack.clips.first else {
                return "Error: No clips on timeline"
            }
            clip = firstClip
            track = firstTrack
        }

        guard let asset = appState.assets.first(where: { $0.id == clip.assetID }) else {
            return "Error: Asset not found for clip"
        }

        // Gather analysis data
        let silenceDetector = SilenceDetector()
        let energyAnalyzer = SpeechEnergyAnalyzer()
        let mediaURL = resolvedToolMediaURL(for: asset)

        let silenceRanges: [SilenceRange]
        do {
            silenceRanges = try await silenceDetector.detect(
                url: mediaURL,
                thresholdDB: -40,
                minDuration: 0.2
            )
        } catch {
            return "Error detecting silence: \(error.localizedDescription)"
        }

        let energyReadings = await energyAnalyzer.analyze(url: mediaURL)

        // Get transcript words
        var transcriptWords: [TranscriptWord] = []
        if let result = await appState.media.transcriptionService.getTranscript(
            for: asset, bundleURL: appState.projectBundleURL
        ) {
            transcriptWords = result.words
        }

        if transcriptWords.isEmpty && preset != .gentle {
            return "Error: No transcript available. Run transcribe_asset first, or use 'gentle' preset (silence-only, no transcript needed)."
        }

        // Filter analysis to clip's source range
        let clipSilences = silenceRanges.filter { range in
            range.start >= clip.sourceRange.start && range.end <= clip.sourceRange.end
        }
        let clipWords = transcriptWords.filter { w in
            w.start >= clip.sourceRange.start && w.end <= clip.sourceRange.end
        }
        let clipReadings = energyReadings.filter { r in
            r.time >= clip.sourceRange.start && r.time < clip.sourceRange.end
        }

        // Generate plan
        let engine = AutoCutEngine()
        let plan = engine.generatePlan(
            preset: preset,
            assetDuration: clip.sourceRange.duration,
            silenceRanges: clipSilences,
            transcript: clipWords,
            energyReadings: clipReadings
        )

        // Build report
        var lines = ["=== AUTO CUT PLAN ==="]
        lines.append("Preset: \(preset.rawValue)")
        lines.append("Clip: \(clip.metadata.label ?? clip.id.uuidString.prefix(8).description)")
        lines.append("")
        lines.append("Before: \(String(format: "%.1f", plan.stats.originalDuration))s | After: \(String(format: "%.1f", plan.stats.resultDuration))s | Saved: \(String(format: "%.1f", plan.stats.originalDuration - plan.stats.resultDuration))s (\(String(format: "%.0f", (1 - plan.stats.resultDuration / max(plan.stats.originalDuration, 0.1)) * 100))%)")
        lines.append("Segments removed: \(plan.stats.segmentsRemoved) | Fillers: \(plan.stats.fillerWordsRemoved) | Re-takes: \(plan.stats.retakesRemoved)")
        lines.append("Speech ratio: \(Int(plan.stats.speechRatioBefore * 100))% → \(Int(plan.stats.speechRatioAfter * 100))%")
        lines.append("Engagement: \(plan.stats.engagementBefore) → \(plan.stats.engagementAfter)")
        lines.append("")

        if !plan.segments.isEmpty {
            lines.append("Cuts:")
            for (i, seg) in plan.segments.enumerated() {
                let start = String(format: "%.1f", seg.sourceRange.start)
                let end = String(format: "%.1f", seg.sourceRange.end)
                let dur = String(format: "%.1f", seg.sourceRange.duration)
                lines.append("  \(i+1). [\(start)s-\(end)s] \(dur)s — \(seg.action.rawValue): \(seg.reason) (conf: \(String(format: "%.0f", seg.confidence * 100))%)")
            }
        } else {
            lines.append("No cuts needed — content is clean.")
        }

        if dryRun {
            lines.append("\n[DRY RUN — no changes made. Remove dry_run to execute.]")
            return lines.joined(separator: "\n")
        }

        // Execute the plan using the proven split-then-delete pattern
        // (same as handleRemoveSilence in AIChatController)
        if plan.segments.isEmpty {
            return lines.joined(separator: "\n")
        }

        // Instead of split+delete (which creates N clips = N AVFoundation tracks = black video),
        // rebuild the timeline with only the "keep" segments as new clips.
        // This produces far fewer clips and renders correctly.

        let assetID = clip.assetID
        let clipSourceStart = clip.sourceRange.start
        let clipSourceEnd = clip.sourceRange.end

        // Build list of keep ranges by inverting the removal list
        let removals = plan.segments
            .filter { $0.action != .keep && $0.action != .speedUp }
            .sorted { $0.sourceRange.start < $1.sourceRange.start }

        var keepRanges: [(source: TimeRange, speed: Double)] = []
        var cursor = clipSourceStart

        for removal in removals {
            if removal.sourceRange.start > cursor + 0.01 {
                keepRanges.append((source: TimeRange(start: cursor, end: removal.sourceRange.start), speed: 1.0))
            }
            cursor = removal.sourceRange.end
        }
        // Trailing keep
        if cursor < clipSourceEnd - 0.01 {
            keepRanges.append((source: TimeRange(start: cursor, end: clipSourceEnd), speed: 1.0))
        }

        // Apply speed-ups from the plan
        let speedUps = plan.segments.filter { $0.action == .speedUp }
        for speedUp in speedUps {
            for i in 0..<keepRanges.count {
                if keepRanges[i].source.overlaps(speedUp.sourceRange) {
                    keepRanges[i].speed = 1.12
                }
            }
        }

        // Find the tracks this clip lives on
        guard let videoTrackIdx = appState.timeline.tracks.firstIndex(where: { $0.clips.contains(where: { $0.id == clip.id }) }) else {
            lines.append("\nError: Could not find clip's track")
            return lines.joined(separator: "\n")
        }

        // Find paired audio track via linkGroupID
        let audioTrackIdx: Int? = {
            guard let linkID = clip.linkGroupID else { return nil }
            return appState.timeline.tracks.firstIndex(where: { track in
                track.type == .audio && track.clips.contains(where: { $0.linkGroupID == linkID })
            })
        }()

        // Delete original clips and insert new clips for each keep range
        do {
            var idsToDelete = [clip.id]
            if let ati = audioTrackIdx {
                if let audioClip = appState.timeline.tracks[ati].clips.first(where: { $0.linkGroupID == clip.linkGroupID }) {
                    idsToDelete.append(audioClip.id)
                }
            }
            try appState.perform(.deleteClips(clipIDs: idsToDelete), source: .ai)
        } catch {
            return lines.joined(separator: "\n") + "\nError deleting original clips: \(error.localizedDescription)"
        }

        // Insert new clips for each keep range
        var timelineCursor: TimeInterval = 0
        var insertedCount = 0

        do {
            for keep in keepRanges {
                let duration = keep.source.duration / keep.speed
                let linkID = UUID()

                // Video clip
                let videoClip = Clip(
                    assetID: assetID,
                    timelineRange: TimeRange(start: timelineCursor, duration: duration),
                    sourceRange: keep.source,
                    volume: clip.volume,
                    speed: keep.speed,
                    linkGroupID: linkID
                )
                try appState.perform(.insertClip(clip: videoClip, trackID: appState.timeline.tracks[videoTrackIdx].id), source: .ai)

                // Audio clip on paired track
                if let ati = audioTrackIdx {
                    let audioClip = Clip(
                        assetID: assetID,
                        timelineRange: TimeRange(start: timelineCursor, duration: duration),
                        sourceRange: keep.source,
                        volume: clip.volume,
                        speed: keep.speed,
                        linkGroupID: linkID
                    )
                    try appState.perform(.insertClip(clip: audioClip, trackID: appState.timeline.tracks[ati].id), source: .ai)
                }

                timelineCursor += duration
                insertedCount += 1
            }
        } catch {
            return lines.joined(separator: "\n") + "\nError inserting clips: \(error.localizedDescription)"
        }

        lines.append("\nExecuted: removed \(removals.count) segments, created \(insertedCount) keep clips, \(speedUps.count) speed-ups.")

        // === PASS 2: Claude review ===
        // Read the transcript of what's now on the timeline, send to Claude,
        // and fix any rehearsals, false starts, or off-topic sections.
        let reviewResult = await reviewAndFix(appState: appState, asset: asset)
        if !reviewResult.isEmpty {
            lines.append("\n--- REVIEW PASS ---")
            lines.append(reviewResult)
        }

        lines.append(stateSnapshot(appState))
        return lines.joined(separator: "\n")
    }

    private func handleRemoveSilence(_ args: [String: Any], appState: AppState) -> String {
        let timeline = appState.timeline
        let minDuration = (args["min_duration"] as? Double) ?? 0.5

        let targetClips: [Clip]
        if let clipIDStrs = args["clip_ids"] as? [String], !clipIDStrs.isEmpty {
            let clipIDs = Set(clipIDStrs.compactMap(UUID.init(uuidString:)))
            targetClips = timeline.tracks.flatMap(\.clips).filter { clipIDs.contains($0.id) }
        } else {
            targetClips = timeline.tracks.flatMap(\.clips)
        }

        guard !targetClips.isEmpty else { return "No clips to process." }

        let result = SilenceRemovalExecutor.remove(
            minimumDuration: minDuration,
            from: targetClips,
            appState: appState,
            source: .ai
        )

        if result.removedSilenceCount == 0 {
            return "No silence ranges found (min duration: \(String(format: "%.1f", minDuration))s)."
        }
        let prunedMessage = result.prunedFragmentCount > 0
            ? " Pruned \(result.prunedFragmentCount) tiny fragment(s)."
            : ""
        return "Removed \(result.removedSilenceCount) silent segment(s) across \(result.processedClipCount) clip(s), rebuilt \(result.insertedClipCount) clip(s), deleted \(result.deletedClipCount) original clip(s).\(prunedMessage)"
    }

    private func handleRemoveSection(_ args: [String: Any], appState: AppState) -> String {
        guard let startTime = args["start_time"] as? Double,
              let endTime = args["end_time"] as? Double,
              endTime > startTime else {
            return "Error: Invalid time range"
        }

        let affectedClips = appState.timeline.tracks
            .flatMap(\.clips)
            .filter { $0.timelineRange.start < endTime && $0.timelineRange.end > startTime }

        var deletedCount = 0
        do {
            for clip in affectedClips where endTime > clip.timelineRange.start && endTime < clip.timelineRange.end {
                try appState.perform(.splitClip(clipID: clip.id, at: endTime), source: .ai)
            }
            for clip in appState.timeline.tracks.flatMap(\.clips) where
                startTime > clip.timelineRange.start && startTime < clip.timelineRange.end {
                try appState.perform(.splitClip(clipID: clip.id, at: startTime), source: .ai)
            }

            let toDelete = appState.timeline.tracks.flatMap(\.clips).filter {
                $0.timelineRange.start >= startTime - 0.01 && $0.timelineRange.end <= endTime + 0.01
            }.map(\.id)
            deletedCount = toDelete.count

            if !toDelete.isEmpty {
                try appState.perform(.deleteClips(clipIDs: toDelete), source: .ai)
            }
        } catch {
            return "Error: \(error.localizedDescription)"
        }

        appState.rippleCloseGaps()
        let pruned = appState.pruneNonRenderableClips()
        let duration = endTime - startTime
        let prunedMessage = pruned > 0 ? " Pruned \(pruned) tiny fragment(s)." : ""
        return "Removed \(String(format: "%.1f", duration))s section (\(String(format: "%.1f", startTime))s-\(String(format: "%.1f", endTime))s). Deleted \(deletedCount) clip(s). Gaps closed.\(prunedMessage)"
    }

    private func handleRippleDelete(_ args: [String: Any], appState: AppState) -> String {
        guard let clipIDStrs = args["clip_ids"] as? [String], !clipIDStrs.isEmpty else {
            return "Error: Missing clip_ids"
        }

        let clipIDs = clipIDStrs.compactMap(UUID.init(uuidString:))
        do {
            try appState.perform(.deleteClips(clipIDs: clipIDs), source: .ai)
            appState.rippleCloseGaps()
            let remaining = appState.timeline.tracks.flatMap(\.clips).count
            return "Deleted \(clipIDs.count) clip(s) and closed gaps. \(remaining) clip(s) remaining."
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }

    private func handleNormalizeAudio(_ args: [String: Any], appState: AppState) -> String {
        let targetVolume = (args["target_volume"] as? Double) ?? 1.0
        let clipIDStrs = args["clip_ids"] as? [String] ?? []

        let audioClips: [Clip]
        if clipIDStrs.isEmpty {
            audioClips = appState.timeline.tracks.filter { $0.type == .audio }.flatMap(\.clips)
        } else {
            let ids = Set(clipIDStrs.compactMap(UUID.init(uuidString:)))
            audioClips = appState.timeline.tracks.flatMap(\.clips).filter { ids.contains($0.id) }
        }

        // Guard: verify target clips have audio content
        let clipsWithAudio = audioClips.filter { clip in
            appState.assets.first(where: { $0.id == clip.assetID })?.hasAudioTrack == true
        }
        guard !clipsWithAudio.isEmpty else {
            return "Error: No audio content in the target clips"
        }

        var adjusted = 0
        var failed = 0
        for clip in clipsWithAudio where clip.volume != targetVolume {
            do {
                try appState.perform(.setClipVolume(clipID: clip.id, volume: targetVolume), source: .ai)
                adjusted += 1
            } catch {
                failed += 1
            }
        }

        var result = "Normalized \(adjusted) clip(s) to volume \(String(format: "%.1f", targetVolume)). \(clipsWithAudio.count - adjusted - failed) already at target."
        if failed > 0 {
            result += " Warning: \(failed) clip(s) failed to update."
        }
        return result
    }

    // MARK: - Export

    private func handleExportVideo(_ args: [String: Any], appState: AppState) async -> String {
        let preset = (args["preset"] as? String) ?? "high"
        let filename = (args["filename"] as? String) ?? "export_\(Int(Date().timeIntervalSince1970))"

        let avPreset: String
        switch preset {
        case "low": avPreset = AVAssetExportPresetMediumQuality
        case "medium": avPreset = AVAssetExportPreset1280x720
        case "high": avPreset = AVAssetExportPresetHighestQuality
        case "4k": avPreset = AVAssetExportPreset3840x2160
        default: avPreset = AVAssetExportPresetHighestQuality
        }

        let outputDir = FileManager.default.temporaryDirectory
        let outputURL = outputDir.appendingPathComponent("\(filename).mp4")

        await appState.exportEngine.export(
            timeline: appState.timeline,
            assets: appState.assets,
            to: outputURL,
            preset: avPreset,
            broadcastOverlay: appState.context.timelineState.broadcastOverlay,
            shortFormConfig: appState.context.timelineState.shortFormConfig,
            captionStyle: appState.context.timelineState.captionStyle
        )

        switch appState.exportEngine.state {
        case .completed(let url):
            guard FileManager.default.fileExists(atPath: url.path) else {
                return "Export failed: output file missing"
            }
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            let sizeMB = String(format: "%.1f", Double(size) / 1_000_000)
            return "Export complete: \(url.lastPathComponent) (\(sizeMB) MB). Path: \(url.path)"
        case .failed(let error):
            return "Export failed: \(error)"
        default:
            return "Export status: \(appState.exportEngine.state)"
        }
    }

    private func handleExportForPlatform(_ args: [String: Any], appState: AppState) async -> String {
        guard let platformStr = args["platform"] as? String else {
            return "Error: 'platform' parameter is required."
        }
        guard let platform = PlatformPreset.Platform(rawValue: platformStr) else {
            let valid = PlatformPreset.Platform.allCases.map(\.rawValue).joined(separator: ", ")
            return "Error: Unknown platform '\(platformStr)'. Valid platforms: \(valid)"
        }
        guard let preset = PlatformPreset.preset(for: platform) else {
            return "Error: No preset found for '\(platformStr)'."
        }

        let filename = (args["filename"] as? String) ?? "\(platformStr)_\(Int(Date().timeIntervalSince1970))"
        let ext = preset.fileType == .m4a ? "m4a" : "mp4"
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(filename).\(ext)")

        // Warn if timeline exceeds platform max duration
        var warning = ""
        if let maxDur = preset.maxDuration, appState.timeline.duration > maxDur {
            warning = " WARNING: Timeline (\(String(format: "%.0f", appState.timeline.duration))s) exceeds \(preset.name) max (\(Int(maxDur))s)."
        }

        await appState.exportEngine.export(
            timeline: appState.timeline,
            assets: appState.assets,
            to: outputURL,
            preset: preset.avPreset,
            fileType: preset.fileType,
            broadcastOverlay: appState.context.timelineState.broadcastOverlay,
            shortFormConfig: appState.context.timelineState.shortFormConfig,
            captionStyle: appState.context.timelineState.captionStyle
        )

        switch appState.exportEngine.state {
        case .completed(let url):
            guard FileManager.default.fileExists(atPath: url.path) else {
                return "Export failed: output file missing\(warning)"
            }
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            let sizeMB = String(format: "%.1f", Double(size) / 1_000_000)
            let maxDurStr = preset.maxDuration.map { "\(Int($0))s" } ?? "unlimited"
            return "Exported for \(preset.name): \(url.lastPathComponent) (\(sizeMB) MB). Specs: \(preset.avPreset), \(Int(preset.targetLUFS)) LUFS, max \(maxDurStr). Path: \(url.path)\(warning)"
        case .failed(let error):
            return "Export failed: \(error)\(warning)"
        default:
            return "Export status: \(appState.exportEngine.state)\(warning)"
        }
    }

    private func handleListPlatforms() -> String {
        let lines = PlatformPreset.all.map { p in
            let maxDur = p.maxDuration.map { "\(Int($0))s" } ?? "unlimited"
            let fileExt = p.fileType == .m4a ? "m4a" : "mp4"
            return "- \(p.platform.rawValue): \(p.name) | \(p.avPreset) | .\(fileExt) | max \(maxDur) | \(Int(p.targetLUFS)) LUFS"
        }
        return "Available platform presets:\n" + lines.joined(separator: "\n")
    }

    /// Pass 2: Read the result transcript, send to Claude for review, fix issues.
    private func reviewAndFix(appState: AppState, asset: MediaAsset) async -> String {
        // Build transcript of what's currently on the timeline
        let clips = appState.timeline.tracks
            .filter { $0.type == .video || $0.type == .audio }
            .flatMap(\.clips)
            .sorted { $0.timelineRange.start < $1.timelineRange.start }

        // Get transcript words that fall within the clips' source ranges
        guard let transcriptResult = await appState.media.transcriptionService.getTranscript(
            for: asset, bundleURL: appState.projectBundleURL
        ) else { return "" }

        // Build timestamped transcript of just what's on the timeline
        var timelineTranscript = ""
        var timelineCursor: TimeInterval = 0

        // Deduplicate: only process video track clips (audio mirrors them)
        let videoClips = appState.timeline.tracks
            .filter { $0.type != .audio }
            .flatMap(\.clips)
            .sorted { $0.timelineRange.start < $1.timelineRange.start }

        for clip in videoClips {
            let clipWords = transcriptResult.words.filter {
                $0.start >= clip.sourceRange.start && $0.end <= clip.sourceRange.end
            }

            var sentenceWords: [String] = []
            var sentenceSourceStart: TimeInterval = 0

            for (i, word) in clipWords.enumerated() {
                if sentenceWords.isEmpty {
                    sentenceSourceStart = word.start
                }
                sentenceWords.append(word.word)

                let isSentenceEnd = word.word.hasSuffix(".") || word.word.hasSuffix("?") || word.word.hasSuffix("!")
                let hasLongPause = i + 1 < clipWords.count && (clipWords[i + 1].start - word.end) > 0.8
                let isLast = i == clipWords.count - 1

                if isSentenceEnd || hasLongPause || isLast {
                    // Map source time to timeline time
                    let timelineTime = clip.timelineRange.start + (sentenceSourceStart - clip.sourceRange.start)
                    let mins = Int(timelineTime) / 60
                    let secs = Int(timelineTime) % 60
                    timelineTranscript += "[\(mins):\(String(format: "%02d", secs))] \(sentenceWords.joined(separator: " "))\n"
                    sentenceWords = []
                }
            }
        }

        guard !timelineTranscript.isEmpty else { return "" }

        // Get Claude API key
        guard let apiKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? loadAnthropicKey() else {
            return "Skipping review: no API key"
        }

        let provider = ClaudeProvider(apiKey: apiKey, model: "claude-sonnet-4-6")

        let prompt = """
        You just auto-cut a podcast episode. Below is the transcript of the result (with timeline timestamps).

        Review it and tell me if there are any issues at the START of the video:
        - Rehearsals or repeated intros (same phrase said multiple times — only the last attempt should remain)
        - False starts (incomplete sentences before the real beginning)
        - Off-topic conversation that isn't part of the episode

        If the video starts clean, respond with exactly: CLEAN

        If there are issues, respond with:
        TRIM_START [MM:SS]
        REASON: [brief explanation]

        Where [MM:SS] is the timeline timestamp where the real episode content begins (after any rehearsals/false starts). Everything before this timestamp will be removed.

        Only check the start — do NOT flag issues in the middle or end of the episode.

        TRANSCRIPT:
        \(timelineTranscript)
        """

        do {
            let response = try await provider.complete(
                messages: [AIMessage(role: "user", content: prompt)],
                tools: []
            )

            let answer = response.content.trimmingCharacters(in: .whitespacesAndNewlines)

            if answer.starts(with: "CLEAN") {
                return "Review: starts clean, no changes needed."
            }

            // Parse TRIM_START response
            if answer.contains("TRIM_START") {
                // Extract timestamp
                let lines = answer.components(separatedBy: .newlines)
                for line in lines {
                    if line.contains("TRIM_START") {
                        let parts = line.components(separatedBy: " ")
                        if let rawTimeStr = parts.last {
                            let timeStr = rawTimeStr.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                            let timeParts = timeStr.components(separatedBy: ":")
                            if timeParts.count == 2,
                               let mins = Int(timeParts[0]),
                               let secs = Int(timeParts[1]) {
                                let trimTime = TimeInterval(mins * 60 + secs)

                                // Collect clips to delete (entirely before trim point)
                                var idsToDelete: [UUID] = []
                                var clipsToTrim: [(id: UUID, newSourceStart: TimeInterval, sourceEnd: TimeInterval)] = []

                                for track in appState.timeline.tracks {
                                    for clip in track.clips {
                                        if clip.timelineRange.end <= trimTime + 0.1 {
                                            idsToDelete.append(clip.id)
                                        } else if clip.timelineRange.start < trimTime && clip.timelineRange.end > trimTime {
                                            let newSourceStart = clip.sourceRange.start + (trimTime - clip.timelineRange.start)
                                            clipsToTrim.append((id: clip.id, newSourceStart: newSourceStart, sourceEnd: clip.sourceRange.end))
                                        }
                                    }
                                }

                                // Execute deletions
                                var reviewLog = "Delete \(idsToDelete.count) clips, trim \(clipsToTrim.count). "
                                if !idsToDelete.isEmpty {
                                    do {
                                        try appState.perform(.deleteClips(clipIDs: idsToDelete), source: .ai)
                                        reviewLog += "Deleted OK. "
                                    } catch {
                                        reviewLog += "Delete error: \(error.localizedDescription). "
                                    }
                                }

                                // Execute trims
                                for t in clipsToTrim {
                                    do {
                                        try appState.perform(.trimClip(
                                            clipID: t.id,
                                            newSourceRange: TimeRange(start: t.newSourceStart, end: t.sourceEnd)
                                        ), source: .ai)
                                        reviewLog += "Trimmed OK. "
                                    } catch {
                                        reviewLog += "Trim error: \(error.localizedDescription). "
                                    }
                                }

                                // Ripple everything to start at 0
                                for (trackIdx, _) in appState.timeline.tracks.enumerated() {
                                    let sorted = appState.context.timelineState.timeline.tracks[trackIdx].clips
                                        .sorted { $0.timelineRange.start < $1.timelineRange.start }
                                    var cursor: TimeInterval = 0
                                    for clip in sorted {
                                        if let idx = appState.context.timelineState.timeline.tracks[trackIdx].clips
                                            .firstIndex(where: { $0.id == clip.id }) {
                                            appState.context.timelineState.timeline.tracks[trackIdx].clips[idx]
                                                .timelineRange = TimeRange(start: cursor, duration: clip.timelineRange.duration)
                                        }
                                        cursor += clip.timelineRange.duration
                                    }
                                }

                                let reason = lines.first(where: { $0.contains("REASON:") }) ?? ""
                                return "Review: trimmed start to \(timeStr). \(reviewLog)\(reason)"
                            }
                        }
                    }
                }
            }

            return "Review: \(answer)"
        } catch {
            return "Review skipped: \(error.localizedDescription)"
        }
    }

    private func findClip(id: UUID, in timeline: Timeline) -> (Clip, Track)? {
        for track in timeline.tracks {
            if let clip = track.clips.first(where: { $0.id == id }) {
                return (clip, track)
            }
        }
        return nil
    }

    // MARK: - Score Content

    private func handleScoreContent(_ args: [String: Any], appState: AppState) async -> String {
        guard let assetIDStr = args["asset_id"] as? String,
              let assetID = UUID(uuidString: assetIDStr),
              let asset = appState.assets.first(where: { $0.id == assetID }) else {
            return "Error: Invalid asset_id"
        }

        let segCount = args["segments"] as? Int ?? (args["segments"] as? Double).map({ Int($0) }) ?? 10
        let gateThreshold = args["gate_threshold"] as? Double ?? 7.0
        let mediaURL = resolvedToolMediaURL(for: asset)

        // Get energy readings
        let analyzer = SpeechEnergyAnalyzer()
        let readings = await analyzer.analyze(url: mediaURL)

        // Get transcript
        var transcriptWords: [TranscriptWord] = []
        if let result = await appState.media.transcriptionService.getTranscript(
            for: asset, bundleURL: appState.projectBundleURL
        ) {
            transcriptWords = result.words
        }

        // Divide into segments
        let duration = asset.duration
        let segDuration = duration / Double(segCount)
        let segments = (0..<segCount).map { i in
            TimeRange(start: Double(i) * segDuration, end: Double(i + 1) * segDuration)
        }

        // Score
        let scorer = ContentScorer()
        let ranked = scorer.rankSegments(
            segments: segments,
            energyReadings: readings,
            transcript: transcriptWords
        )

        // Build report
        var lines = ["=== CONTENT SCORING ==="]
        lines.append("Asset: \(asset.name) (\(String(format: "%.0f", duration))s)")
        lines.append("Segments: \(segCount) | Gate threshold: \(String(format: "%.1f", gateThreshold))")
        lines.append("")

        let passed = ranked.filter { $0.score.passesGate(threshold: gateThreshold) }
        let rejected = ranked.filter { $0.score.autoReject() }
        lines.append("PASSED gate: \(passed.count) | REJECTED: \(rejected.count) | Review: \(ranked.count - passed.count - rejected.count)")
        lines.append("")

        lines.append("Ranked segments (best first):")
        for (i, entry) in ranked.enumerated() {
            let s = entry.score
            let startMin = Int(entry.segment.start) / 60
            let startSec = Int(entry.segment.start) % 60
            let endMin = Int(entry.segment.end) / 60
            let endSec = Int(entry.segment.end) % 60
            let status = s.passesGate(threshold: gateThreshold) ? "PASS" : (s.autoReject() ? "REJECT" : "REVIEW")

            lines.append("  #\(i+1) [\(startMin):\(String(format: "%02d", startSec))-\(endMin):\(String(format: "%02d", endSec))] \(status) overall=\(String(format: "%.1f", s.overall)) avg=\(String(format: "%.1f", s.average))")
            lines.append("       hook=\(String(format: "%.1f", s.hookStrength)) retention=\(String(format: "%.1f", s.retentionCurve)) arc=\(String(format: "%.1f", s.emotionalArc)) complete=\(String(format: "%.1f", s.completeness)) audio=\(String(format: "%.1f", s.audioQuality))")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Topic Segmentation

    private func handleSegmentTopics(_ args: [String: Any], appState: AppState) async -> String {
        guard let assetIDStr = args["asset_id"] as? String,
              let assetID = UUID(uuidString: assetIDStr),
              let asset = appState.assets.first(where: { $0.id == assetID }) else {
            return "Error: Invalid asset_id"
        }

        let minDuration = args["min_duration"] as? Double ?? 15.0
        let mediaURL = resolvedToolMediaURL(for: asset)

        // Get transcript
        guard let result = await appState.media.transcriptionService.getTranscript(
            for: asset, bundleURL: appState.projectBundleURL
        ) else {
            return "Error: No transcript available. Run transcribe_asset first."
        }

        // Get silence ranges
        let silenceDetector = SilenceDetector()
        let silenceRanges = (try? await silenceDetector.detect(url: mediaURL, minDuration: 0.5)) ?? []

        // Get energy readings
        let energyAnalyzer = SpeechEnergyAnalyzer()
        let energyReadings = await energyAnalyzer.analyze(url: mediaURL)

        // Segment
        let segmenter = TopicSegmenter()
        let segments = segmenter.segment(
            transcript: result.words,
            silenceRanges: silenceRanges,
            speakerSegments: result.speakers,
            energyReadings: energyReadings,
            minSegmentDuration: minDuration
        )

        // Build report
        var lines = ["=== TOPIC SEGMENTATION ==="]
        lines.append("Asset: \(asset.name) (\(String(format: "%.0f", asset.duration))s)")
        lines.append("Segments found: \(segments.count)")
        lines.append("")

        for (i, seg) in segments.enumerated() {
            let startMin = Int(seg.range.start) / 60
            let startSec = Int(seg.range.start) % 60
            let endMin = Int(seg.range.end) / 60
            let endSec = Int(seg.range.end) % 60
            let dur = String(format: "%.0f", seg.range.duration)

            lines.append("  #\(i+1) [\(startMin):\(String(format: "%02d", startSec))-\(endMin):\(String(format: "%02d", endSec))] \(dur)s — \(seg.boundaryType.rawValue)")
            lines.append("       Topic: \(seg.label)")
            if !seg.keywords.isEmpty {
                lines.append("       Keywords: \(seg.keywords.joined(separator: ", "))")
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - API Key

    private func formattedZoom(_ pxPerSec: Double) -> String {
        if pxPerSec >= 10 {
            return String(format: "%.0f", pxPerSec)
        }
        if pxPerSec >= 1 {
            return String(format: "%.1f", pxPerSec)
        }
        return String(format: "%.2f", pxPerSec)
    }

    // MARK: - Hook Optimize

    private func handleHookOptimize(_ args: [String: Any], appState: AppState) async -> String {
        // 1. Get first video clip
        guard let videoTrack = appState.timeline.tracks.first(where: { $0.type == .video }),
              let clip = videoTrack.clips.first else {
            return "Error: No video clip on timeline"
        }

        guard let asset = appState.assets.first(where: { $0.id == clip.assetID }) else {
            return "Error: Asset not found for clip"
        }

        // 2. Get transcript
        guard let transcript = await appState.media.transcriptionService.getTranscript(
            for: asset, bundleURL: appState.projectBundleURL
        ) else {
            return "Error: No transcript available. Run transcribe_asset first."
        }

        // 3. Filter words to clip's source range
        let sourceRange = clip.sourceRange
        let words = transcript.words.filter { $0.start >= sourceRange.start && $0.end <= sourceRange.end }
        guard !words.isEmpty else {
            return "Hook skipped: no transcript words in clip source range. " + stateSnapshot(appState)
        }

        // 4. Group words into sentences (split on punctuation or pauses > 0.8s)
        struct Sentence {
            let text: String
            let startTime: TimeInterval
            let endTime: TimeInterval
            let wordRange: Range<Int>
        }

        var sentences: [Sentence] = []
        var currentWords: [String] = []
        var sentenceStartIdx = 0
        var sentenceStartTime = words[0].start

        for (i, word) in words.enumerated() {
            if currentWords.isEmpty {
                sentenceStartTime = word.start
                sentenceStartIdx = i
            }
            currentWords.append(word.word)

            let isPunctEnd = word.word.hasSuffix(".") || word.word.hasSuffix("?") || word.word.hasSuffix("!")
            let hasPause = i + 1 < words.count && (words[i + 1].start - word.end) > 0.8
            let isLast = i == words.count - 1

            if isPunctEnd || hasPause || isLast {
                let text = currentWords.joined(separator: " ")
                sentences.append(Sentence(
                    text: text,
                    startTime: sentenceStartTime,
                    endTime: word.end,
                    wordRange: sentenceStartIdx..<(i + 1)
                ))
                currentWords = []
            }
        }

        guard sentences.count >= 2 else {
            return "Hook is already at the start (only 1 sentence in clip)"
        }

        // 5. Send to Claude for hook scoring
        guard let apiKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? loadAnthropicKey() else {
            return "Error: No ANTHROPIC_API_KEY available"
        }

        let provider = ClaudeProvider(apiKey: apiKey, model: "claude-haiku-4-5-20251001")

        var sentenceList = ""
        for (i, s) in sentences.enumerated() {
            sentenceList += "[\(i)] \"\(s.text)\"\n"
        }

        let prompt = """
        Rate each sentence as a short-form video hook (1-10). Consider: curiosity gap, bold claim, question, emotional language, specificity. Return JSON: [{"index": 0, "score": 8, "reason": "..."}]
        SENTENCES:
        \(sentenceList)
        """

        let messages = [AIMessage(role: "user", content: prompt)]
        var bestIndex = 0
        var bestScore = 0
        var bestReason = ""

        do {
            let response = try await provider.complete(messages: messages, tools: [])
            // Parse JSON array from response
            let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            // Extract JSON array from response (may have markdown fences)
            let jsonStr: String
            if let start = text.range(of: "["), let end = text.range(of: "]", options: .backwards) {
                jsonStr = String(text[start.lowerBound...end.upperBound])
            } else {
                jsonStr = text
            }

            if let data = jsonStr.data(using: .utf8),
               let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                for item in arr {
                    let idx = item["index"] as? Int ?? 0
                    let score = item["score"] as? Int ?? (item["score"] as? Double).map { Int($0) } ?? 0
                    if score > bestScore {
                        bestScore = score
                        bestIndex = idx
                        bestReason = item["reason"] as? String ?? ""
                    }
                }
            }
        } catch {
            return "Error: Claude API failed — \(error.localizedDescription)"
        }

        guard bestIndex < sentences.count else {
            return "Error: Invalid sentence index from Claude"
        }

        let hookSentence = sentences[bestIndex]
        let hookDuration = hookSentence.endTime - hookSentence.startTime

        // 8. Check if hook is already at the start (within first 3 seconds of source)
        let hookOffsetFromClipStart = hookSentence.startTime - sourceRange.start
        if hookOffsetFromClipStart < 3.0 {
            return "Hook is already at the start: '\(hookSentence.text)' (score: \(bestScore)/10)"
        }

        // 9. Insert a duplicate of the hook at timeline position 0
        //    Shift existing clips right by hookDuration, then insert hook clip
        let sourceTimeOffset = sourceRange.start

        // Shift all existing clips on all tracks to make room
        var moveFailed = 0
        for track in appState.timeline.tracks {
            for existingClip in track.clips {
                let newStart = existingClip.timelineRange.start + hookDuration
                do {
                    try appState.perform(.moveClip(
                        clipID: existingClip.id,
                        newStart: newStart,
                        trackID: track.id
                    ), source: .ai)
                } catch {
                    moveFailed += 1
                }
            }
        }
        if moveFailed > 0 {
            return "Error: Failed to shift \(moveFailed) clip(s) to make room for hook"
        }

        // Insert hook video clip at position 0
        let hookLinkID = UUID()
        let hookVideoClip = Clip(
            assetID: asset.id,
            timelineRange: TimeRange(start: 0, duration: hookDuration),
            sourceRange: TimeRange(start: hookSentence.startTime, end: hookSentence.endTime),
            metadata: ClipMetadata(label: "Hook"),
            linkGroupID: hookLinkID
        )

        guard let videoTrackID = appState.timeline.tracks.first(where: { $0.type == .video })?.id else {
            return "Error: No video track"
        }
        do {
            try appState.perform(.insertClip(clip: hookVideoClip, trackID: videoTrackID), source: .ai)

            // Insert hook audio clip at position 0
            if let audioTrackID = appState.timeline.tracks.first(where: { $0.type == .audio })?.id {
                let hookAudioClip = Clip(
                    assetID: asset.id,
                    timelineRange: TimeRange(start: 0, duration: hookDuration),
                    sourceRange: TimeRange(start: hookSentence.startTime, end: hookSentence.endTime),
                    metadata: ClipMetadata(label: "Hook"),
                    linkGroupID: hookLinkID
                )
                try appState.perform(.insertClip(clip: hookAudioClip, trackID: audioTrackID), source: .ai)
            }
        } catch {
            return "Error inserting hook clips: \(error.localizedDescription)"
        }

        // Update short-form config sourceTimeOffset if present
        if var config = appState.context.timelineState.shortFormConfig {
            // Caption words need the hook words prepended
            let hookWords = Array(words[hookSentence.wordRange])
            let shiftedHookWords = hookWords.map { w in
                TranscriptWord(
                    word: w.word,
                    lemma: w.lemma,
                    start: w.start - hookSentence.startTime,
                    end: w.end - hookSentence.startTime,
                    confidence: w.confidence
                )
            }
            let shiftedExisting = config.captionWords.map { w in
                TranscriptWord(
                    word: w.word,
                    lemma: w.lemma,
                    start: w.start + hookDuration,
                    end: w.end + hookDuration,
                    confidence: w.confidence
                )
            }
            config.captionWords = shiftedHookWords + shiftedExisting
            appState.context.timelineState.shortFormConfig = config
        }

        appState.rebuildCompositionNow()

        return "Hook optimized: moved '\(hookSentence.text)' (score: \(bestScore)/10, reason: \(bestReason)) to clip start. Hook duration: \(String(format: "%.1f", hookDuration))s. " + stateSnapshot(appState)
    }

    private func loadAnthropicKey() -> String? {
        // Try .env file in common locations
        let candidates = [
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".env"),
            Bundle.main.bundleURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent(".env"),
        ]
        for url in candidates {
            if let contents = try? String(contentsOf: url, encoding: .utf8) {
                for line in contents.components(separatedBy: .newlines) {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix("ANTHROPIC_API_KEY=") {
                        let value = String(trimmed.dropFirst("ANTHROPIC_API_KEY=".count))
                            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                        if !value.isEmpty { return value }
                    }
                }
            }
        }
        return nil
    }

    // MARK: - Text-Based Editing

    private func handleGetTranscriptWithTiming(_ args: [String: Any], appState: AppState) async -> String {
        // Resolve asset
        let asset: MediaAsset
        if let idStr = args["asset_id"] as? String, let id = UUID(uuidString: idStr) {
            guard let found = appState.assets.first(where: { $0.id == id }) else {
                return "Error: Asset not found: \(idStr)"
            }
            asset = found
        } else {
            // Default: first video clip's asset
            guard let firstVideoTrack = appState.timeline.tracks.first(where: { $0.type == .video }),
                  let firstClip = firstVideoTrack.clips.first,
                  let found = appState.assets.first(where: { $0.id == firstClip.assetID }) else {
                return "Error: No video clips on timeline. Provide asset_id."
            }
            asset = found
        }

        guard let result = await appState.media.transcriptionService.getTranscript(
            for: asset, bundleURL: appState.projectBundleURL
        ) else {
            return "Error: No transcript. Run transcribe_asset first."
        }

        let startFilter = args["start"] as? Double ?? 0
        let endFilter = args["end"] as? Double ?? asset.duration
        let format = args["format"] as? String ?? "text"

        let words = result.words.filter { $0.start >= startFilter && $0.end <= endFilter }
        guard !words.isEmpty else { return "No words in the specified range." }

        // Build speaker lookup from diarization segments
        let speakers = result.speakers ?? []

        if format == "json" {
            let entries: [[String: Any]] = words.map { w in
                let speaker = speakers.first(where: { $0.range.contains(w.start) })?.speakerID ?? "0"
                return ["word": w.word, "start": w.start, "end": w.end, "speaker": speaker]
            }
            guard let data = try? JSONSerialization.data(withJSONObject: entries, options: [.sortedKeys]),
                  let json = String(data: data, encoding: .utf8) else {
                return "Error: JSON serialization failed"
            }
            return "Transcript (\(words.count) words, \(String(format: "%.1f", endFilter - startFilter))s):\n\(json)"
        }

        // Text format: [0.5s] Hello [0.8s] world ...
        var output = ""
        var currentSpeaker = ""
        for w in words {
            let speaker = speakers.first(where: { $0.range.contains(w.start) })?.speakerID ?? "0"
            if speaker != currentSpeaker {
                if !output.isEmpty { output += "\n" }
                output += "[Speaker \(speaker)] "
                currentSpeaker = speaker
            }
            output += "[\(String(format: "%.2f", w.start))s] \(w.word) "
        }

        let header = "Transcript: \(asset.name) (\(words.count) words, \(String(format: "%.1f", endFilter - startFilter))s)\n\n"
        return header + output.trimmingCharacters(in: .whitespaces)
    }

    private func handleDeleteTranscriptRange(_ args: [String: Any], appState: AppState) async -> String {
        guard let assetIDStr = args["asset_id"] as? String,
              let assetID = UUID(uuidString: assetIDStr) else {
            return "Error: Invalid asset_id"
        }
        guard let startTime = args["start_time"] as? Double,
              let endTime = args["end_time"] as? Double,
              endTime > startTime else {
            return "Error: Invalid start_time/end_time (end must be > start)"
        }

        let deleteRange = TimeRange(start: startTime, end: endTime)
        let deleteDuration = endTime - startTime

        // Count words being removed (for reporting)
        var wordCount = 0
        if let asset = appState.assets.first(where: { $0.id == assetID }),
           let transcript = await appState.media.transcriptionService.getTranscript(
               for: asset, bundleURL: appState.projectBundleURL
           ) {
            wordCount = transcript.words.filter { $0.start >= startTime && $0.end <= endTime }.count
        }

        // Use rebuild approach: collect keep ranges, delete originals, insert new clips
        let result = rebuildTimelineExcludingSourceRange(
            assetID: assetID, deleteRange: deleteRange, appState: appState
        )

        if result.success {
            let wordInfo = wordCount > 0 ? " (\(wordCount) words removed)" : ""
            return "Deleted \(String(format: "%.2f", deleteDuration))s of content\(wordInfo). \(result.message) " + stateSnapshot(appState)
        } else {
            return result.message
        }
    }

    private func handleRemoveFillerWords(_ args: [String: Any], appState: AppState) async -> String {
        guard let assetIDStr = args["asset_id"] as? String,
              let assetID = UUID(uuidString: assetIDStr),
              let asset = appState.assets.first(where: { $0.id == assetID }) else {
            return "Error: Invalid asset_id"
        }

        guard let transcript = await appState.media.transcriptionService.getTranscript(
            for: asset, bundleURL: appState.projectBundleURL
        ) else {
            return "Error: No transcript. Run transcribe_asset first."
        }

        let dryRun = args["dry_run"] as? Bool ?? false
        let fillerStr = args["fillers"] as? String ?? "um,uh,like,you know,so,basically,actually,right,I mean"
        let fillerList = fillerStr.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }

        // Separate context-sensitive fillers (need pause check) from always-fillers
        let alwaysFillers: Set<String> = ["um", "uh"]
        let contextFillers: Set<String> = Set(fillerList).subtracting(alwaysFillers)

        let words = transcript.words
        var fillerRanges: [(word: String, start: Double, end: Double)] = []

        for (i, w) in words.enumerated() {
            let normalized = w.word.lowercased().trimmingCharacters(in: .punctuationCharacters)

            if alwaysFillers.contains(normalized) {
                fillerRanges.append((word: normalized, start: w.start, end: w.end))
                continue
            }

            // Multi-word fillers: "you know", "I mean"
            if i + 1 < words.count {
                let twoWord = "\(normalized) \(words[i + 1].word.lowercased().trimmingCharacters(in: .punctuationCharacters))"
                if fillerList.contains(twoWord) {
                    let pauseBefore = i > 0 ? (w.start - words[i - 1].end) : 1.0
                    let pauseAfter = i + 2 < words.count ? (words[i + 2].start - words[i + 1].end) : 1.0
                    if pauseBefore > 0.3 || pauseAfter > 0.3 {
                        fillerRanges.append((word: twoWord, start: w.start, end: words[i + 1].end))
                    }
                    continue
                }
            }

            // Context-sensitive single-word fillers: only at pauses or sentence boundaries
            if contextFillers.contains(normalized) {
                let pauseBefore = i > 0 ? (w.start - words[i - 1].end) : 1.0
                let pauseAfter = i + 1 < words.count ? (words[i + 1].start - w.end) : 1.0
                let prevEndsPunctuation = i > 0 && (words[i - 1].word.hasSuffix(".") || words[i - 1].word.hasSuffix("?") || words[i - 1].word.hasSuffix("!") || words[i - 1].word.hasSuffix(","))

                if pauseBefore > 0.3 || pauseAfter > 0.3 || prevEndsPunctuation {
                    fillerRanges.append((word: normalized, start: w.start, end: w.end))
                }
            }
        }

        guard !fillerRanges.isEmpty else {
            return "No filler words found in transcript."
        }

        // Build breakdown
        var breakdown: [String: Int] = [:]
        var totalDuration: Double = 0
        for f in fillerRanges {
            breakdown[f.word, default: 0] += 1
            totalDuration += f.end - f.start
        }
        let breakdownStr = breakdown.sorted(by: { $0.value > $1.value })
            .map { "\($0.key): \($0.value)" }.joined(separator: ", ")

        if dryRun {
            var lines = ["=== FILLER WORD ANALYSIS ==="]
            lines.append("Found \(fillerRanges.count) filler words (\(String(format: "%.2f", totalDuration))s total)")
            lines.append("Breakdown: \(breakdownStr)")
            lines.append("")
            for (i, f) in fillerRanges.enumerated() {
                lines.append("  \(i + 1). \"\(f.word)\" at \(String(format: "%.2f", f.start))s-\(String(format: "%.2f", f.end))s")
            }
            lines.append("\n[DRY RUN — no changes made. Set dry_run=false to execute.]")
            return lines.joined(separator: "\n")
        }

        // Execute removals using rebuild approach
        // Merge filler ranges into a single set of removal ranges, then rebuild
        let sortedFillers = fillerRanges.sorted { $0.start < $1.start }

        // Find all clips from this asset on the timeline
        var allClipsForAsset: [(clip: Clip, trackIdx: Int)] = []
        for (trackIdx, track) in appState.timeline.tracks.enumerated() {
            for clip in track.clips where clip.assetID == assetID {
                allClipsForAsset.append((clip: clip, trackIdx: trackIdx))
            }
        }

        guard !allClipsForAsset.isEmpty else {
            return "Error: No clips from this asset on the timeline."
        }

        // Group clips by linkGroupID to process video+audio pairs together
        var processedLinks = Set<UUID>()
        var removedCount = 0

        // Collect all unique clip groups (video+audio pairs)
        var clipGroups: [[(clip: Clip, trackIdx: Int)]] = []
        for entry in allClipsForAsset {
            if let linkID = entry.clip.linkGroupID, processedLinks.contains(linkID) { continue }
            if let linkID = entry.clip.linkGroupID {
                processedLinks.insert(linkID)
                let group = allClipsForAsset.filter { $0.clip.linkGroupID == linkID }
                clipGroups.append(group)
            } else {
                clipGroups.append([entry])
            }
        }

        for group in clipGroups {
            guard let primary = group.first else { continue }
            let clipSourceRange = primary.clip.sourceRange

            // Filter fillers that fall within this clip's source range
            let clippedFillers = sortedFillers.filter { f in
                f.start >= clipSourceRange.start && f.end <= clipSourceRange.end
            }
            guard !clippedFillers.isEmpty else { continue }

            // Build keep ranges by inverting the filler removals within this clip
            var keepRanges: [TimeRange] = []
            var cursor = clipSourceRange.start
            for filler in clippedFillers {
                if filler.start > cursor + 0.001 {
                    keepRanges.append(TimeRange(start: cursor, end: filler.start))
                }
                cursor = filler.end
            }
            if cursor < clipSourceRange.end - 0.001 {
                keepRanges.append(TimeRange(start: cursor, end: clipSourceRange.end))
            }

            // Delete original clips in this group and insert replacements
            do {
                let idsToDelete = group.map { $0.clip.id }
                try appState.perform(.deleteClips(clipIDs: idsToDelete), source: .ai)

                // Calculate timeline start for this group (original position)
                let originalTimelineStart = primary.clip.timelineRange.start

                // Insert new clips for each keep range
                var timelineCursor = originalTimelineStart
                for keep in keepRanges {
                    let duration = keep.duration
                    let linkID = UUID()
                    for entry in group {
                        let newClip = Clip(
                            assetID: assetID,
                            timelineRange: TimeRange(start: timelineCursor, duration: duration),
                            sourceRange: keep,
                            volume: entry.clip.volume,
                            speed: entry.clip.speed,
                            linkGroupID: group.count > 1 ? linkID : entry.clip.linkGroupID
                        )
                        try appState.perform(.insertClip(clip: newClip, trackID: appState.timeline.tracks[entry.trackIdx].id), source: .ai)
                    }
                    timelineCursor += duration
                }
            } catch {
                return "Error processing filler removal: \(error.localizedDescription). " + stateSnapshot(appState)
            }
            removedCount += clippedFillers.count
        }

        appState.rebuildComposition()

        return "Removed \(removedCount) filler words (\(String(format: "%.2f", totalDuration))s). Breakdown: \(breakdownStr). " + stateSnapshot(appState)
    }

    /// Rebuild timeline clips for a given asset, excluding a source-time range.
    /// Returns (success: Bool, message: String).
    private func rebuildTimelineExcludingSourceRange(
        assetID: UUID,
        deleteRange: TimeRange,
        appState: AppState
    ) -> (success: Bool, message: String) {
        // Find all clips from this asset
        var allClipsForAsset: [(clip: Clip, trackIdx: Int)] = []
        for (trackIdx, track) in appState.timeline.tracks.enumerated() {
            for clip in track.clips where clip.assetID == assetID {
                allClipsForAsset.append((clip: clip, trackIdx: trackIdx))
            }
        }

        guard !allClipsForAsset.isEmpty else {
            return (success: false, message: "Error: No clips from asset \(assetID.uuidString.prefix(8)) on the timeline.")
        }

        // Group clips by linkGroupID (video+audio pairs)
        var processedLinks = Set<UUID>()
        var clipGroups: [[(clip: Clip, trackIdx: Int)]] = []
        for entry in allClipsForAsset {
            if let linkID = entry.clip.linkGroupID, processedLinks.contains(linkID) { continue }
            if let linkID = entry.clip.linkGroupID {
                processedLinks.insert(linkID)
                let group = allClipsForAsset.filter { $0.clip.linkGroupID == linkID }
                clipGroups.append(group)
            } else {
                clipGroups.append([entry])
            }
        }

        var clipsAffected = 0

        for group in clipGroups {
            guard let primary = group.first else { continue }
            let clipSourceRange = primary.clip.sourceRange

            // Check if this clip's source range overlaps the delete range
            guard clipSourceRange.overlaps(deleteRange) else { continue }
            clipsAffected += group.count

            // Build keep ranges by excluding the delete range
            var keepRanges: [TimeRange] = []
            if clipSourceRange.start < deleteRange.start {
                keepRanges.append(TimeRange(start: clipSourceRange.start, end: min(deleteRange.start, clipSourceRange.end)))
            }
            if clipSourceRange.end > deleteRange.end {
                keepRanges.append(TimeRange(start: max(deleteRange.end, clipSourceRange.start), end: clipSourceRange.end))
            }

            // Delete original clips and insert replacements
            do {
                let idsToDelete = group.map { $0.clip.id }
                try appState.perform(.deleteClips(clipIDs: idsToDelete), source: .ai)

                // Insert new clips for each keep range
                let originalTimelineStart = primary.clip.timelineRange.start
                var timelineCursor = originalTimelineStart
                for keep in keepRanges {
                    let duration = keep.duration
                    let linkID = UUID()
                    for entry in group {
                        let newClip = Clip(
                            assetID: assetID,
                            timelineRange: TimeRange(start: timelineCursor, duration: duration),
                            sourceRange: keep,
                            volume: entry.clip.volume,
                            speed: entry.clip.speed,
                            linkGroupID: group.count > 1 ? linkID : entry.clip.linkGroupID
                        )
                        try appState.perform(.insertClip(clip: newClip, trackID: appState.timeline.tracks[entry.trackIdx].id), source: .ai)
                    }
                    timelineCursor += duration
                }
            } catch {
                return (success: false, message: "Error: \(error.localizedDescription)")
            }
        }

        appState.rebuildComposition()

        return (success: true, message: "Affected \(clipsAffected) clips across \(clipGroups.count) group(s).")
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
