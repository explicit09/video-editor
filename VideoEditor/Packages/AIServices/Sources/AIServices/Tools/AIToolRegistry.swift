import Foundation
import EditorCore

/// Registry of all tools available to AI models.
/// Each tool maps to EditorIntents — same execution path as human actions.
public struct AIToolRegistry: Sendable {

    public static let allTools: [AIToolDefinition] = [
        addTrack,
        insertClip,
        moveClip,
        deleteClips,
        splitClip,
        trimClip,
        setMarker,
        removeSilence,
        setClipVolume,
        setClipOpacity,
        setClipSpeed,
        muteTrack,
        duplicateClip,
        setClipEffect,
        removeSection,
        rippleDelete,
        normalizeAudio,
        removeTrack,
        lockTrack,
        setTrackVolume,
        renameClip,
        setClipTransition,
        deleteMarker,
        setClipTransform,
        rollTrim,
        autoReframe,
        detectBeats,
        scoreThumbnails,
        suggestBroll,
        applyPersonMask,
        trackObject,
        voiceCleanup,
        denoiseAudio,
        denoiseVideo,
        stabilizeVideo,
        setCaptionStyle,
        applyLUT,
        measureLoudness,
        autoDuck,
        chromaKey,
        getTranscript,
        transcribeAsset,
        searchTranscript,
        deleteAsset,
        setOverlayConfig,
        getOverlayConfig,
    ]

    // MARK: - Content tools (request data on demand, save tokens)

    public static let getTranscript = AIToolDefinition(
        name: "get_transcript",
        description: "Get the transcript text for a specific asset or clip. Call this ONLY when you need to read what's being said (e.g., finding ums, searching for topics, content-aware editing). Do NOT call for structural edits like moving/splitting/deleting clips.",
        parameters: .object([
            "asset_id": .init(type: "string", description: "UUID of the asset to get transcript for"),
        ], required: ["asset_id"])
    )

    public static let transcribeAsset = AIToolDefinition(
        name: "transcribe_asset",
        description: "Transcribe a media asset that hasn't been transcribed yet. This sends audio to a transcription service and may take a moment. Only call if get_transcript returns no transcript.",
        parameters: .object([
            "asset_id": .init(type: "string", description: "UUID of the asset to transcribe"),
        ], required: ["asset_id"])
    )

    public static let searchTranscript = AIToolDefinition(
        name: "search_transcript",
        description: "Search across all transcribed assets for mentions of a word or phrase. Returns matching timestamps with surrounding context. Assets must be transcribed first.",
        parameters: .object([
            "query": .init(type: "string", description: "Text to search for in transcripts"),
            "asset_id": .init(type: "string", description: "Optional: search only this asset (omit to search all)"),
            "max_results": .init(type: "number", description: "Maximum results to return (default 10)"),
        ], required: ["query"])
    )

    public static let deleteAsset = AIToolDefinition(
        name: "delete_asset",
        description: "Remove an imported asset from the media library. Cannot delete assets that are currently used by clips on the timeline. Use to clean up unused or duplicate imports.",
        parameters: .object([
            "asset_id": .init(type: "string", description: "UUID of the asset to delete"),
        ], required: ["asset_id"])
    )

    public static let setOverlayConfig = AIToolDefinition(
        name: "set_overlay_config",
        description: "Set broadcast overlay configuration. Renders professional graphics over the video: episode title card (0-30s), host name bar, scrolling sponsor/topic ticker, chapter cards, and host intro strip (38-92s). Pass enabled=false to disable.",
        parameters: .object([
            "enabled": .init(type: "boolean", description: "Enable/disable overlay rendering"),
            "episode_title": .init(type: "string", description: "Episode title (uppercase)"),
            "episode_subtitle": .init(type: "string", description: "Episode subtitle"),
            "host_a_name": .init(type: "string", description: "Host A name"),
            "host_a_title": .init(type: "string", description: "Host A title"),
            "host_b_name": .init(type: "string", description: "Host B name"),
            "host_b_title": .init(type: "string", description: "Host B title"),
        ], required: [])
    )

    public static let getOverlayConfig = AIToolDefinition(
        name: "get_overlay_config",
        description: "Get the current broadcast overlay configuration.",
        parameters: .object([:], required: [])
    )

    // MARK: - Tool definitions (matching Claude/OpenAI function-calling schema)

