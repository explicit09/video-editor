import Foundation

/// Owns project persistence. Reads timeline from the authoritative TimelineState.
/// Does NOT hold its own copy of the timeline.
public actor ProjectStore {
    private var metadata: ProjectMetadata
    private var bundleURL: URL?

    public init(name: String = "Untitled") {
        self.metadata = ProjectMetadata(
            id: UUID(),
            name: name,
            settings: .default,
            createdAt: Date(),
            modifiedAt: Date()
        )
    }

    // MARK: - Read

    public func projectMetadata() -> ProjectMetadata {
        metadata
    }

    // MARK: - Write

    public func updateMetadata(_ transform: (inout ProjectMetadata) -> Void) {
        transform(&metadata)
        metadata.modifiedAt = Date()
    }

    // MARK: - Save (reads timeline from authoritative source)

    public func save(to url: URL, timeline: Timeline) throws {
        let fm = FileManager.default
        for subdir in ["media", "proxies", "cache", "analysis"] {
            let dir = url.appendingPathComponent(subdir)
            if !fm.fileExists(atPath: dir.path) {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }
        }
        if !fm.fileExists(atPath: url.path) {
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
        }

        let meta = self.metadata

        // manifest.json
        let manifest = ProjectManifest(
            id: meta.id,
            name: meta.name,
            settings: meta.settings,
            createdAt: meta.createdAt,
            modifiedAt: meta.modifiedAt,
            version: 1
        )
        let manifestData = try JSONEncoder.pretty.encode(manifest)
        try manifestData.write(to: url.appendingPathComponent("manifest.json"))

        // timeline.json — reads from the authoritative source passed in
        let timelineData = try JSONEncoder.pretty.encode(timeline)
        try timelineData.write(to: url.appendingPathComponent("timeline.json"))
    }

    /// Load project from a bundle directory. Returns the timeline to set on TimelineState.
    public func load(from url: URL) throws -> Timeline {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let manifestData = try Data(contentsOf: url.appendingPathComponent("manifest.json"))
        let manifest = try decoder.decode(ProjectManifest.self, from: manifestData)

        let timelineData = try Data(contentsOf: url.appendingPathComponent("timeline.json"))
        let timeline = try decoder.decode(Timeline.self, from: timelineData)

        self.metadata = ProjectMetadata(
            id: manifest.id,
            name: manifest.name,
            settings: manifest.settings,
            createdAt: manifest.createdAt,
            modifiedAt: manifest.modifiedAt
        )
        self.bundleURL = url

        return timeline
    }
}

// MARK: - ProjectMetadata (separate from Timeline — no split brain)

public struct ProjectMetadata: Codable, Sendable {
    public let id: UUID
    public var name: String
    public var settings: ProjectSettings
    public var createdAt: Date
    public var modifiedAt: Date

    public init(id: UUID = UUID(), name: String, settings: ProjectSettings = .default, createdAt: Date = Date(), modifiedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.settings = settings
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}

// MARK: - ProjectManifest (on-disk format)

struct ProjectManifest: Codable {
    let id: UUID
    var name: String
    var settings: ProjectSettings
    var createdAt: Date
    var modifiedAt: Date
    var version: Int
}

// MARK: - JSONEncoder convenience

extension JSONEncoder {
    static let pretty: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}
