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
    ]

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
            // This will be implemented with silence detection data
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

    public var errorDescription: String? {
        switch self {
        case .unknownTool(let name): "Unknown tool: \(name)"
        case .invalidArgument(let msg): "Invalid argument: \(msg)"
        }
    }
}