    public static let addTrack = AIToolDefinition(
        name: "add_track",
        description: "Add a new track to the timeline. Returns the track ID for use in subsequent operations.",
        parameters: .object([
            "type": .init(type: "string", description: "Track type", enumValues: ["video", "audio", "text", "effect"]),
            "name": .init(type: "string", description: "Track name (optional)"),
            "track_id": .init(type: "string", description: "UUID to assign to the track (optional, auto-generated if omitted)"),
        ], required: ["type"])
    )

    public static let insertClip = AIToolDefinition(
        name: "insert_clip",
        description: "Insert a media asset as a clip on a track at a specific time position",
        parameters: .object([
            "asset_id": .init(type: "string", description: "UUID of the media asset to insert"),
            "track_id": .init(type: "string", description: "UUID of the target track"),
            "start_time": .init(type: "number", description: "Timeline position in seconds to insert at"),
            "duration": .init(type: "number", description: "Clip duration in seconds (defaults to asset duration)"),
        ], required: ["asset_id", "track_id", "start_time"])
    )

    public static let moveClip = AIToolDefinition(
        name: "move_clip",
        description: "Move a clip to a new position on the timeline",
        parameters: .object([
            "clip_id": .init(type: "string", description: "UUID of the clip to move"),
            "new_start": .init(type: "number", description: "New start time in seconds"),
            "track_id": .init(type: "string", description: "UUID of the target track"),
        ], required: ["clip_id", "new_start", "track_id"])
    )

    public static let deleteClips = AIToolDefinition(
        name: "delete_clips",
        description: "Delete one or more clips from the timeline",
        parameters: .object([
            "clip_ids": .init(type: "array", description: "Array of clip UUIDs to delete", items: .init(type: "string")),
        ], required: ["clip_ids"])
    )

    public static let splitClip = AIToolDefinition(
        name: "split_clip",
        description: "Split a clip into two parts at a specific time",
        parameters: .object([
            "clip_id": .init(type: "string", description: "UUID of the clip to split"),
            "at": .init(type: "number", description: "Timeline time in seconds to split at"),
        ], required: ["clip_id", "at"])
    )

    public static let trimClip = AIToolDefinition(
        name: "trim_clip",
        description: "Trim a clip by changing its source in/out points",
        parameters: .object([
            "clip_id": .init(type: "string", description: "UUID of the clip to trim"),
            "source_start": .init(type: "number", description: "New source start time in seconds"),
            "source_end": .init(type: "number", description: "New source end time in seconds"),
        ], required: ["clip_id", "source_start", "source_end"])
    )

    public static let setMarker = AIToolDefinition(
        name: "set_marker",
        description: "Add a marker at a specific time on the timeline",
        parameters: .object([
            "time": .init(type: "number", description: "Time in seconds"),
            "label": .init(type: "string", description: "Marker label"),
        ], required: ["time", "label"])
    )

    public static let removeSilence = AIToolDefinition(
        name: "remove_silence",
        description: "Remove silent segments from clips based on detected silence ranges",
        parameters: .object([
            "clip_ids": .init(type: "array", description: "Clip UUIDs to remove silence from (empty = all clips)", items: .init(type: "string")),
            "threshold_db": .init(type: "number", description: "Silence threshold in dB (default: -40)"),
            "min_duration": .init(type: "number", description: "Minimum silence duration in seconds to remove (default: 0.5)"),
        ], required: [])
    )

    public static let setClipVolume = AIToolDefinition(
        name: "set_clip_volume",
        description: "Set the audio volume of a clip. 1.0 = normal, 0.0 = silent, 2.0 = double volume",
        parameters: .object([
            "clip_id": .init(type: "string", description: "UUID of the clip to adjust"),
            "volume": .init(type: "number", description: "Volume level (0.0 to 2.0, default 1.0)"),
        ], required: ["clip_id", "volume"])
    )

    public static let setClipOpacity = AIToolDefinition(
        name: "set_clip_opacity",
        description: "Set the visual opacity of a clip. 1.0 = fully visible, 0.0 = transparent",
        parameters: .object([
            "clip_id": .init(type: "string", description: "UUID of the clip to adjust"),
            "opacity": .init(type: "number", description: "Opacity level (0.0 to 1.0)"),
        ], required: ["clip_id", "opacity"])
    )

