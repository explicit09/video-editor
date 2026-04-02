import Foundation

/// Simple version control for project snapshots.
/// Saves named snapshots of the timeline state that can be restored.
public actor VersionControl {
    public struct Snapshot: Codable, Sendable, Identifiable {
        public let id: UUID
        public let name: String
        public let timestamp: Date
        public let timelineData: Data // Encoded Timeline

        public init(id: UUID = UUID(), name: String, timestamp: Date = Date(), timelineData: Data) {
            self.id = id
            self.name = name
            self.timestamp = timestamp
            self.timelineData = timelineData
        }
    }

    private var snapshots: [Snapshot] = []
    private let storageURL: URL

    public init(projectBundleURL: URL) {
        self.storageURL = projectBundleURL.appendingPathComponent("versions")
    }

    /// Save a named snapshot of the current timeline.
    public func saveSnapshot(name: String, timeline: Timeline) throws {
        loadFromDisk()
        let data = try JSONEncoder().encode(timeline)
        let snapshot = Snapshot(name: name, timelineData: data)
        snapshots.append(snapshot)

        // Persist to disk
        try FileManager.default.createDirectory(at: storageURL, withIntermediateDirectories: true)
        let fileURL = storageURL.appendingPathComponent("\(snapshot.id.uuidString).json")
        try JSONEncoder().encode(snapshot).write(to: fileURL)

        // Save index
        try saveIndex()
    }

    /// List all snapshots.
    public func listSnapshots() -> [Snapshot] {
        loadFromDisk()
        return snapshots.sorted { $0.timestamp > $1.timestamp }
    }

    /// Restore a snapshot by ID.
    public func restoreSnapshot(id: UUID) throws -> Timeline {
        loadFromDisk()
        guard let snapshot = snapshots.first(where: { $0.id == id }) else {
            throw VersionError.snapshotNotFound
        }
        return try JSONDecoder().decode(Timeline.self, from: snapshot.timelineData)
    }

    /// Delete a snapshot.
    public func deleteSnapshot(id: UUID) throws {
        loadFromDisk()
        snapshots.removeAll { $0.id == id }
        let fileURL = storageURL.appendingPathComponent("\(id.uuidString).json")
        try? FileManager.default.removeItem(at: fileURL)
        try saveIndex()
    }

    /// Load snapshots from disk on startup.
    public func loadFromDisk() {
        snapshots = Array(loadSnapshotIndexAndFiles().values)
            .sorted { $0.timestamp > $1.timestamp }
    }

    private func saveIndex() throws {
        let indexURL = storageURL.appendingPathComponent("index.json")
        let data = try JSONEncoder().encode(snapshots)
        try data.write(to: indexURL)
    }

    private func loadSnapshotIndexAndFiles() -> [UUID: Snapshot] {
        var merged: [UUID: Snapshot] = [:]
        let decoder = JSONDecoder()
        let indexURL = storageURL.appendingPathComponent("index.json")

        if let data = try? Data(contentsOf: indexURL),
           let indexedSnapshots = try? decoder.decode([Snapshot].self, from: data) {
            for snapshot in indexedSnapshots {
                merged[snapshot.id] = snapshot
            }
        }

        guard let fileURLs = try? FileManager.default.contentsOfDirectory(
            at: storageURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return merged
        }

        for fileURL in fileURLs where fileURL.pathExtension == "json" && fileURL.lastPathComponent != "index.json" {
            guard let data = try? Data(contentsOf: fileURL),
                  let snapshot = try? decoder.decode(Snapshot.self, from: data) else {
                continue
            }
            merged[snapshot.id] = snapshot
        }

        return merged
    }
}

public enum VersionError: Error, LocalizedError {
    case snapshotNotFound

    public var errorDescription: String? {
        switch self {
        case .snapshotNotFound: "Snapshot not found"
        }
    }
}
