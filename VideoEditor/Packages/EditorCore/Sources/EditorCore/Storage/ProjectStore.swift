import Foundation

/// Owns project persistence. Save/load to project bundle on disk.
public actor ProjectStore {
    private var project: Project
    private var bundleURL: URL?

    public init(project: Project = Project(name: "Untitled")) {
        self.project = project
    }

    // MARK: - Read

    public func currentProject() -> Project {
        project
    }

    // MARK: - Write

    public func updateProject(_ transform: (inout Project) -> Void) {
        transform(&project)
        project.modifiedAt = Date()
    }

    public func setTimeline(_ timeline: Timeline) {
        project.timeline = timeline
        project.modifiedAt = Date()
    }

    // MARK: - Persistence

    /// Save project to a bundle directory.
    public func save(to url: URL) throws {
        let fm = FileManager.default
        let mediaDir = url.appendingPathComponent("media")
        let proxiesDir = url.appendingPathComponent("proxies")
        let cacheDir = url.appendingPathComponent("cache")
        let analysisDir = url.appendingPathComponent("analysis")

        for dir in [url, mediaDir, proxiesDir, cacheDir, analysisDir] {
            if !fm.fileExists(atPath: dir.path) {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }
        }

        // manifest.json
        let manifest = ProjectManifest(
            id: project.id,
            name: project.name,
            settings: project.settings,
            createdAt: project.createdAt,
            modifiedAt: project.modifiedAt,
            version: 1
        )
        let manifestData = try JSONEncoder.pretty.encode(manifest)
        try manifestData.write(to: url.appendingPathComponent("manifest.json"))

        // timeline.json
        let timelineData = try JSONEncoder.pretty.encode(project.timeline)
        try timelineData.write(to: url.appendingPathComponent("timeline.json"))

        self.bundleURL = url
    }

    /// Load project from a bundle directory.
    public func load(from url: URL) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let manifestData = try Data(contentsOf: url.appendingPathComponent("manifest.json"))
        let manifest = try decoder.decode(ProjectManifest.self, from: manifestData)

        let timelineData = try Data(contentsOf: url.appendingPathComponent("timeline.json"))
        let timeline = try decoder.decode(Timeline.self, from: timelineData)

        self.project = Project(
            id: manifest.id,
            name: manifest.name,
            settings: manifest.settings,
            timeline: timeline,
            createdAt: manifest.createdAt,
            modifiedAt: manifest.modifiedAt
        )
        self.bundleURL = url
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