    public static let setClipSpeed = AIToolDefinition(
        name: "set_clip_speed",
        description: "Set the playback speed of a clip. Changes clip duration proportionally.",
        parameters: .object([
            "clip_id": .init(type: "string", description: "UUID of the clip to adjust"),
            "speed": .init(type: "number", description: "Speed multiplier (0.25 = quarter speed, 1.0 = normal, 2.0 = double speed)"),
        ], required: ["clip_id", "speed"])
    )

    public static let muteTrack = AIToolDefinition(
        name: "mute_track",
        description: "Mute or unmute a track",
        parameters: .object([
            "track_id": .init(type: "string", description: "UUID of the track"),
            "muted": .init(type: "boolean", description: "true to mute, false to unmute"),
        ], required: ["track_id", "muted"])
    )

    public static let duplicateClip = AIToolDefinition(
        name: "duplicate_clip",
        description: "Duplicate a clip, placing the copy immediately after the original on the same track",
        parameters: .object([
            "clip_id": .init(type: "string", description: "UUID of the clip to duplicate"),
        ], required: ["clip_id"])
    )

    public static let setClipEffect = AIToolDefinition(
        name: "set_clip_effect",
        description: "Apply a visual effect to a clip. Supported types: colorCorrection (brightness/contrast/saturation/temperature), blur (radius), sharpen (sharpness).",
        parameters: .object([
            "clip_id": .init(type: "string", description: "UUID of the clip"),
            "effect_type": .init(type: "string", description: "Effect type: colorCorrection, blur, or sharpen"),
            "brightness": .init(type: "number", description: "Brightness adjustment (-1 to 1, default 0). Only for colorCorrection."),
            "contrast": .init(type: "number", description: "Contrast (0 to 4, default 1). Only for colorCorrection."),
            "saturation": .init(type: "number", description: "Saturation (0 to 3, default 1). Only for colorCorrection."),
            "temperature": .init(type: "number", description: "Color temperature in Kelvin (2000-10000, default 6500). Only for colorCorrection."),
            "radius": .init(type: "number", description: "Blur radius (0-100, default 10). Only for blur."),
            "sharpness": .init(type: "number", description: "Sharpness (0-2, default 0.4). Only for sharpen."),
        ], required: ["clip_id", "effect_type"])
    )

    // MARK: - Track management tools

    public static let removeTrack = AIToolDefinition(
        name: "remove_track",
        description: "Remove an empty track from the timeline. Fails if the track contains clips — delete all clips first.",
        parameters: .object([
            "track_id": .init(type: "string", description: "UUID of the track to remove"),
        ], required: ["track_id"])
    )

    public static let lockTrack = AIToolDefinition(
        name: "lock_track",
        description: "Lock or unlock a track. Locked tracks cannot be edited (no move, trim, split, delete on their clips).",
        parameters: .object([
            "track_id": .init(type: "string", description: "UUID of the track"),
            "locked": .init(type: "boolean", description: "true to lock, false to unlock"),
        ], required: ["track_id", "locked"])
    )

    public static let setTrackVolume = AIToolDefinition(
        name: "set_track_volume",
        description: "Set the volume level of an entire track. Affects all clips on the track during playback/export. Use for background music levels.",
        parameters: .object([
            "track_id": .init(type: "string", description: "UUID of the track"),
            "volume": .init(type: "number", description: "Volume level (0.0 to 2.0, default 1.0)"),
        ], required: ["track_id", "volume"])
    )

    public static let renameClip = AIToolDefinition(
        name: "rename_clip",
        description: "Change a clip's display label for organization.",
        parameters: .object([
            "clip_id": .init(type: "string", description: "UUID of the clip"),
            "label": .init(type: "string", description: "New label text"),
        ], required: ["clip_id", "label"])
    )

    public static let setClipTransition = AIToolDefinition(
        name: "set_clip_transition",
        description: "Set a transition effect on a clip's entry. Types: crossDissolve, fadeToBlack, fadeFromBlack, wipeLeft, wipeRight, none.",
        parameters: .object([
            "clip_id": .init(type: "string", description: "UUID of the clip"),
            "type": .init(type: "string", description: "Transition type"),
            "duration": .init(type: "number", description: "Transition duration in seconds (default 0.5)"),
        ], required: ["clip_id", "type"])
    )

    public static let deleteMarker = AIToolDefinition(
        name: "delete_marker",
        description: "Remove a marker from the timeline.",
        parameters: .object([
            "marker_id": .init(type: "string", description: "UUID of the marker to delete"),
        ], required: ["marker_id"])
    )

    // MARK: - Transform + Roll Trim

    public static let setClipTransform = AIToolDefinition(
        name: "set_clip_transform",
        description: "Set a clip's 2D transform: position, scale, rotation. Use for Ken Burns, picture-in-picture, or repositioning.",
        parameters: .object([
            "clip_id": .init(type: "string", description: "UUID of the clip"),
            "position_x": .init(type: "number", description: "X position offset (default 0)"),
            "position_y": .init(type: "number", description: "Y position offset (default 0)"),
            "scale_x": .init(type: "number", description: "Horizontal scale (1.0 = 100%, default 1)"),
            "scale_y": .init(type: "number", description: "Vertical scale (1.0 = 100%, default 1)"),
            "rotation": .init(type: "number", description: "Rotation in degrees (default 0)"),
        ], required: ["clip_id"])
    )

    public static let rollTrim = AIToolDefinition(
        name: "roll_trim",
        description: "Adjust the boundary between two adjacent clips. Extends one while shortening the other — total duration unchanged.",
        parameters: .object([
            "left_clip_id": .init(type: "string", description: "UUID of the left (outgoing) clip"),
            "right_clip_id": .init(type: "string", description: "UUID of the right (incoming) clip"),
            "new_boundary": .init(type: "number", description: "New boundary time in seconds"),
        ], required: ["left_clip_id", "right_clip_id", "new_boundary"])
    )

    // MARK: - Analysis tools (read-only, return data)

    public static let autoReframe = AIToolDefinition(
        name: "auto_reframe",
        description: "Analyze video and generate crop regions for a target aspect ratio. Tracks faces to keep subjects centered.",
        parameters: .object([
            "asset_id": .init(type: "string", description: "UUID of the asset to analyze"),
            "aspect_ratio": .init(type: "string", description: "Target: 9:16 (vertical), 1:1 (square), 4:5 (portrait), 16:9, 21:9"),
        ], required: ["asset_id", "aspect_ratio"])
    )

    public static let detectBeats = AIToolDefinition(
        name: "detect_beats",
        description: "Analyze audio BPM and beat timestamps. Use for syncing cuts to music.",
        parameters: .object([
            "asset_id": .init(type: "string", description: "UUID of the audio/video asset"),
        ], required: ["asset_id"])
    )

    public static let scoreThumbnails = AIToolDefinition(
        name: "score_thumbnails",
        description: "Find the best thumbnail frames in a video. Scores by face presence, brightness, and sharpness.",
        parameters: .object([
            "asset_id": .init(type: "string", description: "UUID of the video asset"),
            "count": .init(type: "number", description: "Number of top candidates to return (default 5)"),
        ], required: ["asset_id"])
    )

    public static let suggestBroll = AIToolDefinition(
        name: "suggest_broll",
        description: "Suggest B-roll clips from the media library that match transcript topics.",
        parameters: .object([:], required: [])
    )

    public static let applyPersonMask = AIToolDefinition(
        name: "apply_person_mask",
        description: "Apply AI person segmentation to isolate subjects from background. Uses Vision framework.",
        parameters: .object([
            "clip_id": .init(type: "string", description: "UUID of the video clip"),
            "action": .init(type: "string", description: "isolate (transparent bg), replace_color, or replace_image"),
        ], required: ["clip_id"])
    )

    public static let trackObject = AIToolDefinition(
        name: "track_object",
        description: "Track an object or face across video frames. Returns per-frame bounding box positions.",
        parameters: .object([
            "asset_id": .init(type: "string", description: "UUID of the video asset"),
            "track_type": .init(type: "string", description: "face (auto-detect) or region"),
            "start_time": .init(type: "number", description: "Time to start tracking (default 0)"),
        ], required: ["asset_id"])
    )

    public static let voiceCleanup = AIToolDefinition(
        name: "voice_cleanup",
        description: "One-click voice enhancement: noise reduction + EQ + compression. Presets: standard, podcast, interview, presentation, music.",
        parameters: .object([
            "clip_id": .init(type: "string", description: "UUID of the audio clip (optional — applies to all if omitted)"),
            "preset": .init(type: "string", description: "Cleanup preset (default: standard)"),
        ], required: [])
    )

    public static let denoiseAudio = AIToolDefinition(
        name: "denoise_audio",
        description: "Remove background noise from audio using a noise gate.",
        parameters: .object([
            "clip_id": .init(type: "string", description: "UUID of the clip"),
            "threshold_db": .init(type: "number", description: "Noise floor in dB (default -40)"),
        ], required: ["clip_id"])
    )

    public static let denoiseVideo = AIToolDefinition(
        name: "denoise_video",
        description: "Reduce digital noise/grain from video footage using CINoiseReduction.",
        parameters: .object([
            "clip_id": .init(type: "string", description: "UUID of the video clip"),
            "level": .init(type: "number", description: "Noise reduction level 0-1 (default 0.5)"),
        ], required: ["clip_id"])
    )

    public static let stabilizeVideo = AIToolDefinition(
        name: "stabilize_video",
        description: "Remove camera shake from video using motion analysis.",
        parameters: .object([
            "asset_id": .init(type: "string", description: "UUID of the video asset"),
            "smoothing": .init(type: "number", description: "Smoothing factor 0-1 (default 0.8, higher = smoother)"),
        ], required: ["asset_id"])
    )

    public static let setCaptionStyle = AIToolDefinition(
        name: "set_caption_style",
        description: "Set the caption/subtitle style. Styles: standard (pill), karaoke (word highlight), bold, outline, gradient.",
        parameters: .object([
            "style": .init(type: "string", description: "Caption style name"),
        ], required: ["style"])
    )

    public static let applyLUT = AIToolDefinition(
        name: "apply_lut",
        description: "Apply a .cube LUT file to a clip for color grading.",
        parameters: .object([
            "clip_id": .init(type: "string", description: "UUID of the clip"),
            "lut_path": .init(type: "string", description: "Path to the .cube LUT file"),
        ], required: ["clip_id", "lut_path"])
    )

    public static let measureLoudness = AIToolDefinition(
        name: "measure_loudness",
        description: "Measure the integrated loudness (LUFS) of an audio/video asset. Use to check levels before normalization.",
        parameters: .object([
            "asset_id": .init(type: "string", description: "UUID of the asset"),
        ], required: ["asset_id"])
    )

    public static let autoDuck = AIToolDefinition(
        name: "auto_duck",
        description: "Automatically duck music volume during speech. Analyzes transcript to find speech regions and lowers music.",
        parameters: .object([
            "music_track_id": .init(type: "string", description: "UUID of the music track"),
            "duck_level": .init(type: "number", description: "Volume during speech 0-1 (default 0.2)"),
        ], required: ["music_track_id"])
    )

    public static let chromaKey = AIToolDefinition(
        name: "chroma_key",
        description: "Remove green screen background from a clip. Apply chroma key based on target color.",
        parameters: .object([
            "clip_id": .init(type: "string", description: "UUID of the video clip"),
            "target_hue": .init(type: "number", description: "Hue to remove 0-1 (green=0.33, blue=0.66, default 0.33)"),
            "tolerance": .init(type: "number", description: "How much hue variation to include (default 0.1)"),
        ], required: ["clip_id"])
    )

    // MARK: - Compound tools (replace multi-step atomic sequences)

    public static let removeSection = AIToolDefinition(
        name: "remove_section",
        description: "Remove a time range from the timeline and close the gap. Splits at start and end, deletes the middle, then shifts subsequent clips left. Use this instead of manual split+delete+move sequences.",
        parameters: .object([
            "start_time": .init(type: "number", description: "Start of the section to remove (timeline seconds)"),
            "end_time": .init(type: "number", description: "End of the section to remove (timeline seconds)"),
            "track_id": .init(type: "string", description: "Track to operate on (optional — all tracks if omitted)"),
        ], required: ["start_time", "end_time"])
    )

    public static let rippleDelete = AIToolDefinition(
        name: "ripple_delete",
        description: "Delete clips and close the resulting gap by shifting subsequent clips left. Use instead of delete_clips when you want the timeline to contract.",
        parameters: .object([
            "clip_ids": .init(type: "array", description: "UUIDs of clips to delete", items: .init(type: "string")),
        ], required: ["clip_ids"])
    )

    public static let normalizeAudio = AIToolDefinition(
        name: "normalize_audio",
        description: "Adjust volume of multiple clips to a consistent level. Use instead of calling set_clip_volume on each clip individually.",
        parameters: .object([
            "clip_ids": .init(type: "array", description: "Clip UUIDs to normalize (empty = all audio clips)", items: .init(type: "string")),
            "target_volume": .init(type: "number", description: "Target volume level (default 1.0)"),
        ], required: [])
    )
}

// MARK: - AIToolDefinition (JSON Schema compatible)

public struct AIToolDefinition: Codable, Sendable {
    public let name: String
    public let description: String
    public let parameters: ParameterSchema

    public struct ParameterSchema: Codable, Sendable {
        public let type: String
        public let properties: [String: Property]?
        public let required: [String]?
        public let items: Property?

        public final class Property: Codable, Sendable {
            public let type: String
            public let description: String?
            public let enumValues: [String]?
            public let items: Property?

            enum CodingKeys: String, CodingKey {
                case type, description, items
                case enumValues = "enum"
            }

            public init(type: String, description: String? = nil, enumValues: [String]? = nil, items: Property? = nil) {
                self.type = type
                self.description = description
                self.enumValues = enumValues
                self.items = items
            }
        }

        public static func object(_ properties: [String: Property], required: [String] = []) -> ParameterSchema {
            ParameterSchema(type: "object", properties: properties, required: required, items: nil)
        }
    }
}

// MARK: - AIToolResolver (tool call arguments → EditorIntents)

public struct AIToolResolver: Sendable {

    public init() {}

    /// Resolve an AI tool call into EditorIntents.
    @MainActor
    public func resolve(toolName: String, arguments: [String: Any], assets: [MediaAsset] = []) throws -> [EditorIntent] {
        switch toolName {
        case "add_track":
            let typeStr = arguments["type"] as? String ?? "video"
            let name = arguments["name"] as? String ?? typeStr.capitalized
            guard let trackType = TrackType(rawValue: typeStr) else {
                throw AIToolError.invalidArgument("Unknown track type: \(typeStr)")
            }
            // Use AI-provided ID if given, so subsequent tool calls can reference it
            let trackID: UUID
            if let idStr = arguments["track_id"] as? String, let id = UUID(uuidString: idStr) {
                trackID = id
            } else {
                trackID = UUID()
            }
            return [.addTrack(track: Track(id: trackID, name: name, type: trackType))]

        case "insert_clip":
            guard let assetIDStr = arguments["asset_id"] as? String, let assetID = UUID(uuidString: assetIDStr) else {
                throw AIToolError.invalidArgument("Missing or invalid asset_id")
            }
            // Resolve track: try exact ID, then fall back to last track of matching type
            let trackID: UUID
            if let trackIDStr = arguments["track_id"] as? String, let id = UUID(uuidString: trackIDStr) {
                trackID = id
            } else {
                throw AIToolError.invalidArgument("Missing track_id")
            }
            let startTime = (arguments["start_time"] as? Double) ?? 0
            // Look up real asset duration, fall back to explicit duration param
            let assetDuration = assets.first(where: { $0.id == assetID })?.duration
            let duration = (arguments["duration"] as? Double) ?? assetDuration ?? 5

            let clip = Clip(
                assetID: assetID,
                timelineRange: TimeRange(start: startTime, duration: duration),
                sourceRange: TimeRange(start: 0, duration: duration),
                metadata: ClipMetadata(label: assets.first(where: { $0.id == assetID })?.name)
            )
            return [.insertClip(clip: clip, trackID: trackID)]

        case "move_clip":
            guard let clipIDStr = arguments["clip_id"] as? String, let clipID = UUID(uuidString: clipIDStr) else {
                throw AIToolError.invalidArgument("Missing or invalid clip_id")
            }
            guard let newStart = arguments["new_start"] as? Double else {
                throw AIToolError.invalidArgument("Missing new_start")
            }
            guard let trackIDStr = arguments["track_id"] as? String, let trackID = UUID(uuidString: trackIDStr) else {
                throw AIToolError.invalidArgument("Missing or invalid track_id")
            }
            return [.moveClip(clipID: clipID, newStart: newStart, trackID: trackID)]

        case "delete_clips":
            guard let idStrings = arguments["clip_ids"] as? [String] else {
                throw AIToolError.invalidArgument("Missing clip_ids array")
            }
            let ids = idStrings.compactMap { UUID(uuidString: $0) }
            guard !ids.isEmpty else { throw AIToolError.invalidArgument("No valid clip IDs") }
            return [.deleteClips(clipIDs: ids)]

        case "split_clip":
            guard let clipIDStr = arguments["clip_id"] as? String, let clipID = UUID(uuidString: clipIDStr) else {
                throw AIToolError.invalidArgument("Missing or invalid clip_id")
            }
            guard let at = arguments["at"] as? Double else {
                throw AIToolError.invalidArgument("Missing split time")
            }
            return [.splitClip(clipID: clipID, at: at)]

        case "trim_clip":
            guard let clipIDStr = arguments["clip_id"] as? String, let clipID = UUID(uuidString: clipIDStr) else {
                throw AIToolError.invalidArgument("Missing or invalid clip_id")
            }
            guard let start = arguments["source_start"] as? Double, let end = arguments["source_end"] as? Double else {
                throw AIToolError.invalidArgument("Missing source_start or source_end")
            }
            return [.trimClip(clipID: clipID, newSourceRange: TimeRange(start: start, end: end))]

        case "set_marker":
            guard let time = arguments["time"] as? Double else {
                throw AIToolError.invalidArgument("Missing time")
            }
            let label = arguments["label"] as? String ?? ""
            return [.setMarker(at: time, label: label)]

        case "remove_silence":
            // Handled upstream in AIChatController (needs AppState)
            return []

        case "set_clip_volume":
            guard let clipIDStr = arguments["clip_id"] as? String, let clipID = UUID(uuidString: clipIDStr) else {
                throw AIToolError.invalidArgument("Missing clip_id")
            }
            let volume = (arguments["volume"] as? Double) ?? 1.0
            return [.setClipVolume(clipID: clipID, volume: volume)]

        case "set_clip_opacity":
            guard let clipIDStr = arguments["clip_id"] as? String, let clipID = UUID(uuidString: clipIDStr) else {
                throw AIToolError.invalidArgument("Missing clip_id")
            }
            let opacity = (arguments["opacity"] as? Double) ?? 1.0
            return [.setClipOpacity(clipID: clipID, opacity: opacity)]

        case "set_clip_speed":
            guard let clipIDStr = arguments["clip_id"] as? String, let clipID = UUID(uuidString: clipIDStr) else {
                throw AIToolError.invalidArgument("Missing clip_id")
            }
            let speed = (arguments["speed"] as? Double) ?? 1.0
            return [.setClipSpeed(clipID: clipID, speed: speed)]

        case "mute_track":
            guard let trackIDStr = arguments["track_id"] as? String, let trackID = UUID(uuidString: trackIDStr) else {
                throw AIToolError.invalidArgument("Missing track_id")
            }
            let muted = (arguments["muted"] as? Bool) ?? true
            return [.muteTrack(trackID: trackID, muted: muted)]

        case "duplicate_clip":
            guard let clipIDStr = arguments["clip_id"] as? String, let clipID = UUID(uuidString: clipIDStr) else {
                throw AIToolError.invalidArgument("Missing clip_id")
            }
            return [.duplicateClip(clipID: clipID)]

        case "set_clip_effect":
            guard let clipIDStr = arguments["clip_id"] as? String, let clipID = UUID(uuidString: clipIDStr) else {
                throw AIToolError.invalidArgument("Missing clip_id")
            }
            let effectType = (arguments["effect_type"] as? String) ?? "colorCorrection"
            let effect: EffectInstance
            switch effectType {
            case "colorCorrection":
                effect = .colorCorrection(
                    brightness: (arguments["brightness"] as? Double) ?? 0,
                    contrast: (arguments["contrast"] as? Double) ?? 1,
                    saturation: (arguments["saturation"] as? Double) ?? 1,
                    temperature: (arguments["temperature"] as? Double) ?? 6500
                )
            case "blur":
                effect = EffectInstance(type: "blur", parameters: ["radius": (arguments["radius"] as? Double) ?? 10])
            case "sharpen":
                effect = EffectInstance(type: "sharpen", parameters: ["sharpness": (arguments["sharpness"] as? Double) ?? 0.4])
            default:
                throw AIToolError.invalidArgument("Unknown effect type: \(effectType)")
            }
            return [.setClipEffect(clipID: clipID, effect: effect)]

        case "set_clip_transform":
            guard let clipIDStr = arguments["clip_id"] as? String, let clipID = UUID(uuidString: clipIDStr) else {
                throw AIToolError.invalidArgument("Missing clip_id")
            }
            let transform = Transform2D(
                positionX: (arguments["position_x"] as? Double) ?? 0,
                positionY: (arguments["position_y"] as? Double) ?? 0,
                scaleX: (arguments["scale_x"] as? Double) ?? 1,
                scaleY: (arguments["scale_y"] as? Double) ?? 1,
                rotation: (arguments["rotation"] as? Double) ?? 0
            )
            return [.setClipTransform(clipID: clipID, transform: transform)]

        case "roll_trim":
            guard let leftStr = arguments["left_clip_id"] as? String, let leftID = UUID(uuidString: leftStr),
                  let rightStr = arguments["right_clip_id"] as? String, let rightID = UUID(uuidString: rightStr),
                  let boundary = arguments["new_boundary"] as? Double else {
                throw AIToolError.invalidArgument("Missing left_clip_id, right_clip_id, or new_boundary")
            }
            return [.rollTrim(leftClipID: leftID, rightClipID: rightID, newBoundary: boundary)]

        // Analysis tools — handled upstream in AIChatController/MCPServer (need AppState)
        // Return empty intents — the caller handles these before reaching the resolver.
        case "auto_reframe", "detect_beats", "score_thumbnails", "suggest_broll",
             "apply_person_mask", "track_object", "voice_cleanup", "denoise_audio",
             "denoise_video", "stabilize_video", "set_caption_style", "apply_lut",
             "measure_loudness", "auto_duck", "chroma_key":
            return []

        case "remove_track":
            guard let trackIDStr = arguments["track_id"] as? String, let trackID = UUID(uuidString: trackIDStr) else {
                throw AIToolError.invalidArgument("Missing track_id")
            }
            return [.removeTrack(trackID: trackID)]

        case "lock_track":
            guard let trackIDStr = arguments["track_id"] as? String, let trackID = UUID(uuidString: trackIDStr) else {
                throw AIToolError.invalidArgument("Missing track_id")
            }
            let locked = (arguments["locked"] as? Bool) ?? true
            return [.lockTrack(trackID: trackID, locked: locked)]

        case "set_track_volume":
            guard let trackIDStr = arguments["track_id"] as? String, let trackID = UUID(uuidString: trackIDStr) else {
                throw AIToolError.invalidArgument("Missing track_id")
            }
            let volume = (arguments["volume"] as? Double) ?? 1.0
            return [.setTrackVolume(trackID: trackID, volume: volume)]

        case "rename_clip":
            guard let clipIDStr = arguments["clip_id"] as? String, let clipID = UUID(uuidString: clipIDStr) else {
                throw AIToolError.invalidArgument("Missing clip_id")
            }
            let label = (arguments["label"] as? String) ?? ""
            return [.renameClip(clipID: clipID, label: label)]

        case "set_clip_transition":
            guard let clipIDStr = arguments["clip_id"] as? String, let clipID = UUID(uuidString: clipIDStr) else {
                throw AIToolError.invalidArgument("Missing clip_id")
            }
            let typeStr = (arguments["type"] as? String) ?? "none"
            let transitionType = TransitionType(rawValue: typeStr) ?? .none
            let duration = (arguments["duration"] as? Double) ?? 0.5
            return [.setClipTransition(clipID: clipID, transition: ClipTransition(type: transitionType, duration: duration))]

        case "delete_marker":
            guard let markerIDStr = arguments["marker_id"] as? String, let markerID = UUID(uuidString: markerIDStr) else {
                throw AIToolError.invalidArgument("Missing marker_id")
            }
            return [.deleteMarker(markerID: markerID)]

        case "set_overlay_config":
            let enabled = arguments["enabled"] as? Bool ?? true
            let config = BroadcastOverlayConfig(
                isEnabled: enabled,
                episodeTitle: arguments["episode_title"] as? String ?? "",
                episodeSubtitle: arguments["episode_subtitle"] as? String ?? "",
                hostA: HostInfo(
                    name: arguments["host_a_name"] as? String ?? "",
                    title: arguments["host_a_title"] as? String ?? ""
                ),
                hostB: HostInfo(
                    name: arguments["host_b_name"] as? String ?? "",
                    title: arguments["host_b_title"] as? String ?? ""
                )
            )
            return [.setBroadcastOverlay(config: config)]

        case "get_overlay_config":
            // Read-only — handled by AIChatController, not via intents
            return []

        default:
            throw AIToolError.unknownTool(toolName)
        }
    }
}

// MARK: - AIToolError

public enum AIToolError: Error, LocalizedError {
    case unknownTool(String)
    case invalidArgument(String)
    case notYetImplemented(String)

    public var errorDescription: String? {
        switch self {
        case .unknownTool(let name): "Unknown tool: \(name)"
        case .invalidArgument(let msg): "Invalid argument: \(msg)"
        case .notYetImplemented(let msg): msg
        }
    }
}
